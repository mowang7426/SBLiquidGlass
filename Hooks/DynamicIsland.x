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

#pragma mark - KVO 监听背景色变化

static void *kDIKVOContext = &kDIKVOContext;
static void *kDIGlassKey = &kDIGlassKey;
static void *kDIObservingKey = &kDIObservingKey;

@interface DIBackgroundObserver : NSObject
@end

@implementation DIBackgroundObserver

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == kDIKVOContext) {
        @try {
            if ([keyPath isEqualToString:@"backgroundColor"]) {
                UIColor *newColor = change[NSKeyValueChangeNewKey];
                if (newColor && newColor != (id)[NSNull null]) {
                    CGFloat white = 0, alpha = 0;
                    if ([newColor respondsToSelector:@selector(getWhite:alpha:)]) {
                        [newColor getWhite:&white alpha:&alpha];
                        // 如果是黑色或深色背景，改成透明
                        if (white < 0.15 && alpha > 0.1) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                @try {
                                    [object setBackgroundColor:[UIColor clearColor]];
                                } @catch (__unused NSException *e) {}
                            });
                        }
                    }
                }
            }
        } @catch (__unused NSException *e) {}
    }
}

@end

static DIBackgroundObserver *sDIObserver = nil;

#pragma mark - 递归清除背景（增强版）

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

#pragma mark - 开始 KVO 监听

static void diStartObservingView(UIView *view) {
    @try {
        if (!view || !sDIObserver) return;
        if (objc_getAssociatedObject(view, kDIObservingKey)) return;
        
        // 监听当前视图
        [view addObserver:sDIObserver
               forKeyPath:@"backgroundColor"
                  options:NSKeyValueObservingOptionNew
                  context:kDIKVOContext];
        objc_setAssociatedObject(view, kDIObservingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 递归监听子视图
        for (UIView *subview in view.subviews) {
            diStartObservingView(subview);
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
            // 立即清除
            diClearBackgroundRecursive(view);
            
            // 延迟清除（可能背景在后面才设置）
            for (NSNumber *delay in @[@0.1, @0.3, @0.5, @1.0, @2.0]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    @try {
                        diClearBackgroundRecursive(view);
                    } @catch (__unused NSException *e) {}
                });
            }
            
            // 开始 KVO 监听
            diStartObservingView(view);
            
            NSLog(@"[SBLiquidGlass-DI] Started aggressive background clearing");
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
        sDIObserver = [[DIBackgroundObserver alloc] init];
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (KVO + aggressive clear)");
    } @catch (__unused NSException *e) {}
}
