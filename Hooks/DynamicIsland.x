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

#pragma mark - 把背景改成半透明（模拟小白点效果）

static void diMakeBackgroundSemiTransparent(UIView *view) {
    @try {
        if (!view) return;
        
        // 1. 把当前视图的背景改成半透明的黑色（alpha 0.15），模拟小白点的效果
        UIColor *currentBG = view.backgroundColor;
        if (currentBG) {
            CGFloat white = 0, alpha = 0;
            if ([currentBG respondsToSelector:@selector(getWhite:alpha:)]) {
                [currentBG getWhite:&white alpha:&alpha];
                // 如果是深色背景，改成半透明
                if (white < 0.3 && alpha > 0.1) {
                    view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.12];
                }
            }
        }
        
        // 2. 把 layer.backgroundColor 也改成半透明
        if (view.layer.backgroundColor) {
            UIColor *layerBG = [UIColor colorWithCGColor:view.layer.backgroundColor];
            CGFloat white = 0, alpha = 0;
            if ([layerBG respondsToSelector:@selector(getWhite:alpha:)]) {
                [layerBG getWhite:&white alpha:&alpha];
                if (white < 0.3 && alpha > 0.1) {
                    view.layer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.12].CGColor;
                }
            }
        }
        
        // 3. 通过 KVC 访问 backgroundContainer，把它改成半透明
        @try {
            id bgContainer = [view valueForKey:@"backgroundContainer"];
            if (bgContainer && [bgContainer isKindOfClass:[UIView class]]) {
                UIView *bg = (UIView *)bgContainer;
                bg.alpha = 0.15;
                bg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.12];
                NSLog(@"[SBLiquidGlass-DI] Made backgroundContainer semi-transparent");
            }
        } @catch (__unused NSException *e) {}
        
        // 4. 通过 KVC 访问 bgView，把它改成半透明
        @try {
            id bgView = [view valueForKey:@"bgView"];
            if (bgView && [bgView isKindOfClass:[UIView class]]) {
                UIView *bg = (UIView *)bgView;
                bg.alpha = 0.15;
                bg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.12];
                NSLog(@"[SBLiquidGlass-DI] Made bgView semi-transparent");
            }
        } @catch (__unused NSException *e) {}
        
        // 5. 遍历对象的所有属性，查找背景相关的属性，改成半透明
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([view class], &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *name = ivar_getName(ivar);
            if (name) {
                NSString *ivarName = [NSString stringWithUTF8String:name];
                if ([ivarName.lowercaseString containsString:@"bg"] ||
                    [ivarName.lowercaseString containsString:@"background"] ||
                    [ivarName.lowercaseString containsString:@"backdrop"] ||
                    [ivarName.lowercaseString containsString:@"black"] ||
                    [ivarName.lowercaseString containsString:@"platter"]) {
                    @try {
                        id bgView = object_getIvar(view, ivar);
                        if (bgView && [bgView isKindOfClass:[UIView class]]) {
                            UIView *bg = (UIView *)bgView;
                            bg.alpha = 0.15;
                            bg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.12];
                            NSLog(@"[SBLiquidGlass-DI] Made ivar semi-transparent: %@", ivarName);
                        }
                    } @catch (__unused NSException *e) {}
                }
            }
        }
        if (ivars) free(ivars);
        
        // 6. 递归处理子视图
        for (UIView *subview in view.subviews) {
            diMakeBackgroundSemiTransparent(subview);
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Semi-transparent exception: %@", e);
    }
}

#pragma mark - 液态玻璃效果实现

static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) || CGRectGetWidth(view.bounds) < 10) return;
        
        NSLog(@"[SBLiquidGlass-DI] Applying to %@ (nice=%d)", NSStringFromClass(view.class), isNiceIsland);
        
        // 如果是 nice 灵动岛，把背景改成半透明（模拟小白点效果）
        if (isNiceIsland) {
            diMakeBackgroundSemiTransparent(view);
            // 延迟持续修改（背景可能在后面才设置）
            for (NSNumber *delay in @[@0.1, @0.3, @0.5, @1.0, @2.0, @3.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    @try { diMakeBackgroundSemiTransparent(view); } @catch (__unused NSException *e) {}
                });
            }
            NSLog(@"[SBLiquidGlass-DI] Made background semi-transparent (AssistiveTouch style)");
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
        glass.alpha = 0.85; // 液态玻璃效果稍微透明一点，模拟小白点效果
        
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
        
        NSLog(@"[SBLiquidGlass-DI] Done applying glass (AssistiveTouch style)");
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
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (AssistiveTouch semi-transparent style)");
    } @catch (__unused NSException *e) {}
}
