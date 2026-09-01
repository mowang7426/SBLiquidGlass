#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 灵动岛视图识别（通过位置和尺寸）

static void *kDIGlassKey = &kDIGlassKey;
static void *kDIAppliedKey = &kDIAppliedKey;

// 检查视图是否在灵动岛的位置（屏幕顶部中央）
static BOOL diIsInDynamicIslandPosition(UIView *view) {
    @try {
        UIWindow *window = view.window;
        if (!window) return NO;
        
        CGRect frameInWindow = [view convertRect:view.bounds toView:window];
        CGRect screenBounds = window.bounds;
        
        CGFloat centerX = CGRectGetMidX(frameInWindow);
        CGFloat screenCenterX = CGRectGetMidX(screenBounds);
        CGFloat topY = CGRectGetMinY(frameInWindow);
        CGFloat width = CGRectGetWidth(frameInWindow);
        CGFloat height = CGRectGetHeight(frameInWindow);
        
        // 灵动岛通常在屏幕顶部中央
        BOOL isNearTop = topY < 100.0 && topY >= 0.0;
        BOOL isNearCenter = fabs(centerX - screenCenterX) < 200.0;
        // 灵动岛尺寸范围
        BOOL hasReasonableSize = width > 80.0 && width < 500.0 && height > 15.0 && height < 120.0;
        // 宽高比（灵动岛通常是宽大于高）
        BOOL hasReasonableRatio = width > height * 1.5;
        
        return isNearTop && isNearCenter && hasReasonableSize && hasReasonableRatio;
    } @catch (__unused NSException *e) {}
    return NO;
}

// 检查视图是否适合作为液态玻璃的目标（有背景色或模糊效果）
static BOOL diIsSuitableForGlass(UIView *view) {
    @try {
        // 排除已经应用了液态玻璃的视图
        if (objc_getAssociatedObject(view, kDIAppliedKey)) return NO;
        
        // 排除 LGLiveBackdropView 本身
        if ([view isKindOfClass:NSClassFromString(@"LGLiveBackdropView")]) return NO;
        
        // 排除纯透明视图
        if (view.alpha < 0.1) return NO;
        if (view.hidden) return NO;
        
        // 检查是否有背景色或模糊效果
        BOOL hasBackgroundColor = view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0.01;
        BOOL isVisualEffectView = [view isKindOfClass:NSClassFromString(@"UIVisualEffectView")];
        BOOL hasBlur = [view isKindOfClass:NSClassFromString(@"MTMaterialView")] ||
                       [view isKindOfClass:NSClassFromString(@"_SBAdaptiveKeyLineBackdropView")];
        
        return hasBackgroundColor || isVisualEffectView || hasBlur;
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 液态玻璃效果应用

static void diApplyGlassToView(UIView *view) {
    @try {
        if (!lgHostEnabled(@"DynamicIsland")) return;
        if (!diIsInDynamicIslandPosition(view)) return;
        if (!diIsSuitableForGlass(view)) return;
        
        // 标记已经应用
        objc_setAssociatedObject(view, kDIAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        NSLog(@"[SBLiquidGlass-DI] Found dynamic island view: %@ frame=%@ backgroundColor=%@",
              NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.backgroundColor);
        
        // 获取 filterType
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";
        
        // 创建液态玻璃背景视图
        LGLiveBackdropView *glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds
                                                                       groupName:nil
                                                                      filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.layer.cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        // 插入到目标视图的下面
        UIView *superview = view.superview;
        if (superview) {
            [superview insertSubview:glass belowSubview:view];
        } else {
            [view addSubview:glass];
        }
        
        // 关联到目标视图
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 应用滤镜（延迟应用，确保视图已经布局完成）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [glass applyFilters];
            } @catch (__unused NSException *e) {}
        });
        
        NSLog(@"[SBLiquidGlass-DI] Glass applied successfully to %@", NSStringFromClass(view.class));
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception while applying glass: %@", e);
    }
}

static void diRemoveGlassFromView(UIView *view) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        objc_setAssociatedObject(view, kDIAppliedKey, nil, OBJC_ASSOCIATION_ASSIGN);
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook UIView（通用识别）

%hook UIView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
        // 更新已有的液态玻璃视图的 frame
        LGLiveBackdropView *glass = objc_getAssociatedObject(self, kDIGlassKey);
        if (glass) {
            glass.frame = self.bounds;
            glass.layer.cornerRadius = self.layer.cornerRadius > 0 ? self.layer.cornerRadius : CGRectGetHeight(self.bounds) * 0.5;
        }
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (position-based detection)");
    } @catch (__unused NSException *e) {}
}
