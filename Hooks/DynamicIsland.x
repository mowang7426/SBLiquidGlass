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
                // 每次 Nice layout 后重新清理一次刚刚被 Nice 写回的背景。
                diClearNiceBackgroundTree(view, 0);
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

        if (isNiceIsland) {
            // 先清掉 Nice 真正的背景节点。
            diClearNiceBackgroundTree(view, 0);

            // 玻璃作为 Nice 自己的第一个子 View：
            // [Nice View]
            //   ├─ Liquid Glass
            //   └─ Nice 内容
            [view insertSubview:glass atIndex:0];

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

        // 如果已经有玻璃，确保它仍然位于内容最底层。
        LGLiveBackdropView *glass = objc_getAssociatedObject(container, kDIGlassKey);
        if (glass) {
            [container sendSubviewToBack:glass];
        }
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
            [container sendSubviewToBack:glass];
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
