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

#pragma mark - 增强版背景节点识别

static BOOL diNameLooksLikeBackground(NSString *name) {
    if (!name.length) return NO;
    NSString *n = name.lowercaseString;
    // 增强识别：增加更多背景相关的关键词
    return [n containsString:@"background"] ||
           [n containsString:@"backdrop"] ||
           [n containsString:@"platter"] ||
           [n isEqualToString:@"bgview"] ||
           [n containsString:@".bg"] ||
           [n containsString:@"material"] ||
           [n containsString:@"black"] ||
           [n containsString:@"dark"] ||
           [n containsString:@"overlay"] ||
           [n containsString:@"cover"] ||
           [n containsString:@"mask"] ||
           [n containsString:@"fill"] ||
           [n containsString:@"color"];
}

#pragma mark - 增强版背景清除（更彻底）

static void diClearNiceBackgroundTree(UIView *view, NSInteger depth) {
    if (!view || depth > 10) return; // 增加深度到10层
    @try {
        // 根 View 本身只清理背景色，不改变 alpha
        if (depth == 0) {
            view.backgroundColor = [UIColor clearColor];
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
        }
        
        // 处理名字明确指向背景/材质的子 View
        for (UIView *sub in [view.subviews copy]) {
            NSString *className = NSStringFromClass(sub.class);
            if (diNameLooksLikeBackground(className)) {
                // 更彻底的清除
                sub.backgroundColor = [UIColor clearColor];
                sub.layer.backgroundColor = UIColor.clearColor.CGColor;
                sub.alpha = 0.0;
                sub.hidden = YES; // 直接隐藏背景视图
                
                // 清除 layer.contents（如果是黑色图片）
                if (sub.layer.contents) {
                    sub.layer.contents = nil;
                }
                
                // 清除所有 sublayers 的背景色
                for (CALayer *layer in [sub.layer.sublayers copy]) {
                    if (layer.backgroundColor) {
                        layer.backgroundColor = UIColor.clearColor.CGColor;
                    }
                    if (layer.contents) {
                        layer.contents = nil;
                    }
                }
                
                NSLog(@"[SBLiquidGlass-DI] Cleared Nice background node: %@ (depth=%ld)", className, (long)depth);
            }
            diClearNiceBackgroundTree(sub, depth + 1);
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Clear exception: %@", e);
    }
}

#pragma mark - 确保玻璃视图在最底层

static void diEnsureGlassAtBottom(UIView *view, LGLiveBackdropView *glass) {
    @try {
        if (!view || !glass) return;
        // 确保玻璃视图在最底层
        if ([view.subviews firstObject] != glass) {
            [view insertSubview:glass atIndex:0];
            NSLog(@"[SBLiquidGlass-DI] Moved glass to bottom");
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 同步玻璃视图

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
        glass.hidden = NO;
        glass.alpha = 1.0;
        
        // 确保玻璃视图在最底层
        diEnsureGlassAtBottom(view, glass);
    } @catch (__unused NSException *e) {}
}

#pragma mark - 液态玻璃效果实现（增强版）

static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) ||
            CGRectGetWidth(view.bounds) < 10 ||
            CGRectGetHeight(view.bounds) < 5) return;
        
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            if (isNiceIsland) {
                diSyncNiceGlass(view, glass);
                // 每次 Nice layout 后重新清理背景
                diClearNiceBackgroundTree(view, 0);
                // 重新应用滤镜，确保效果持续
                @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
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
        
        // Nice 的玻璃属于 Nice 自己的坐标系
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
        glass.alpha = 1.0;
        glass.backgroundColor = [UIColor clearColor];
        glass.hidden = NO;
        
        if (isNiceIsland) {
            // 先清掉 Nice 真正的背景节点
            diClearNiceBackgroundTree(view, 0);
            // 玻璃作为 Nice 自己的第一个子 View
            [view insertSubview:glass atIndex:0];
            // 再清一次，防止 Nice 的 layout 在插入过程中重新创建背景
            diClearNiceBackgroundTree(view, 0);
            // 确保玻璃在最底层
            diEnsureGlassAtBottom(view, glass);
        } else {
            [view insertSubview:glass atIndex:0];
            view.backgroundColor =
                [[UIColor blackColor] colorWithAlphaComponent:0.05];
        }
        
        objc_setAssociatedObject(view, kDIGlassKey, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 立即应用滤镜
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        
        // 延迟再次应用滤镜，确保视图完全布局后生效
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                [glass applyFilters];
                [glass updateSpecular];
                NSLog(@"[SBLiquidGlass-DI] Filters applied after delay");
            } @catch (__unused NSException *e) {}
        });
        
        // 再次延迟应用（确保动画完成后生效）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                [glass applyFilters];
                NSLog(@"[SBLiquidGlass-DI] Filters applied after 0.8s");
            } @catch (__unused NSException *e) {}
        });
        
        NSLog(@"[SBLiquidGlass-DI] Liquid Glass attached to %@ (nice=%d) frame=%@",
              NSStringFromClass(view.class), isNiceIsland, NSStringFromCGRect(glassFrame));
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
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (enhanced Nice Liquid Glass)");
    } @catch (__unused NSException *e) {}
}
