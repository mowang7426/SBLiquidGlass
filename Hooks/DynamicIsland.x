#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 私有类声明

@interface SBSystemApertureContainerView : UIView
@end

#pragma mark - 全局变量

static void *kDISystemGlassKey = &kDISystemGlassKey;

#pragma mark - 只清除灵动岛容器内部的 MTMaterialView

static void diClearIslandMaterialViews(UIView *container) {
    @try {
        if (!container) return;
        
        // 只遍历容器内部的子视图，不影响外部
        for (UIView *sub in [container.subviews copy]) {
            NSString *className = NSStringFromClass(sub.class);
            
            // 只隐藏 MTMaterialView，不影响其他视图
            if ([className isEqualToString:@"MTMaterialView"]) {
                sub.hidden = YES;
                sub.backgroundColor = [UIColor clearColor];
                if (sub.layer.backgroundColor) {
                    sub.layer.backgroundColor = [UIColor clearColor].CGColor;
                }
                NSLog(@"[SBLiquidGlass-DI] Hid MTMaterialView in island");
            }
            
            // 关闭 UIVisualEffectView 的 effect
            if ([sub isKindOfClass:[UIVisualEffectView class]]) {
                UIVisualEffectView *ev = (UIVisualEffectView *)sub;
                ev.effect = nil;
            }
            
            // 只递归一层，不深入递归，避免影响其他视图
            for (UIView *subsub in [sub.subviews copy]) {
                NSString *subsubClassName = NSStringFromClass(subsub.class);
                if ([subsubClassName isEqualToString:@"MTMaterialView"]) {
                    subsub.hidden = YES;
                    subsub.backgroundColor = [UIColor clearColor];
                    if (subsub.layer.backgroundColor) {
                        subsub.layer.backgroundColor = [UIColor clearColor].CGColor;
                    }
                }
                if ([subsub isKindOfClass:[UIVisualEffectView class]]) {
                    UIVisualEffectView *ev = (UIVisualEffectView *)subsub;
                    ev.effect = nil;
                }
            }
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 系统灵动岛透明 + 液态玻璃效果

static void diApplySystemIslandLiquidGlass(SBSystemApertureContainerView *container) {
    @try {
        if (!container || !container.window) return;
        if (!lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(container.bounds) || CGRectGetWidth(container.bounds) < 10) return;
        
        // 查找或创建液态玻璃视图
        LGLiveBackdropView *glass = objc_getAssociatedObject(container, kDISystemGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";
            
            glass = [[LGLiveBackdropView alloc] initWithFrame:container.bounds
                                                     groupName:nil
                                                    filterType:filterType];
            glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            glass.userInteractionEnabled = NO; // 确保不影响点击
            glass.backgroundColor = [UIColor clearColor];
            glass.opaque = NO;
            
            // 把液态玻璃视图添加到容器内部的最底层
            [container insertSubview:glass atIndex:0];
            
            objc_setAssociatedObject(container, kDISystemGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            NSLog(@"[SBLiquidGlass-DI] Created liquid glass for system island container");
        }
        
        // 更新液态玻璃视图的 frame 和圆角
        glass.frame = container.bounds;
        CGFloat cornerRadius = container.layer.cornerRadius > 0 ? container.layer.cornerRadius : CGRectGetHeight(container.bounds) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        // 确保液态玻璃视图在容器内部的最底层
        if ([container.subviews firstObject] != glass) {
            [container insertSubview:glass atIndex:0];
        }
        
        // 清除容器自身的背景
        container.backgroundColor = [UIColor clearColor];
        container.opaque = NO;
        if (container.layer.backgroundColor) {
            container.layer.backgroundColor = [UIColor clearColor].CGColor;
        }
        
        // 只清除容器内部的 MTMaterialView，不影响其他视图
        diClearIslandMaterialViews(container);
        
        // 应用滤镜
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        
        // 延迟再次清除（系统可能会重新显示 MTMaterialView）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           @try {
                               diClearIslandMaterialViews(container);
                               [glass applyFilters];
                           } @catch (__unused NSException *e) {}
                       });
        
        NSLog(@"[SBLiquidGlass-DI] System island liquid glass applied");
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

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (conservative system island)");
    } @catch (__unused NSException *e) {}
}
