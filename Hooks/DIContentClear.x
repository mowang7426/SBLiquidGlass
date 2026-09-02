// DIContentClear - 灵动岛内容进程黑色背景清除（参考 Liquidify 实现方式）
// 主 tweak 加载到灵动岛内容进程后，用进程名判断，只在相关进程里执行清除

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static NSString *kDIContentLogPath = @"/var/mobile/Documents/di_content_log.txt";
static BOOL gIsDIContentProcess = NO;

#pragma mark - 日志工具

static void diContentLog(NSString *format, ...) {
    @try {
        va_list args;
        va_start(args, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"[DI-Content] %@", msg);
        NSString *logLine = [NSString stringWithFormat:@"[%@] [pid=%d] %@\n",
                             [NSDate date], [[NSProcessInfo processInfo] processIdentifier], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kDIContentLogPath];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:kDIContentLogPath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:kDIContentLogPath];
        }
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 工具函数

static BOOL diContentColorIsBlack(CGColorRef color) {
    if (!color) return NO;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    if (!c) return NO;
    CGFloat r=0,g=0,b=0,a=0;
    if (n >= 4) { r=c[0]; g=c[1]; b=c[2]; a=c[3]; }
    else if (n == 2) { r=g=b=c[0]; a=c[1]; }
    return a > 0.05 && r < 0.25 && g < 0.25 && b < 0.25;
}

static void diContentClearBlackBackgroundsRecursive(UIView *view, NSInteger depth, NSInteger *count) {
    if (!view || depth > 40) return;
    @try {
        if (view.backgroundColor && diContentColorIsBlack(view.backgroundColor.CGColor)) {
            view.backgroundColor = UIColor.clearColor;
            if (count) (*count)++;
        }
        if (view.layer.backgroundColor && diContentColorIsBlack(view.layer.backgroundColor)) {
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
            if (count) (*count)++;
        }
        // 对纯背景视图直接隐藏
        if (view.subviews.count == 0 && !view.layer.contents &&
            view.backgroundColor && diContentColorIsBlack(view.backgroundColor.CGColor)) {
            view.hidden = YES;
            view.alpha = 0.0;
            if (count) (*count)++;
        }
        for (UIView *subview in [view.subviews copy]) {
            diContentClearBlackBackgroundsRecursive(subview, depth + 1, count);
        }
    } @catch (__unused NSException *e) {}
}

static void diContentClearBlackLayersRecursive(CALayer *layer, NSInteger depth, NSInteger *count) {
    if (!layer || depth > 50) return;
    @try {
        NSString *className = NSStringFromClass([layer class]);
        // 跳过内容层
        BOOL isContentLayer = [className isEqualToString:@"CALayerHost"] ||
                               [className isEqualToString:@"CAPortalLayer"] ||
                               [className isEqualToString:@"CAGainMapLayer"] ||
                               [className isEqualToString:@"CATextLayer"];
        if (!isContentLayer && layer.backgroundColor && diContentColorIsBlack(layer.backgroundColor)) {
            layer.backgroundColor = UIColor.clearColor.CGColor;
            if (count) (*count)++;
        }
        // 对纯背景层直接隐藏
        if (!isContentLayer && layer.sublayers.count == 0 && !layer.contents &&
            layer.backgroundColor && diContentColorIsBlack(layer.backgroundColor)) {
            layer.hidden = YES;
            layer.opacity = 0.0;
            if (count) (*count)++;
        }
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diContentClearBlackLayersRecursive(sublayer, depth + 1, count);
        }
    } @catch (__unused NSException *e) {}
}

static void diContentClearAllBlackBackgrounds(void) {
    if (!gIsDIContentProcess) return;
    @try {
        NSInteger count = 0;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            diContentClearBlackBackgroundsRecursive(window, 0, &count);
            diContentClearBlackLayersRecursive(window.layer, 0, &count);
        }
        if (count > 0) {
            diContentLog(@"Cleared %ld black backgrounds", (long)count);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 判断是否是灵动岛相关进程

static BOOL diContentIsDynamicIslandProcess(void) {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSString *lowerName = [processName lowercaseString];
    
    // 参考 Liquidify 的进程列表
    NSArray *keywords = @[@"mediaremote", @"chrono", @"clockangel", @"incall", @"widgetrenderer"];
    for (NSString *kw in keywords) {
        if ([lowerName containsString:kw]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Hooks（只在灵动岛进程里生效）

%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (gIsDIContentProcess && color && diContentColorIsBlack(color.CGColor)) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig(color);
}
- (void)didMoveToWindow {
    %orig;
    if (gIsDIContentProcess && self.window) {
        diContentClearAllBlackBackgrounds();
    }
}
- (void)layoutSubviews {
    %orig;
    if (gIsDIContentProcess) {
        diContentClearAllBlackBackgrounds();
    }
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (gIsDIContentProcess && color && diContentColorIsBlack(color)) {
        %orig(UIColor.clearColor.CGColor);
        return;
    }
    %orig(color);
}
%end

%hook UIViewController
- (void)viewDidLoad {
    %orig;
    if (gIsDIContentProcess) {
        diContentLog(@"viewDidLoad: %@", NSStringFromClass([self class]));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            diContentClearAllBlackBackgrounds();
        });
    }
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (gIsDIContentProcess) {
        diContentClearAllBlackBackgrounds();
    }
}
%end

// 初始化
%ctor {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    diContentLog(@"=== DIContentClear loaded ===");
    diContentLog(@"Process: %@", processName);
    diContentLog(@"PID: %d", [[NSProcessInfo processInfo] processIdentifier]);
    
    gIsDIContentProcess = diContentIsDynamicIslandProcess();
    diContentLog(@"Is DI content process: %@", gIsDIContentProcess ? @"YES" : @"NO");
    
    if (!gIsDIContentProcess) {
        diContentLog(@"Not a DI content process, skipping");
        return;
    }
    
    diContentLog(@"DI content process detected, enabling black background clearing");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        diContentClearAllBlackBackgrounds();
    });
    
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
        diContentClearAllBlackBackgrounds();
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}
