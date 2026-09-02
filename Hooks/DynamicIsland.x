// SBLiquidGlass Test26
// Native Dynamic Island: install the existing Liquid Glass engine as a
// dedicated background layer, while leaving Apple's native content untouched.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"

@interface SBSystemApertureContainerView : UIView
@end

static const void *kLGDynamicIslandGlassKey = &kLGDynamicIslandGlassKey;

static void LGDIInstallGlass(SBSystemApertureContainerView *container) {
    if (!container.window || !lgHostEnabled(@"DynamicIsland")) return;

    @try {
        LGLiveBackdropView *glass =
            objc_getAssociatedObject(container, kLGDynamicIslandGlassKey);

        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"dylv.liquidglass.dynamicisland");

            glass = [[LGLiveBackdropView alloc]
                     initWithFrame:container.bounds
                     groupName:@"dylv.liquidglass.dynamicisland"
                     filterType:filterType];

            glass.userInteractionEnabled = NO;
            glass.layer.cornerCurve = kCACornerCurveContinuous;
            glass.layer.masksToBounds = YES;

            objc_setAssociatedObject(container,
                                     kLGDynamicIslandGlassKey,
                                     glass,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            // Put glass behind Apple's native Dynamic Island content.
            [container insertSubview:glass atIndex:0];
        }

        glass.frame = container.bounds;

        // Match the native aperture's current shape.
        CGFloat radius = MIN(CGRectGetWidth(container.bounds),
                             CGRectGetHeight(container.bounds)) * 0.5;
        if (radius > 0.0) {
            glass.layer.cornerRadius = radius;
        }

        // Only remove a background painted directly by the container itself.
        // Do NOT hide/remove any native content subviews.
        container.backgroundColor = UIColor.clearColor;
        container.layer.backgroundColor = UIColor.clearColor.CGColor;

        [glass applyFilters];
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI-Test26] install exception: %@", e);
    }
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        LGDIInstallGlass(self);
    });
}

- (void)layoutSubviews {
    %orig;
    LGDIInstallGlass(self);
}

%end
