// Native Dynamic Island - Background Driver integration (Test22)
// IMPORTANT: only replace Hooks/DynamicIsland.x
//
// This version stops changing SBSystemApertureWindow.alpha and stops trying to
// erase arbitrary black UIView/CALayer nodes.  The native Dynamic Island uses
// a dedicated CCSystemApertureBackgroundDriver.  We replace the driver's
// backgroundView with our existing LGLiveBackdropView so the glass lives at
// the same background-driver level as the native aperture background.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"

@interface SBSystemApertureContainerView : UIView
@end

@interface SBSystemApertureWindow : UIWindow
@end

@interface CCSystemApertureBackgroundDriver : NSObject
- (instancetype)initWithContainerView:(UIView *)containerView;
- (UIView *)containerView;
- (void)setContainerView:(UIView *)containerView;
- (UIView *)backgroundView;
- (void)setBackgroundView:(UIView *)backgroundView;
- (UIView *)clipHostView;
- (void)setClipHostView:(UIView *)clipHostView;
@end

static const void *kLGDIBackgroundGlassKey = &kLGDIBackgroundGlassKey;
static const void *kLGDIOwnedNativeBackgroundKey = &kLGDIOwnedNativeBackgroundKey;

static BOOL LGDIEnabled(void) {
    @try {
        return lgHostEnabled(@"DynamicIsland");
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static NSString *LGDIFilterType(void) {
    NSString *type = nil;
    @try {
        type = LGFilterTypeForHostPrefix(@"DynamicIsland");
    } @catch (__unused NSException *e) {}
    return type.length ? type : @"dylv.liquidglass.dynamicisland";
}

static BOOL LGDIIsNativeApertureView(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([NSStringFromClass(v.class) isEqualToString:@"SBSystemApertureContainerView"])
            return YES;
    }
    return NO;
}

static void LGDISyncGlass(UIView *host, UIView *glass) {
    if (!host || !glass) return;
    CGRect bounds = host.bounds;
    if (CGRectIsEmpty(bounds)) return;

    glass.frame = bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    glass.backgroundColor = UIColor.clearColor;
    glass.alpha = 1.0;
    glass.hidden = NO;
    glass.userInteractionEnabled = NO;

    CGFloat radius = host.layer.cornerRadius;
    if (radius <= 0.0) {
        radius = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) * 0.5;
    }
    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
}

static LGLiveBackdropView *LGDIEnsureGlass(CCSystemApertureBackgroundDriver *driver,
                                            UIView *nativeBackground) {
    if (!driver || !LGDIEnabled()) return nil;

    UIView *container = driver.containerView;
    if (!container) return nil;
    if (!LGDIIsNativeApertureView(container)) return nil;

    LGLiveBackdropView *glass = objc_getAssociatedObject(driver, kLGDIBackgroundGlassKey);
    if (!glass) {
        NSString *filterType = LGDIFilterType();
        glass = [[LGLiveBackdropView alloc] initWithFrame:container.bounds
                                                 groupName:nil
                                                filterType:filterType];
        glass.backgroundColor = UIColor.clearColor;
        glass.userInteractionEnabled = NO;
        glass.layer.zPosition = -100.0;

        // Keep the original native background alive but out of the visual
        // stack.  Do not destroy it: the driver may expect the same object.
        if (nativeBackground && nativeBackground != glass) {
            objc_setAssociatedObject(driver, kLGDIOwnedNativeBackgroundKey,
                                     nativeBackground, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try {
                nativeBackground.hidden = YES;
                nativeBackground.alpha = 0.0;
            } @catch (__unused NSException *e) {}
        }

        objc_setAssociatedObject(driver, kLGDIBackgroundGlassKey,
                                 glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        NSLog(@"[SBLiquidGlass-DI-Test22] installed driver glass filter=%@ container=%@ background=%@",
              filterType, NSStringFromClass(container.class),
              nativeBackground ? NSStringFromClass(nativeBackground.class) : @"<nil>");
    }

    if (glass.superview != container) {
        [glass removeFromSuperview];
        [container insertSubview:glass atIndex:0];
    }

    LGDISyncGlass(container, glass);
    return glass;
}

static void LGDIRestore(CCSystemApertureBackgroundDriver *driver) {
    if (!driver) return;
    LGLiveBackdropView *glass = objc_getAssociatedObject(driver, kLGDIBackgroundGlassKey);
    UIView *native = objc_getAssociatedObject(driver, kLGDIOwnedNativeBackgroundKey);

    if (glass) [glass removeFromSuperview];
    @try {
        if (native) {
            native.hidden = NO;
            native.alpha = 1.0;
        }
    } @catch (__unused NSException *e) {}

    objc_setAssociatedObject(driver, kLGDIBackgroundGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(driver, kLGDIOwnedNativeBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - The actual native aperture background hook

%hook CCSystemApertureBackgroundDriver

- (instancetype)initWithContainerView:(UIView *)containerView {
    self = %orig(containerView);
    if (self && LGDIEnabled()) {
        @try {
            UIView *background = self.backgroundView;
            LGDIEnsureGlass(self, background);
        } @catch (NSException *e) {
            NSLog(@"[SBLiquidGlass-DI-Test22] init exception: %@", e);
        }
    }
    return self;
}

- (void)setBackgroundView:(UIView *)backgroundView {
    // Let the system establish its own object first.  Then install our glass
    // in the driver's container.  We intentionally keep the native object
    // because the driver may rely on it internally.
    %orig(backgroundView);

    if (!LGDIEnabled()) {
        LGDIRestore(self);
        return;
    }

    @try {
        LGDIEnsureGlass(self, backgroundView);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-Test22] setBackgroundView exception: %@", e);
    }
}

- (void)setContainerView:(UIView *)containerView {
    %orig(containerView);
    if (!LGDIEnabled()) {
        LGDIRestore(self);
        return;
    }

    @try {
        LGDIEnsureGlass(self, self.backgroundView);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-Test22] setContainerView exception: %@", e);
    }
}

- (void)setClipHostView:(UIView *)clipHostView {
    %orig(clipHostView);
    if (!LGDIEnabled()) return;

    @try {
        LGDIEnsureGlass(self, self.backgroundView);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Keep the glass aligned with the native aperture

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    if (!self.window || !LGDIEnabled()) return;

    // No window.alpha manipulation here.  The native aperture window must
    // remain fully opaque at the window-compositing level.
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // The driver owns the real background; this call only gives the
            // driver a chance to re-run after the container has its final frame.
            for (UIView *subview in [self.subviews copy]) {
                if ([NSStringFromClass(subview.class) isEqualToString:@"LGLiveBackdropView"]) {
                    LGDISyncGlass(self, subview);
                }
            }
        } @catch (__unused NSException *e) {}
    });
}

- (void)layoutSubviews {
    %orig;
    if (!self.window || !LGDIEnabled()) return;

    for (UIView *subview in [self.subviews copy]) {
        if ([NSStringFromClass(subview.class) isEqualToString:@"LGLiveBackdropView"]) {
            LGDISyncGlass(self, subview);
        }
    }
}

%end

