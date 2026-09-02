// SBLiquidGlassDI - 灵动岛内容进程黑色背景清除
// 在 MediaRemoteUI / chronod / ClockAngel / InCallService 等进程里
// 清除灵动岛内容视图的黑色背景，让 SpringBoard 里的液态玻璃显示出来

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - 工具函数

static BOOL diColorIsBlack(CGColorRef color) {
    if (!color) return NO;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (!c) return NO;
    CGFloat r=0,g=0,b=0,a=0;
    if (n >= 4) { r=c[0]; g=c[1]; b=c[2]; a=c[3]; }
    else if (n == 2) { r=g=b=c[0]; a=c[1]; }
    // alpha > 0.1 且 RGB 都 < 0.2（接近纯黑）
    return a > 0.1 && r < 0.2 && g < 0.2 && b < 0.2;
}

// 递归清除视图及其所有子视图的黑色背景
static void diClearBlackBackgroundsRecursive(UIView *view, NSInteger depth, NSInteger *count) {
    if (!view || depth > 30) return;
    @try {
        if (view.backgroundColor && diColorIsBlack(view.backgroundColor.CGColor)) {
            view.backgroundColor = UIColor.clearColor;
            if (count) (*count)++;
        }
        // 清除 layer 的背景色
        if (view.layer.backgroundColor && diColorIsBlack(view.layer.backgroundColor)) {
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
            if (count) (*count)++;
        }
        for (UIView *subview in [view.subviews copy]) {
            diClearBlackBackgroundsRecursive(subview, depth + 1, count);
        }
    } @catch (__unused NSException *e) {}
}

// 递归清除 layer 及其所有子层的黑色背景
static void diClearBlackLayersRecursive(CALayer *layer, NSInteger depth, NSInteger *count) {
    if (!layer || depth > 40) return;
    @try {
        NSString *className = NSStringFromClass([layer class]);
        // 跳过内容层
        BOOL isContentLayer = [className isEqualToString:@"CALayerHost"] ||
                               [className isEqualToString:@"CAPortalLayer"] ||
                               [className isEqualToString:@"CAGainMapLayer"] ||
                               [className isEqualToString:@"CATextLayer"];
        if (!isContentLayer && layer.backgroundColor && diColorIsBlack(layer.backgroundColor)) {
            layer.backgroundColor = UIColor.clearColor.CGColor;
            if (count) (*count)++;
        }
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diClearBlackLayersRecursive(sublayer, depth + 1, count);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 全局清除

static void diClearAllBlackBackgrounds(void) {
    @try {
        NSInteger count = 0;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            diClearBlackBackgroundsRecursive(window, 0, &count);
            diClearBlackLayersRecursive(window.layer, 0, &count);
        }
        if (count > 0) {
            NSLog(@"[SBLiquidGlassDI] Cleared %ld black backgrounds", (long)count);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hooks

// hook UIView setBackgroundColor: 拦截黑色背景
%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (color && diColorIsBlack(color.CGColor)) {
        // 把黑色改成透明
        %orig(UIColor.clearColor);
        return;
    }
    %orig(color);
}
%end

// hook CALayer setBackgroundColor: 拦截黑色背景
%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && diColorIsBlack(color)) {
        %orig(UIColor.clearColor.CGColor);
        return;
    }
    %orig(color);
}
%end

// hook UIViewController viewDidLoad，加载后清除黑色背景
%hook UIViewController
- (void)viewDidLoad {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        diClearAllBlackBackgrounds();
    });
}
- (void)viewDidLayoutSubviews {
    %orig;
    diClearAllBlackBackgrounds();
}
%end

// hook UIWindow didAddSubview，新视图添加后清除
%hook UIWindow
- (void)didAddSubview:(UIView *)subview {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSInteger count = 0;
        diClearBlackBackgroundsRecursive(subview, 0, &count);
        diClearBlackLayersRecursive(subview.layer, 0, &count);
    });
}
%end

// 初始化：延迟清除 + 定时清除
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        diClearAllBlackBackgrounds();
    });
    // 每 2 秒清除一次，防止系统恢复
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer * _Nonnull t) {
        diClearAllBlackBackgrounds();
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}
