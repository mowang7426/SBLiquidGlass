// SBLiquidGlass Test27
// Fix Test26 crash: no dispatch_async from the Dynamic Island hook.
// The glass is attached to the nearest broader Aperture ancestor so
// expanded Dynamic Island states can cover both left and right sides.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"

@interface SBSystemApertureContainerView : UIView
@end

static const void *kLGDIGlassKey = &kLGDIGlassKey;

static UIView *LGDIFindGlassHost(SBSystemApertureContainerView *container) {
    UIView *candidate = container;
    UIView *best = container;

    // Walk upward, preferring an Aperture-named ancestor that is wider
    // than the current container. This is intended to catch the host
    // that contains both sides of the expanded Dynamic Island.
    for (NSInteger i = 0; i < 6 && candidate.superview; i++) {
        candidate = candidate.superview;
        NSString *name = NSStringFromClass(candidate.class);
        if ([name rangeOfString:@"Aperture" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            if (candidate.bounds.size.width >= container.bounds.size.width &&
                candidate.bounds.size.height >= container.bounds.size.height) {
                best = candidate;
            }
        }
    }

    return best;
}

static void LGDIUpdateGlass(SBSystemApertureContainerView *container) {
    if (!container.window || !lgHostEnabled(@"DynamicIsland")) return;

    UIView *host = LGDIFindGlassHost(container);
    if (!host) return;

    LGLiveBackdropView *glass =
        objc_getAssociatedObject(host, kLGDIGlassKey);

    if (!glass) {
        NSString *filterType =
            LGFilterTypeForHostPrefix(@"dylv.liquidglass.dynamicisland");

        glass = [[LGLiveBackdropView alloc]
                 initWithFrame:host.bounds
                 groupName:@"dylv.liquidglass.dynamicisland"
                 filterType:filterType];

        glass.userInteractionEnabled = NO;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;

        // Native Dynamic Island content stays untouched above the glass.
        [host insertSubview:glass atIndex:0];

        objc_setAssociatedObject(host,
                                 kLGDIGlassKey,
                                 glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    glass.frame = host.bounds;

    // Dynamic Island's native aperture is pill-like in compact mode and
    // becomes a larger rounded surface when expanded.
    CGFloat radius = MIN(CGRectGetWidth(host.bounds),
                         CGRectGetHeight(host.bounds)) * 0.5;
    glass.layer.cornerRadius = MAX(0.0, radius);

    glass.hidden = NO;
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        LGDIUpdateGlass(self);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-Test27] didMove exception: %@", e);
    }
}

- (void)layoutSubviews {
    %orig;
    @try {
        LGDIUpdateGlass(self);
    } @catch (__unused NSException *e) {}
}

%end
