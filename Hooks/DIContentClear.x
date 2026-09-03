// DIContentClear - 参考 Liquidify 实现，专门 hook _UISystemBackgroundView 和 MTMaterialView
// 这两个类才是灵动岛黑色背景的真正来源！

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

#pragma mark - 判断是否是灵动岛相关进程

static BOOL diContentIsDynamicIslandProcess(void) {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSString *lowerName = [processName lowercaseString];
    
    NSArray *keywords = @[@"mediaremote", @"chrono", @"clockangel", @"incall", @"widgetrenderer"];
    for (NSString *kw in keywords) {
        if ([lowerName containsString:kw]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - 清除黑色背景的通用函数

static void diContentClearView(UIView *view) {
    if (!gIsDIContentProcess || !view) return;
    @try {
        NSString *className = NSStringFromClass([view class]);
        diContentLog(@"Clearing background for view: %@ frame=%@",
                     className, NSStringFromCGRect(view.frame));
        
        view.backgroundColor = UIColor.clearColor;
        view.alpha = 0.0;
        view.hidden = YES;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
        view.layer.opacity = 0.0;
        view.layer.hidden = YES;
    } @catch (__unused NSException *e) {}
}

#pragma mark - 递归扫描并清除背景视图

static void diScanAndClearView(UIView *view) {
    if (!view || !gIsDIContentProcess) return;
    @try {
        NSString *className = NSStringFromClass([view class]);
        if ([className isEqualToString:@"_UISystemBackgroundView"] ||
            [className isEqualToString:@"MTMaterialView"]) {
            diContentLog(@"Scan found background view: %@", className);
            diContentClearView(view);
        }
        for (UIView *subview in [view.subviews copy]) {
            diScanAndClearView(subview);
        }
    } @catch (__unused NSException *e) {}
}

static void diScanAllWindows(void) {
    if (!gIsDIContentProcess) return;
    @try {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            for (UIView *view in [window.subviews copy]) {
                diScanAndClearView(view);
            }
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - hook _UISystemBackgroundView（关键！灵动岛黑色背景主要来源）

%hook _UISystemBackgroundView

- (void)didMoveToWindow {
    %orig;
    UIView *selfView = (UIView *)self;
    if (gIsDIContentProcess && selfView.window) {
        diContentLog(@"_UISystemBackgroundView didMoveToWindow, clearing...");
        diContentClearView(selfView);
    }
}

- (void)layoutSubviews {
    %orig;
    if (gIsDIContentProcess) {
        diContentClearView((UIView *)self);
    }
}

- (void)setBackgroundColor:(UIColor *)color {
    if (gIsDIContentProcess) {
        diContentLog(@"_UISystemBackgroundView setBackgroundColor intercepted: %@", color);
        %orig(UIColor.clearColor);
        UIView *selfView = (UIView *)self;
        selfView.alpha = 0.0;
        selfView.hidden = YES;
        return;
    }
    %orig(color);
}

%end

#pragma mark - hook MTMaterialView（关键！灵动岛黑色背景另一来源）

%hook MTMaterialView

- (void)didMoveToWindow {
    %orig;
    UIView *selfView = (UIView *)self;
    if (gIsDIContentProcess && selfView.window) {
        diContentLog(@"MTMaterialView didMoveToWindow, clearing...");
        diContentClearView(selfView);
    }
}

- (void)layoutSubviews {
    %orig;
    if (gIsDIContentProcess) {
        diContentClearView((UIView *)self);
    }
}

- (void)setBackgroundColor:(UIColor *)color {
    if (gIsDIContentProcess) {
        diContentLog(@"MTMaterialView setBackgroundColor intercepted: %@", color);
        %orig(UIColor.clearColor);
        UIView *selfView = (UIView *)self;
        selfView.alpha = 0.0;
        selfView.hidden = YES;
        return;
    }
    %orig(color);
}

%end

#pragma mark - 初始化

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
    
    diContentLog(@"DI content process detected! Enabling black background clearing");
    diContentLog(@"Hooking _UISystemBackgroundView and MTMaterialView...");
    
    // 延迟扫描并清除已存在的背景视图
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        diScanAllWindows();
    });
    
    // 定时扫描，防止系统恢复背景
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
        diScanAllWindows();
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}
