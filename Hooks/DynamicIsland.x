// Dynamic Island Native Test10 - 激进清除背景视图版
// 直接隐藏 _UILumaTrackingBackdropView、_SBAdaptiveKeyLineBackdropView、MTMaterialView
// 这些视图里的 CABackdropLayer 才是黑色背景的真正来源

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;

#pragma mark - 工具函数

// 判断一个颜色是不是黑色
static BOOL diColorIsBlack(CGColorRef color) {
    if (!color) return NO;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (!c) return NO;
    CGFloat r=0,g=0,b=0,a=0;
    if (n >= 4) { r=c[0]; g=c[1]; b=c[2]; a=c[3]; }
    else if (n == 2) { r=g=b=c[0]; a=c[1]; }
    return a > 0.1 && r < 0.15 && g < 0.15 && b < 0.15;
}

// 递归清除所有层的黑色背景
static void diClearAllBlackLayersRecursive(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 30) return;
    @try {
        // 清除黑色背景色
        if (diColorIsBlack(layer.backgroundColor)) {
            NSLog(@"[DI-Native] Clearing black layer: %@ bounds=%@",
                  NSStringFromClass([layer class]), NSStringFromCGRect(layer.bounds));
            layer.backgroundColor = UIColor.clearColor.CGColor;
        }
        // 清除 CABackdropLayer 的背景（CABackdropLayer 可能用私有属性渲染黑色）
        NSString *className = NSStringFromClass([layer class]);
        if ([className rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            // 不隐藏 CABackdropLayer，因为它可能负责模糊效果
            // 只清除它的背景色和 opacity
            if (layer.opacity > 0.5) {
                // 保持一定的透明度，让模糊效果还在
            }
        }
        // 递归处理子层
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diClearAllBlackLayersRecursive(sublayer, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

// 递归隐藏背景视图（_UILumaTrackingBackdropView、_SBAdaptiveKeyLineBackdropView、MTMaterialView）
static void diHideBackgroundViewsRecursive(UIView *view, NSInteger depth) {
    if (!view || depth > 20) return;
    @try {
        NSString *className = NSStringFromClass([view class]);

        // 隐藏这些背景视图
        if ([className rangeOfString:@"LumaTrackingBackdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"AdaptiveKeyLineBackdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"MTMaterialView" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"MaterialView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSLog(@"[DI-Native] Hiding background view: %@ frame=%@",
                  className, NSStringFromCGRect(view.frame));
            view.hidden = YES;
            view.alpha = 0.0;
        }

        // 清除视图的黑色背景色
        if (view.backgroundColor && diColorIsBlack(view.backgroundColor.CGColor)) {
            view.backgroundColor = UIColor.clearColor;
        }

        // 递归处理子视图
        for (UIView *subview in [view.subviews copy]) {
            diHideBackgroundViewsRecursive(subview, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

// 找到灵动岛的实际内容视图（通过 frame 大小识别）
static UIView *diFindIslandContentView(UIView *root) {
    if (!root) return nil;
    for (UIView *sub in [root.subviews copy]) {
        CGRect frame = sub.frame;
        if (CGRectGetWidth(frame) > 100 && CGRectGetWidth(frame) < 500 &&
            CGRectGetHeight(frame) > 30 && CGRectGetHeight(frame) < 200) {
            // 找到了，返回这个视图
            return sub;
        }
        UIView *found = diFindIslandContentView(sub);
        if (found) return found;
    }
    return nil;
}

#pragma mark - 液态玻璃应用

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (root.subviews.count == 0) return;

        // 第一步：激进隐藏所有背景视图
        diHideBackgroundViewsRecursive(root, 0);

        // 第二步：递归清除所有层的黑色背景
        diClearAllBlackLayersRecursive(root.layer, 0);

        // 找到灵动岛的实际内容视图
        UIView *contentView = diFindIslandContentView(root);
        if (!contentView) {
            NSLog(@"[DI-Native] Could not find island content view");
            return;
        }

        NSLog(@"[DI-Native] Found island content view: %@ frame=%@",
              NSStringFromClass(contentView.class),
              NSStringFromCGRect(contentView.frame));

        // 清除内容视图的背景
        contentView.backgroundColor = UIColor.clearColor;
        diClearAllBlackLayersRecursive(contentView.layer, 0);

        // 创建或获取液态玻璃层
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";

            // 玻璃层的 frame 用 content view 的 frame
            CGRect glassFrame = contentView.frame;

            glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.userInteractionEnabled = NO;

            // 插到 root 的最底层
            [root insertSubview:glass atIndex:0];

            objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            NSLog(@"[DI-Native] Glass attached, frame=%@", NSStringFromCGRect(glassFrame));
        }

        // 同步玻璃层的 frame 和 cornerRadius
        glass.frame = contentView.frame;
        CGFloat radius = contentView.layer.cornerRadius;
        if (radius <= 0.0)
            radius = CGRectGetHeight(contentView.bounds) * 0.5;
        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;

        // 确保玻璃在最底层
        if ([root.subviews indexOfObject:glass] != 0) {
            [root insertSubview:glass atIndex:0];
        }

        // 再清一次背景（系统可能在 layout 后重新设置）
        diHideBackgroundViewsRecursive(root, 0);
        diClearAllBlackLayersRecursive(root.layer, 0);

    } @catch (NSException *e) {
        NSLog(@"[DI-Native] Exception: %@", e);
    }
}

static void diRemoveGlass(SBSystemApertureContainerView *root) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (glass) [glass removeFromSuperview];
        objc_setAssociatedObject(root, kDIGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hooks

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
