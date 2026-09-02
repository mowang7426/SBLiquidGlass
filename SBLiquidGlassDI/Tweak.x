// SBLiquidGlassDI - 灵动岛内容进程黑色背景清除（v2 带日志+更激进）
// 在 MediaRemoteUI / chronod / ClockAngel / InCallService 等进程里
// 清除灵动岛内容视图的黑色背景

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static NSString *kDILogPath = @"/var/mobile/Documents/sbliquidglassdi_log.txt";

#pragma mark - 日志工具

static void diLog(NSString *format, ...) {
    @try {
        va_list args;
        va_start(args, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"[SBLiquidGlassDI] %@", msg);
        NSString *logLine = [NSString stringWithFormat:@"[%@] [pid=%d] %@\n",
                             [NSDate date], [[NSProcessInfo processInfo] processIdentifier], msg];
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
    // 更宽松：alpha > 0.05 且 RGB 都 < 0.25
    return a > 0.05 && r < 0.25 && g < 0.25 && b < 0.25;
}

// 递归清除视图及其所有子视图的黑色背景（最激进版）
static void diClearBlackBackgroundsRecursive(UIView *view, NSInteger depth, NSInteger *count) {
    if (!view || depth > 40) return;
    @try {
        // 清除视图背景色
        if (view.backgroundColor && diColorIsBlack(view.backgroundColor.CGColor)) {
            view.backgroundColor = UIColor.clearColor;
            if (count) (*count)++;
        }
        // 清除 layer 背景色
        if (view.layer.backgroundColor && diColorIsBlack(view.layer.backgroundColor)) {
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
            if (count) (*count)++;
        }
        // 对普通 UIView，如果它是纯背景视图（没有子视图且没有内容），直接隐藏
        if (view.subviews.count == 0 && !view.layer.contents &&
            view.backgroundColor && diColorIsBlack(view.backgroundColor.CGColor)) {
            view.hidden = YES;
            view.alpha = 0.0;
            if (count) (*count)++;
        }
        for (UIView *subview in [view.subviews copy]) {
            diClearBlackBackgroundsRecursive(subview, depth + 1, count);
        }
    } @catch (__unused NSException *e) {}
}

// 递归清除 layer 及其所有子层的黑色背景
static void diClearBlackLayersRecursive(CALayer *layer, NSInteger depth, NSInteger *count) {
    if (!layer || depth > 50) return;
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
        // 对普通 CALayer，如果是纯背景层，直接隐藏
        if (!isContentLayer && layer.sublayers.count == 0 && !layer.contents &&
            layer.backgroundColor && diColorIsBlack(layer.backgroundColor)) {
            layer.hidden = YES;
            layer.opacity = 0.0;
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
            diLog(@"Cleared %ld black backgrounds", (long)count);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hooks

// hook UIView setBackgroundColor: 拦截黑色
%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (color && diColorIsBlack(color.CGColor)) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig(color);
}
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        diClearAllBlackBackgrounds();
    }
}
- (void)layoutSubviews {
    %orig;
    diClearAllBlackBackgrounds();
}
%end

// hook CALayer setBackgroundColor: 拦截黑色
%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && diColorIsBlack(color)) {
        %orig(UIColor.clearColor.CGColor);
        return;
    }
    %orig(color);
}
%end

// hook UIViewController
%hook UIViewController
- (void)viewDidLoad {
    %orig;
    diLog(@"viewDidLoad: %@", NSStringFromClass([self class]));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        diClearAllBlackBackgrounds();
    });
}
- (void)viewDidLayoutSubviews {
    %orig;
    diClearAllBlackBackgrounds();
}
%end

// 初始化
%ctor {
    diLog(@"=== SBLiquidGlassDI loaded ===");
    diLog(@"Process: %@", [[NSProcessInfo processInfo] processName]);
    diLog(@"PID: %d", [[NSProcessInfo processInfo] processIdentifier]);

    // 延迟清除
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        diClearAllBlackBackgrounds();
    });

    // 每 1 秒清除一次，防止系统恢复
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
        diClearAllBlackBackgrounds();
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}
