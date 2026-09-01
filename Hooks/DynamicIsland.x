#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 调试和识别

static void *kDIGlassKey = &kDIGlassKey;
static void *kDIAppliedKey = &kDIAppliedKey;
static NSInteger sDICheckCount = 0;

// 检查视图是否在灵动岛的位置（放宽条件）
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
        
        // 放宽条件：屏幕顶部区域，中央，合理尺寸
        BOOL isNearTop = topY < 150.0 && topY >= -50.0;
        BOOL isNearCenter = fabs(centerX - screenCenterX) < 250.0;
        BOOL hasReasonableSize = width > 50.0 && width < 600.0 && height > 10.0 && height < 150.0;
        BOOL hasReasonableRatio = width > height;
        
        return isNearTop && isNearCenter && hasReasonableSize && hasReasonableRatio;
    } @catch (__unused NSException *e) {}
    return NO;
}

// 检查视图类名是否包含灵动岛相关关键词
static BOOL diClassNameMatches(UIView *view) {
    @try {
        NSString *className = NSStringFromClass(view.class);
        return [className containsString:@"Aperture"] ||
               [className containsString:@"DynamicIsland"] ||
               [className containsString:@"Island"] ||
               [className hasPrefix:@"NBX"] ||
               [className containsString:@"NiceAperture"] ||
               [className containsString:@"Pill"] ||
               [className containsString:@"Capsule"];
    } @catch (__unused NSException *e) {}
    return NO;
}

// 检查 window 类名是否包含灵动岛相关关键词
static BOOL diWindowMatches(UIView *view) {
    @try {
        UIWindow *window = view.window;
        if (!window) return NO;
        NSString *windowClass = NSStringFromClass(window.class);
        return [windowClass containsString:@"Aperture"] ||
               [windowClass containsString:@"DynamicIsland"] ||
               [windowClass containsString:@"Island"];
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 液态玻璃效果应用

static void diApplyGlassToView(UIView *view) {
    @try {
        if (!lgHostEnabled(@"DynamicIsland")) return;
        if (objc_getAssociatedObject(view, kDIAppliedKey)) return;
        
        // 识别条件：类名匹配 OR window匹配 OR (位置匹配 AND 有背景)
        BOOL classMatch = diClassNameMatches(view);
        BOOL windowMatch = diWindowMatches(view);
        BOOL positionMatch = diIsInDynamicIslandPosition(view);
        BOOL hasBackground = view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0.01;
        
        BOOL shouldApply = classMatch || windowMatch || (positionMatch && hasBackground);
        
        if (!shouldApply) return;
        
        // 标记已经应用
        objc_setAssociatedObject(view, kDIAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        NSLog(@"[SBLiquidGlass-DI] >>> Applying to: %@ frame=%@ classMatch=%d windowMatch=%d posMatch=%d hasBG=%d",
              NSStringFromClass(view.class), NSStringFromCGRect(view.frame),
              classMatch, windowMatch, positionMatch, hasBackground);
        
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
            NSLog(@"[SBLiquidGlass-DI] Inserted below %@ in %@", NSStringFromClass(view.class), NSStringFromClass(superview.class));
        } else {
            [view addSubview:glass];
            NSLog(@"[SBLiquidGlass-DI] Added as subview");
        }
        
        // 关联到目标视图
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 应用滤镜
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                [glass applyFilters];
                NSLog(@"[SBLiquidGlass-DI] Filters applied");
            } @catch (__unused NSException *e) {
                NSLog(@"[SBLiquidGlass-DI] Filter apply exception: %@", e);
            }
        });
        
        NSLog(@"[SBLiquidGlass-DI] <<< Done applying to %@", NSStringFromClass(view.class));
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception: %@", e);
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

#pragma mark - Hook UIView

%hook UIView

- (void)didMoveToWindow {
    %orig;
    @try {
        sDICheckCount++;
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
        // 每 1000 次输出一次统计
        if (sDICheckCount % 1000 == 0) {
            NSLog(@"[SBLiquidGlass-DI] Checked %ld views", (long)sDICheckCount);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
        // 更新已有的液态玻璃视图
        LGLiveBackdropView *glass = objc_getAssociatedObject(self, kDIGlassKey);
        if (glass) {
            glass.frame = self.bounds;
            CGFloat cornerRadius = self.layer.cornerRadius > 0 ? self.layer.cornerRadius : CGRectGetHeight(self.bounds) * 0.5;
            glass.layer.cornerRadius = cornerRadius;
        }
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (debug version with extensive logging)");
    } @catch (__unused NSException *e) {}
}
