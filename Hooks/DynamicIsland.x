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

#pragma mark - 系统灵动岛透明 + 液态玻璃效果

static void diApplySystemIslandLiquidGlass(UIView *container) {
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
            glass.userInteractionEnabled = NO;
            glass.backgroundColor = [UIColor clearColor];
            glass.opaque = NO;
            
            // 把液态玻璃视图添加到容器的最底层
            [container insertSubview:glass atIndex:0];
            
            objc_setAssociatedObject(container, kDISystemGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            NSLog(@"[SBLiquidGlass-DI] Created liquid glass for system island");
        }
        
        // 更新液态玻璃视图的 frame 和圆角
        glass.frame = container.bounds;
        CGFloat cornerRadius = container.layer.cornerRadius > 0 ? container.layer.cornerRadius : CGRectGetHeight(container.bounds) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        // 确保液态玻璃视图在最底层
        if ([container.subviews firstObject] != glass) {
            [container insertSubview:glass atIndex:0];
        }
        
        // 清除容器自身的背景
        container.backgroundColor = [UIColor clearColor];
        container.opaque = NO;
        if (container.layer.backgroundColor) {
            container.layer.backgroundColor = [UIColor clearColor].CGColor;
        }
        
        // 遍历子视图，清除所有 MTMaterialView 和不透明的背景
        for (UIView *sub in [container.subviews copy]) {
            if (sub == glass) continue;
            
            // 清除背景
            sub.backgroundColor = [UIColor clearColor];
            sub.opaque = NO;
            if (sub.layer.backgroundColor) {
                sub.layer.backgroundColor = [UIColor clearColor].CGColor;
            }
            
            // 如果是 MTMaterialView，隐藏它（液态玻璃视图已经替换了它的位置）
            if ([NSStringFromClass(sub.class) isEqualToString:@"MTMaterialView"]) {
                sub.hidden = YES;
            }
            
            // 如果是 UIVisualEffectView，关闭 effect
            if ([sub isKindOfClass:[UIVisualEffectView class]]) {
                UIVisualEffectView *ev = (UIVisualEffectView *)sub;
                ev.effect = nil;
            }
            
            // 递归清除子视图的背景
            for (UIView *subsub in [sub.subviews copy]) {
                subsub.backgroundColor = [UIColor clearColor];
                subsub.opaque = NO;
                if (subsub.layer.backgroundColor) {
                    subsub.layer.backgroundColor = [UIColor clearColor].CGColor;
                }
                if ([NSStringFromClass(subsub.class) isEqualToString:@"MTMaterialView"]) {
                    subsub.hidden = YES;
                }
                if ([subsub isKindOfClass:[UIVisualEffectView class]]) {
                    UIVisualEffectView *ev = (UIVisualEffectView *)subsub;
                    ev.effect = nil;
                }
            }
        }
        
        // 应用滤镜
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        
        NSLog(@"[SBLiquidGlass-DI] System island liquid glass applied");
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception: %@", e);
    }
}

static void diRemoveSystemIslandGlass(UIView *container) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(container, kDISystemGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(container, kDISystemGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook 系统灵动岛容器视图

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplySystemIslandLiquidGlass(self);
        } else {
            diRemoveSystemIslandGlass(self);
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
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (system island transparent + liquid)");
    } @catch (__unused NSException *e) {}
}
