#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// Native Dynamic Island: the black platter is NOT the outer
// SBSystemApertureContainerView.  Apple keeps it in
// _SBSystemApertureContainerViewContentView / SBFTouchPassThroughView.
// This test hooks those real content/background nodes and puts our glass
// behind Apple's content instead of merely stacking glass on top of black.

@interface SBSystemApertureContainerView : UIView
@end

@interface _SBSystemApertureContainerViewContentView : UIView
@end

@interface SBFTouchPassThroughView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;

static BOOL diIsInsideNativeAperture(UIView *view) {
    UIView *p = view;
    for (NSInteger i = 0; p && i < 8; i++, p = p.superview) {
        NSString *name = NSStringFromClass(p.class);
        if ([name isEqualToString:@"SBSystemApertureContainerView"] ||
            [name isEqualToString:@"_SBSystemApertureContainerViewContentView"])
            return YES;
    }
    return NO;
}

static void diMakeNativeContentTransparent(UIView *view) {
    if (!view) return;
    @try {
        // This is the actual native Dynamic Island content/background view.
        view.backgroundColor = UIColor.clearColor;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
        view.opaque = NO;

        // Do not touch the content subviews here. Apple owns their layout.
    } @catch (__unused NSException *e) {}
}

static void diSyncNativeGlass(UIView *host, LGLiveBackdropView *glass) {
    if (!host || !glass) return;

    glass.frame = host.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    glass.backgroundColor = UIColor.clearColor;
    glass.alpha = 1.0;

    CGFloat radius = host.layer.cornerRadius;
    if (radius <= 0.0)
        radius = MIN(CGRectGetWidth(host.bounds),
                     CGRectGetHeight(host.bounds)) * 0.5;

    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
}

static void diApplyNativeGlass(_SBSystemApertureContainerViewContentView *host) {
    @try {
        if (!host || !host.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(host.bounds) || CGRectGetWidth(host.bounds) < 10.0) return;

        // CRITICAL: remove Apple's opaque black content background first.
        diMakeNativeContentTransparent(host);

        LGLiveBackdropView *glass = objc_getAssociatedObject(host, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length)
                filterType = @"dylv.liquidglass.dynamicisland";

            glass = [[LGLiveBackdropView alloc] initWithFrame:host.bounds
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.alpha = 1.0;

            // Glass is the FIRST layer in the real content view.
            // Apple's text/buttons remain above it.
            [host insertSubview:glass atIndex:0];

            objc_setAssociatedObject(host, kDIGlassKey, glass,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}

            NSLog(@"[SBLiquidGlass-DI-NativeTest3] glass attached to CONTENT %@ filter=%@",
                  NSStringFromClass(host.class), filterType);
        }

        diSyncNativeGlass(host, glass);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-NativeTest3] exception: %@", e);
    }
}

static void diRemoveNativeGlass(_SBSystemApertureContainerViewContentView *host) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(host, kDIGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(host, kDIGlassKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Native Dynamic Island root

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    // The content view is created/attached by Apple after the outer root.
    for (UIView *sub in [self.subviews copy]) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_SBSystemApertureContainerViewContentView"]) {
            diApplyNativeGlass((_SBSystemApertureContainerViewContentView *)sub);
        }
    }
}

- (void)layoutSubviews {
    %orig;

    for (UIView *sub in [self.subviews copy]) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"_SBSystemApertureContainerViewContentView"]) {
            diApplyNativeGlass((_SBSystemApertureContainerViewContentView *)sub);
        }
    }
}

%end

#pragma mark - Real native black platter/content view

%hook _SBSystemApertureContainerViewContentView

- (void)didMoveToWindow {
    %orig;
    if (self.window) diApplyNativeGlass(self);
    else diRemoveNativeGlass(self);
}

- (void)layoutSubviews {
    %orig;
    diApplyNativeGlass(self);
}

- (void)setBackgroundColor:(UIColor *)color {
    // Apple may rewrite the black background during every state transition.
    // Keep this private content view transparent while preserving the setter
    // for all other behavior.
    if (self.window && diIsInsideNativeAperture(self)) {
        %orig(UIColor.clearColor);
    } else {
        %orig(color);
    }
}

%end

#pragma mark - Native platter alpha node

%hook SBFTouchPassThroughView

- (void)layoutSubviews {
    %orig;

    // VisibleIsland's research found the native aperture background/alpha
    // node at subviews[2].  Scope it strictly to the Dynamic Island so this
    // hook cannot alter unrelated SBFTouchPassThroughView instances.
    if (!diIsInsideNativeAperture(self)) return;
    if (self.subviews.count < 3) return;

    @try {
        UIView *nativePlatter = self.subviews[2];
        if (nativePlatter != objc_getAssociatedObject(self, kDIGlassKey)) {
            nativePlatter.backgroundColor = UIColor.clearColor;
            nativePlatter.layer.backgroundColor = UIColor.clearColor.CGColor;
            nativePlatter.alpha = 0.0;
        }
    } @catch (__unused NSException *e) {}
}

%end
