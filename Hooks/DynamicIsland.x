// Dynamic Island Native Test14 - 日志写文件+调试版
// 把所有 DI-Native 日志写到 /var/mobile/Documents/di_native_log.txt
// 用户直接把这个文件发给我，不用找控制台了
// 同时优化黑色背景清除逻辑

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;
static NSString *kDILogPath = @"/var/mobile/Documents/di_native_log.txt";

#pragma mark - 日志工具（写文件）

static void diLog(NSString *format, ...) {
    @try {
        va_list args;
        va_start(args, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        // 同时输出到系统日志
        NSLog(@"[DI-Native] %@", msg);

        // 写到文件
        NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n",
                             [NSDate date], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kDILogPath];
        if (!fh) {
            // 文件不存在，创建
            [[NSFileManager defaultManager] createFileAtPath:kDILogPath
                                                      contents:nil
                                                    attributes:nil];
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

// 判断一个颜色是不是黑色（包括深灰）
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

// 判断一个层是不是内容层（不能隐藏）
static BOOL diIsContentLayer(CALayer *layer) {
    NSString *className = NSStringFromClass([layer class]);
    return [className isEqualToString:@"CALayerHost"] ||
           [className isEqualToString:@"CAPortalLayer"] ||
           [className isEqualToString:@"CAGainMapLayer"] ||
           [className isEqualToString:@"CAGradientLayer"] ||
           [className isEqualToString:@"_UIReplicantLayer"] ||
           [className isEqualToString:@"CABackdropLayer"] ||
           [className isEqualToString:@"CAEAGLLayer"] ||
           [className isEqualToString:@"CAMetalLayer"] ||
           [className isEqualToString:@"CAReplicatorLayer"] ||
           [className isEqualToString:@"CATextLayer"] ||
           [className isEqualToString:@"CAShapeLayer"];
}

// 递归打印图层树（用于调试）
static void diPrintLayerTree(CALayer *layer, NSInteger depth, NSMutableString *output) {
    if (!layer || depth > 15) return;
    @try {
        NSMutableString *indent = [NSMutableString string];
        for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];

        NSString *className = NSStringFromClass([layer class]);
        CGRect bounds = layer.bounds;
        CGRect frame = layer.frame;
        NSString *bgInfo = @"";
        if (layer.backgroundColor) {
            size_t n = CGColorGetNumberOfComponents(layer.backgroundColor);
            const CGFloat *c = CGColorGetComponents(layer.backgroundColor);
            if (c && n >= 4) {
                bgInfo = [NSString stringWithFormat:@" bg=rgba(%.2f,%.2f,%.2f,%.2f)", c[0], c[1], c[2], c[3]];
            } else if (c && n == 2) {
                bgInfo = [NSString stringWithFormat:@" bg=gray(%.2f,%.2f)", c[0], c[1]];
            }
        }
        NSString *hiddenInfo = layer.hidden ? @" HIDDEN" : @"";
        NSString *opacityInfo = layer.opacity < 1.0 ? [NSString stringWithFormat:@" opacity=%.2f", layer.opacity] : @"";

        [output appendFormat:@"%@%@ frame=%@ bounds=%@%@%@%@\n",
         indent, className, NSStringFromCGRect(frame), NSStringFromCGRect(bounds),
         bgInfo, hiddenInfo, opacityInfo];

        for (CALayer *sublayer in [layer.sublayers copy]) {
            diPrintLayerTree(sublayer, depth + 1, output);
        }
    } @catch (__unused NSException *e) {}
}

// 递归清除所有层的黑色背景（超激进版）
static void diClearAllBlackLayersRecursive(CALayer *layer, NSInteger depth, NSInteger *hiddenCount) {
    if (!layer || depth > 50) return;
    @try {
        // 跳过内容层
        if (diIsContentLayer(layer)) {
            if (diColorIsBlack(layer.backgroundColor)) {
                layer.backgroundColor = UIColor.clearColor.CGColor;
            }
            for (CALayer *sublayer in [layer.sublayers copy]) {
                diClearAllBlackLayersRecursive(sublayer, depth + 1, hiddenCount);
            }
            return;
        }

        // 超激进：只要背景是黑色，就直接隐藏
        if (diColorIsBlack(layer.backgroundColor)) {
            diLog(@"Hiding black layer: %@ bounds=%@",
                  NSStringFromClass([layer class]), NSStringFromCGRect(layer.bounds));
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
            diClearAllBlackLayersRecursive(sublayer, depth + 1, hiddenCount);
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

// 在图层树里找灵动岛的容器层（更宽松的条件）
static CALayer *diFindIslandContainerLayer(CALayer *layer, NSInteger depth) {
    if (!layer || depth > 30) return nil;
    @try {
        CGRect bounds = layer.bounds;
        CGFloat w = CGRectGetWidth(bounds);
        CGFloat h = CGRectGetHeight(bounds);

        // 更宽松的条件：宽 80-500，高 25-200
        if (w > 80 && w < 500 && h > 25 && h < 200) {
            NSString *className = NSStringFromClass([layer class]);
            if (![className isEqualToString:@"CALayerHost"] &&
                ![className isEqualToString:@"CAPortalLayer"] &&
                ![className isEqualToString:@"CAGainMapLayer"] &&
                ![className isEqualToString:@"CABackdropLayer"]) {
                // 检查子层里有没有 CALayerHost
                for (CALayer *sublayer in layer.sublayers) {
                    if ([NSStringFromClass([sublayer class]) isEqualToString:@"CALayerHost"]) {
                        diLog(@"Found island container layer: %@ bounds=%@ cornerRadius=%.1f",
                              className, NSStringFromCGRect(bounds), layer.cornerRadius);
                        return layer;
                    }
                    CALayer *found = diFindIslandContainerLayer(sublayer, depth + 1);
                    if (found) return found;
                }
            }
        }

        for (CALayer *sublayer in [layer.sublayers copy]) {
            CALayer *found = diFindIslandContainerLayer(sublayer, depth + 1);
            if (found) return found;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

#pragma mark - 液态玻璃应用

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        // 每次调用先清空日志文件（只保留最新一次的日志）
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[NSFileManager defaultManager] removeItemAtPath:kDILogPath error:nil];
        });

        diLog(@"=== diApplyGlassToRoot called ===");
        diLog(@"root: %@", NSStringFromClass([root class]));
        diLog(@"root.subviews.count: %lu", (unsigned long)root.subviews.count);

        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) {
            diLog(@"Abort: root=%@ window=%@ enabled=%d",
                  root ? @"yes" : @"no",
                  root.window ? @"yes" : @"no",
                  lgHostEnabled(@"DynamicIsland"));
            return;
        }
        if (root.subviews.count == 0) {
            diLog(@"Abort: root.subviews.count == 0");
            return;
        }

        // 第一步：打印整个图层树（用于调试）
        NSMutableString *layerTree = [NSMutableString stringWithString:@"=== Layer Tree ===\n"];
        diPrintLayerTree(root.layer, 0, layerTree);
        diLog(@"%@", layerTree);

        // 第二步：激进隐藏所有背景视图
        diHideBackgroundViewsRecursive(root, 0);

        // 第三步：在图层树里找灵动岛的容器层
        CALayer *containerLayer = diFindIslandContainerLayer(root.layer, 0);
        if (!containerLayer) {
            diLog(@"ERROR: Could not find island container layer!");
            return;
        }

        diLog(@"Using container layer: %@ bounds=%@",
              NSStringFromClass([containerLayer class]),
              NSStringFromCGRect(containerLayer.bounds));

        // 第四步：超激进清除黑色背景
        NSInteger hiddenCount = 0;
        diClearAllBlackLayersRecursive(containerLayer, 0, &hiddenCount);
        diClearAllBlackLayersRecursive(root.layer, 0, &hiddenCount);
        diLog(@"Total hidden black layers: %ld", (long)hiddenCount);

        // 第五步：计算玻璃层的 frame
        CGRect glassFrameInRootLayer = [root.layer convertRect:containerLayer.frame fromLayer:containerLayer.superlayer];
        diLog(@"Container frame: %@, converted to root layer: %@",
              NSStringFromCGRect(containerLayer.frame),
              NSStringFromCGRect(glassFrameInRootLayer));

        CGRect glassFrame = glassFrameInRootLayer;

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
        CGFloat radius = containerLayer.cornerRadius;
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

        // 第六步：延迟多次清除
        void (^clearBlock)(void) = ^{
            @try {
                NSInteger count = 0;
                diHideBackgroundViewsRecursive(root, 0);
                diClearAllBlackLayersRecursive(containerLayer, 0, &count);
                diClearAllBlackLayersRecursive(root.layer, 0, &count);
                diLog(@"Delayed clear: hidden %ld layers", (long)count);
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
