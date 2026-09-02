// Dynamic Island Native Test9 - 精准清除黑色背景层版
// 根据 dump 出来的真实层级结构，精准清除灵动岛的所有黑色背景层
// 灵动岛的黑色背景在图层树里（CALayer.backgroundColor），不是视图的 backgroundColor

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;

#pragma mark - 工具函数

// 判断一个颜色是不是黑色（包括纯黑和接近黑的深灰）
static BOOL diColorIsBlack(CGColorRef color) {
    if (!color) return NO;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (!c) return NO;
    CGFloat r=0,g=0,b=0,a=0;
    if (n >= 4) { r=c[0]; g=c[1]; b=c[2]; a=c[3]; }
    else if (n == 2) { r=g=b=c[0]; a=c[1]; }
    // alpha > 0.1 且 RGB 都 < 0.15（接近纯黑）
    return a > 0.1 && r < 0.15 && g < 0.15 && b < 0.15;
}

// 判断一个层是不是灵动岛的黑色背景层
static BOOL diLayerIsIslandBlackBackground(CALayer *layer, CALayer *referenceLayer) {
    if (!layer || !referenceLayer) return NO;
    CGRect refBounds = referenceLayer.bounds;
    if (CGRectIsEmpty(refBounds)) return NO;

    CGFloat refW = CGRectGetWidth(refBounds);
    CGFloat refH = CGRectGetHeight(refBounds);
    if (refW < 1 || refH < 1) return NO;

    // 层的尺寸接近参考层（覆盖大部分面积）
    CGRect layerBounds = layer.bounds;
    CGFloat ratioW = CGRectGetWidth(layerBounds) / refW;
    CGFloat ratioH = CGRectGetHeight(layerBounds) / refH;
    BOOL coversMost = (ratioW > 0.7 && ratioH > 0.6);

    // 背景色是黑色
    BOOL hasBlackBg = diColorIsBlack(layer.backgroundColor);

    // 类名是背景相关的
    NSString *className = NSStringFromClass([layer class]);
    BOOL isBackgroundClass = [className rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                              [className rangeOfString:@"Material" options:NSCaseInsensitiveSearch].location != NSNotFound;

    // 排除内容层：CALayerHost（跨进程渲染）、CAPortalLayer（门户层）、CAGainMapLayer（增益图）、CAGradientLayer（渐变层）
    BOOL isContentLayer = [className isEqualToString:@"CALayerHost"] ||
                           [className isEqualToString:@"CAPortalLayer"] ||
                           [className isEqualToString:@"CAGainMapLayer"] ||
                           [className isEqualToString:@"CAGradientLayer"] ||
                           [className isEqualToString:@"_UIReplicantLayer"];

    if (isContentLayer) return NO;

    return coversMost && (hasBlackBg || isBackgroundClass);
}

// 递归清除灵动岛的所有黑色背景层
static void diClearIslandBlackBackgroundsRecursive(CALayer *layer, CALayer *referenceLayer, NSInteger depth) {
    if (!layer || !referenceLayer || depth > 25) return;
    @try {
        if (diLayerIsIslandBlackBackground(layer, referenceLayer)) {
            NSLog(@"[DI-Native] Clearing black background: %@ bounds=%@ bg=%@",
                  NSStringFromClass([layer class]),
                  NSStringFromCGRect(layer.bounds),
                  layer.backgroundColor ? @"black" : @"none");
            layer.backgroundColor = UIColor.clearColor.CGColor;
            layer.opacity = 0.0;
            // 不直接 hidden，因为有些层可能承载内容；只清背景色和透明度
        }

        // 递归处理子层
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diClearIslandBlackBackgroundsRecursive(sublayer, referenceLayer, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

// 找到灵动岛的实际内容视图（通过 frame 大小识别）
static UIView *diFindIslandContentView(UIView *root) {
    if (!root) return nil;

    // 递归查找 frame 大小接近灵动岛（宽 100-150，高 30-50）的视图
    for (UIView *sub in [root.subviews copy]) {
        CGRect frame = sub.frame;
        if (CGRectGetWidth(frame) > 100 && CGRectGetWidth(frame) < 160 &&
            CGRectGetHeight(frame) > 30 && CGRectGetHeight(frame) < 50) {
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

        // 找到灵动岛的实际内容视图
        UIView *contentView = diFindIslandContentView(root);
        if (!contentView) {
            NSLog(@"[DI-Native] Could not find island content view");
            return;
        }

        NSLog(@"[DI-Native] Found island content view: %@ frame=%@",
              NSStringFromClass(contentView.class),
              NSStringFromCGRect(contentView.frame));

        // 关键：递归清除灵动岛内容视图及其所有子层的黑色背景
        // 灵动岛的黑色背景在图层树里，不是视图的 backgroundColor
        diClearIslandBlackBackgroundsRecursive(contentView.layer, contentView.layer, 0);

        // 同时清除 root 下所有层的黑色背景（有些背景层可能在 content view 外面）
        diClearIslandBlackBackgroundsRecursive(root.layer, contentView.layer, 0);

        // 创建或获取液态玻璃层
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";

            // 玻璃层的 frame 用 content view 的 frame（在 root 坐标系里）
            CGRect glassFrame = contentView.frame;

            glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.userInteractionEnabled = NO;

            // 插到 root 的最底层（index 0）
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
