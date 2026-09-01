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

#pragma mark - 检查视图是否在灵动岛层级中

static BOOL diIsInDynamicIslandHierarchy(UIView *view) {
    @try {
        UIView *candidate = view;
        for (NSInteger level = 0; candidate && level < 15; level++, candidate = candidate.superview) {
            NSString *className = NSStringFromClass(candidate.class);
            if ([className containsString:@"Aperture"] ||
                [className containsString:@"DynamicIsland"] ||
                [className containsString:@"Island"] ||
                [className hasPrefix:@"NBX"] ||
                [className containsString:@"NiceAperture"]) {
                return YES;
            }
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 超级彻底的背景清除（递归）

static void diUltimateClearBackground(UIView *view) {
    @try {
        if (!view) return;
        
        // 1. 清除 backgroundColor
        view.backgroundColor = [UIColor clearColor];
        
        // 2. 清除 layer.backgroundColor
        view.layer.backgroundColor = [UIColor clearColor].CGColor;
        
        // 3. 清除 layer.contents（如果是黑色图片）
        if (view.layer.contents) {
            // 检查 contents 是否是图片
            if ([view.layer.contents isKindOfClass:[UIImage class]] ||
                CFGetTypeID((__bridge CFTypeRef)view.layer.contents) == CGImageGetTypeID()) {
                view.layer.contents = nil;
            }
        }
        
        // 4. 如果是 UIVisualEffectView，清除 effect
        if ([view isKindOfClass:NSClassFromString(@"UIVisualEffectView")]) {
            UIVisualEffectView *ev = (UIVisualEffectView *)view;
            ev.effect = nil;
        }
        
        // 5. 尝试查找并隐藏背景视图（通过属性名）
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([view class], &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *name = ivar_getName(ivar);
            if (name) {
                NSString *ivarName = [NSString stringWithUTF8String:name];
                // 查找背景相关的属性
                if ([ivarName.lowercaseString containsString:@"bgview"] ||
                    [ivarName.lowercaseString containsString:@"backgroundview"] ||
                    [ivarName.lowercaseString containsString:@"backdrop"] ||
                    [ivarName.lowercaseString containsString:@"blackview"]) {
                    id bgView = object_getIvar(view, ivar);
                    if (bgView && [bgView isKindOfClass:[UIView class]]) {
                        UIView *bg = (UIView *)bgView;
                        bg.hidden = YES;
                        bg.alpha = 0.0;
                        bg.backgroundColor = [UIColor clearColor];
                        NSLog(@"[SBLiquidGlass-DI] Hid background ivar: %@", ivarName);
                    }
                }
            }
        }
        if (ivars) free(ivars);
        
        // 6. 递归清除子视图
        for (UIView *subview in view.subviews) {
            diUltimateClearBackground(subview);
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Clear exception: %@", e);
    }
}

#pragma mark - 液态玻璃效果实现

static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10) return;
        
        NSLog(@"[SBLiquidGlass-DI] Applying to %@ (nice=%d)", NSStringFromClass(view.class), isNiceIsland);
        
        // 如果是 nice 灵动岛，进行超级彻底的背景清除
        if (isNiceIsland) {
            diUltimateClearBackground(view);
            // 延迟持续清除（背景可能在后面才设置）
            for (NSNumber *delay in @[@0.1, @0.3, @0.5, @1.0, @2.0, @3.0, @5.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    @try { diUltimateClearBackground(view); } @catch (__unused NSException *e) {}
                });
            }
            NSLog(@"[SBLiquidGlass-DI] Ultimate background clear done");
        }
        
        // 检查是否已经应用了液态玻璃
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            if (isNiceIsland) {
                if (!CGRectEqualToRect(glass.frame, view.frame)) glass.frame = view.frame;
            } else {
                if (!CGRectEqualToRect(glass.frame, view.bounds)) glass.frame = view.bounds;
            }
            CGFloat cornerRadius = view.layer.cornerRadius > 0 ? view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
            if (fabs(glass.layer.cornerRadius - cornerRadius) > 0.5) {
                glass.layer.cornerRadius = cornerRadius;
            }
            return;
        }
        
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType) filterType = @"dylv.liquidglass.dynamicisland";
        
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
            UIView *superview = view.superview;
            if (superview) {
                [superview insertSubview:glass belowSubview:view];
            }
        } else {
            [view insertSubview:glass atIndex:0];
            view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.1];
        }
        
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        });
        
        NSLog(@"[SBLiquidGlass-DI] Done applying glass");
    } @catch (__unused NSException *e) {
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
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (ultimate clear version)");
    } @catch (__unused NSException *e) {}
}
