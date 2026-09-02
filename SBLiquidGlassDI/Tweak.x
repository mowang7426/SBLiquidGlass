// SBLiquidGlassDI - 灵动岛内容进程黑色背景清除（通用版 v3）
// 在所有进程里加载，然后判断进程名，只在灵动岛相关进程里执行

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static NSString *kDILogPath = @"/var/mobile/Documents/sbliquidglassdi_log.txt";
static BOOL gIsDIProcess = NO;

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
    return a > 0.05 && r < 0.25 && g < 0.25 && b < 0.25;
}

static void diClearBlackBackgroundsRecursive(UIView *view, NSInteger depth, NSInteger *count) {
    if (!view || depth > 40) return;
    @try {
        if (view.backgroundColor && diColorIsBlack(view.backgroundColor.CGColor)) {
            view.backgroundColor = UIColor.clearColor;
            if (count) (*count)++;
        }
        if (view.layer.backgroundColor && diColorIsBlack(view.layer.backgroundColor)) {
            view.layer.backgroundColor = UIColor.clearColor.CGColor;
            if (count) (*count)++;
        }
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

static void diClearBlackLayersRecursive(CALayer *layer, NSInteger depth, NSInteger *count) {
    if (!layer || depth > 50) return;
    @try {
        NSString *className = NSStringFromClass([layer class]);
        BOOL isContentLayer = [className isEqualToString:@"CALayerHost"] ||
                               [className isEqualToString:@"CAPortalLayer"] ||
                               [className isEqualToString:@"CAGainMapLayer"] ||
                               [className isEqualToString:@"CATextLayer"];
        if (!isContentLayer && layer.backgroundColor && diColorIsBlack(layer.backgroundColor)) {
            layer.backgroundColor = UIColor.clearColor.CGColor;
            if (count) (*count)++;
        }
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

static void diClearAllBlackBackgrounds(void) {
    if (!gIsDIProcess) return;
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

#pragma mark - 判断是否是灵动岛相关进程

static BOOL diIsDynamicIslandProcess(void) {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSString *lowerName = [processName lowercaseString];
    
    // 包含这些关键词的进程都认为是灵动岛相关
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
    if (gIsDIProcess && color && diColorIsBlack(color.CGColor)) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig(color);
}
- (void)didMoveToWindow {
    %orig;
    if (gIsDIProcess && self.window) {
        diClearAllBlackBackgrounds();
    }
}
- (void)layoutSubviews {
    %orig;
    if (gIsDIProcess) {
        diClearAllBlackBackgrounds();
    }
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (gIsDIProcess && color && diColorIsBlack(color)) {
        %orig(UIColor.clearColor.CGColor);
        return;
    }
    %orig(color);
}
%end

%hook UIViewController
- (void)viewDidLoad {
    %orig;
    if (gIsDIProcess) {
        diLog(@"viewDidLoad: %@", NSStringFromClass([self class]));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            diClearAllBlackBackgrounds();
        });
    }
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (gIsDIProcess) {
        diClearAllBlackBackgrounds();
    }
}
%end

// 初始化
%ctor {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    diLog(@"=== SBLiquidGlassDI loaded ===");
    diLog(@"Process: %@", processName);
    diLog(@"PID: %d", [[NSProcessInfo processInfo] processIdentifier]);
    
    gIsDIProcess = diIsDynamicIslandProcess();
    diLog(@"Is DI process: %@", gIsDIProcess ? @"YES" : @"NO");
    
    if (!gIsDIProcess) {
        diLog(@"Not a DI process, skipping hooks");
        return;
    }
    
    diLog(@"DI process detected, enabling black background clearing");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        diClearAllBlackBackgrounds();
    });
    
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
        diClearAllBlackBackgrounds();
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}
