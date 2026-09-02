// Native Dynamic Island - Background Driver integration (Test23)
// IMPORTANT: ONLY replace Hooks/DynamicIsland.x
//
// Test22 hid the driver's entire backgroundView. That was too aggressive:
// native aperture content (including the right-side activity/icon surface)
// can live in or below that view. Test23 keeps the native backgroundView and
// its content alive, but removes only its opaque visual material/backdrop and
// puts SBLiquidGlass behind the native content.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
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
- (UIView *)frostedBackdropView;
- (UIImageView *)manualBackdropView;
@end

static const void *kDI23GlassKey = &kDI23GlassKey;

static BOOL DI23Enabled(void) {
    @try { return lgHostEnabled(@"DynamicIsland"); }
    @catch (__unused NSException *e) { return NO; }
}

static NSString *DI23Filter(void) {
    @try {
        NSString *s = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (s.length) return s;
    } @catch (__unused NSException *e) {}
    return @"dylv.liquidglass.dynamicisland";
}

static void DI23ClearPaint(UIView *v) {
    if (!v) return;
    @try {
        v.backgroundColor = UIColor.clearColor;
        v.opaque = NO;
        v.layer.backgroundColor = UIColor.clearColor.CGColor;
    } @catch (__unused NSException *e) {}
}

static void DI23ClearMaterialChildren(UIView *v) {
    if (!v) return;
    for (UIView *sub in [v.subviews copy]) {
        NSString *n = NSStringFromClass(sub.class);
        BOOL visualEffect = [sub isKindOfClass:NSClassFromString(@"UIVisualEffectView")];
        BOOL namedMaterial = ([n rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                              [n rangeOfString:@"Material" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                              [n rangeOfString:@"Frost" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                              [n rangeOfString:@"Platter" options:NSCaseInsensitiveSearch].location != NSNotFound);
        if (visualEffect) {
            @try {
                [(UIVisualEffectView *)sub setEffect:nil];
                sub.backgroundColor = UIColor.clearColor;
                sub.opaque = NO;
                sub.layer.backgroundColor = UIColor.clearColor.CGColor;
            } @catch (__unused NSException *e) {}
        } else if (namedMaterial) {
            DI23ClearPaint(sub);
        }
        DI23ClearMaterialChildren(sub);
    }
}

static void DI23Sync(UIView *host, LGLiveBackdropView *glass) {
    if (!host || !glass) return;
    CGRect b = host.bounds;
    if (CGRectIsEmpty(b)) return;
    glass.frame = b;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.backgroundColor = UIColor.clearColor;
    glass.alpha = 1.0;
    glass.hidden = NO;
    glass.userInteractionEnabled = NO;
    CGFloat r = host.layer.cornerRadius;
    if (r <= 0.0) r = MIN(CGRectGetWidth(b), CGRectGetHeight(b)) * 0.5;
    glass.layer.cornerRadius = r;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
}

static LGLiveBackdropView *DI23Install(CCSystemApertureBackgroundDriver *driver) {
    if (!driver || !DI23Enabled()) return nil;

    UIView *container = driver.containerView;
    UIView *background = driver.backgroundView;
    UIView *clip = driver.clipHostView;
    if (!container || !background) return nil;

    // We only accept the native aperture tree. Never touch unrelated views.
    BOOL native = NO;
    for (UIView *v = background; v; v = v.superview) {
        if ([NSStringFromClass(v.class) isEqualToString:@"SBSystemApertureContainerView"]) {
            native = YES; break;
        }
    }
    if (!native) return nil;

    // Preserve the native backgroundView itself. Only neutralize the paint
    // supplied by its material/backdrop children.
    DI23ClearPaint(background);
    DI23ClearMaterialChildren(background);

    // Liquidify exposes these exact driver-owned objects. Hide only the
    // frosted/manual backdrop objects, never the whole backgroundView.
    @try {
        UIView *frosted = [driver frostedBackdropView];
        if (frosted) {
            frosted.hidden = YES;
            frosted.alpha = 0.0;
        }
    } @catch (__unused NSException *e) {}
    @try {
        UIImageView *manual = [driver manualBackdropView];
        if (manual) {
            manual.hidden = YES;
            manual.alpha = 0.0;
        }
    } @catch (__unused NSException *e) {}

    LGLiveBackdropView *glass = objc_getAssociatedObject(driver, kDI23GlassKey);
    if (!glass) {
        // Put the glass directly into the driver's backgroundView. This keeps
        // it in the driver's clipping/compositing domain instead of the
        // aperture container's general content stack.
        glass = [[LGLiveBackdropView alloc] initWithFrame:background.bounds
                                                 groupName:nil
                                                filterType:DI23Filter()];
        glass.backgroundColor = UIColor.clearColor;
        glass.userInteractionEnabled = NO;
        glass.layer.zPosition = -1000.0;
        [background insertSubview:glass atIndex:0];
        objc_setAssociatedObject(driver, kDI23GlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        NSLog(@"[SBLiquidGlass-DI-Test23] driver=%@ background=%@ clip=%@ glass installed filter=%@",
              NSStringFromClass(driver.class), NSStringFromClass(background.class),
              clip ? NSStringFromClass(clip.class) : @"<nil>", DI23Filter());
    } else if (glass.superview != background) {
        [glass removeFromSuperview];
        [background insertSubview:glass atIndex:0];
    }

    DI23Sync(background, glass);
    return glass;
}

static void DI23Restore(CCSystemApertureBackgroundDriver *driver) {
    LGLiveBackdropView *glass = objc_getAssociatedObject(driver, kDI23GlassKey);
    if (glass) [glass removeFromSuperview];
    objc_setAssociatedObject(driver, kDI23GlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook CCSystemApertureBackgroundDriver

- (instancetype)initWithContainerView:(UIView *)containerView {
    self = %orig(containerView);
    if (self && DI23Enabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { DI23Install(self); } @catch (NSException *e) {
                NSLog(@"[SBLiquidGlass-DI-Test23] init exception: %@", e);
            }
        });
    }
    return self;
}

- (void)setBackgroundView:(UIView *)backgroundView {
    %orig(backgroundView);
    if (!DI23Enabled()) { DI23Restore(self); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { DI23Install(self); } @catch (NSException *e) {
            NSLog(@"[SBLiquidGlass-DI-Test23] setBackgroundView exception: %@", e);
        }
    });
}

- (void)setContainerView:(UIView *)containerView {
    %orig(containerView);
    if (!DI23Enabled()) { DI23Restore(self); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { DI23Install(self); } @catch (__unused NSException *e) {}
    });
}

- (void)setClipHostView:(UIView *)clipHostView {
    %orig(clipHostView);
    if (!DI23Enabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { DI23Install(self); } @catch (__unused NSException *e) {}
    });
}

%end

%hook SBSystemApertureContainerView

- (void)layoutSubviews {
    %orig;
    if (!self.window || !DI23Enabled()) return;
    for (UIView *sub in [self.subviews copy]) {
        if ([sub isKindOfClass:NSClassFromString(@"LGLiveBackdropView")])
            DI23Sync(self, (LGLiveBackdropView *)sub);
    }
}

%end
