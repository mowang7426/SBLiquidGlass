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
static IMP sOriginalSetBackgroundColor = NULL;
static BOOL sSwizzled = NO;

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

#pragma mark - Swizzle 后的 setBackgroundColor:

static void diSetBackgroundColor(id self, SEL _cmd, UIColor *color) {
    @try {
        // 调用原始实现
        if (sOriginalSetBackgroundColor) {
            ((void (*)(id, SEL, UIColor *))sOriginalSetBackgroundColor)(self, _cmd, color);
        }
        
        // 如果视图在灵动岛层级中，并且设置的是黑色或深色背景，改成透明
        if (color && [self isKindOfClass:[UIView class]]) {
            UIView *view = (UIView *)self;
            if (diIsInDynamicIslandHierarchy(view)) {
                CGFloat white = 0, alpha = 0;
                if ([color respondsToSelector:@selector(getWhite:alpha:)]) {
                    [color getWhite:&white alpha:&alpha];
                    if (white < 0.2 && alpha > 0.1) {
                        // 延迟改成透明，避免递归
                        dispatch_async(dispatch_get_main_queue(), ^{
                            @try {
                                view.backgroundColor = [UIColor clearColor];
                            } @catch (__unused NSException *e) {}
                        });
                    }
                }
            }
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 执行 Swizzle

static void diSwizzleSetBackgroundColor(void) {
    @try {
        if (sSwizzled) return;
        sSwizzled = YES;
        
        Class uiViewClass = [UIView class];
        SEL selector = @selector(setBackgroundColor:);
        Method method = class_getInstanceMethod(uiViewClass, selector);
        if (method) {
            sOriginalSetBackgroundColor = method_getImplementation(method);
            method_setImplementation(method, (IMP)diSetBackgroundColor);
            NSLog(@"[SBLiquidGlass-DI] Swizzled setBackgroundColor:");
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Swizzle exception: %@", e);
    }
}

#pragma mark - 递归清除背景

static void diClearBackgroundRecursive(UIView *view) {
    @try {
        if (!view) return;
        view.backgroundColor = [UIColor clearColor];
        view.layer.backgroundColor = [UIColor clearColor].CGColor;
        for (UIView *subview in view.subviews) {
            diClearBackgroundRecursive(subview);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 液态玻璃效果实现

static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10) return;
        
        NSLog(@"[SBLiquidGlass-DI] Applying to %@ (nice=%d)", NSStringFromClass(view.class), isNiceIsland);
        
        // 如果是 nice 灵动岛，进行强力背景清除
        if (isNiceIsland) {
            diClearBackgroundRecursive(view);
            // 延迟持续清除
            for (NSNumber *delay in @[@0.1, @0.3, @0.5, @1.0, @2.0, @3.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    @try { diClearBackgroundRecursive(view); } @catch (__unused NSException *e) {}
                });
            }
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
        diSwizzleSetBackgroundColor();
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (runtime swizzle version)");
    } @catch (__unused NSException *e) {}
}
