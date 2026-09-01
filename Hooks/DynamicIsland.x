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

#pragma mark - 递归清除背景

// 递归清除视图及其所有子视图的背景色
static void diClearBackgroundRecursive(UIView *view) {
    @try {
        if (!view) return;
        
        // 清除当前视图的背景色
        view.backgroundColor = [UIColor clearColor];
        
        // 清除 layer 的背景色
        view.layer.backgroundColor = [UIColor clearColor].CGColor;
        
        // 递归清除子视图
        for (UIView *subview in view.subviews) {
            diClearBackgroundRecursive(subview);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 液态玻璃效果实现

static void *kDIGlassKey = &kDIGlassKey;
static void *kDIClearedKey = &kDIClearedKey;

// 应用液态玻璃效果到灵动岛视图
static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10) return;
        
        NSLog(@"[SBLiquidGlass-DI] Applying to %@ (nice=%d) frame=%@",
              NSStringFromClass(view.class), isNiceIsland, NSStringFromCGRect(view.frame));
        
        // 如果是 nice 灵动岛，先递归清除所有背景
        if (isNiceIsland && !objc_getAssociatedObject(view, kDIClearedKey)) {
            diClearBackgroundRecursive(view);
            objc_setAssociatedObject(view, kDIClearedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[SBLiquidGlass-DI] Cleared all backgrounds recursively");
        }
        
        // 检查是否已经应用了液态玻璃
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            // 更新 frame
            if (isNiceIsland) {
                if (!CGRectEqualToRect(glass.frame, view.frame)) {
                    glass.frame = view.frame;
                }
            } else {
                if (!CGRectEqualToRect(glass.frame, view.bounds)) {
                    glass.frame = view.bounds;
                }
            }
            CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
            if (fabs(glass.layer.cornerRadius - cornerRadius) > 0.5) {
                glass.layer.cornerRadius = cornerRadius;
            }
            return;
        }
        
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";
        
        // 创建液态玻璃视图
        CGRect glassFrame = isNiceIsland ? view.frame : view.bounds;
        glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                 groupName:nil
                                                filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight |
                                 UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        if (isNiceIsland) {
            // nice 灵动岛：添加到父视图中，位于 view 下面
            UIView *superview = view.superview;
            if (superview) {
                [superview insertSubview:glass belowSubview:view];
                NSLog(@"[SBLiquidGlass-DI] Inserted glass below view in superview: %@", NSStringFromClass(superview.class));
            }
        } else {
            // 系统灵动岛：添加到内部最底层
            [view insertSubview:glass atIndex:0];
            view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.1];
        }
        
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 延迟应用滤镜
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        });
        
        NSLog(@"[SBLiquidGlass-DI] Done applying glass");
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception: %@", e);
    }
}

// 移除液态玻璃效果
static void diRemoveGlass(UIView *view) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
        objc_setAssociatedObject(view, kDIClearedKey, nil, OBJC_ASSOCIATION_ASSIGN);
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
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (recursive background clear)");
    } @catch (__unused NSException *e) {}
}
