// Dynamic Island Native Test19 - 安全版，不误隐藏内容视图
// 修复：只隐藏纯背景视图（没有子视图、没有 contents），不隐藏内容视图（专辑封面等）

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

// 安全版：只清除纯背景层的黑色背景，不隐藏任何层（避免误隐藏内容）
static void diClearAllBlackLayersRecursive(CALayer *layer, NSInteger depth, NSInteger *clearedCount) {
    if (!layer || depth > 50) return;
    @try {
        // 真正的内容层跳过
        if (diIsTrueContentLayer(layer)) return;
        
        NSString *className = NSStringFromClass([layer class]);
        BOOL isBackdrop = [className rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound;
        
        // 对 CABackdropLayer：只清除背景色，不隐藏（保留模糊效果）
        if (isBackdrop) {
            if (diColorIsBlack(layer.backgroundColor)) {
                diLog(@"Clearing CABackdropLayer black bg: %@ bounds=%@",
                      className, NSStringFromCGRect(layer.bounds));
                layer.backgroundColor = UIColor.clearColor.CGColor;
                if (clearedCount) (*clearedCount)++;
            }
            for (CALayer *sublayer in [layer.sublayers copy]) {
                diClearAllBlackLayersRecursive(sublayer, depth + 1, clearedCount);
            }
            return;
        }
        
        // 对普通 CALayer：只清除背景色，不隐藏（避免误隐藏内容）
        if (diColorIsBlack(layer.backgroundColor)) {
            diLog(@"Clearing CALayer black bg: %@ bounds=%@",
                  className, NSStringFromCGRect(layer.bounds));
            layer.backgroundColor = UIColor.clearColor.CGColor;
            if (clearedCount) (*clearedCount)++;
        }
        
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diClearAllBlackLayersRecursive(sublayer, depth + 1, clearedCount);
        }
    } @catch (__unused NSException *e) {}
}

// 安全版：只清除背景视图的背景色，不隐藏任何视图（避免误隐藏专辑封面等内容）
static void diHideBackgroundViewsRecursive(UIView *view, NSInteger depth) {
    if (!view || depth > 20) return;
    @try {
        NSString *className = NSStringFromClass([view class]);
        
        // 只对明确的背景类清除背景色，不隐藏
        BOOL isBackgroundClass = [className rangeOfString:@"LumaTrackingBackdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                 [className rangeOfString:@"AdaptiveKeyLineBackdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                 [className isEqualToString:@"MTMaterialView"] ||
                                 [className isEqualToString:@"_UISystemBackgroundView"];
        
        if (isBackgroundClass) {
            diLog(@"Clearing background view: %@ frame=%@", className, NSStringFromCGRect(view.frame));
            view.backgroundColor = UIColor.clearColor;
            // 不隐藏，只清除背景色，避免影响内容
        }
        
        // 对所有视图，如果背景是纯黑色且没有子视图，才清除背景色
        if (view.backgroundColor && diColorIsBlack(view.backgroundColor.CGColor) &&
            view.subviews.count == 0 && !view.layer.contents) {
            view.backgroundColor = UIColor.clearColor;
        }
        
        for (UIView *subview in [view.subviews copy]) {
            diHideBackgroundViewsRecursive(subview, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 液态玻璃应用

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[NSFileManager defaultManager] removeItemAtPath:kDILogPath error:nil];
        });
        
        diLog(@"=== diApplyGlassToRoot called ===");
        diLog(@"root.frame=%@ root.bounds=%@",
              NSStringFromCGRect(root.frame), NSStringFromCGRect(root.bounds));
        
        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (root.subviews.count == 0) return;
        
        // 第一步：安全清除背景视图（只清除背景色，不隐藏）
        diHideBackgroundViewsRecursive(root, 0);
        
        // 第二步：直接用 root.bounds 作为灵动岛区域的 frame
        CGRect islandFrame = root.bounds;
        diLog(@"Using root.bounds as island frame: %@", NSStringFromCGRect(islandFrame));
        
        // 第三步：安全清除所有黑色背景（只清除背景色，不隐藏）
        NSInteger clearedCount = 0;
        diClearAllBlackLayersRecursive(root.layer, 0, &clearedCount);
        diLog(@"Total: cleared %ld layer backgrounds", (long)clearedCount);
        
        // 第四步：玻璃层 frame 直接用 root.bounds
        CGRect glassFrame = islandFrame;
        if (CGRectGetWidth(glassFrame) < 50 || CGRectGetHeight(glassFrame) < 20) {
            glassFrame = root.bounds;
        }
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
        CGFloat radius = root.layer.cornerRadius;
        if (radius <= 0) radius = CGRectGetHeight(glassFrame) * 0.5;
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
                NSInteger c = 0;
                diHideBackgroundViewsRecursive(root, 0);
                diClearAllBlackLayersRecursive(root.layer, 0, &c);
                diLog(@"Delayed clear: cleared %ld backgrounds", (long)c);
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
