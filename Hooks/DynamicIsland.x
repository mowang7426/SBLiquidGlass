#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 私有类声明

@interface SBSystemApertureContainerView : UIView
@end

@interface ArtWorkManager : NSObject
+ (instancetype)shared;
- (UIView *)getCurrentContainerView;
- (void)layoutContainerViews:(id)arg;
@end

#pragma mark - 全局变量

static void *kDIGlassKey = &kDIGlassKey;
static BOOL sDidHookNiceClasses = NO;

#pragma mark - 判断是否是 nice 灵动岛的类

static BOOL diIsNiceIslandClass(Class cls) {
    if (!cls) return NO;
    NSString *name = NSStringFromClass(cls);
    if (!name.length) return NO;
    
    // nice 灵动岛的类名特征
    if ([name hasPrefix:@"NB"] || [name hasPrefix:@"AB"] || [name hasPrefix:@"AC"]) {
        return YES;
    }
    
    // 检查是否有 nice 灵动岛的特征属性
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    BOOL hasNiceIvar = NO;
    for (unsigned int i = 0; i < count && !hasNiceIvar; i++) {
        const char *ivarName = ivar_getName(ivars[i]);
        if (ivarName) {
            NSString *n = [NSString stringWithUTF8String:ivarName];
            if ([n containsString:@"backgroundContainer"] ||
                [n containsString:@"bgView"] ||
                [n containsString:@"topblackborder"] ||
                [n containsString:@"artworkView"]) {
                hasNiceIvar = YES;
            }
        }
    }
    if (ivars) free(ivars);
    
    return hasNiceIvar;
}

#pragma mark - 强制透明的 setBackgroundColor: 替换

static void diForceClearBackgroundColor(id self, SEL _cmd, UIColor *color) {
    @try {
        // 如果是黑色或深色，强制改成透明
        if (color) {
            const CGFloat *components = CGColorGetComponents(color.CGColor);
            size_t count = CGColorGetNumberOfComponents(color.CGColor);
            CGFloat r = 0, g = 0, b = 0, a = 1;
            if (count >= 4) {
                r = components[0]; g = components[1]; b = components[2]; a = components[3];
            } else if (count == 2) {
                r = g = b = components[0]; a = components[1];
            }
            
            // 如果是深色（黑色、深灰），改成透明
            if (a > 0.1 && r < 0.15 && g < 0.15 && b < 0.15) {
                color = [UIColor clearColor];
            }
        }
        
        // 调用原始实现
        struct objc_super superInfo = {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self))
        };
        void (*origImp)(id, SEL, UIColor *) = (void (*)(id, SEL, UIColor *))objc_msgSendSuper2;
        origImp(&superInfo, _cmd, color);
    } @catch (__unused NSException *e) {}
}

#pragma mark - 强制透明的 drawRect: 替换

static void diForceTransparentDrawRect(id self, SEL _cmd, CGRect rect) {
    @try {
        // 不调用原始的 drawRect:，阻止绘制黑色背景
        // 只清除背景
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (context) {
            CGContextClearRect(context, rect);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook nice 灵动岛的所有类

static void diHookNiceIslandClasses(void) {
    if (sDidHookNiceClasses) return;
    sDidHookNiceClasses = YES;
    
    @try {
        int numClasses = objc_getClassList(NULL, 0);
        Class *classes = NULL;
        classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
        numClasses = objc_getClassList(classes, numClasses);
        
        int hookedCount = 0;
        
        for (int i = 0; i < numClasses; i++) {
            Class cls = classes[i];
            if (!diIsNiceIslandClass(cls)) continue;
            
            // Hook setBackgroundColor:
            SEL bgSEL = @selector(setBackgroundColor:);
            Method bgMethod = class_getInstanceMethod(cls, bgSEL);
            if (bgMethod) {
                IMP originalImp = method_getImplementation(bgMethod);
                IMP newImp = (IMP)diForceClearBackgroundColor;
                if (originalImp != newImp) {
                    class_replaceMethod(cls, bgSEL, newImp, method_getTypeEncoding(bgMethod));
                    hookedCount++;
                }
            }
            
            // Hook drawRect:
            SEL drawSEL = @selector(drawRect:);
            Method drawMethod = class_getInstanceMethod(cls, drawSEL);
            if (drawMethod) {
                IMP originalImp = method_getImplementation(drawMethod);
                IMP newImp = (IMP)diForceTransparentDrawRect;
                if (originalImp != newImp) {
                    class_replaceMethod(cls, drawSEL, newImp, method_getTypeEncoding(drawMethod));
                    hookedCount++;
                }
            }
            
            NSLog(@"[SBLiquidGlass-DI] Hooked nice island class: %@", NSStringFromClass(cls));
        }
        
        free(classes);
        
        NSLog(@"[SBLiquidGlass-DI] Total hooked nice island methods: %d", hookedCount);
    } @catch (NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Hook classes exception: %@", e);
    }
}

#pragma mark - 递归清除所有黑色背景

static void diAggressivelyClearAllBlackBackgrounds(UIView *view, NSInteger depth) {
    if (!view || depth > 15) return;
    @try {
        // 清除当前视图的背景
        view.backgroundColor = [UIColor clearColor];
        view.opaque = NO;
        if (view.layer.backgroundColor) {
            view.layer.backgroundColor = [UIColor clearColor].CGColor;
        }
        if (view.layer.contents) {
            view.layer.contents = nil;
        }
        
        // 如果是 UIVisualEffectView，关闭 effect
        if ([view isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *ev = (UIVisualEffectView *)view;
            ev.effect = nil;
        }
        
        // 清除所有 sublayers
        for (CALayer *layer in [view.layer.sublayers copy]) {
            if (layer.backgroundColor) {
                layer.backgroundColor = [UIColor clearColor].CGColor;
            }
            if (layer.contents) {
                layer.contents = nil;
            }
            if ([layer isKindOfClass:[CAShapeLayer class]]) {
                CAShapeLayer *shape = (CAShapeLayer *)layer;
                shape.fillColor = [UIColor clearColor].CGColor;
                shape.strokeColor = [UIColor clearColor].CGColor;
            }
            if ([layer isKindOfClass:[CAGradientLayer class]]) {
                CAGradientLayer *grad = (CAGradientLayer *)layer;
                grad.colors = nil;
            }
        }
        
        // 通过 KVC 清除背景容器和背景视图
        NSArray *backgroundKeys = @[@"backgroundContainer", @"bgView", @"topblackborder", @"placeholderBackground", @"labelbgview"];
        for (NSString *key in backgroundKeys) {
            @try {
                id bgObj = [view valueForKey:key];
                if (bgObj && [bgObj isKindOfClass:[UIView class]]) {
                    UIView *bgView = (UIView *)bgObj;
                    bgView.backgroundColor = [UIColor clearColor];
                    bgView.alpha = 0.0;
                    bgView.hidden = YES;
                    if (bgView.layer.backgroundColor) {
                        bgView.layer.backgroundColor = [UIColor clearColor].CGColor;
                    }
                    NSLog(@"[SBLiquidGlass-DI] Cleared background via KVC: %@", key);
                }
            } @catch (__unused NSException *e) {}
        }
        
        // 递归处理子视图
        for (UIView *sub in [view.subviews copy]) {
            diAggressivelyClearAllBlackBackgrounds(sub, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 液态玻璃效果实现

static void diApplyGlassToView(UIView *view, BOOL isNiceIsland) {
    @try {
        if (!view || !lgHostEnabled(@"DynamicIsland")) return;
        if (CGRectIsEmpty(view.bounds) ||
            CGRectGetWidth(view.bounds) < 10 ||
            CGRectGetHeight(view.bounds) < 5) return;
        
        // 延迟 hook nice 灵动岛的类
        if (isNiceIsland) {
            diHookNiceIslandClasses();
        }
        
        LGLiveBackdropView *glass = objc_getAssociatedObject(view, kDIGlassKey);
        if (glass) {
            if (isNiceIsland) {
                glass.frame = view.bounds;
                glass.layer.cornerRadius = view.layer.cornerRadius > 0 ?
                    view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
                // 每次 layout 后激进清除所有黑色背景
                diAggressivelyClearAllBlackBackgrounds(view, 0);
                // 确保玻璃在最底层
                [view insertSubview:glass atIndex:0];
            } else {
                glass.frame = view.bounds;
                glass.layer.cornerRadius = view.layer.cornerRadius > 0 ?
                    view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
            }
            return;
        }
        
        NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
        if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";
        
        CGRect glassFrame = view.bounds;
        glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                 groupName:nil
                                                filterType:filterType];
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        CGFloat radius = view.layer.cornerRadius > 0 ?
            view.layer.cornerRadius : CGRectGetHeight(view.bounds) * 0.5;
        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;
        glass.alpha = 1.0;
        glass.backgroundColor = [UIColor clearColor];
        
        if (isNiceIsland) {
            // 激进清除所有黑色背景
            diAggressivelyClearAllBlackBackgrounds(view, 0);
            // 玻璃放在最底层
            [view insertSubview:glass atIndex:0];
            // 再清除一次
            diAggressivelyClearAllBlackBackgrounds(view, 0);
        } else {
            [view insertSubview:glass atIndex:0];
            view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.05];
        }
        
        objc_setAssociatedObject(view, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
        
        // 延迟再次应用
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                diAggressivelyClearAllBlackBackgrounds(view, 0);
                [glass applyFilters];
            } @catch (__unused NSException *e) {}
        });
        
        NSLog(@"[SBLiquidGlass-DI] Liquid Glass attached to %@ (nice=%d)",
              NSStringFromClass(view.class), isNiceIsland);
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
        if (self.window) diApplyGlassToView(self, NO);
        else diRemoveGlass(self);
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try { diApplyGlassToView(self, NO); } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook Nice ArtWorkManager

%hook ArtWorkManager

- (UIView *)getCurrentContainerView {
    UIView *container = %orig;
    @try {
        if (container && container.window) {
            diApplyGlassToView(container, YES);
        }
    } @catch (__unused NSException *e) {}
    return container;
}

- (void)layoutContainerViews:(id)arg {
    %orig;
    @try {
        UIView *container = [self getCurrentContainerView];
        if (container && container.window) {
            diApplyGlassToView(container, YES);
        }
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (aggressive runtime hook)");
        // 延迟 hook nice 灵动岛的类
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           diHookNiceIslandClasses();
                       });
    } @catch (__unused NSException *e) {}
}
