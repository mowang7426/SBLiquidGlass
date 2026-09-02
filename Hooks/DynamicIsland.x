// Dynamic Island Native Test13 - 图层树定位+超激进清除版
// 直接在图层树里找灵动岛容器层来定位玻璃层（不用视图树的 contentView）
// 超激进清除：只要背景是黑色的非内容层，直接 hidden=YES

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;

#pragma mark - 工具函数

// 判断一个颜色是不是黑色（包括深灰）
static BOOL diColorIsBlack(CGColorRef color) {
    if (!color) return NO;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (!c) return NO;
    CGFloat r=0,g=0,b=0,a=0;
    if (n >= 4) { r=c[0]; g=c[1]; b=c[2]; a=c[3]; }
    else if (n == 2) { r=g=b=c[0]; a=c[1]; }
    return a > 0.05 && r < 0.25 && g < 0.25 && b < 0.25;
}

// 判断一个层是不是内容层（不能隐藏）
static BOOL diIsContentLayer(CALayer *layer) {
    NSString *className = NSStringFromClass([layer class]);
    return [className isEqualToString:@"CALayerHost"] ||
           [className isEqualToString:@"CAPortalLayer"] ||
           [className isEqualToString:@"CAGainMapLayer"] ||
           [className isEqualToString:@"CAGradientLayer"] ||
           [className isEqualToString:@"_UIReplicantLayer"] ||
           [className isEqualToString:@"CABackdropLayer"] ||
           [className isEqualToString:@"CAEAGLLayer"] ||
           [className isEqualToString:@"CAMetalLayer"] ||
           [className isEqualToString:@"CAReplicatorLayer"] ||
           [className isEqualToString:@"CATextLayer"] ||
           [className isEqualToString:@"CAShapeLayer"];
}

// 递归清除所有层的黑色背景（超激进版：只要黑色就隐藏）
static void diClearAllBlackLayersRecursive(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 50) return;
    @try {
        // 跳过内容层
        if (diIsContentLayer(layer)) {
            // 但还是要清除它的背景色
            if (diColorIsBlack(layer.backgroundColor)) {
                layer.backgroundColor = UIColor.clearColor.CGColor;
            }
            // 内容层也要递归处理子层
            for (CALayer *sublayer in [layer.sublayers copy]) {
                diClearAllBlackLayersRecursive(sublayer, depth + 1);
            }
            return;
        }

        // 超激进：只要背景是黑色，就直接隐藏
        if (diColorIsBlack(layer.backgroundColor)) {
            NSLog(@"[DI-Native] Hiding black layer: %@ bounds=%@ bg=black",
                  NSStringFromClass([layer class]), NSStringFromCGRect(layer.bounds));
            layer.hidden = YES;
            layer.opacity = 0.0;
            layer.backgroundColor = UIColor.clearColor.CGColor;
            // 隐藏了就不用处理子层了（子层也会被隐藏）
            return;
        }

        // 清除背景色（即使不是纯黑，只要是深色也清）
        if (layer.backgroundColor) {
            size_t n = CGColorGetNumberOfComponents(layer.backgroundColor);
            const CGFloat *c = CGColorGetComponents(layer.backgroundColor);
            if (c && n >= 4 && c[3] > 0.1 && c[0] < 0.3 && c[1] < 0.3 && c[2] < 0.3) {
                layer.backgroundColor = UIColor.clearColor.CGColor;
            }
        }

        // 递归处理子层
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diClearAllBlackLayersRecursive(sublayer, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

// 递归隐藏背景视图
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

// 在图层树里找灵动岛的容器层（最外层、有 cornerRadius、尺寸合适）
static CALayer *diFindIslandContainerLayer(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 30) return nil;
    @try {
        CGRect bounds = layer.bounds;
        // 灵动岛的尺寸：宽 100-450，高 30-150，有 cornerRadius
        if (CGRectGetWidth(bounds) > 100 && CGRectGetWidth(bounds) < 450 &&
            CGRectGetHeight(bounds) > 30 && CGRectGetHeight(bounds) < 150 &&
            layer.cornerRadius > 5) {
            NSString *className = NSStringFromClass([layer class]);
            // 排除内容层
            if (![className isEqualToString:@"CALayerHost"] &&
                ![className isEqualToString:@"CAPortalLayer"] &&
                ![className isEqualToString:@"CAGainMapLayer"] &&
                ![className isEqualToString:@"CABackdropLayer"]) {
                // 这可能是灵动岛的容器层
                // 检查它的子层里有没有 CALayerHost（说明它包含内容）
                for (CALayer *sublayer in layer.sublayers) {
                    if ([NSStringFromClass([sublayer class]) isEqualToString:@"CALayerHost"]) {
                        NSLog(@"[DI-Native] Found island container layer: %@ bounds=%@ cornerRadius=%.1f",
                              className, NSStringFromCGRect(bounds), layer.cornerRadius);
                        return layer;
                    }
                    // 递归检查子层的子层
                    CALayer *found = diFindIslandContainerLayer(sublayer, depth + 1);
                    if (found) return found;
                }
            }
        }

        // 递归查找
        for (CALayer *sublayer in [layer.sublayers copy]) {
            CALayer *found = diFindIslandContainerLayer(sublayer, depth + 1);
            if (found) return found;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

#pragma mark - 液态玻璃应用

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (root.subviews.count == 0) return;

        // 第一步：激进隐藏所有背景视图
        diHideBackgroundViewsRecursive(root, 0);

        // 第二步：在图层树里找灵动岛的容器层
        CALayer *containerLayer = diFindIslandContainerLayer(root.layer, 0);
        if (!containerLayer) {
            NSLog(@"[DI-Native] Could not find island container layer");
            // 找不到就不处理了
            return;
        }

        NSLog(@"[DI-Native] Using container layer: %@ bounds=%@",
              NSStringFromClass([containerLayer class]),
              NSStringFromCGRect(containerLayer.bounds));

        // 第三步：超激进清除容器层及其所有子层的黑色背景
        diClearAllBlackLayersRecursive(containerLayer, 0);

        // 同时清除 root 下所有层的黑色背景（有些背景层可能在容器层外面）
        diClearAllBlackLayersRecursive(root.layer, 0);

        // 第四步：计算玻璃层的 frame
        // 把容器层的 frame 转换到 root.layer 的坐标系
        CGRect glassFrameInRootLayer = [root.layer convertRect:containerLayer.frame fromLayer:containerLayer.superlayer];
        NSLog(@"[DI-Native] Container frame: %@, converted to root layer: %@",
              NSStringFromCGRect(containerLayer.frame),
              NSStringFromCGRect(glassFrameInRootLayer));

        // 玻璃层是 UIView，插到 root 里，frame 用 root 坐标系
        // UIView 的 frame 和它的 layer 的 frame 是一样的（在 root 的坐标系里）
        CGRect glassFrame = glassFrameInRootLayer;

        // 创建或获取液态玻璃层
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";

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
        glass.frame = glassFrame;
        CGFloat radius = containerLayer.cornerRadius;
        if (radius <= 0.0)
            radius = CGRectGetHeight(glassFrame) * 0.5;
        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;

        // 确保玻璃在最底层
        if ([root.subviews indexOfObject:glass] != 0) {
            [root insertSubview:glass atIndex:0];
        }

        // 第五步：延迟多次清除（防止系统恢复黑色背景）
        void (^clearBlock)(void) = ^{
            @try {
                diHideBackgroundViewsRecursive(root, 0);
                diClearAllBlackLayersRecursive(containerLayer, 0);
                diClearAllBlackLayersRecursive(root.layer, 0);
            } @catch (__unused NSException *e) {}
        };

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), clearBlock);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), clearBlock);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            clearBlock();
            NSLog(@"[DI-Native] All clear passes completed");
        });

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
