#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;
static void *kDILoggedKey = &kDILoggedKey;

static BOOL diNameLooksLikeBackground(NSString *name) {
    if (!name.length) return NO;
    NSString *n = name.lowercaseString;
    return [n containsString:@"background"] ||
           [n containsString:@"backdrop"] ||
           [n containsString:@"material"] ||
           [n containsString:@"visualeffect"] ||
           [n containsString:@"uibackdrop"] ||
           [n containsString:@"platter"] ||
           [n containsString:@"backgroundview"];
}

static BOOL diColorLooksOpaqueBlack(CGColorRef color) {
    if (!color) return NO;
    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (!c) return NO;

    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (count >= 4) {
        r = c[0]; g = c[1]; b = c[2]; a = c[3];
    } else if (count == 2) {
        r = g = b = c[0]; a = c[1];
    } else {
        return NO;
    }
    return a > 0.80 && r < 0.12 && g < 0.12 && b < 0.12;
}

static void diLogLayerTree(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 8) return;
    NSString *indent = @"";
    for (NSInteger i = 0; i < depth; i++) indent = [indent stringByAppendingString:@"  "];

    NSString *name = layer.name ?: @"-";
    NSString *delegate = layer.delegate ? NSStringFromClass([layer.delegate class]) : @"-";
    NSString *filters = layer.filters.count ? [NSString stringWithFormat:@" filters=%lu", (unsigned long)layer.filters.count] : @"";
    NSString *bg = layer.backgroundColor ? [NSString stringWithFormat:@" bg=%@", layer.backgroundColor] : @"";
    NSLog(@"[SBLiquidGlass-DI-NativeTest2] %@%@ name=%@ delegate=%@ opacity=%.2f hidden=%d%@%@",
          indent, NSStringFromClass(layer.class), name, delegate,
          layer.opacity, layer.hidden, bg, filters);

    for (CALayer *sub in [layer.sublayers copy]) {
        diLogLayerTree(sub, depth + 1);
    }
}

// Neutralize Apple's opaque material/background without touching normal content.
static void diNeutralizeNativeBackgrounds(UIView *view, NSInteger depth) {
    if (!view || depth > 10) return;

    @try {
        NSString *cls = NSStringFromClass(view.class);
        BOOL namedBackground = diNameLooksLikeBackground(cls);
        BOOL isEffect = [view isKindOfClass:[UIVisualEffectView class]];

        if (isEffect) {
            UIVisualEffectView *effectView = (UIVisualEffectView *)view;
            // Apple Dynamic Island's own material is no longer needed; our
            // LGLiveBackdropView supplies the replacement glass.
            effectView.effect = nil;
            effectView.backgroundColor = UIColor.clearColor;
            effectView.layer.backgroundColor = UIColor.clearColor.CGColor;
            effectView.layer.filters = nil;
            NSLog(@"[SBLiquidGlass-DI-NativeTest2] disabled UIVisualEffectView %@", cls);
        } else if (namedBackground) {
            view.backgroundColor = UIColor.clearColor;
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
            view.layer.filters = nil;
            NSLog(@"[SBLiquidGlass-DI-NativeTest2] cleared background view %@", cls);
        }

        // The native island can draw its black platter directly from CALayer.
        // Only clear layers that are actually solid/near-solid black.
        if (diColorLooksOpaqueBlack(view.layer.backgroundColor)) {
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
        }

        for (CALayer *layer in [view.layer.sublayers copy]) {
            if (diColorLooksOpaqueBlack(layer.backgroundColor)) {
                layer.backgroundColor = UIColor.clearColor.CGColor;
            }
            // A private backdrop/material layer may expose a CAFilter rather
            // than a normal view. Remove filters only from clearly named
            // background/material nodes.
            if (namedBackground) layer.filters = nil;
        }

        for (UIView *sub in [view.subviews copy]) {
            diNeutralizeNativeBackgrounds(sub, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

static void diSyncGlass(UIView *view, LGLiveBackdropView *glass) {
    if (!view || !glass) return;
    glass.frame = view.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;

    CGFloat radius = view.layer.cornerRadius;
    if (radius <= 0.0)
        radius = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5;

    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
}

static void diApplyNativeGlass(SBSystemApertureContainerView *view) {
    @try {
        if (!view || !view.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10.0) return;

        if (!objc_getAssociatedObject(view, kDILoggedKey)) {
            objc_setAssociatedObject(view, kDILoggedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[SBLiquidGlass-DI-NativeTest2] ROOT %@ bounds=%@ subviews=%lu",
                  NSStringFromClass(view.class), NSStringFromCGRect(view.bounds),
                  (unsigned long)view.subviews.count);
            diLogLayerTree(view.layer, 0);
        }

        diNeutralizeNativeBackgrounds(view, 0);

        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";

            glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.alpha = 1.0;
            [view insertSubview:glass atIndex:0];
            objc_setAssociatedObject(view, kDIGlassKey, glass,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            NSLog(@"[SBLiquidGlass-DI-NativeTest2] glass attached filter=%@", filterType);
        }

        diSyncGlass(view, glass);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-NativeTest2] exception: %@", e);
    }
}

static void diRemoveNativeGlass(SBSystemApertureContainerView *view) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(view, kDILoggedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {}
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    if (self.window) diApplyNativeGlass(self);
    else diRemoveNativeGlass(self);
}

- (void)layoutSubviews {
    %orig;
    diApplyNativeGlass(self);
}

%end
