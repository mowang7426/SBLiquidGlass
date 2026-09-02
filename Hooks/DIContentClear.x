// DIContentClear - 灵动岛内容进程黑色背景清除（参考 Liquidify 实现）
// 关键：hook _UISystemBackgroundView 和 MTMaterialView，这两个才是灵动岛黑色背景的真正来源
// 修复：hook 私有类时，把 self 强制转换成 UIView *

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

#pragma mark - hook _UISystemBackgroundView（关键！这是灵动岛黑色背景的主要来源）

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

#pragma mark - hook MTMaterialView（关键！这也是灵动岛黑色背景的来源）

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

#pragma mark - hook 普通 UIView（兜底）

%hook UIView

- (void)setBackgroundColor:(UIColor *)color {
    if (gIsDIContentProcess && color) {
        CGColorRef cgColor = color.CGColor;
        if (cgColor) {
            size_t n = CGColorGetNumberOfComponents(cgColor);
            const CGFloat *c = CGColorGetComponents(cgColor);
            if (c && n >= 4 && c[3] > 0.05 && c[0] < 0.25 && c[1] < 0.25 && c[2] < 0.25) {
                NSString *className = NSStringFromClass([self class]);
                diContentLog(@"UIView setBackgroundColor intercepted (black): %@ color=%@", className, color);
                %orig(UIColor.clearColor);
                return;
            }
        }
    }
    %orig(color);
}

- (void)didMoveToWindow {
    %orig;
    if (gIsDIContentProcess && self.window) {
        NSString *className = NSStringFromClass([self class]);
        if ([className containsString:@"Background"] ||
            [className containsString:@"Backdrop"] ||
            [className containsString:@"Material"]) {
            diContentLog(@"UIView didMoveToWindow (background class): %@", className);
            diContentClearView(self);
        }
    }
}

%end

#pragma mark - hook CALayer（兜底）

%hook CALayer

- (void)setBackgroundColor:(CGColorRef)color {
    if (gIsDIContentProcess && color) {
        size_t n = CGColorGetNumberOfComponents(color);
        const CGFloat *c = CGColorGetComponents(color);
        if (c && n >= 4 && c[3] > 0.05 && c[0] < 0.25 && c[1] < 0.25 && c[2] < 0.25) {
            NSString *className = NSStringFromClass([self class]);
            diContentLog(@"CALayer setBackgroundColor intercepted (black): %@", className);
            %orig(UIColor.clearColor.CGColor);
            self.opacity = 0.0;
            self.hidden = YES;
            return;
        }
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
    
    diContentLog(@"DI content process detected, enabling black background clearing");
    diContentLog(@"Hooking _UISystemBackgroundView and MTMaterialView...");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                for (UIView *view in [window.subviews copy]) {
                    NSString *className = NSStringFromClass([view class]);
                    if ([className containsString:@"Background"] ||
                        [className containsString:@"Backdrop"] ||
                        [className containsString:@"Material"]) {
                        diContentLog(@"Initial clear: %@", className);
                        diContentClearView(view);
                    }
                }
            }
        } @catch (__unused NSException *e) {}
    });
    
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull t) {
        @try {
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                for (UIView *view in [window.subviews copy]) {
                    NSString *className = NSStringFromClass([view class]);
                    if ([className containsString:@"Background"] ||
                        [className containsString:@"Backdrop"] ||
                        [className containsString:@"Material"]) {
                        diContentClearView(view);
                    }
                }
            }
        } @catch (__unused NSException *e) {}
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}
