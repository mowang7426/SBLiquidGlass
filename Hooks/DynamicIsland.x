// Dynamic Island Native Test15 - 修复CABackdropLayer+正确容器层
// 根本原因：黑色背景是 CABackdropLayer (bg=gray(0,0))，但之前被当成内容层排除了
// 修复：清除 CABackdropLayer 的黑色背景色，找到正确的外层容器

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;
static NSString *kDILogPath = @"/var/mobile/Documents/di_native_log.txt";

#pragma mark - 日志工具

static void diLog(NSString *format, ...) {
    @try {
        va_list args;
        va_start(args, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"[DI-Native] %@", msg);
        NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kDILogPath];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:kDILogPath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:kDILogPath];
        }
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 工具函数

static BOOL diColorIsBlack(CGColorRef color) {
    if (!color) return NO;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (!c) return NO;
    CGFloat r=0,g=0,b=0,a=0;
    if (n >= 4) { r=c[0]; g=c[1]; b=c[2]; a=c[3]; }
    else if (n == 2) { r=g=b=c[0]; a=c[1]; }
    return a > 0.05 && r < 0.25 && g < 0.25 && b < 0.25;
}

// 真正的内容层（不能隐藏，不能清背景）
// 注意：CABackdropLayer 不在这个列表里了！它是背景层，需要清除
static BOOL diIsTrueContentLayer(CALayer *layer) {
    NSString *className = NSStringFromClass([layer class]);
    return [className isEqualToString:@"CALayerHost"] ||
           [className isEqualToString:@"CAPortalLayer"] ||
           [className isEqualToString:@"CAGainMapLayer"] ||
           [className isEqualToString:@"CAGradientLayer"] ||
           [className isEqualToString:@"_UIReplicantLayer"] ||
           [className isEqualToString:@"CAEAGLLayer"] ||
           [className isEqualToString:@"CAMetalLayer"] ||
           [className isEqualToString:@"CAReplicatorLayer"] ||
           [className isEqualToString:@"CATextLayer"] ||
           [className isEqualToString:@"CAShapeLayer"];
}

// 递归清除所有层的黑色背景（包括 CABackdropLayer！）
static void diClearAllBlackLayersRecursive(CALayer *layer, NSInteger depth, NSInteger *hiddenCount, NSInteger *clearedCount) {
    if (!layer || depth > 50) return;
    @try {
        // 真正的内容层跳过
        if (diIsTrueContentLayer(layer)) {
            return;
        }

        NSString *className = NSStringFromClass([layer class]);
        BOOL isBackdrop = [className rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound;

        // 对 CABackdropLayer：清除背景色，但不隐藏（保留模糊效果）
        if (isBackdrop) {
            if (diColorIsBlack(layer.backgroundColor)) {
                diLog(@"Clearing CABackdropLayer black bg: %@ bounds=%@",
                      className, NSStringFromCGRect(layer.bounds));
                layer.backgroundColor = UIColor.clearColor.CGColor;
                if (clearedCount) (*clearedCount)++;
            }
            // CABackdropLayer 还要递归处理子层
            for (CALayer *sublayer in [layer.sublayers copy]) {
                diClearAllBlackLayersRecursive(sublayer, depth + 1, hiddenCount, clearedCount);
            }
            return;
        }

        // 对普通 CALayer：如果背景是黑色，直接隐藏
        if (diColorIsBlack(layer.backgroundColor)) {
            diLog(@"Hiding black CALayer: %@ bounds=%@",
                  className, NSStringFromCGRect(layer.bounds));
            layer.hidden = YES;
            layer.opacity = 0.0;
            layer.backgroundColor = UIColor.clearColor.CGColor;
            if (hiddenCount) (*hiddenCount)++;
            return;
        }

        // 清除深色背景
        if (layer.backgroundColor) {
            size_t n = CGColorGetNumberOfComponents(layer.backgroundColor);
            const CGFloat *c = CGColorGetComponents(layer.backgroundColor);
            if (c && n >= 4 && c[3] > 0.1 && c[0] < 0.3 && c[1] < 0.3 && c[2] < 0.3) {
                layer.backgroundColor = UIColor.clearColor.CGColor;
            }
        }

        for (CALayer *sublayer in [layer.sublayers copy]) {
            diClearAllBlackLayersRecursive(sublayer, depth + 1, hiddenCount, clearedCount);
        }
    } @catch (__unused NSException *e) {}
}

// 递归隐藏背景视图
static void diHideBackgroundViewsRecursive(UIView *view, NSInteger depth) {
    if (!view || depth > 20) return;
    @try {
        NSString *className = NSStringFromClass([view class]);
        if ([className rangeOfString:@"LumaTrackingBackdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"AdaptiveKeyLineBackdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"MTMaterialView" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [className rangeOfString:@"MaterialView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            diLog(@"Hiding background view: %@ frame=%@", className, NSStringFromCGRect(view.frame));
            view.hidden = YES;
            view.alpha = 0.0;
        }
        if (view.backgroundColor && diColorIsBlack(view.backgroundColor.CGColor)) {
            view.backgroundColor = UIColor.clearColor;
        }
        for (UIView *subview in [view.subviews copy]) {
            diHideBackgroundViewsRecursive(subview, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

// 找到灵动岛的最外层容器（尺寸约为灵动岛大小，有子层包含 CABackdropLayer）
static CALayer *diFindIslandOuterContainer(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 20) return nil;
    @try {
        CGRect bounds = layer.bounds;
        CGFloat w = CGRectGetWidth(bounds);
        CGFloat h = CGRectGetHeight(bounds);

        NSString *className = NSStringFromClass([layer class]);
        BOOL isBackdrop = [className rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound;

        // 最外层容器的特征：
        // 1. 尺寸约为灵动岛大小（宽 100-450，高 25-100）
        // 2. 子层里包含 CABackdropLayer
        // 3. 类名是普通 CALayer（不是 CABackdropLayer）
        if (!isBackdrop && w > 100 && w < 450 && h > 25 && h < 100) {
            for (CALayer *sublayer in layer.sublayers) {
                NSString *subClassName = NSStringFromClass([sublayer class]);
                if ([subClassName rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    diLog(@"Found outer container: %@ bounds=%@",
                          className, NSStringFromCGRect(bounds));
                    return layer;
                }
            }
        }

        for (CALayer *sublayer in [layer.sublayers copy]) {
            CALayer *found = diFindIslandOuterContainer(sublayer, depth + 1);
            if (found) return found;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

#pragma mark - 液态玻璃应用

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[NSFileManager defaultManager] removeItemAtPath:kDILogPath error:nil];
        });

        diLog(@"=== diApplyGlassToRoot called ===");

        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (root.subviews.count == 0) return;

        // 第一步：隐藏背景视图
        diHideBackgroundViewsRecursive(root, 0);

        // 第二步：找到灵动岛的最外层容器
        CALayer *outerContainer = diFindIslandOuterContainer(root.layer, 0);
        if (!outerContainer) {
            diLog(@"ERROR: Could not find outer container!");
            return;
        }

        diLog(@"Using outer container: %@ bounds=%@ frame=%@",
              NSStringFromClass([outerContainer class]),
              NSStringFromCGRect(outerContainer.bounds),
              NSStringFromCGRect(outerContainer.frame));

        // 第三步：清除所有黑色背景（包括 CABackdropLayer！）
        NSInteger hiddenCount = 0, clearedCount = 0;
        diClearAllBlackLayersRecursive(outerContainer, 0, &hiddenCount, &clearedCount);
        diClearAllBlackLayersRecursive(root.layer, 0, &hiddenCount, &clearedCount);
        diLog(@"Total: hidden %ld layers, cleared %ld CABackdropLayer backgrounds",
              (long)hiddenCount, (long)clearedCount);

        // 第四步：计算玻璃层的 frame（用最外层容器的 frame，转换到 root 坐标系）
        CGRect glassFrame = [root.layer convertRect:outerContainer.frame fromLayer:outerContainer.superlayer];
        diLog(@"Glass frame: %@", NSStringFromCGRect(glassFrame));

        // 创建或获取液态玻璃层
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";

            glass = [[LGLiveBackdropView alloc] initWithFrame:glassFrame
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.userInteractionEnabled = NO;
            [root insertSubview:glass atIndex:0];
            objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            diLog(@"Glass attached, frame=%@", NSStringFromCGRect(glassFrame));
        }

        // 同步玻璃层的 frame 和 cornerRadius
        glass.frame = glassFrame;
        CGFloat radius = outerContainer.cornerRadius;
        if (radius <= 0.0)
            radius = CGRectGetHeight(glassFrame) * 0.5;
        glass.layer.cornerRadius = radius;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.masksToBounds = YES;

        if ([root.subviews indexOfObject:glass] != 0) {
            [root insertSubview:glass atIndex:0];
        }

        diLog(@"Glass updated: frame=%@ cornerRadius=%.1f",
              NSStringFromCGRect(glass.frame), glass.layer.cornerRadius);

        // 第五步：延迟多次清除（防止系统恢复）
        void (^clearBlock)(void) = ^{
            @try {
                NSInteger h = 0, c = 0;
                diHideBackgroundViewsRecursive(root, 0);
                diClearAllBlackLayersRecursive(outerContainer, 0, &h, &c);
                diClearAllBlackLayersRecursive(root.layer, 0, &h, &c);
                diLog(@"Delayed clear: hidden %ld, cleared %ld", (long)h, (long)c);
            } @catch (__unused NSException *e) {}
        };

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), clearBlock);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), clearBlock);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            clearBlock();
            diLog(@"=== All clear passes completed ===");
        });

    } @catch (NSException *e) {
        diLog(@"EXCEPTION: %@", e);
    }
}

static void diRemoveGlass(SBSystemApertureContainerView *root) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (glass) [glass removeFromSuperview];
        objc_setAssociatedObject(root, kDIGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hooks

%hook SBSystemApertureContainerView
- (void)didMoveToWindow {
    %orig;
    if (self.window) diApplyGlassToRoot(self);
    else diRemoveGlass(self);
}
- (void)layoutSubviews {
    %orig;
    if (self.window) diApplyGlassToRoot(self);
}
%end
