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

#pragma mark - 液态玻璃效果实现

static void *kDIGlassKey = &kDIGlassKey;

// 应用液态玻璃效果到系统灵动岛（添加到内部最底层）
static void diApplyGlassToSystemIsland(UIView *view) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (objc_getAssociatedObject(view, kDIGlassKey)) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10) return;
        
        NSLog(@"[SBLiquidGlass-DI] Applying to system island: %@", NSStringFromClass(view.class));
        
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";
        
        LGLiveBackdropView *glass = [[LGLiveBackdropView alloc] initWithFrame:view.bounds
                                                                       groupName:nil
                                                                      filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        // 系统灵动岛：添加到内部最底层
        [view insertSubview:glass atIndex:0];
        view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.1];
        
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        });
    } @catch (__unused NSException *e) {}
}

// 应用液态玻璃效果到 nice 灵动岛（添加到父视图中，位于 view 下面）
static void diApplyGlassToNiceIsland(UIView *view) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (objc_getAssociatedObject(view, kDIGlassKey)) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10) return;
        
        UIView *superview = view.superview;
        if (!superview) return;
        
        NSLog(@"[SBLiquidGlass-DI] Applying to nice island: %@ frame=%@ superview=%@",
              NSStringFromClass(view.class), NSStringFromCGRect(view.frame), NSStringFromClass(superview.class));
        
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";
        
        // nice 灵动岛：使用 view.frame（在父视图中的位置），添加到父视图中，位于 view 下面
        LGLiveBackdropView *glass = [[LGLiveBackdropView alloc] initWithFrame:view.frame
                                                                       groupName:nil
                                                                      filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        
        // 添加到父视图中，位于 view 下面
        [superview insertSubview:glass belowSubview:view];
        
        // 把 nice 灵动岛的背景设置为完全透明，让液态玻璃效果透出来
        view.backgroundColor = [UIColor clearColor];
        
        // 遍历子视图，把背景视图也设置为透明
        for (UIView *subview in view.subviews) {
            @try {
                NSString *subClassName = NSStringFromClass(subview.class);
                if ([subClassName containsString:@"Backdrop"] ||
                    [subClassName containsString:@"Background"] ||
                    [subClassName containsString:@"Blur"] ||
                    [subClassName containsString:@"Material"] ||
                    [subClassName containsString:@"KeyLine"]) {
                    subview.backgroundColor = [UIColor clearColor];
                    subview.alpha = 0.0;
                    subview.hidden = YES;
                    NSLog(@"[SBLiquidGlass-DI] Hid nice island background: %@", subClassName);
                }
            } @catch (__unused NSException *e) {}
        }
        
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        });
        
        NSLog(@"[SBLiquidGlass-DI] Done applying to nice island");
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception: %@", e);
    }
}

// 更新液态玻璃视图的 frame
static void diUpdateGlassFrame(UIView *view, BOOL isNiceIsland) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (!glass) return;
        
        if (isNiceIsland) {
            // nice 灵动岛：glass 在父视图中，frame 应该等于 view.frame
            if (!CGRectEqualToRect(glass.frame, view.frame)) {
                glass.frame = view.frame;
            }
        } else {
            // 系统灵动岛：glass 在 view 内部，frame 应该等于 view.bounds
            if (!CGRectEqualToRect(glass.frame, view.bounds)) {
                glass.frame = view.bounds;
            }
        }
        
        CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
        if (fabs(glass.layer.cornerRadius - cornerRadius) > 0.5) {
            glass.layer.cornerRadius = cornerRadius;
        }
    } @catch (__unused NSException *e) {}
}

// 移除液态玻璃效果
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
            diApplyGlassToSystemIsland(self);
        } else {
            diRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToSystemIsland(self);
        diUpdateGlassFrame(self, NO);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook nice 灵动岛自定义视图

%hook NBXLddClassic2View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToNiceIsland(self);
        } else {
            diRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToNiceIsland(self);
        diUpdateGlassFrame(self, YES);
    } @catch (__unused NSException *e) {}
}

%end

%hook NBXLddClassic3View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToNiceIsland(self);
        } else {
            diRemoveGlass(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToNiceIsland(self);
        diUpdateGlassFrame(self, YES);
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (nice island below view approach)");
    } @catch (__unused NSException *e) {}
}
