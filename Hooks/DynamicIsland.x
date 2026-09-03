// SBLiquidGlass Test32
// Native Dynamic Island: target the real MagiciansCurtainView found by Test31.
// IMPORTANT: this version does NOT touch the full-screen touch-pass-through views.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface _SBSystemApertureMagiciansCurtainView : UIView
@end

static void *kDI32GlassKey = &kDI32GlassKey;

static LGLiveBackdropView *di32GlassForView(UIView *view) {
    return objc_getAssociatedObject(view, kDI32GlassKey);
}

static void di32RemoveGlass(UIView *view) {
    @try {
        LGLiveBackdropView *glass = di32GlassForView(view);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(view, kDI32GlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
}

static void di32EnsureGlass(UIView *view) {
    @try {
        if (!view || !view.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 20.0) return;

        LGLiveBackdropView *glass = di32GlassForView(view);
        CGFloat radius = view.layer.cornerRadius;
        if (radius <= 0.0) radius = CGRectGetHeight(view.bounds) * 0.5;

        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";

            glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds
                                                     groupName:nil
                                                    filterType:filterType];
            glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight;
            glass.userInteractionEnabled = NO;
            glass.backgroundColor = UIColor.clearColor;
            glass.opaque = NO;
            glass.alpha = 1.0;
            glass.layer.cornerCurve = kCACornerCurveContinuous;
            glass.layer.cornerRadius = radius;
            glass.layer.masksToBounds = YES;

            // The real native island is the host. Put our backdrop INSIDE it,
            // underneath the native gain-map/content views, so the system's
            // geometry, animation and hit-testing remain untouched.
            [view insertSubview:glass atIndex:0];
            objc_setAssociatedObject(view, kDI32GlassKey, glass,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            dispatch_async(dispatch_get_main_queue(), ^{
                @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            });
        } else {
            glass.frame = view.bounds;
            glass.layer.cornerRadius = radius;
        }

        // Test31 showed the curtain itself has no backgroundColor, but is
        // marked opaque. Clear that flag so the injected backdrop can show.
        view.backgroundColor = UIColor.clearColor;
        view.opaque = NO;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
        view.layer.cornerRadius = radius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.layer.masksToBounds = YES;

        // Do NOT hide/modify the native black UIView blindly. In Test31 it was
        // already hidden; touching it caused no benefit and risks breaking
        // system aperture state. We only neutralize a visible, exact-size,
        // opaque black sibling when it is clearly a backdrop.
        for (UIView *sub in [view.subviews copy]) {
            if (sub == glass) continue;
            if (!sub.hidden && sub.alpha > 0.99 && sub.opaque &&
                CGRectEqualToRect(sub.bounds, view.bounds) &&
                sub.backgroundColor) {
                CGFloat r=0,g=0,b=0,a=0;
                if ([sub.backgroundColor getRed:&r green:&g blue:&b alpha:&a] &&
                    r < 0.01 && g < 0.01 && b < 0.01 && a > 0.99) {
                    sub.backgroundColor = UIColor.clearColor;
                    sub.opaque = NO;
                    sub.layer.backgroundColor = UIColor.clearColor.CGColor;
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-Test32] exception: %@", e);
    }
}

%hook _SBSystemApertureMagiciansCurtainView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) di32EnsureGlass(self);
        else di32RemoveGlass(self);
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try { di32EnsureGlass(self); } @catch (__unused NSException *e) {}
}

%end

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test32] native MagiciansCurtain glass hook loaded");
}
