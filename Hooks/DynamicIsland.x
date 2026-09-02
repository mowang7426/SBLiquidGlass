#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// Native Dynamic Island Test1.
// IMPORTANT: _SBSystemApertureContainerViewContentView has an internal
// invariant about its child contentView. Never insert our own subview into it.
// The previous Test3 violated that invariant and caused sbsa_onlyObjectOrNilAssert.

@interface SBSystemApertureContainerView : UIView
@end
@interface _SBSystemApertureContainerViewContentView : UIView
@end
@interface SBFTouchPassThroughView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;
static void *kDIContentKey = &kDIContentKey;

static BOOL diIsNativeApertureView(UIView *view) {
    for (UIView *p = view; p; p = p.superview) {
        NSString *n = NSStringFromClass(p.class);
        if ([n isEqualToString:@"SBSystemApertureContainerView"])
            return YES;
    }
    return NO;
}

static void diClearBackgroundOnly(UIView *view) {
    if (!view) return;
    @try {
        view.backgroundColor = UIColor.clearColor;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
        view.opaque = NO;
    } @catch (__unused NSException *e) {}
}

static void diClearRootAndApertureBackgrounds(UIView *root) {
    if (!root) return;

    // Test1: the native aperture ROOT may itself be the opaque black surface
    // that the CABackdropLayer is sampling. Clear only the root and known
    // background/material containers; do not alter Apple's content hierarchy.
    diClearBackgroundOnly(root);

    for (UIView *sub in [root.subviews copy]) {
        NSString *n = NSStringFromClass(sub.class);
        if ([n rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [n rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [n rangeOfString:@"Material" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [n rangeOfString:@"Platter" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [n isEqualToString:@"SBFTouchPassThroughView"]) {
            diClearBackgroundOnly(sub);
        }
    }
}

static void diClearKnownNativeBackgrounds(UIView *view) {
    if (!view) return;
    NSString *n = NSStringFromClass(view.class);

    // Do NOT recursively modify arbitrary Apple subviews. Only target known
    // material/platter/background classes, because Apple's content hierarchy
    // has strict child-count/layout assumptions.
    if ([n rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [n rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [n rangeOfString:@"Material" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [n rangeOfString:@"Platter" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        diClearBackgroundOnly(view);
    }

    for (UIView *sub in [view.subviews copy]) {
        diClearKnownNativeBackgrounds(sub);
    }
}

static void diSyncGlassToContent(UIView *container, UIView *content, LGLiveBackdropView *glass) {
    if (!container || !content || !glass) return;

    // Glass is a SIBLING of Apple's special content view, never its child.
    glass.frame = content.frame;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    glass.backgroundColor = UIColor.clearColor;
    glass.alpha = 1.0;

    CGFloat radius = content.layer.cornerRadius;
    if (radius <= 0.0)
        radius = MIN(CGRectGetWidth(content.bounds), CGRectGetHeight(content.bounds)) * 0.5;
    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
}

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (root.subviews.count == 0) return;

        UIView *content = nil;
        for (UIView *sub in [root.subviews copy]) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"_SBSystemApertureContainerViewContentView"]) {
                content = sub;
                break;
            }
        }
        if (!content || CGRectIsEmpty(content.bounds)) return;

        // Test1: clear the aperture root first. If the root itself is the
        // opaque black surface, the sibling backdrop would otherwise sample
        // that black surface instead of the content behind Dynamic Island.
        diClearRootAndApertureBackgrounds(root);

        // Then clear only the content view's own background and known material
        // descendants. Never insert/remove subviews from Apple's content view.
        diClearBackgroundOnly(content);
        diClearKnownNativeBackgrounds(content);

        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";

            glass = [[LGLiveBackdropView alloc] initWithFrame:content.frame
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.userInteractionEnabled = NO;

            // SIBLING insertion: never touch _SBSystemApertureContainerViewContentView.subviews.
            NSUInteger idx = [root.subviews indexOfObject:content];
            if (idx == NSNotFound) idx = 0;
            [root insertSubview:glass atIndex:idx];

            objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(root, kDIContentKey, content, OBJC_ASSOCIATION_ASSIGN);

            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            NSLog(@"[SBLiquidGlass-DI-NativeTest1] glass sibling attached root=%@ content=%@ filter=%@",
                  NSStringFromClass(root.class), NSStringFromClass(content.class), filterType);
        }

        // Apple may reorder its content view during transitions; always put
        // our glass immediately BELOW it so text/buttons remain untouched.
        if (glass.superview != root) {
            [root insertSubview:glass atIndex:0];
        } else {
            NSUInteger contentIndex = [root.subviews indexOfObject:content];
            if (contentIndex != NSNotFound && [root.subviews indexOfObject:glass] != contentIndex - 1) {
                [root insertSubview:glass atIndex:contentIndex];
            }
        }

        diSyncGlassToContent(root, content, glass);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-NativeTest1] exception: %@", e);
    }
}

static void diRemoveGlass(SBSystemApertureContainerView *root) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (glass) [glass removeFromSuperview];
        objc_setAssociatedObject(root, kDIGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(root, kDIContentKey, nil, OBJC_ASSOCIATION_ASSIGN);
    } @catch (__unused NSException *e) {}
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    if (self.window) diApplyGlassToRoot(self);
    else diRemoveGlass(self);
}

- (void)layoutSubviews {
    %orig;
    if (self.window) diApplyGlassToRoot(self);
}

%end

%hook _SBSystemApertureContainerViewContentView

- (void)didMoveToWindow {
    %orig;
    // Do not add/remove subviews here. This class has an internal contentView invariant.
    if (self.window) {
        diClearBackgroundOnly(self);
        diClearKnownNativeBackgrounds(self);
    }
}

- (void)layoutSubviews {
    %orig;
    if (self.window) {
        diClearBackgroundOnly(self);
        diClearKnownNativeBackgrounds(self);
    }
}

- (void)setBackgroundColor:(UIColor *)color {
    // Safe: preserve Apple's setter and only replace the color value.
    if (self.window && diIsNativeApertureView(self)) %orig(UIColor.clearColor);
    else %orig(color);
}

%end

%hook SBFTouchPassThroughView

- (void)layoutSubviews {
    %orig;
    if (!diIsNativeApertureView(self)) return;

    // The pass-through container can itself carry the opaque surface.
    diClearBackgroundOnly(self);

    // Only clear the known platter/background node; NEVER set alpha on the
    // whole touch-pass-through hierarchy, since it may contain live content.
    for (UIView *sub in [self.subviews copy]) {
        NSString *n = NSStringFromClass(sub.class);
        if ([n rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [n rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [n rangeOfString:@"Platter" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [n rangeOfString:@"Material" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            diClearBackgroundOnly(sub);
        }
    }
}

%end
