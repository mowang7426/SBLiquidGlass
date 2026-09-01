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

#pragma mark - 全局变量

static void *kDIGlassKey = &kDIGlassKey;

#pragma mark - Nice 灵动岛背景处理

// Nice 灵动岛自己的背景必须保持透明，否则它会把 CABackdropLayer 的结果盖住。
// 只处理明确的背景节点，不再递归修改整个视图树，也不使用多次延迟定时器。
static void diClearKnownNiceBackground(UIView *view) {
    if (!view) return;

    @try {
        view.backgroundColor = UIColor.clearColor;
        view.opaque = NO;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
    } @catch (__unused NSException *e) {}

    NSArray<NSString *> *keys = @[
        @"backgroundContainer",
        @"bgView",
        @"backdrop",
        @"platter",
        @"backgroundView"
    ];

    for (NSString *key in keys) {
        @try {
            id candidate = [view valueForKey:key];
            if ([candidate isKindOfClass:[UIView class]]) {
                UIView *bg = (UIView *)candidate;
                bg.backgroundColor = UIColor.clearColor;
                bg.opaque = NO;
                bg.layer.backgroundColor = UIColor.clearColor.CGColor;
            }
        } @catch (__unused NSException *e) {}
    }

    // Nice 的实现版本不同，部分背景只存在于 ivar 中；只清理“明确命名”的背景 ivar。
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(view.class, &count);
    for (unsigned int i = 0; i < count; i++) {
        Ivar ivar = ivars[i];
        const char *rawName = ivar_getName(ivar);
        if (!rawName) continue;

        NSString *name = [NSString stringWithUTF8String:rawName].lowercaseString;
        BOOL isKnownBackground =
            [name containsString:@"background"] ||
            [name isEqualToString:@"_bgview"] ||
            [name isEqualToString:@"_backdrop"] ||
            [name containsString:@"platter"];
        if (!isKnownBackground) continue;

        @try {
            id candidate = object_getIvar(view, ivar);
            if ([candidate isKindOfClass:[UIView class]]) {
                UIView *bg = (UIView *)candidate;
                bg.backgroundColor = UIColor.clearColor;
                bg.opaque = NO;
                bg.layer.backgroundColor = UIColor.clearColor.CGColor;
            }
        } @catch (__unused NSException *e) {}
    }
    if (ivars) free(ivars);
}

#pragma mark - 液态玻璃效果实现



static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10) return;

        // Nice 灵动岛使用“材质作为自身背景”的模式：玻璃必须位于 Nice view 内部，
        // 而不是插到 superview 下面。这样 Nice 的内容仍然保持原有层级和动画。
        if (isNiceIsland) {
            diClearKnownNiceBackground(view);
        }

        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";

            // 玻璃 view 始终使用自己的 bounds 坐标系。
            glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds
                                                     groupName:nil
                                                    filterType:filterType];
            glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            glass.userInteractionEnabled = NO;
            glass.backgroundColor = UIColor.clearColor;
            glass.opaque = NO;

            // 液态玻璃是背景材质，不再使用 0.85 alpha 模拟半透明。
            // 由 CABackdropLayer + CAFilter 自己决定最终合成结果。
            glass.alpha = 1.0;

            [view insertSubview:glass atIndex:0];
            objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            NSLog(@"[SBLiquidGlass-DI] Nice glass inserted inside %@", NSStringFromClass(view.class));
        } else if (glass.superview != view) {
            [glass removeFromSuperview];
            [view insertSubview:glass atIndex:0];
        }

        // Nice 展开/收缩时 bounds 会不断变化；每次 layout 都同步玻璃几何。
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        glass.frame = view.bounds;
        CGFloat cornerRadius = view.layer.cornerRadius > 0.0
            ? view.layer.cornerRadius
            : MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        [CATransaction commit];

        // 保证 Nice 自己的背景不会覆盖玻璃；内容子视图不动。
        if (isNiceIsland) {
            diClearKnownNiceBackground(view);
        } else {
            view.backgroundColor = UIColor.clearColor;
            view.opaque = NO;
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
        }

        [glass applyFilters];
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

#pragma mark - Hook nice 灵动岛自定义视图

%hook NBXLddClassic2View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self, YES);
        } else {
            diRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self, YES);
    } @catch (__unused NSException *e) {}
}

%end

%hook NBXLddClassic3View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self, YES);
        } else {
            diRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self, YES);
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (Nice in-view Liquid Glass mode)");
    } @catch (__unused NSException *e) {}
}
