// Dynamic Island Native Test11 - 修复坐标+激进清除版
// 修复：玻璃层 frame 坐标系转换（之前在灵动岛旁边）
// 修复：更激进地清除内容视图的黑色背景层

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
    // alpha > 0.05 且 RGB 都 < 0.2（包括深灰）
    return a > 0.05 && r < 0.2 && g < 0.2 && b < 0.2;
}

// 递归清除所有层的黑色背景（最激进版）
static void diClearAllBlackLayersRecursive(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 40) return;
    @try {
        // 清除黑色背景色
        if (diColorIsBlack(layer.backgroundColor)) {
            NSLog(@"[DI-Native] Clearing black layer: %@ bounds=%@",
                  NSStringFromClass([layer class]), NSStringFromCGRect(layer.bounds));
            layer.backgroundColor = UIColor.clearColor.CGColor;
        }

        // 对所有层都尝试清除 opacity（如果它是纯背景层）
        NSString *className = NSStringFromClass([layer class]);
        BOOL isContentLayer = [className isEqualToString:@"CALayerHost"] ||
                               [className isEqualToString:@"CAPortalLayer"] ||
                               [className isEqualToString:@"CAGainMapLayer"] ||
                               [className isEqualToString:@"CAGradientLayer"] ||
                               [className isEqualToString:@"_UIReplicantLayer"] ||
                               [className isEqualToString:@"CABackdropLayer"];

        // 如果不是内容层，且尺寸较大，可能是背景层，降低 opacity
        if (!isContentLayer && CGRectGetWidth(layer.bounds) > 50 && CGRectGetHeight(layer.bounds) > 20) {
            // 不直接设为0，保留一点，避免把内容也弄没了
            // layer.opacity = MAX(layer.opacity, 0.0);
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

// 找到灵动岛的实际内容视图（通过 frame 大小识别）
static UIView *diFindIslandContentView(UIView *root) {
    if (!root) return nil;
    for (UIView *sub in [root.subviews copy]) {
        CGRect frame = sub.frame;
        // 灵动岛展开时宽度可能很大（200-400），收起时宽度约 120
        if (CGRectGetWidth(frame) > 80 && CGRectGetWidth(frame) < 500 &&
            CGRectGetHeight(frame) > 25 && CGRectGetHeight(frame) < 200) {
            // 找到了，返回这个视图
            return sub;
        }
        UIView *found = diFindIslandContentView(sub);
        if (found) return found;
    }
    return nil;
}

// 找到灵动岛的容器层（通过 frame 大小识别，在图层树里找）
static CALayer *diFindIslandContainerLayer(CALayer *layer) {
    if (!layer) return nil;
    CGRect bounds = layer.bounds;
    // 灵动岛的尺寸：宽 100-450，高 30-150
    if (CGRectGetWidth(bounds) > 100 && CGRectGetWidth(bounds) < 450 &&
        CGRectGetHeight(bounds) > 30 && CGRectGetHeight(bounds) < 150 &&
        layer.cornerRadius > 5) {
        // 检查是不是内容层（CALayerHost 等）
        NSString *className = NSStringFromClass([layer class]);
        if (![className isEqualToString:@"CALayerHost"] &&
            ![className isEqualToString:@"CAPortalLayer"] &&
            ![className isEqualToString:@"CAGainMapLayer"]) {
            return layer;
        }
    }
    for (CALayer *sublayer in [layer.sublayers copy]) {
        CALayer *found = diFindIslandContainerLayer(sublayer);
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
            NSLog(@"[DI-Native] Could not find island content view in view tree");
            // 尝试在图层树里找
            CALayer *containerLayer = diFindIslandContainerLayer(root.layer);
            if (containerLayer) {
                NSLog(@"[DI-Native] Found container layer: %@ bounds=%@",
                      NSStringFromClass([containerLayer class]),
                      NSStringFromCGRect(containerLayer.bounds));
                // 用这个层的 frame 作为玻璃层的 frame
                CGRect glassFrame = containerLayer.frame;
                // 创建玻璃层
                LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
                if (!glass) {
                    NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
                    if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";
                    glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                             groupName:nil
                                                            filterType:filterType];
                    glass.backgroundColor = UIColor.clearColor;
                    glass.userInteractionEnabled = NO;
                    [root insertSubview:glass atIndex:0];
                    objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
                    NSLog(@"[DI-Native] Glass attached (from layer), frame=%@", NSStringFromCGRect(glassFrame));
                }
                glass.frame = glassFrame;
                glass.layer.cornerRadius = containerLayer.cornerRadius;
                glass.layer.cornerCurve = kCACornerCurveContinuous;
                glass.layer.masksToBounds = YES;
                if ([root.subviews indexOfObject:glass] != 0) {
                    [root insertSubview:glass atIndex:0];
                }
                return;
            }
            return;
        }

        NSLog(@"[DI-Native] Found island content view: %@ frame=%@",
              NSStringFromClass(contentView.class),
              NSStringFromCGRect(contentView.frame));

        // 清除内容视图的背景
        contentView.backgroundColor = UIColor.clearColor;
        diClearAllBlackLayersRecursive(contentView.layer, 0);

        // 关键修复：把 contentView 的 frame 转换到 root 坐标系
        CGRect glassFrame = [contentView convertRect:contentView.bounds toView:root];
        NSLog(@"[DI-Native] Glass frame (converted): %@", NSStringFromCGRect(glassFrame));

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
