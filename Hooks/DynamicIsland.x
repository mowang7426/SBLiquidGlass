// Native Dynamic Island - Liquidify-style driver/backdrop integration (Test24)
// IMPORTANT: ONLY replace Hooks/DynamicIsland.x
//
// Test22 hid the whole backgroundView -> native right-side content disappeared.
// Test23 kept backgroundView alive, but the actual opaque backdrop was still
// winning.  Test24 follows the structure exposed by Liquidify 1.3.7:
// CCSystemApertureBackgroundDriver owns backgroundView + backdropLayer +
// frostedBackdropView + manualBackdropView.
//
// We DO NOT hide backgroundView and DO NOT change window.alpha.
// We neutralize only the driver's dedicated backdrop surfaces, then place
// SBLiquidGlass below the native content at the same parent level as the
// driver's backgroundView.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"

@interface SBSystemApertureContainerView : UIView
@end

@interface CCSystemApertureBackgroundDriver : NSObject
- (instancetype)initWithContainerView:(UIView *)containerView;
- (UIView *)containerView;
- (void)setContainerView:(UIView *)containerView;
- (UIView *)backgroundView;
- (void)setBackgroundView:(UIView *)backgroundView;
- (UIView *)clipHostView;
- (void)setClipHostView:(UIView *)clipHostView;
- (CALayer *)backdropLayer;
- (UIView *)frostedBackdropView;
- (UIImageView *)manualBackdropView;
@end

static const void *kDI24GlassKey = &kDI24GlassKey;
static const void *kDI24NativeBackdropKey = &kDI24NativeBackdropKey;
static const void *kDI24NativeFrostKey = &kDI24NativeFrostKey;
static const void *kDI24NativeManualKey = &kDI24NativeManualKey;

static BOOL DI24Enabled(void) {
    @try { return lgHostEnabled(@"DynamicIsland"); }
    @catch (__unused NSException *e) { return NO; }
}

static NSString *DI24Filter(void) {
    @try {
        NSString *s = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (s.length) return s;
    } @catch (__unused NSException *e) {}
    return @"dylv.liquidglass.dynamicisland";
}

static BOOL DI24IsNativeAperture(UIView *v) {
    for (UIView *p = v; p; p = p.superview) {
        if ([NSStringFromClass(p.class) isEqualToString:@"SBSystemApertureContainerView"])
            return YES;
    }
    return NO;
}

static void DI24ClearViewPaint(UIView *v) {
    if (!v) return;
    @try {
        v.backgroundColor = UIColor.clearColor;
        v.opaque = NO;
        v.layer.backgroundColor = UIColor.clearColor.CGColor;
    } @catch (__unused NSException *e) {}
}

static void DI24NeutralizeBackdropLayer(CALayer *layer) {
    if (!layer) return;
    @try {
        // This is the driver's dedicated backdrop layer.  Keep the layer
        // object alive, but remove its visual contribution.
        layer.backgroundColor = UIColor.clearColor.CGColor;
        layer.contents = nil;
        layer.filters = nil;
        layer.compositingFilter = nil;
        layer.opacity = 0.0;
        layer.hidden = YES;
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-Test24] backdrop neutralize exception: %@", e);
    }
}

static void DI24NeutralizeFrosted(UIView *v) {
    if (!v) return;
    @try {
        if ([v isKindOfClass:UIVisualEffectView.class]) {
            [(UIVisualEffectView *)v setEffect:nil];
        }
        v.backgroundColor = UIColor.clearColor;
        v.opaque = NO;
        v.alpha = 0.0;
        v.hidden = YES;
        v.layer.backgroundColor = UIColor.clearColor.CGColor;
    } @catch (__unused NSException *e) {}
}

static UIView *DI24GlassHost(CCSystemApertureBackgroundDriver *driver,
                             UIView *background,
                             UIView *clipHost,
                             UIView *container) {
    // Prefer the exact parent of backgroundView. This gives the glass the same
    // clipping/compositing domain as the native background without hiding the
    // backgroundView itself.
    UIView *parent = background.superview;
    if (parent && DI24IsNativeAperture(parent)) return parent;
    if (clipHost && DI24IsNativeAperture(clipHost)) return clipHost;
    if (container && DI24IsNativeAperture(container)) return container;
    return nil;
}

static void DI24SyncGlass(LGLiveBackdropView *glass,
                          UIView *background,
                          UIView *host) {
    if (!glass || !background || !host) return;

    CGRect frame = [background.superview isEqual:host]
        ? background.frame
        : [background convertRect:background.bounds toView:host];
    if (CGRectIsEmpty(frame)) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    glass.frame = frame;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    glass.backgroundColor = UIColor.clearColor;
    glass.alpha = 1.0;
    glass.hidden = NO;
    glass.userInteractionEnabled = NO;

    CGFloat radius = background.layer.cornerRadius;
    if (radius <= 0.0) {
        radius = MIN(CGRectGetWidth(background.bounds),
                     CGRectGetHeight(background.bounds)) * 0.5;
    }
    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
    [CATransaction commit];
}

static LGLiveBackdropView *DI24Install(CCSystemApertureBackgroundDriver *driver) {
    if (!driver || !DI24Enabled()) return nil;

    UIView *container = nil;
    UIView *background = nil;
    UIView *clipHost = nil;
    CALayer *backdrop = nil;
    UIView *frosted = nil;
    UIImageView *manual = nil;

    @try { container = driver.containerView; } @catch (__unused NSException *e) {}
    @try { background = driver.backgroundView; } @catch (__unused NSException *e) {}
    @try { clipHost = driver.clipHostView; } @catch (__unused NSException *e) {}
    @try { backdrop = driver.backdropLayer; } @catch (__unused NSException *e) {}
    @try { frosted = driver.frostedBackdropView; } @catch (__unused NSException *e) {}
    @try { manual = driver.manualBackdropView; } @catch (__unused NSException *e) {}

    if (!container || !background || !DI24IsNativeAperture(container)) return nil;

    UIView *host = DI24GlassHost(driver, background, clipHost, container);
    if (!host) return nil;

    // Keep every native content view alive.  Only remove the visual output of
    // the driver's background surfaces.
    if (backdrop) {
        objc_setAssociatedObject(driver, kDI24NativeBackdropKey,
                                 backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DI24NeutralizeBackdropLayer(backdrop);
    }
    if (frosted) {
        objc_setAssociatedObject(driver, kDI24NativeFrostKey,
                                 frosted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DI24NeutralizeFrosted(frosted);
    }
    if (manual) {
        objc_setAssociatedObject(driver, kDI24NativeManualKey,
                                 manual, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DI24NeutralizeFrosted(manual);
    }

    // backgroundView itself may carry a solid UIView/layer paint. Clear only
    // that paint; do not hide or alpha the view, because native activity
    // content can live below it.
    DI24ClearViewPaint(background);

    LGLiveBackdropView *glass = objc_getAssociatedObject(driver, kDI24GlassKey);
    if (!glass) {
        glass = [[LGLiveBackdropView alloc] initWithFrame:CGRectZero
                                                 groupName:nil
                                                filterType:DI24Filter()];
        glass.backgroundColor = UIColor.clearColor;
        glass.userInteractionEnabled = NO;

        // The native backgroundView remains above this glass.  Thus the
        // native icons/text stay interactive/visible while the glass samples
        // the content behind the aperture.
        NSUInteger index = [host.subviews indexOfObject:background];
        if (index == NSNotFound) index = 0;
        [host insertSubview:glass atIndex:index];

        objc_setAssociatedObject(driver, kDI24GlassKey,
                                 glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}

        NSLog(@"[SBLiquidGlass-DI-Test24] driver=%@ container=%@ host=%@ background=%@ backdrop=%@ frosted=%@ manual=%@ filter=%@",
              NSStringFromClass(driver.class),
              NSStringFromClass(container.class),
              NSStringFromClass(host.class),
              NSStringFromClass(background.class),
              backdrop ? NSStringFromClass(backdrop.class) : @"<nil>",
              frosted ? NSStringFromClass(frosted.class) : @"<nil>",
              manual ? NSStringFromClass(manual.class) : @"<nil>",
              DI24Filter());
    } else if (glass.superview != host) {
        [glass removeFromSuperview];
        NSUInteger index = [host.subviews indexOfObject:background];
        if (index == NSNotFound) index = 0;
        [host insertSubview:glass atIndex:index];
    }

    DI24SyncGlass(glass, background, host);
    return glass;
}

static void DI24Restore(CCSystemApertureBackgroundDriver *driver) {
    if (!driver) return;

    LGLiveBackdropView *glass = objc_getAssociatedObject(driver, kDI24GlassKey);
    if (glass) [glass removeFromSuperview];

    CALayer *backdrop = objc_getAssociatedObject(driver, kDI24NativeBackdropKey);
    UIView *frosted = objc_getAssociatedObject(driver, kDI24NativeFrostKey);
    UIImageView *manual = objc_getAssociatedObject(driver, kDI24NativeManualKey);

    @try {
        if (backdrop) {
            backdrop.hidden = NO;
            backdrop.opacity = 1.0;
        }
    } @catch (__unused NSException *e) {}
    @try {
        if (frosted) {
            frosted.hidden = NO;
            frosted.alpha = 1.0;
        }
    } @catch (__unused NSException *e) {}
    @try {
        if (manual) {
            manual.hidden = NO;
            manual.alpha = 1.0;
        }
    } @catch (__unused NSException *e) {}

    objc_setAssociatedObject(driver, kDI24GlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(driver, kDI24NativeBackdropKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(driver, kDI24NativeFrostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(driver, kDI24NativeManualKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Liquidify-style native background driver hook

%hook CCSystemApertureBackgroundDriver

- (instancetype)initWithContainerView:(UIView *)containerView {
    self = %orig(containerView);
    if (self && DI24Enabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { DI24Install(self); }
            @catch (NSException *e) {
                NSLog(@"[SBLiquidGlass-DI-Test24] init exception: %@", e);
            }
        });
    }
    return self;
}

- (void)setBackgroundView:(UIView *)backgroundView {
    %orig(backgroundView);
    if (!DI24Enabled()) {
        DI24Restore(self);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { DI24Install(self); }
        @catch (NSException *e) {
            NSLog(@"[SBLiquidGlass-DI-Test24] setBackgroundView exception: %@", e);
        }
    });
}

- (void)setContainerView:(UIView *)containerView {
    %orig(containerView);
    if (!DI24Enabled()) {
        DI24Restore(self);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { DI24Install(self); } @catch (__unused NSException *e) {}
    });
}

- (void)setClipHostView:(UIView *)clipHostView {
    %orig(clipHostView);
    if (!DI24Enabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { DI24Install(self); } @catch (__unused NSException *e) {}
    });
}

%end

#pragma mark - Keep geometry synchronized with native aperture animation

%hook SBSystemApertureContainerView

- (void)layoutSubviews {
    %orig;
    if (!self.window || !DI24Enabled()) return;
    // The background driver owns the glass geometry. Do not touch
    // window.alpha or native content here.
}

%end

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test24] loaded; native driver/backdrop integration enabled");
}
