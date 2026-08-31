#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import "../Shared/LGCoverSheetState.h"

typedef NS_ENUM(NSInteger, LGCoverSheetMode) {
    LGCoverSheetModeIdle,
    LGCoverSheetModePresentingGlass,
    LGCoverSheetModeDismissing
};

static LGCoverSheetMode sLGCoverSheetMode = LGCoverSheetModeIdle;
static NSHashTable<UIView *> *sLGCoverSheetPanels;
static NSHashTable<UIViewController *> *sLGCoverSheetWallpaperControllers;
static CADisplayLink *sLGCoverSheetDisplayLink;
static const void *kLGCoverSheetGlassKey = &kLGCoverSheetGlassKey;
static const void *kLGCoverSheetWallpaperSnapshotKey =
    &kLGCoverSheetWallpaperSnapshotKey;
static const void *kLGCoverSheetOriginalHiddenKey =
    &kLGCoverSheetOriginalHiddenKey;
static const void *kLGCoverSheetOriginalAlphaKey =
    &kLGCoverSheetOriginalAlphaKey;
static const void *kLGCoverSheetFadeKey = &kLGCoverSheetFadeKey;
static const void *kLGCoverSheetMaskKey = &kLGCoverSheetMaskKey;
static const void *kLGCoverSheetBorderKey = &kLGCoverSheetBorderKey;
static const void *kLGCoverSheetMaskOrientationKey =
    &kLGCoverSheetMaskOrientationKey;
static const void *kLGCoverSheetDimLayerKey = &kLGCoverSheetDimLayerKey;
static const CGFloat kLGCoverSheetBottomCornerRadiusPoints = 39.0;
static const CGFloat kLGCoverSheetDimOpacity = 0.18;
static BOOL sLGCoverSheetCommitEndPresented;
static BOOL sLGCoverSheetPerformingFade;
static BOOL sLGCoverSheetFadeToHome;
static BOOL sLGCoverSheetBeginDismissalFadeIn;
static dispatch_block_t sLGCoverSheetDeferredDismissalCommit;
static const CFTimeInterval kLGCoverSheetHandoffDuration = 0.20;
static UIDeviceOrientation sLGCoverSheetLastLandscapeOrientation =
    UIDeviceOrientationLandscapeLeft;
static UIDeviceOrientation sLGCoverSheetLastPortraitOrientation =
    UIDeviceOrientationPortrait;

static void LGCoverSheetLogOrientation(UIView *view,
                                       UIDeviceOrientation resolved,
                                       NSString *source,
                                       CGPoint xAxis,
                                       CGPoint yAxis) {
    static UIDeviceOrientation lastResolved = UIDeviceOrientationUnknown;
    static UIDeviceOrientation lastDevice = UIDeviceOrientationUnknown;
    static UIInterfaceOrientation lastInterface = UIInterfaceOrientationUnknown;
    static NSString *lastSource;
    UIDeviceOrientation device = UIDevice.currentDevice.orientation;
    UIInterfaceOrientation interfaceOrientation =
        view.window.windowScene.interfaceOrientation;
    if (resolved == lastResolved && device == lastDevice &&
        interfaceOrientation == lastInterface &&
        [source isEqualToString:lastSource]) {
        return;
    }
    lastResolved = resolved;
    lastDevice = device;
    lastInterface = interfaceOrientation;
    lastSource = [source copy];
    LGLog(@"[coversheet-orientation] source=%@ resolved=%ld device=%ld scene=%ld "
           "xAxis={%.2f,%.2f} yAxis={%.2f,%.2f} bounds=%@ window=%@",
          source, (long)resolved, (long)device, (long)interfaceOrientation,
          xAxis.x, xAxis.y, yAxis.x, yAxis.y,
          NSStringFromCGRect(view.bounds), NSStringFromCGRect(view.window.bounds));
}

static UIDeviceOrientation LGCoverSheetDeviceOrientation(UIView *view) {

    if (view.window) {
        id<UICoordinateSpace> fixedSpace =
            view.window.screen.fixedCoordinateSpace;
        CGRect bounds = view.bounds;
        CGPoint p0 = [view convertPoint:bounds.origin
                      toCoordinateSpace:fixedSpace];
        CGPoint px = [view convertPoint:
            CGPointMake(CGRectGetMaxX(bounds), CGRectGetMinY(bounds))
                      toCoordinateSpace:fixedSpace];
        CGPoint py = [view convertPoint:
            CGPointMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds))
                      toCoordinateSpace:fixedSpace];
        CGPoint xAxis = CGPointMake(px.x - p0.x, px.y - p0.y);
        CGPoint yAxis = CGPointMake(py.x - p0.x, py.y - p0.y);
        BOOL portraitBasis = fabs(xAxis.x) > fabs(xAxis.y) &&
                             fabs(yAxis.y) > fabs(yAxis.x);
        if (portraitBasis && xAxis.x < 0.0 && yAxis.y < 0.0) {
            sLGCoverSheetLastPortraitOrientation =
                UIDeviceOrientationPortraitUpsideDown;
            LGCoverSheetLogOrientation(
                view, UIDeviceOrientationPortraitUpsideDown,
                @"fixed-space-upside-down", xAxis, yAxis);
            return UIDeviceOrientationPortraitUpsideDown;
        }
        if (portraitBasis && xAxis.x > 0.0 && yAxis.y > 0.0) {
            sLGCoverSheetLastPortraitOrientation = UIDeviceOrientationPortrait;
            LGCoverSheetLogOrientation(view, UIDeviceOrientationPortrait,
                                       @"fixed-space-portrait", xAxis, yAxis);
            return UIDeviceOrientationPortrait;
        }
    }

    UIDeviceOrientation deviceOrientation =
        UIDevice.currentDevice.orientation;
    if (CGRectGetWidth(view.bounds) > CGRectGetHeight(view.bounds) &&
        UIDeviceOrientationIsLandscape(deviceOrientation)) {
        sLGCoverSheetLastLandscapeOrientation = deviceOrientation;
        LGCoverSheetLogOrientation(view, deviceOrientation,
                                   @"landscape-bounds-device",
                                   CGPointZero, CGPointZero);
        return deviceOrientation;
    }

    UIInterfaceOrientation interfaceOrientation =
        view.window.windowScene.interfaceOrientation;
    if (interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        sLGCoverSheetLastPortraitOrientation =
            UIDeviceOrientationPortraitUpsideDown;
        LGCoverSheetLogOrientation(
            view, UIDeviceOrientationPortraitUpsideDown,
            @"window-scene-upside-down", CGPointZero, CGPointZero);
        return UIDeviceOrientationPortraitUpsideDown;
    }
    if (interfaceOrientation == UIInterfaceOrientationPortrait) {
        sLGCoverSheetLastPortraitOrientation = UIDeviceOrientationPortrait;
        LGCoverSheetLogOrientation(view, UIDeviceOrientationPortrait,
                                   @"window-scene-portrait",
                                   CGPointZero, CGPointZero);
        return UIDeviceOrientationPortrait;
    }

    UIDeviceOrientation orientation = deviceOrientation;
    if (UIDeviceOrientationIsPortrait(orientation)) {
        sLGCoverSheetLastPortraitOrientation = orientation;
        LGCoverSheetLogOrientation(view, orientation, @"device-portrait",
                                   CGPointZero, CGPointZero);
        return orientation;
    }
    if (UIDeviceOrientationIsLandscape(orientation)) {
        sLGCoverSheetLastLandscapeOrientation = orientation;
        LGCoverSheetLogOrientation(view, orientation, @"device-landscape",
                                   CGPointZero, CGPointZero);
        return orientation;
    }
    UIDeviceOrientation fallback =
        CGRectGetWidth(view.bounds) > CGRectGetHeight(view.bounds)
        ? sLGCoverSheetLastLandscapeOrientation
        : sLGCoverSheetLastPortraitOrientation;
    LGCoverSheetLogOrientation(view, fallback, @"remembered-fallback",
                               CGPointZero, CGPointZero);
    return fallback;
}

static BOOL LGCoverSheetEnabled(void) {
    return lgHostEnabled(@"CoverSheet");
}

static BOOL LGCoverSheetModeUsesGlass(LGCoverSheetMode mode) {
    return mode == LGCoverSheetModePresentingGlass ||
           mode == LGCoverSheetModeDismissing;
}

static void LGCoverSheetConsumeDeferredDismissalCommit(void) {
    dispatch_block_t commit = sLGCoverSheetDeferredDismissalCommit;
    sLGCoverSheetDeferredDismissalCommit = nil;
    if (commit) commit();
}

static UIView *LGCoverSheetWallpaperSnapshot(UIView *panel) {
    return objc_getAssociatedObject(panel,
                                    kLGCoverSheetWallpaperSnapshotKey);
}

static void LGCoverSheetRemoveWallpaperSnapshot(UIView *panel) {
    UIView *snapshot = LGCoverSheetWallpaperSnapshot(panel);
    [snapshot removeFromSuperview];
    objc_setAssociatedObject(panel, kLGCoverSheetWallpaperSnapshotKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
}

static void LGCoverSheetMatchViewGeometry(UIView *destination,
                                           UIView *source,
                                           UIView *container) {
    if (!destination || !source || !container || CGRectIsEmpty(source.bounds)) {
        return;
    }

    CGRect bounds = source.bounds;
    CGPoint origin = [source convertPoint:bounds.origin toView:container];
    CGPoint xEdge = [source convertPoint:
        CGPointMake(CGRectGetMaxX(bounds), CGRectGetMinY(bounds))
                                  toView:container];
    CGPoint yEdge = [source convertPoint:
        CGPointMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds))
                                  toView:container];
    CGPoint center = [source convertPoint:
        CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
                                   toView:container];
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 0.0 || height <= 0.0) return;

    CGAffineTransform transform = CGAffineTransformMake(
        (xEdge.x - origin.x) / width,
        (xEdge.y - origin.y) / width,
        (yEdge.x - origin.x) / height,
        (yEdge.y - origin.y) / height,
        0.0, 0.0);
    destination.bounds = bounds;
    destination.center = center;
    destination.transform = transform;
}

static void LGCoverSheetCaptureWallpaperSnapshots(void) {
    for (UIView *panel in sLGCoverSheetPanels.allObjects) {
        UIView *parent = panel.superview;
        if (!parent || !panel.window) continue;

        LGCoverSheetRemoveWallpaperSnapshot(panel);

        UIView *source = nil;
        CGFloat sourceWindowLevel = -CGFLOAT_MAX;
        for (UIViewController *controller in
                 sLGCoverSheetWallpaperControllers.allObjects) {
            UIView *candidate = controller.viewIfLoaded;
            if (!candidate.window || candidate.hidden ||
                candidate.alpha <= 0.001) {
                continue;
            }
            CGFloat level = candidate.window.windowLevel;
            if (!source || level > sourceWindowLevel) {
                source = candidate;
                sourceWindowLevel = level;
            }
        }
        if (!source) source = panel;

        UIView *snapshot = [source snapshotViewAfterScreenUpdates:NO];
        if (!snapshot) continue;
        LGCoverSheetMatchViewGeometry(snapshot, source, parent);
        snapshot.autoresizingMask = UIViewAutoresizingNone;
        snapshot.userInteractionEnabled = NO;
        [parent insertSubview:snapshot belowSubview:panel];
        objc_setAssociatedObject(panel, kLGCoverSheetWallpaperSnapshotKey,
                                 snapshot,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void LGCoverSheetAddOpacityFade(UIView *view, CGFloat targetAlpha) {
    if (!view) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.alpha = targetAlpha;
    [CATransaction commit];

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.0;
    fade.toValue = @(targetAlpha);
    fade.duration = kLGCoverSheetHandoffDuration;
    fade.timingFunction = [CAMediaTimingFunction
        functionWithName:kCAMediaTimingFunctionEaseOut];
    [view.layer addAnimation:fade forKey:@"dylv.coversheet.fadeIn"];
}

static void LGCoverSheetRegisterWallpaperController(UIViewController *controller) {
    if (!controller) return;
    if (!sLGCoverSheetWallpaperControllers) {
        sLGCoverSheetWallpaperControllers = [NSHashTable weakObjectsHashTable];
    }
    [sLGCoverSheetWallpaperControllers addObject:controller];
}

static void LGCoverSheetUpdateBottomCornerMask(LGLiveBackdropView *glass) {
    if (!glass || CGRectIsEmpty(glass.bounds)) return;
    // the layer transform rotates this local bottom edge into place
    CAShapeLayer *mask =
        objc_getAssociatedObject(glass, kLGCoverSheetMaskKey);
    if (!mask) {
        mask = [CAShapeLayer layer];
        mask.fillColor = UIColor.blackColor.CGColor;
        objc_setAssociatedObject(glass, kLGCoverSheetMaskKey, mask,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        glass.layer.mask = mask;
    }
    CAShapeLayer *border =
        objc_getAssociatedObject(glass, kLGCoverSheetBorderKey);
    if (!border) {
        border = [CAShapeLayer layer];
        border.fillColor = UIColor.clearColor.CGColor;
        border.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
        objc_setAssociatedObject(glass, kLGCoverSheetBorderKey, border,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [glass.layer addSublayer:border];
    }
    UIDeviceOrientation orientation = LGCoverSheetDeviceOrientation(glass);
    NSNumber *maskedOrientation =
        objc_getAssociatedObject(glass, kLGCoverSheetMaskOrientationKey);
    if (CGRectEqualToRect(mask.frame, glass.bounds) && mask.path &&
        CGRectEqualToRect(border.frame, glass.bounds) && border.path &&
        maskedOrientation.unsignedIntegerValue == (NSUInteger)orientation) {
        return;
    }

    CGFloat scale = glass.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    CGFloat lineWidth = 1.0 / MAX(scale, 1.0);

    UIRectCorner roundedCorners =
        UIRectCornerBottomLeft | UIRectCornerBottomRight;
    UIBezierPath *maskPath = [UIBezierPath
        bezierPathWithRoundedRect:glass.bounds
               byRoundingCorners:roundedCorners
                     cornerRadii:CGSizeMake(kLGCoverSheetBottomCornerRadiusPoints,
                                            kLGCoverSheetBottomCornerRadiusPoints)];
    CGRect borderRect = CGRectInset(glass.bounds, lineWidth * 0.5,
                                    lineWidth * 0.5);
    UIBezierPath *borderPath = [UIBezierPath
        bezierPathWithRoundedRect:borderRect
               byRoundingCorners:roundedCorners
                     cornerRadii:CGSizeMake(MAX(0.0,
                                                kLGCoverSheetBottomCornerRadiusPoints - lineWidth * 0.5),
                                            MAX(0.0,
                                                kLGCoverSheetBottomCornerRadiusPoints - lineWidth * 0.5))];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = glass.bounds;
    mask.path = maskPath.CGPath;
    border.frame = glass.bounds;
    border.contentsScale = scale;
    border.lineWidth = lineWidth;
    border.path = borderPath.CGPath;
    [CATransaction commit];
    objc_setAssociatedObject(glass, kLGCoverSheetMaskOrientationKey,
                             @((NSUInteger)orientation),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static LGLiveBackdropView *LGCoverSheetEnsureGlass(UIView *panel) {
    UIView *parent = panel.superview;
    if (!parent) return nil;

    LGLiveBackdropView *glass =
        objc_getAssociatedObject(panel, kLGCoverSheetGlassKey);
    if (glass && !CGRectIsEmpty(glass.bounds) && !CGRectIsEmpty(panel.bounds)) {
        BOOL glassLandscape = CGRectGetWidth(glass.bounds) >
                              CGRectGetHeight(glass.bounds);
        BOOL panelLandscape = CGRectGetWidth(panel.bounds) >
                              CGRectGetHeight(panel.bounds);
        if (glassLandscape != panelLandscape) {

            [glass removeFromSuperview];
            objc_setAssociatedObject(panel, kLGCoverSheetGlassKey, nil,
                                     OBJC_ASSOCIATION_ASSIGN);
            glass = nil;
        }
    }
    if (!glass) {
        glass = LGCreateRegisteredGlass(panel.frame, nil, @"CoverSheet");
        glass.autoresizingMask = UIViewAutoresizingNone;
        glass.userInteractionEnabled = NO;
        glass.backgroundColor = UIColor.clearColor;
        glass.layer.cornerRadius = 0.0;
        glass.layer.masksToBounds = NO;
        glass.hidden = YES;
        objc_setAssociatedObject(panel, kLGCoverSheetGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CALayer *dimLayer =
        objc_getAssociatedObject(glass, kLGCoverSheetDimLayerKey);
    if (!dimLayer) {
        dimLayer = [CALayer layer];
        dimLayer.backgroundColor = UIColor.blackColor.CGColor;
        dimLayer.opacity = kLGCoverSheetDimOpacity;
        dimLayer.actions = @{@"bounds": NSNull.null,
                             @"position": NSNull.null,
                             @"opacity": NSNull.null};
        [glass.layer addSublayer:dimLayer];
        objc_setAssociatedObject(glass, kLGCoverSheetDimLayerKey, dimLayer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    dimLayer.frame = glass.bounds;
    if (glass.superview != parent) {
        [glass removeFromSuperview];
    }

    [parent insertSubview:glass belowSubview:panel];
    return glass;
}

static void LGCoverSheetSyncGlassGeometry(UIView *panel,
                                          LGLiveBackdropView *glass) {
    if (!panel || !glass || glass.superview != panel.superview) return;

    // presentation geometry keeps the glass attached during interactive pulls
    CALayer *modelLayer = panel.layer;
    CALayer *sourceLayer = modelLayer.presentationLayer ?: modelLayer;
    BOOL modelLandscape = CGRectGetWidth(modelLayer.bounds) >
                          CGRectGetHeight(modelLayer.bounds);
    BOOL presentationLandscape = CGRectGetWidth(sourceLayer.bounds) >
                                 CGRectGetHeight(sourceLayer.bounds);
    if (modelLandscape != presentationLandscape) {

        sourceLayer = modelLayer;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    glass.layer.anchorPoint = sourceLayer.anchorPoint;
    glass.layer.bounds = sourceLayer.bounds;
    glass.layer.position = sourceLayer.position;
    glass.layer.transform = sourceLayer.transform;
    [CATransaction commit];
    CALayer *dimLayer =
        objc_getAssociatedObject(glass, kLGCoverSheetDimLayerKey);
    dimLayer.frame = glass.bounds;
    LGCoverSheetUpdateBottomCornerMask(glass);

    if (LGCoverSheetModeUsesGlass(sLGCoverSheetMode)) {

        CGPoint captureOrigin = glass.frame.origin;
        if (glass.window) {
            CGPoint windowOriginInGlass =
                [glass convertPoint:glass.window.bounds.origin
                           fromView:glass.window];
            captureOrigin = CGPointMake(-windowOriginInGlass.x,
                                        -windowOriginInGlass.y);
        }
        CGFloat width = CGRectGetWidth(glass.bounds);
        CGFloat height = CGRectGetHeight(glass.bounds);
        CGFloat scale = glass.window.screen.scale;
        if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
        UIDeviceOrientation deviceOrientation =
            LGCoverSheetDeviceOrientation(glass);
        if (width > height && !UIDeviceOrientationIsLandscape(deviceOrientation)) {

            deviceOrientation = sLGCoverSheetLastLandscapeOrientation;
        } else if (UIDeviceOrientationIsLandscape(deviceOrientation)) {
            sLGCoverSheetLastLandscapeOrientation = deviceOrientation;
        }
        static UIDeviceOrientation lastLoggedOrientation =
            UIDeviceOrientationUnknown;
        static NSUInteger initialGeometryLogs = 0;
        if (deviceOrientation != lastLoggedOrientation ||
            initialGeometryLogs < 8) {
            lastLoggedOrientation = deviceOrientation;
            initialGeometryLogs++;
            CATransform3D transform = sourceLayer.transform;
            LGLog(@"[coversheet-state-write] orientation=%ld mode=%ld "
                   "capture={%.2f,%.2f} ratio={%.4f,%.4f} size={%.2f,%.2f} "
                   "glassFrame=%@ glassBounds=%@ layerBasis={%.3f,%.3f,%.3f,%.3f}",
                  (long)deviceOrientation, (long)sLGCoverSheetMode,
                  captureOrigin.x, captureOrigin.y,
                  width > 0.0 ? captureOrigin.x / width : 0.0,
                  height > 0.0 ? captureOrigin.y / height : 0.0,
                  width, height, NSStringFromCGRect(glass.frame),
                  NSStringFromCGRect(glass.bounds), transform.m11,
                  transform.m12, transform.m21, transform.m22);
        }
        LGCoverSheetWriteSharedState(
            true,
            width > 0.0 ? captureOrigin.x / width : 0.0,
            height > 0.0 ? captureOrigin.y / height : 0.0,
            scale, (uint32_t)deviceOrientation);
    }
}

@interface LGCoverSheetDisplayLinkTarget : NSObject
- (void)lg_coverSheetDisplayLinkTick:(CADisplayLink *)displayLink;
@end

@implementation LGCoverSheetDisplayLinkTarget
- (void)lg_coverSheetDisplayLinkTick:(CADisplayLink *)displayLink {
    (void)displayLink;
    if (!LGCoverSheetModeUsesGlass(sLGCoverSheetMode)) return;
    for (UIView *panel in sLGCoverSheetPanels.allObjects) {
        LGLiveBackdropView *glass =
            objc_getAssociatedObject(panel, kLGCoverSheetGlassKey);
        if (glass && !glass.hidden) {
            LGCoverSheetSyncGlassGeometry(panel, glass);
        }
    }
}
@end

static LGCoverSheetDisplayLinkTarget *sLGCoverSheetDisplayLinkTarget;

static void LGCoverSheetSetDisplayLinkActive(BOOL active) {
    if (active) {
        if (sLGCoverSheetDisplayLink) return;
        if (!sLGCoverSheetDisplayLinkTarget) {
            sLGCoverSheetDisplayLinkTarget =
                [LGCoverSheetDisplayLinkTarget new];
        }
        sLGCoverSheetDisplayLink =
            [CADisplayLink displayLinkWithTarget:sLGCoverSheetDisplayLinkTarget
                                         selector:@selector(lg_coverSheetDisplayLinkTick:)];
        [sLGCoverSheetDisplayLink addToRunLoop:NSRunLoop.mainRunLoop
                                       forMode:NSRunLoopCommonModes];
    } else {
        [sLGCoverSheetDisplayLink invalidate];
        sLGCoverSheetDisplayLink = nil;
    }
}

static CGFloat LGCoverSheetRestorePanelVisibility(UIView *panel) {
    NSNumber *originalHidden =
        objc_getAssociatedObject(panel, kLGCoverSheetOriginalHiddenKey);
    NSNumber *originalAlpha =
        objc_getAssociatedObject(panel, kLGCoverSheetOriginalAlphaKey);
    CGFloat alpha = originalAlpha ? originalAlpha.doubleValue : panel.alpha;
    if (originalHidden) panel.hidden = originalHidden.boolValue;
    objc_setAssociatedObject(panel, kLGCoverSheetOriginalHiddenKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(panel, kLGCoverSheetOriginalAlphaKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    return alpha;
}

static void LGCoverSheetCrossfadeToLockscreen(UIView *panel,
                                               LGLiveBackdropView *glass) {
    if (objc_getAssociatedObject(panel, kLGCoverSheetFadeKey)) {
        return;
    }
    CGFloat targetAlpha = LGCoverSheetRestorePanelVisibility(panel);
    glass.hidden = NO;
    glass.alpha = 1.0;
    LGCoverSheetAddOpacityFade(panel, targetAlpha);
    NSArray<UIViewController *> *wallpaperControllers =
        sLGCoverSheetWallpaperControllers.allObjects;
    for (UIViewController *controller in wallpaperControllers) {
        UIView *wallpaperView = controller.view;
        if (!wallpaperView.window || wallpaperView.hidden) continue;
        LGCoverSheetAddOpacityFade(wallpaperView, wallpaperView.alpha);
    }
    objc_setAssociatedObject(panel, kLGCoverSheetFadeKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView animateWithDuration:kLGCoverSheetHandoffDuration
                          delay:0.0
                        options:(UIViewAnimationOptionBeginFromCurrentState |
                                 UIViewAnimationOptionCurveEaseOut |
                                 UIViewAnimationOptionAllowUserInteraction)
                     animations:^{
        glass.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        glass.hidden = YES;
        glass.alpha = 1.0;
        objc_setAssociatedObject(panel, kLGCoverSheetFadeKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
    }];
}

static void LGCoverSheetCrossfadeToHome(UIView *panel,
                                        LGLiveBackdropView *glass) {
    if (objc_getAssociatedObject(panel, kLGCoverSheetFadeKey)) {
        return;
    }

    objc_setAssociatedObject(panel, kLGCoverSheetFadeKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    panel.hidden = YES;
    glass.hidden = NO;
    glass.alpha = 1.0;
    UIView *snapshot = LGCoverSheetWallpaperSnapshot(panel);
    snapshot.hidden = NO;
    snapshot.alpha = 1.0;
    [UIView animateWithDuration:kLGCoverSheetHandoffDuration
                          delay:0.0
                        options:(UIViewAnimationOptionBeginFromCurrentState |
                                 UIViewAnimationOptionCurveEaseOut |
                                 UIViewAnimationOptionAllowUserInteraction)
                     animations:^{
        glass.alpha = 0.0;
        snapshot.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        CGFloat alpha = LGCoverSheetRestorePanelVisibility(panel);
        panel.alpha = alpha;
        glass.hidden = YES;
        glass.alpha = 1.0;
        LGCoverSheetRemoveWallpaperSnapshot(panel);
        objc_setAssociatedObject(panel, kLGCoverSheetFadeKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        LGCoverSheetConsumeDeferredDismissalCommit();
    }];
}

static void LGCoverSheetSyncPanel(UIView *panel) {
    if (!panel) return;
    if (!LGCoverSheetEnabled()) {
        [panel.layer removeAllAnimations];
        CGFloat alpha = LGCoverSheetRestorePanelVisibility(panel);
        panel.alpha = alpha;
        LGLiveBackdropView *glass =
            objc_getAssociatedObject(panel, kLGCoverSheetGlassKey);
        [glass removeFromSuperview];
        LGCoverSheetRemoveWallpaperSnapshot(panel);
        objc_setAssociatedObject(panel, kLGCoverSheetGlassKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(panel, kLGCoverSheetFadeKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        return;
    }
    LGLiveBackdropView *glass = LGCoverSheetEnsureGlass(panel);
    if (!glass) return;
    LGCoverSheetSyncGlassGeometry(panel, glass);
    BOOL beginDismissalFadeIn =
        sLGCoverSheetBeginDismissalFadeIn &&
        sLGCoverSheetMode == LGCoverSheetModeDismissing;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (LGCoverSheetModeUsesGlass(sLGCoverSheetMode)) {
        if (!objc_getAssociatedObject(panel,
                                      kLGCoverSheetOriginalHiddenKey)) {
            objc_setAssociatedObject(
                panel, kLGCoverSheetOriginalHiddenKey, @(panel.hidden),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                panel, kLGCoverSheetOriginalAlphaKey, @(panel.alpha),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        panel.hidden = YES;
        glass.alpha = 1.0;
        if (beginDismissalFadeIn) {
            [glass.layer removeAnimationForKey:
                @"dylv.coversheet.dismissalFadeIn"];
            CABasicAnimation *fadeIn =
                [CABasicAnimation animationWithKeyPath:@"opacity"];
            fadeIn.fromValue = @0.0;
            fadeIn.toValue = @1.0;
            fadeIn.duration = kLGCoverSheetHandoffDuration;
            fadeIn.timingFunction = [CAMediaTimingFunction
                functionWithName:kCAMediaTimingFunctionEaseOut];
            [glass.layer addAnimation:fadeIn
                               forKey:@"dylv.coversheet.dismissalFadeIn"];
        }

        glass.hidden = NO;
        UIView *snapshot = LGCoverSheetWallpaperSnapshot(panel);
        snapshot.hidden =
            sLGCoverSheetMode != LGCoverSheetModeDismissing;
    } else {
        if (sLGCoverSheetPerformingFade) {
            [CATransaction commit];
            if (sLGCoverSheetFadeToHome) {
                LGCoverSheetCrossfadeToHome(panel, glass);
            } else {
                LGCoverSheetCrossfadeToLockscreen(panel, glass);
            }
            return;
        }
        if (objc_getAssociatedObject(panel, kLGCoverSheetFadeKey)) {
            [CATransaction commit];
            return;
        }
        CGFloat alpha = LGCoverSheetRestorePanelVisibility(panel);
        panel.alpha = alpha;
        glass.hidden = YES;
        glass.alpha = 1.0;
        LGCoverSheetRemoveWallpaperSnapshot(panel);
    }
    [CATransaction commit];
}

static void LGCoverSheetSetMode(LGCoverSheetMode mode) {
    if (!LGCoverSheetEnabled()) mode = LGCoverSheetModeIdle;
    LGCoverSheetMode previousMode = sLGCoverSheetMode;
    sLGCoverSheetMode = mode;
    sLGCoverSheetBeginDismissalFadeIn =
        mode == LGCoverSheetModeDismissing &&
        previousMode != LGCoverSheetModeDismissing;
    BOOL enteringIdle = mode == LGCoverSheetModeIdle;
    BOOL fadeToLockscreen =
        enteringIdle &&
        previousMode == LGCoverSheetModePresentingGlass &&
        sLGCoverSheetCommitEndPresented;
    sLGCoverSheetFadeToHome =
        enteringIdle &&
        previousMode == LGCoverSheetModeDismissing &&
        !sLGCoverSheetCommitEndPresented;
    sLGCoverSheetPerformingFade =
        fadeToLockscreen || sLGCoverSheetFadeToHome;
    sLGCoverSheetCommitEndPresented = NO;
    if (!LGCoverSheetModeUsesGlass(mode)) {
        LGCoverSheetWriteSharedState(false, 0.0f, 0.0f, 0.0f, 0u);
    }
    LGCoverSheetSetDisplayLinkActive(
        LGCoverSheetModeUsesGlass(mode));
    for (UIView *panel in sLGCoverSheetPanels.allObjects) {
        LGCoverSheetSyncPanel(panel);
    }
    sLGCoverSheetBeginDismissalFadeIn = NO;
    sLGCoverSheetPerformingFade = NO;
    sLGCoverSheetFadeToHome = NO;
}

%hook SBCoverSheetPanelBackgroundContainerView

- (void)didMoveToWindow {
    %orig;
    UIView *panel = (UIView *)self;
    if (!sLGCoverSheetPanels) {
        sLGCoverSheetPanels = [NSHashTable weakObjectsHashTable];
    }
    if (panel.window) {
        [sLGCoverSheetPanels addObject:panel];
        LGCoverSheetSyncPanel(panel);
    } else {
        LGLiveBackdropView *glass =
            objc_getAssociatedObject(panel, kLGCoverSheetGlassKey);
        [glass removeFromSuperview];
        LGCoverSheetRemoveWallpaperSnapshot(panel);
        objc_setAssociatedObject(panel, kLGCoverSheetGlassKey, nil,
                                 OBJC_ASSOCIATION_ASSIGN);
        [sLGCoverSheetPanels removeObject:panel];
    }
}

- (void)layoutSubviews {
    %orig;
    LGCoverSheetSyncPanel((UIView *)self);
}

%end

%hook PBUIPosterWallpaperRemoteViewController

- (void)viewDidLoad {
    %orig;
    if (LGCoverSheetEnabled())
        LGCoverSheetRegisterWallpaperController((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (LGCoverSheetEnabled())
        LGCoverSheetRegisterWallpaperController((UIViewController *)self);
}

%end

%hook SBCoverSheetPresentationManager

- (void)coverSheetSlidingViewController:(id)controller
prepareForPresentationTransitionForUserGesture:(BOOL)userGesture {
    %orig;
    (void)controller;
    if (LGCoverSheetEnabled() && userGesture) {
        LGCoverSheetSetMode(LGCoverSheetModePresentingGlass);
    }
}

- (void)coverSheetSlidingViewController:(id)controller
prepareForDismissalTransitionForReversingTransition:(BOOL)reversing
                         forUserGesture:(BOOL)userGesture {
    if (LGCoverSheetEnabled() && userGesture) {

        LGCoverSheetCaptureWallpaperSnapshots();
    }
    %orig;
    (void)controller;
    (void)reversing;
    if (LGCoverSheetEnabled() && userGesture) {
        LGCoverSheetSetMode(LGCoverSheetModeDismissing);
    }
}

- (void)coverSheetSlidingViewController:(id)controller
               committingToEndPresented:(BOOL)endPresented {
    if (!LGCoverSheetEnabled()) {
        %orig;
        sLGCoverSheetCommitEndPresented = NO;
        LGCoverSheetSetMode(LGCoverSheetModeIdle);
        LGCoverSheetConsumeDeferredDismissalCommit();
        return;
    }
    BOOL completedDismissal =
        sLGCoverSheetMode == LGCoverSheetModeDismissing && !endPresented;
    BOOL hasFrozenWallpaper = NO;
    if (completedDismissal) {
        for (UIView *panel in sLGCoverSheetPanels.allObjects) {
            if (LGCoverSheetWallpaperSnapshot(panel)) {
                hasFrozenWallpaper = YES;
                break;
            }
        }
    }
    if (completedDismissal && hasFrozenWallpaper) {
        id manager = self;
        id slidingController = controller;
        sLGCoverSheetDeferredDismissalCommit = [^{
            (void)manager;
            %orig(slidingController, endPresented);
        } copy];
        sLGCoverSheetCommitEndPresented = endPresented;
        LGCoverSheetSetMode(LGCoverSheetModeIdle);

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)((kLGCoverSheetHandoffDuration + 0.05) *
                                    NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                LGCoverSheetConsumeDeferredDismissalCommit();
            });
        return;
    }

    %orig;
    (void)controller;
    sLGCoverSheetCommitEndPresented = endPresented;
    LGCoverSheetSetMode(LGCoverSheetModeIdle);
}

%end

%ctor {
    sLGCoverSheetPanels = [NSHashTable weakObjectsHashTable];
    sLGCoverSheetWallpaperControllers = [NSHashTable weakObjectsHashTable];
    lgObservePreferenceReload(^{
        if (!LGCoverSheetEnabled()) {
            sLGCoverSheetMode = LGCoverSheetModeIdle;
            sLGCoverSheetCommitEndPresented = NO;
            sLGCoverSheetPerformingFade = NO;
            sLGCoverSheetFadeToHome = NO;
            sLGCoverSheetBeginDismissalFadeIn = NO;
            LGCoverSheetSetDisplayLinkActive(NO);
            LGCoverSheetWriteSharedState(false, 0.0f, 0.0f, 0.0f, 0u);
            LGCoverSheetConsumeDeferredDismissalCommit();
        }
        for (UIView *panel in sLGCoverSheetPanels.allObjects) {
            LGCoverSheetSyncPanel(panel);
        }
    });
}
