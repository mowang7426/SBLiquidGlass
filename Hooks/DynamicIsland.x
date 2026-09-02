#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 私有类声明

@interface SBSystemApertureContainerView : UIView
@end

@interface _SBSystemApertureMagiciansCurtainView : UIView
@end

#pragma mark - 全局变量

static void *kDISystemGlassKey = &kDISystemGlassKey;
static void *kDIDidProcessKey = &kDIDidProcessKey;

#pragma mark - 递归清除所有黑色背景

static void diRecursivelyClearAllBlackBackgrounds(UIView *view, NSInteger depth) {
    if (!view || depth > 12) return;
    @try {
        // 清除当前视图的背景
        view.backgroundColor = [UIColor clearColor];
        view.opaque = NO;
        if (view.layer.backgroundColor) {
            view.layer.backgroundColor = [UIColor clearColor].CGColor;
        }
        if (view.layer.contents) {
            view.layer.contents = nil;
        }
        
        // 如果是 MTMaterialView，隐藏它
        if ([NSStringFromClass(view.class) isEqualToString:@"MTMaterialView"]) {
            view.hidden = YES;
        }
        
        // 如果是 UIVisualEffectView，关闭 effect
        if ([view isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *ev = (UIVisualEffectView *)view;
            ev.effect = nil;
        }
        
        // 清除所有 sublayers
        for (CALayer *layer in [view.layer.sublayers copy]) {
            if (layer.backgroundColor) {
                layer.backgroundColor = [UIColor clearColor].CGColor;
            }
            if (layer.contents) {
                layer.contents = nil;
            }
            if ([layer isKindOfClass:[CAShapeLayer class]]) {
                CAShapeLayer *shape = (CAShapeLayer *)layer;
                shape.fillColor = [UIColor clearColor].CGColor;
                shape.strokeColor = [UIColor clearColor].CGColor;
            }
        }
        
        // 递归处理子视图
        for (UIView *sub in [view.subviews copy]) {
            diRecursivelyClearAllBlackBackgrounds(sub, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 找到最顶层的灵动岛容器

static UIView *diFindTopLevelIslandContainer(UIView *view) {
    if (!view) return nil;
    
    // 向上查找，找到最顶层的灵动岛相关容器
    UIView *current = view;
    UIView *topContainer = nil;
    
    while (current) {
        NSString *className = NSStringFromClass(current.class);
        if ([className containsString:@"Aperture"] ||
            [className containsString:@"Island"] ||
            [className containsString:@"Curtain"] ||
            [className containsString:@"Pill"] ||
            [className containsString:@"Platter"]) {
            topContainer = current;
        }
        current = current.superview;
    }
    
    return topContainer ?: view;
}

#pragma mark - 系统灵动岛透明 + 液态玻璃效果

static void diApplySystemIslandLiquidGlass(UIView *view) {
    @try {
        if (!view || !view.window) return;
        if (!lgHostEnabled(@"DynamicIsland")) return;
        
        // 找到最顶层的灵动岛容器
        UIView *container = diFindTopLevelIslandContainer(view);
        if (!container) container = view;
        
        // 避免重复处理
        if (objc_getAssociatedObject(container, kDIDidProcessKey)) {
            // 已经处理过，只需要更新 frame 和清除背景
            LGLiveBackdropView *glass = objc_getAssociatedObject(container, kDISystemGlassKey);
            if (glass) {
                glass.frame = container.bounds;
                CGFloat cornerRadius = container.layer.cornerRadius > 0 ? container.layer.cornerRadius : CGRectGetHeight(container.bounds) * 0.5;
                glass.layer.cornerRadius = cornerRadius;
                [container insertSubview:glass atIndex:0];
            }
            diRecursivelyClearAllBlackBackgrounds(container, 0);
            return;
        }
        
        if (CGRectIsEmpty(container.bounds) || CGRectGetWidth(container.bounds) < 10) return;
        
        // 标记已经处理
        objc_setAssociatedObject(container, kDIDidProcessKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        NSLog(@"[SBLiquidGlass-DI] Processing island container: %@ frame=%@",
              NSStringFromClass(container.class), NSStringFromCGRect(container.frame));
        
        // 创建液态玻璃视图
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";
        
        LGLiveBackdropView *glass = [[LGLiveBackdropView alloc] initWithFrame:container.bounds
                                                                       groupName:nil
                                                                      filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.userInteractionEnabled = NO;
        glass.backgroundColor = [UIColor clearColor];
        glass.opaque = NO;
        
        CGFloat cornerRadius = container.layer.cornerRadius > 0 ? container.layer.cornerRadius : CGRectGetHeight(container.bounds) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        // 把液态玻璃视图添加到容器的最底层
        [container insertSubview:glass atIndex:0];
        
        objc_setAssociatedObject(container, kDISystemGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 递归清除所有黑色背景
        diRecursivelyClearAllBlackBackgrounds(container, 0);
        
        // 应用滤镜
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        
        // 延迟再次清除和应用（因为系统可能会重新设置背景）
        for (NSNumber *delay in @[@0.1, @0.3, @0.5, @1.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               @try {
                                   diRecursivelyClearAllBlackBackgrounds(container, 0);
                                   [glass applyFilters];
                               } @catch (__unused NSException *e) {}
                           });
        }
        
        NSLog(@"[SBLiquidGlass-DI] System island liquid glass applied to: %@", NSStringFromClass(container.class));
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception: %@", e);
    }
}

#pragma mark - Hook 系统灵动岛容器视图

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplySystemIslandLiquidGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplySystemIslandLiquidGlass(self);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook 系统灵动岛 Curtain 视图（展开后的面板）

%hook _SBSystemApertureMagiciansCurtainView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplySystemIslandLiquidGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplySystemIslandLiquidGlass(self);
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (aggressive system island)");
    } @catch (__unused NSException *e) {}
}
