// SBLiquidGlass Test29
// Native Dynamic Island hierarchy probe.
// IMPORTANT: this build does NOT add glass and does NOT modify any UI.
// It only records the real SBSystemApertureWindow/container hierarchy so
// the next build can target Apple's actual background layer.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "../Shared/LGGlassKit.h"

@interface SBSystemApertureContainerView : UIView
@end

static NSString * const kLGDITest29Log =
    @"/var/mobile/Documents/SBLiquidGlass_DI_Test29.log";

static void LGDI29Write(NSString *line) {
    NSLog(@"[SBLiquidGlass-DI-Test29] %@", line);

    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:kLGDITest29Log]) {
            [fm createFileAtPath:kLGDITest29Log contents:nil attributes:nil];
        }

        NSFileHandle *fh =
            [NSFileHandle fileHandleForWritingAtPath:kLGDITest29Log];
        if (fh) {
            NSString *s = [line stringByAppendingString:@"\n"];
            [fh seekToEndOfFile];
            [fh writeData:[s dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {
    }
}

static void LGDI29DumpView(UIView *view, NSInteger depth, NSInteger maxDepth) {
    if (!view || depth > maxDepth) return;

    NSString *indent = @"";
    for (NSInteger i = 0; i < depth; i++) indent = [indent stringByAppendingString:@"  "];

    CALayer *layer = view.layer;

    NSString *bg = @"nil";
    if (view.backgroundColor) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [view.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
        bg = [NSString stringWithFormat:@"rgba(%.2f,%.2f,%.2f,%.2f)",
              r, g, b, a];
    }

    NSString *layerBG = layer.backgroundColor
        ? [NSString stringWithFormat:@"%@", layer.backgroundColor]
        : @"nil";

    LGDI29Write([NSString stringWithFormat:
        @"%@VIEW %@ frame=%@ bounds=%@ hidden=%d alpha=%.2f bg=%@ subviews=%lu | LAYER %@ frame=%@ opacity=%.2f bg=%@ sublayers=%lu",
        indent,
        NSStringFromClass(view.class),
        NSStringFromCGRect(view.frame),
        NSStringFromCGRect(view.bounds),
        view.hidden,
        view.alpha,
        bg,
        (unsigned long)view.subviews.count,
        NSStringFromClass(layer.class),
        NSStringFromCGRect(layer.frame),
        layer.opacity,
        layerBG,
        (unsigned long)layer.sublayers.count]);

    for (UIView *sub in view.subviews) {
        LGDI29DumpView(sub, depth + 1, maxDepth);
    }
}

static void LGDI29DumpSuperviews(UIView *view) {
    NSInteger level = 0;
    UIView *v = view;

    while (v && level < 8) {
        LGDI29Write([NSString stringWithFormat:
            @"SUPER[%ld] %@ frame=%@ bounds=%@ window=%@ subviews=%lu",
            (long)level,
            NSStringFromClass(v.class),
            NSStringFromCGRect(v.frame),
            NSStringFromCGRect(v.bounds),
            v.window ? @"YES" : @"NO",
            (unsigned long)v.subviews.count]);

        v = v.superview;
        level++;
    }
}

static void LGDI29DumpLayerTree(CALayer *layer, NSInteger depth, NSInteger maxDepth) {
    if (!layer || depth > maxDepth) return;

    NSString *indent = @"";
    for (NSInteger i = 0; i < depth; i++) indent = [indent stringByAppendingString:@"  "];

    LGDI29Write([NSString stringWithFormat:
        @"%@LAYER %@ frame=%@ bounds=%@ opacity=%.2f hidden=%d mask=%@ filters=%@ sublayers=%lu",
        indent,
        NSStringFromClass(layer.class),
        NSStringFromCGRect(layer.frame),
        NSStringFromCGRect(layer.bounds),
        layer.opacity,
        layer.hidden,
        layer.mask ? NSStringFromClass(layer.mask.class) : @"nil",
        layer.filters,
        (unsigned long)layer.sublayers.count]);

    for (CALayer *sub in layer.sublayers) {
        LGDI29DumpLayerTree(sub, depth + 1, maxDepth);
    }
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;

    @try {
        if (!self.window || !lgHostEnabled(@"DynamicIsland")) return;

        static BOOL dumped = NO;
        if (dumped) return;
        dumped = YES;

        [[NSFileManager defaultManager] removeItemAtPath:kLGDITest29Log error:nil];

        LGDI29Write(@"========== TEST29 BEGIN ==========");
        LGDI29Write([NSString stringWithFormat:
            @"container=%@ frame=%@ bounds=%@",
            NSStringFromClass(self.class),
            NSStringFromCGRect(self.frame),
            NSStringFromCGRect(self.bounds)]);

        LGDI29Write(@"--- SUPERVIEW CHAIN ---");
        LGDI29DumpSuperviews(self);

        LGDI29Write(@"--- VIEW TREE (depth 5) ---");
        LGDI29DumpView(self, 0, 5);

        LGDI29Write(@"--- CONTAINER LAYER TREE (depth 5) ---");
        LGDI29DumpLayerTree(self.layer, 0, 5);

        LGDI29Write(@"--- WINDOW INFO ---");
        UIWindow *w = self.window;
        LGDI29Write([NSString stringWithFormat:
            @"WINDOW %@ frame=%@ bounds=%@ alpha=%.2f hidden=%d level=%.1f root=%@",
            NSStringFromClass(w.class),
            NSStringFromCGRect(w.frame),
            NSStringFromCGRect(w.bounds),
            w.alpha,
            w.hidden,
            w.windowLevel,
            w.rootViewController
                ? NSStringFromClass(w.rootViewController.class)
                : @"nil"]);

        LGDI29Write(@"========== TEST29 END ==========");
    } @catch (NSException *e) {
        LGDI29Write([NSString stringWithFormat:@"EXCEPTION %@", e]);
    }
}

%end

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test29] hierarchy probe loaded; UI unchanged");
}
