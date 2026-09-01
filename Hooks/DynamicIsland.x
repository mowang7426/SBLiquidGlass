#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 私有类声明

// 声明系统灵动岛容器视图
@interface SBSystemApertureContainerView : UIView
@end

// 声明 nice 灵动岛自定义视图
@interface NBXLddClassic2View : UIView
@end

@interface NBXLddClassic3View : UIView
@end

#pragma mark - 安全的灵动岛液态玻璃实现

static void *kDIGlassKey = &kDIGlassKey;

// 安全地应用液态玻璃效果到指定视图
static void diSafeApplyGlass(UIView *view) {
    @try {
        if (!view) return;
        if (!lgHostEnabled(@"DynamicIsland")) return;
        
        // 检查是否已经应用
        if (objc_getAssociatedObject(view, kDIGlassKey)) return;
        
        // 安全检查：视图必须有有效的 frame
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10 || CGRectGetHeight(view.bounds) < 5) return;
        
        NSLog(@"[SBLiquidGlass-DI] Applying to %@ frame=%@", NSStringFromClass(view.class), NSStringFromCGRect(view.frame));
        
        // 获取 filterType
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";
        
        // 创建液态玻璃背景视图
        LGLiveBackdropView *glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds
                                                                       groupName:nil
                                                                      filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        glass.alpha = 0.9;
        
        // 插入到目标视图的下面
        UIView *superview = view.superview;
        if (superview) {
            [superview insertSubview:glass belowSubview:view];
        }
        
        // 关联到目标视图
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 延迟应用滤镜
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [glass applyFilters];
            } @catch (__unused NSException *e) {}
        });
        
        NSLog(@"[SBLiquidGlass-DI] Done applying to %@", NSStringFromClass(view.class));
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception: %@", e);
    }
}

// 安全地移除液态玻璃效果
static void diSafeRemoveGlass(UIView *view) {
    @try {
        if (!view) return;
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
}

// 更新液态玻璃视图的 frame
static void diSafeUpdateGlass(UIView *view) {
    @try {
        if (!view) return;
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            glass.frame = view.bounds;
            CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
            glass.layer.cornerRadius = cornerRadius;
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook 系统灵动岛容器视图

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diSafeApplyGlass(self);
        } else {
            diSafeRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diSafeApplyGlass(self);
        diSafeUpdateGlass(self);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook nice 灵动岛自定义视图

%hook NBXLddClassic2View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diSafeApplyGlass(self);
        } else {
            diSafeRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diSafeApplyGlass(self);
        diSafeUpdateGlass(self);
    } @catch (__unused NSException *e) {}
}

%end

%hook NBXLddClassic3View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diSafeApplyGlass(self);
        } else {
            diSafeRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diSafeApplyGlass(self);
        diSafeUpdateGlass(self);
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (safe version with private class declarations)");
    } @catch (__unused NSException *e) {}
}
