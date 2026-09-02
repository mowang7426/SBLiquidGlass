#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;

// Native Dynamic Island only.
// Test1 goal: keep Apple's content untouched, remove only obvious native
// background/material layers, and put our backdrop in the native container.
static BOOL diLooksLikeNativeBackground(NSString *name) {
    if (!name.length) return NO;
    NSString *n = name.lowercaseString;
    return [n containsString:@"background"] ||
           [n containsString:@"backdrop"] ||
           [n containsString:@"material"] ||
           [n containsString:@"platter"] ||
           [n containsString:@"visualeffect"] ||
           [n containsString:@"_uibackdrop"];
}

static void diClearNativeBackgrounds(UIView *view, NSInteger depth) {
    if (!view || depth > 10) return;

    @try {
        NSString *cls = NSStringFromClass(view.class);
        BOOL obvious = diLooksLikeNativeBackground(cls);

        if (obvious) {
            view.backgroundColor = UIColor.clearColor;
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
            // Do not hide the view: Apple may use it for geometry or clipping.
            // We only neutralize its explicit solid fill.
            for (CALayer *layer in [view.layer.sublayers copy]) {
                if (layer.backgroundColor) {
                    layer.backgroundColor = UIColor.clearColor.CGColor;
                }
            }
        }

        for (UIView *sub in [view.subviews copy]) {
            diClearNativeBackgrounds(sub, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

static void diSyncNativeGlass(UIView *view, LGLiveBackdropView *glass) {
    if (!view || !glass) return;
    glass.frame = view.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;

    CGFloat radius = view.layer.cornerRadius;
    if (radius <= 0.0) {
        radius = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5;
    }
    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
}

static void diApplyNativeGlass(SBSystemApertureContainerView *view) {
    @try {
        if (!view || !view.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10.0) return;

        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            diSyncNativeGlass(view, glass);
            diClearNativeBackgrounds(view, 0);
            return;
        }

        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";

        glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds
                                                 groupName:nil
                                                filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;
        glass.backgroundColor = UIColor.clearColor;
        glass.alpha = 1.0;

        diClearNativeBackgrounds(view, 0);

        // Keep the glass behind Apple's Dynamic Island content.
        [view insertSubview:glass atIndex:0];
        diSyncNativeGlass(view, glass);

        objc_setAssociatedObject(view, kDIGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}

        NSLog(@"[SBLiquidGlass-DI-NativeTest1] attached to %@ bounds=%@",
              NSStringFromClass(view.class), NSStringFromCGRect(view.bounds));
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-NativeTest1] exception: %@", e);
    }
}

static void diRemoveNativeGlass(SBSystemApertureContainerView *view) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (__unused NSException *e) {}
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) diApplyNativeGlass(self);
        else diRemoveNativeGlass(self);
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try { diApplyNativeGlass(self); }
    @catch (__unused NSException *e) {}
}

%end
