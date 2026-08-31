#import <UIKit/UIKit.h>
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 系统开关/滑条全局玻璃：在全系统所有 UISwitch / UISlider 上叠加玻璃背景。
// 使用 UIVisualEffectView + UIBlurEffect（UIKit 标准 API），避免 CABackdropLayer 私有类在非标准环境中崩溃。

static void *kSystemSwitchGlassKey = &kSystemSwitchGlassKey;
static void *kSystemSliderGlassKey = &kSystemSliderGlassKey;

static CGFloat lgPrefFloat(NSString *key, CGFloat fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v floatValue];
    return fallback;
}

static UIVisualEffectView *lgMakeBlurView(CGRect frame, CGFloat cornerRadius) {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = frame;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.layer.cornerRadius = cornerRadius;
    blurView.layer.cornerCurve = kCACornerCurveContinuous;
    blurView.clipsToBounds = YES;
    blurView.userInteractionEnabled = NO;
    return blurView;
}

#pragma mark - UISwitch

@interface UISwitch (LGGlass)
@end

@implementation UISwitch (LGGlass)

- (void)lg_switchDidMoveToWindow {
    [self lg_switchDidMoveToWindow]; // call original
    if (!lgHostEnabled(@"SystemSwitch")) return;

    UIVisualEffectView *blurView = objc_getAssociatedObject(self, kSystemSwitchGlassKey);
    if (!blurView) {
        blurView = lgMakeBlurView(self.bounds, 16.0);
        [self insertSubview:blurView atIndex:0];
        objc_setAssociatedObject(self, kSystemSwitchGlassKey, blurView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    blurView.frame = self.bounds;
    blurView.hidden = !lgHostEnabled(@"SystemSwitch");
    blurView.alpha = lgPrefFloat(@"SystemSwitch.Opacity", 0.7);
}

- (void)lg_switchLayoutSubviews {
    [self lg_switchLayoutSubviews];
    UIVisualEffectView *blurView = objc_getAssociatedObject(self, kSystemSwitchGlassKey);
    if (blurView) {
        blurView.frame = self.bounds;
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

    UIVisualEffectView *blurView = objc_getAssociatedObject(self, kSystemSliderGlassKey);
    if (!blurView) {
        CGFloat trackHeight = 4.0;
        CGRect trackFrame = CGRectMake(0, (self.bounds.size.height - trackHeight) / 2.0,
                                        self.bounds.size.width, trackHeight);
        blurView = lgMakeBlurView(trackFrame, trackHeight / 2.0);
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [self insertSubview:blurView atIndex:0];
        objc_setAssociatedObject(self, kSystemSliderGlassKey, blurView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat trackHeight = 4.0;
    blurView.frame = CGRectMake(0, (self.bounds.size.height - trackHeight) / 2.0,
                              self.bounds.size.width, trackHeight);
    blurView.hidden = !lgHostEnabled(@"SystemSlider");
    blurView.alpha = lgPrefFloat(@"SystemSlider.Opacity", 0.6);
}

- (void)lg_sliderLayoutSubviews {
    [self lg_sliderLayoutSubviews];
    UIVisualEffectView *blurView = objc_getAssociatedObject(self, kSystemSliderGlassKey);
    if (blurView) {
        CGFloat trackHeight = 4.0;
        blurView.frame = CGRectMake(0, (self.bounds.size.height - trackHeight) / 2.0,
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
