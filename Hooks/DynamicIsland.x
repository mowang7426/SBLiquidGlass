// Dynamic Island Native Test12 - 最激进清除版
// 对非内容层的黑色背景层直接 hidden=YES
// layout 后延迟再清一次（防止系统恢复）
// 清除 contents 里的黑色内容

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
    return a > 0.05 && r < 0.2 && g < 0.2 && b < 0.2;
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
           [className isEqualToString:@"CAMetalLayer"];
}

// 递归清除所有层的黑色背景（最激进版：直接隐藏背景层）
static void diClearAllBlackLayersRecursive(CALayer *layer, CGRect referenceBounds, NSInteger depth) {
    if (!layer || depth > 40) return;
    @try {
        // 跳过内容层
        if (diIsContentLayer(layer)) {
            // 但还是要清除它的背景色
            if (diColorIsBlack(layer.backgroundColor)) {
                layer.backgroundColor = UIColor.clearColor.CGColor;
            }
            return;
        }

        CGRect layerBounds = layer.bounds;
        CGFloat ratioW = CGRectGetWidth(layerBounds) / CGRectGetWidth(referenceBounds);
        CGFloat ratioH = CGRectGetHeight(layerBounds) / CGRectGetHeight(referenceBounds);
        BOOL coversMost = (ratioW > 0.6 && ratioH > 0.5);

        // 如果这个层覆盖了大部分面积，并且背景是黑色，直接隐藏
        if (coversMost && diColorIsBlack(layer.backgroundColor)) {
            NSLog(@"[DI-Native] Hiding black background layer: %@ bounds=%@",
                  NSStringFromClass([layer class]), NSStringFromCGRect(layer.bounds));
            layer.hidden = YES;
            layer.opacity = 0.0;
            layer.backgroundColor = UIColor.clearColor.CGColor;
            return; // 隐藏了就不用处理子层了
        }

        // 清除背景色
        if (diColorIsBlack(layer.backgroundColor)) {
            layer.backgroundColor = UIColor.clearColor.CGColor;
        }

        // 清除 contents（如果是纯色的黑色）
        // 注意：不要清除有内容的 contents
        // layer.contents = nil; // 暂时不清除，可能会影响内容

        // 递归处理子层
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diClearAllBlackLayersRecursive(sublayer, referenceBounds, depth + 1);
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
        if (CGRectGetWidth(frame) > 80 && CGRectGetWidth(frame) < 500 &&
            CGRectGetHeight(frame) > 25 && CGRectGetHeight(frame) < 200) {
            return sub;
        }
        UIView *found = diFindIslandContentView(sub);
        if (found) return found;
    }
    return nil;
}

// 找到灵动岛的容器层（在图层树里找）
static CALayer *diFindIslandContainerLayer(CALayer *layer) {
    if (!layer) return nil;
    CGRect bounds = layer.bounds;
    if (CGRectGetWidth(bounds) > 100 && CGRectGetWidth(bounds) < 450 &&
        CGRectGetHeight(bounds) > 30 && CGRectGetHeight(bounds) < 150 &&
        layer.cornerRadius > 5) {
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

        // 找到灵动岛的实际内容视图
        UIView *contentView = diFindIslandContentView(root);
        CGRect referenceBounds = CGRectZero;

        if (contentView) {
            referenceBounds = contentView.bounds;
            NSLog(@"[DI-Native] Found island content view: %@ frame=%@",
                  NSStringFromClass(contentView.class),
                  NSStringFromCGRect(contentView.frame));
        } else {
            // 尝试在图层树里找
            CALayer *containerLayer = diFindIslandContainerLayer(root.layer);
            if (containerLayer) {
                referenceBounds = containerLayer.bounds;
                NSLog(@"[DI-Native] Found container layer: %@ bounds=%@",
                      NSStringFromClass([containerLayer class]),
                      NSStringFromCGRect(containerLayer.bounds));
            }
        }

        if (CGRectIsEmpty(referenceBounds)) {
            NSLog(@"[DI-Native] Could not find island content view or container layer");
            return;
        }

        // 第二步：递归清除所有层的黑色背景（最激进版：直接隐藏背景层）
        diClearAllBlackLayersRecursive(root.layer, referenceBounds, 0);

        // 清除内容视图的背景
        if (contentView) {
            contentView.backgroundColor = UIColor.clearColor;
            diClearAllBlackLayersRecursive(contentView.layer, referenceBounds, 0);
        }

        // 计算玻璃层的 frame（转换到 root 坐标系）
        CGRect glassFrame;
        if (contentView) {
            glassFrame = [contentView convertRect:contentView.bounds toView:root];
        } else {
            CALayer *containerLayer = diFindIslandContainerLayer(root.layer);
            glassFrame = containerLayer.frame;
        }
        NSLog(@"[DI-Native] Glass frame: %@", NSStringFromCGRect(glassFrame));

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

            [root insertSubview:glass atIndex:0];

            objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            NSLog(@"[DI-Native] Glass attached, frame=%@", NSStringFromCGRect(glassFrame));
        }

        // 同步玻璃层的 frame 和 cornerRadius
        glass.frame = glassFrame;
        CGFloat radius = 0;
        if (contentView) {
            radius = contentView.layer.cornerRadius;
        } else {
            CALayer *containerLayer = diFindIslandContainerLayer(root.layer);
            radius = containerLayer.cornerRadius;
        }
        if (radius <= 0.0)
            radius = CGRectGetHeight(glassFrame) * 0.5;
        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;

        // 确保玻璃在最底层
        if ([root.subviews indexOfObject:glass] != 0) {
            [root insertSubview:glass atIndex:0];
        }

        // 第三步：延迟 0.1 秒再清一次（防止系统在 layout 后恢复黑色背景）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                diHideBackgroundViewsRecursive(root, 0);
                diClearAllBlackLayersRecursive(root.layer, referenceBounds, 0);
                if (contentView) {
                    diClearAllBlackLayersRecursive(contentView.layer, referenceBounds, 0);
                }
                NSLog(@"[DI-Native] Second pass clear completed");
            } @catch (__unused NSException *e) {}
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
