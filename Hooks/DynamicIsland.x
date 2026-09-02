// SBLiquidGlass Test28
// Fix Test27: NEVER walk to an Aperture/full-screen ancestor.
// Install the glass only inside Apple's SBSystemApertureContainerView.
// Hooking every container instance lets compact/expanded left+right
// Dynamic Island regions get their own correctly-sized glass surface.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"

@interface SBSystemApertureContainerView : UIView
@end

static const void *kLGDIGlassKey = &kLGDIGlassKey;

static void LGDIUpdateGlass(SBSystemApertureContainerView *container) {
    if (!container || !container.window) return;
    if (!lgHostEnabled(@"DynamicIsland")) return;

    CGRect bounds = container.bounds;
    if (CGRectIsEmpty(bounds) || bounds.size.width < 2.0 || bounds.size.height < 2.0) return;

    @try {
        LGLiveBackdropView *glass =
            objc_getAssociatedObject(container, kLGDIGlassKey);

        if (!glass) {
            NSString *filterType =
                LGFilterTypeForHostPrefix(@"dylv.liquidglass.dynamicisland");

            glass = [[LGLiveBackdropView alloc]
                     initWithFrame:bounds
                     groupName:@"dylv.liquidglass.dynamicisland"
                     filterType:filterType];

            glass.userInteractionEnabled = NO;
            glass.layer.cornerCurve = kCACornerCurveContinuous;
            glass.layer.masksToBounds = YES;

            // Do not change the container/window alpha or background.
            // Do not touch any native content views.
            [container insertSubview:glass atIndex:0];

            objc_setAssociatedObject(container,
                                     kLGDIGlassKey,
                                     glass,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        glass.frame = bounds;

        CGFloat radius = MIN(CGRectGetWidth(bounds),
                             CGRectGetHeight(bounds)) * 0.5;
        glass.layer.cornerRadius = MAX(0.0, radius);
        glass.hidden = NO;

        [glass applyFilters];
    }
    @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-Test28] exception: %@", e);
    }
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    LGDIUpdateGlass(self);
}

- (void)layoutSubviews {
    %orig;
    LGDIUpdateGlass(self);
}

%end

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test28] Native container-only glass enabled");
}
