#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 私有类声明

@interface SBSystemApertureContainerView : UIView
@end

@interface NBXLddClassic2View : UIView
@end

@interface NBXLddClassic3View : UIView
@end

@interface ArtWorkManager : NSObject
- (UIView *)getCurrentContainerView;
- (void)layoutContainerViews:(id)arg;
@end

#pragma mark - 全局变量

static void *kDIGlassKey = &kDIGlassKey;

#pragma mark - Nice 灵动岛背景层处理

// Test3：不再给 Nice 整棵 View 树反复设置“半透明黑色”。
// 只清理明显的背景/材质层，让真正的 LGLiveBackdropView 成为背景材质。
// 内容层、图标、文字和 Nice 自己的动画保持不动。

static BOOL diNameLooksLikeBackground(NSString *name) {
    if (!name.length) return NO;
    NSString *n = name.lowercaseString;
    return [n containsString:@"background"] ||
           [n containsString:@"backdrop"] ||
           [n containsString:@"platter"] ||
           [n isEqualToString:@"bgview"] ||
           [n containsString:@".bg"] ||
           [n containsString:@"material"];
}

static void diClearNiceBackgroundTree(UIView *view, NSInteger depth) {
    if (!view || depth > 8) return;

    @try {
        // 根 View 本身只清理背景色，不改变 alpha，避免影响 Nice 内容。
        if (depth == 0) {
            view.backgroundColor = [UIColor clearColor];
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
        }

        // 只处理名字明确指向背景/材质的子 View。
        for (UIView *sub in [view.subviews copy]) {
            NSString *className = NSStringFromClass(sub.class);

            if (diNameLooksLikeBackground(className)) {
                sub.backgroundColor = [UIColor clearColor];
                sub.layer.backgroundColor = UIColor.clearColor.CGColor;

                // 背景容器本身可以隐藏；如果它承载内容则不命中这些名字。
                sub.alpha = 0.0;

                // 同时清掉它的直接 sublayers 背景色，避免黑色 CALayer 继续盖住玻璃。
                for (CALayer *layer in [sub.layer.sublayers copy]) {
                    if (layer.backgroundColor) {
                        layer.backgroundColor = UIColor.clearColor.CGColor;
                    }
                }

                NSLog(@"[SBLiquidGlass-DI] Cleared Nice background node: %@", className);
            }

            diClearNiceBackgroundTree(sub, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}


// Test6：Nice 的黑色填充很可能不是 backgroundColor，而是由 opaque/draw/layer
// backing store 或自定义背景 view 绘制。只对“背景候选节点”关闭不透明绘制，
// 不再依赖名字命中就直接隐藏整个 View。
static BOOL diIsLikelyBackgroundView(UIView *v) {
    if (!v) return NO;
    NSString *n = NSStringFromClass(v.class).lowercaseString;
    if (diNameLooksLikeBackground(n)) return YES;
    NSString *label = v.accessibilityIdentifier.lowercaseString;
    if (label.length && diNameLooksLikeBackground(label)) return YES;
    return NO;
}

static void diNeutralizeNiceBackgroundView(UIView *v, NSInteger depth) {
    if (!v || depth > 10) return;

    @try {
        BOOL candidate = diIsLikelyBackgroundView(v);

        if (candidate) {
            // 不隐藏 View：Nice 有些背景容器同时承担布局。
            // 只让 UIKit/CoreAnimation 不再把它作为不透明黑色 backing。
            v.opaque = NO;
            v.clearsContextBeforeDrawing = NO;
            v.backgroundColor = UIColor.clearColor;
            v.layer.opaque = NO;
            v.layer.backgroundColor = UIColor.clearColor.CGColor;

            // 避免常见的遮罩/填充继续提供纯黑底。
            v.layer.shadowOpacity = 0.0;

            for (CALayer *l in [v.layer.sublayers copy]) {
                NSString *ln = (l.name ?: @"").lowercaseString;
                BOOL layerCandidate =
                    [ln containsString:@"background"] ||
                    [ln containsString:@"backdrop"] ||
                    [ln containsString:@"material"] ||
                    [ln containsString:@"platter"] ||
                    [ln containsString:@"backview"];

                if (layerCandidate || l.opaque) {
                    l.opaque = NO;
                    if (layerCandidate)
                        l.backgroundColor = UIColor.clearColor.CGColor;

                    if ([l isKindOfClass:[CAShapeLayer class]] && layerCandidate) {
                        ((CAShapeLayer *)l).fillColor = UIColor.clearColor.CGColor;
                    }
                }
            }

            NSLog(@"[SBLiquidGlass-DI] Test6 neutralized background view %@", NSStringFromClass(v.class));
        }

        for (UIView *sub in [v.subviews copy]) {
            diNeutralizeNiceBackgroundView(sub, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

static void diSyncNiceGlass(UIView *view, LGLiveBackdropView *glass) {
    if (!view || !glass) return;

    @try {
        glass.frame = view.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;

        CGFloat radius = view.layer.cornerRadius;
        if (radius <= 0.0) {
            radius = MIN(CGRectGetWidth(view.bounds),
                         CGRectGetHeight(view.bounds)) * 0.5;
        }

        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
    } @catch (__unused NSException *e) {}
}

#pragma mark - 液态玻璃效果实现


// Test5：Nice 的黑色区域在 Test4 中仍然不透，说明遮挡物很可能不是
// UIView.backgroundColor，而是较大的 CALayer/CAShapeLayer 绘制出来的。
// 这一版只对“覆盖容器大部分面积”的背景型 layer 做清理，避免碰内容图层。
static BOOL diLayerLooksLikeIslandBackground(CALayer *layer, UIView *container) {
    if (!layer || !container) return NO;
    CGRect b = layer.bounds;
    CGFloat cw = CGRectGetWidth(container.bounds);
    CGFloat ch = CGRectGetHeight(container.bounds);
    if (cw < 1 || ch < 1) return NO;

    CGFloat rw = CGRectGetWidth(b) / cw;
    CGFloat rh = CGRectGetHeight(b) / ch;
    BOOL large = (rw >= 0.70 && rh >= 0.45);
    BOOL rounded = layer.cornerRadius > 0.5;

    NSString *name = layer.name.lowercaseString;
    BOOL named = name.length &&
        ([name containsString:@"back"] ||
         [name containsString:@"bg"] ||
         [name containsString:@"pill"] ||
         [name containsString:@"material"] ||
         [name containsString:@"background"]);

    return large && (rounded || named);
}

static void diClearLargeBackgroundLayers(CALayer *layer, UIView *container, NSInteger depth) {
    if (!layer || !container || depth > 12) return;

    @try {
        if (diLayerLooksLikeIslandBackground(layer, container)) {
            layer.backgroundColor = UIColor.clearColor.CGColor;
            if ([layer isKindOfClass:[CAShapeLayer class]]) {
                CAShapeLayer *shape = (CAShapeLayer *)layer;
                shape.fillColor = UIColor.clearColor.CGColor;
            }
            NSLog(@"[SBLiquidGlass-DI] Test5 cleared large background layer %@ bounds=%@",
                  layer.name ?: NSStringFromClass(layer.class), NSStringFromCGRect(layer.bounds));
        }

        for (CALayer *sub in [layer.sublayers copy]) {
            diClearLargeBackgroundLayers(sub, container, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

static void diPutNiceGlassBetweenBackgroundAndContent(UIView *container,
                                                       LGLiveBackdropView *glass) {
    if (!container || !glass) return;

    @try {
        // 关键变化：Test4 把 glass 放在 index 0，容易落到 Nice 的“黑底”下面。
        // Test5 改成先放到最上面，再把现有内容放到 glass 上方。
        [container bringSubviewToFront:glass];
        glass.layer.zPosition = 0.5;
        glass.userInteractionEnabled = NO;

        for (UIView *sub in [container.subviews copy]) {
            if (sub == glass) continue;
            // 让 Nice 原有内容始终位于玻璃之上。
            sub.layer.zPosition = MAX(sub.layer.zPosition, 1.0);
        }
    } @catch (__unused NSException *e) {}
}

static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) ||
            CGRectGetWidth(view.bounds) < 10 ||
            CGRectGetHeight(view.bounds) < 5) return;

        LGLiveBackdropView *glass =
            objc_getAssociatedObject(view, kDIGlassKey);

        if (glass) {
            if (isNiceIsland) {
                diSyncNiceGlass(view, glass);
                diPutNiceGlassBetweenBackgroundAndContent(view, glass);
                diClearLargeBackgroundLayers(view.layer, view, 0);
                // 每次 Nice layout 后重新清理一次刚刚被 Nice 写回的背景。
                diClearNiceBackgroundTree(view, 0);
                diNeutralizeNiceBackgroundView(view, 0);
                view.opaque = NO;
                view.layer.opaque = NO;
            } else {
                glass.frame = view.bounds;
                CGFloat radius = view.layer.cornerRadius > 0 ?
                    view.layer.cornerRadius :
                    CGRectGetHeight(view.bounds) * 0.5;
                glass.layer.cornerRadius = radius;
            }
            return;
        }

        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType.length)
            filterType = @"dylv.liquidglass.dynamicisland";

        // 关键：Nice 的玻璃必须属于 Nice 自己的坐标系。
        CGRect glassFrame = view.bounds;

        glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                 groupName:nil
                                                filterType:filterType];

        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;

        CGFloat radius = view.layer.cornerRadius;
        if (radius <= 0.0) {
            radius = MIN(CGRectGetWidth(view.bounds),
                         CGRectGetHeight(view.bounds)) * 0.5;
        }

        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;

        // 不再用 alpha 0.85 叠加一层黑色；让 Backdrop 自己负责玻璃材质。
        glass.alpha = 1.0;
        glass.backgroundColor = [UIColor clearColor];
        glass.opaque = NO;
        glass.layer.opaque = NO;
        glass.layer.backgroundColor = UIColor.clearColor.CGColor;

        if (isNiceIsland) {
            // 先清掉 Nice 真正的背景节点。
            diClearNiceBackgroundTree(view, 0);

            // Test5：不再把玻璃放到 index 0。
            // 先把它放到最上层，再把 Nice 原有内容提升到玻璃之上，
            // 从而让玻璃层可以位于 Nice 的黑色背景绘制之上。
            [view addSubview:glass];
            diPutNiceGlassBetweenBackgroundAndContent(view, glass);

            // 清理容器层级中覆盖大面积的背景 CALayer / CAShapeLayer。
            diClearLargeBackgroundLayers(view.layer, view, 0);

            // Test6：处理自定义绘制/opaque backing 造成的黑底。
            diNeutralizeNiceBackgroundView(view, 0);
            view.opaque = NO;
            view.clearsContextBeforeDrawing = NO;
            view.layer.opaque = NO;

            // 再清一次，防止 Nice 的 layout 在插入过程中重新创建背景。
            diClearNiceBackgroundTree(view, 0);
        } else {
            [view insertSubview:glass atIndex:0];
            view.backgroundColor =
                [[UIColor blackColor] colorWithAlphaComponent:0.05];
        }

        objc_setAssociatedObject(view, kDIGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 立即应用，避免第一次显示时出现普通黑色背景闪烁。
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}

        NSLog(@"[SBLiquidGlass-DI] Liquid Glass attached to %@ (nice=%d)",
              NSStringFromClass(view.class), isNiceIsland);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception: %@", e);
    }
}

static void diRemoveGlass(UIView *view) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook 系统灵动岛容器视图

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self, NO);
        } else {
            diRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self, NO);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook Nice ArtWorkManager：真正的当前容器

// Test4：Nice 的 NBXLddClassic2/3View 只是内容元素，不再把它们当作
// 整个灵动岛的根容器。Nice 自己的 ArtWorkManager 提供了
// getCurrentContainerView，这才是我们要挂材质的对象。

static void diPrepareNiceContainer(UIView *container) {
    if (!container) return;

    @try {
        // 只处理容器自身背景，避免把 Nice 的内容元素透明掉。
        container.backgroundColor = [UIColor clearColor];
        container.layer.backgroundColor = UIColor.clearColor.CGColor;

        // 清理容器下明确的背景/材质节点；保留其它内容。
        diClearNiceBackgroundTree(container, 0);

        // Test5 不再把玻璃压到黑色背景下面；层级在后续函数中单独维护。
    } @catch (__unused NSException *e) {}
}

static void diApplyGlassToNiceCurrentContainer(UIView *container) {
    if (!container) return;
    if (!lgHostEnabled(@"DynamicIsland")) return;

    @try {
        diPrepareNiceContainer(container);
        diApplyGlassToView(container, YES);
        diPrepareNiceContainer(container);

        LGLiveBackdropView *glass = objc_getAssociatedObject(container, kDIGlassKey);
        if (glass) {
            diPutNiceGlassBetweenBackgroundAndContent(container, glass);
            diClearLargeBackgroundLayers(container.layer, container, 0);
            diSyncNiceGlass(container, glass);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        }

        NSLog(@"[SBLiquidGlass-DI] Nice current container = %@ frame=%@",
              NSStringFromClass(container.class), NSStringFromCGRect(container.frame));
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Nice container exception: %@", e);
    }
}

%hook ArtWorkManager

- (UIView *)getCurrentContainerView {
    UIView *container = %orig;

    @try {
        if (container && container.window) {
            diApplyGlassToNiceCurrentContainer(container);
        }
    } @catch (__unused NSException *e) {}

    return container;
}

- (void)layoutContainerViews:(id)arg {
    %orig;

    // Nice 每次重新布局后再取一次当前容器，确保展开/收缩时玻璃跟随。
    @try {
        UIView *container = [self getCurrentContainerView];
        if (container && container.window) {
            diApplyGlassToNiceCurrentContainer(container);
        }
    } @catch (__unused NSException *e) {}
}

%end
