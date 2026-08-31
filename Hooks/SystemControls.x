#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 系统开关/滑条全局液态玻璃：在全系统所有 UISwitch / UISlider 上叠加玻璃背景。
// 注意：这是 UIKit 级 hook，会影响所有进程（SpringBoard 内的设置、控制中心等）。

static void *kSystemSwitchGlassKey = &kSystemSwitchGlassKey;
static void *kSystemSliderGlassKey = &kSystemSliderGlassKey;

static CGFloat lgPrefFloat(NSString *key, CGFloat fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v floatValue];
    return fallback;
}

#pragma mark - UISwitch

@interface UISwitch (LGGlass)
@end

@implementation UISwitch (LGGlass)

- (void)lg_switchDidMoveToWindow {
    [self lg_switchDidMoveToWindow]; // call original
    if (!lgHostEnabled(@"SystemSwitch")) return;

    LGLiveBackdropView *glass = objc_getAssociatedObject(self, kSystemSwitchGlassKey);
    if (!glass) {
        glass = [[LGLiveBackdropView alloc] initWithFrame:self.bounds];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.layer.cornerRadius = 16.0;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
        glass.userInteractionEnabled = NO;
        [self insertSubview:glass atIndex:0];
        objc_setAssociatedObject(self, kSystemSwitchGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lgTrackGlass(glass, @"SystemSwitch", self);
    }
    glass.frame = self.bounds;
    glass.hidden = !lgHostEnabled(@"SystemSwitch");
    glass.alpha = lgPrefFloat(@"SystemSwitch.Opacity", 0.7);
}

- (void)lg_switchLayoutSubviews {
    [self lg_switchLayoutSubviews];
    LGLiveBackdropView *glass = objc_getAssociatedObject(self, kSystemSwitchGlassKey);
    if (glass) {
        glass.frame = self.bounds;
    }
}

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [UISwitch class];
        Method orig1 = class_getInstanceMethod(cls, @selector(didMoveToWindow));
        Method new1 = class_getInstanceMethod(cls, @selector(lg_switchDidMoveToWindow));
        if (orig1 && new1) method_exchangeImplementations(orig1, new1);

        Method orig2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
        Method new2 = class_getInstanceMethod(cls, @selector(lg_switchLayoutSubviews));
        if (orig2 && new2) method_exchangeImplementations(orig2, new2);
    });
}

@end

#pragma mark - UISlider

@interface UISlider (LGGlass)
@end

@implementation UISlider (LGGlass)

- (void)lg_sliderDidMoveToWindow {
    [self lg_sliderDidMoveToWindow];
    if (!lgHostEnabled(@"SystemSlider")) return;

    LGLiveBackdropView *glass = objc_getAssociatedObject(self, kSystemSliderGlassKey);
    if (!glass) {
        // 滑条的玻璃背景放在 track 区域
        CGFloat trackHeight = 4.0;
        CGRect trackFrame = CGRectMake(0, (self.bounds.size.height - trackHeight) / 2.0,
                                        self.bounds.size.width, trackHeight);
        glass = [[LGLiveBackdropView alloc] initWithFrame:trackFrame];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        glass.layer.cornerRadius = trackHeight / 2.0;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = YES;
        glass.userInteractionEnabled = NO;
        [self insertSubview:glass atIndex:0];
        objc_setAssociatedObject(self, kSystemSliderGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lgTrackGlass(glass, @"SystemSlider", self);
    }
    CGFloat trackHeight = 4.0;
    glass.frame = CGRectMake(0, (self.bounds.size.height - trackHeight) / 2.0,
                              self.bounds.size.width, trackHeight);
    glass.hidden = !lgHostEnabled(@"SystemSlider");
    glass.alpha = lgPrefFloat(@"SystemSlider.Opacity", 0.6);
}

- (void)lg_sliderLayoutSubviews {
    [self lg_sliderLayoutSubviews];
    LGLiveBackdropView *glass = objc_getAssociatedObject(self, kSystemSliderGlassKey);
    if (glass) {
        CGFloat trackHeight = 4.0;
        glass.frame = CGRectMake(0, (self.bounds.size.height - trackHeight) / 2.0,
                                  self.bounds.size.width, trackHeight);
    }
}

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [UISlider class];
        Method orig1 = class_getInstanceMethod(cls, @selector(didMoveToWindow));
        Method new1 = class_getInstanceMethod(cls, @selector(lg_sliderDidMoveToWindow));
        if (orig1 && new1) method_exchangeImplementations(orig1, new1);

        Method orig2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
        Method new2 = class_getInstanceMethod(cls, @selector(lg_sliderLayoutSubviews));
        if (orig2 && new2) method_exchangeImplementations(orig2, new2);
    });
}

@end
