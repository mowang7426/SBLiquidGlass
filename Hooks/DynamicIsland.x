// SBLiquidGlass Test31
// Native Dynamic Island compositor/background probe.
// NO visual modifications. NO glass. NO alpha/background/hit-test changes.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../Shared/LGGlassKit.h"

// Logos does not automatically provide a compile-time declaration for the
// private UIKit class used by %hook. Declare the known UIView base so normal
// UIView properties (window, superview, frame, subviews, layer, etc.) compile.
@interface SBSystemApertureContainerView : UIView
@end

static NSString * const kLog = @"/var/mobile/Documents/SBLiquidGlass_DI_Test31.log";

static void LG31(NSString *s) {
    NSLog(@"[SBLiquidGlass-DI-Test31] %@", s);
    @try {
        if (![[NSFileManager defaultManager] fileExistsAtPath:kLog])
            [[NSFileManager defaultManager] createFileAtPath:kLog contents:nil attributes:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kLog];
        if (h) { [h seekToEndOfFile]; [h writeData:[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    } @catch (__unused NSException *e) {}
}

static NSString *LG31BG(UIColor *c) {
    if (!c) return @"nil";
    CGFloat r=0,g=0,b=0,a=0;
    if ([c getRed:&r green:&g blue:&b alpha:&a])
        return [NSString stringWithFormat:@"rgba(%.3f,%.3f,%.3f,%.3f)",r,g,b,a];
    return [NSString stringWithFormat:@"%@", c];
}

static NSString *LG31Class(id o) { return o ? NSStringFromClass([o class]) : @"nil"; }

static void LG31ViewTree(UIView *v, NSInteger depth, NSInteger maxDepth) {
    if (!v || depth > maxDepth) return;
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i=0;i<depth;i++) [indent appendString:@"  "];
    CALayer *l = v.layer;
    LG31([NSString stringWithFormat:
        @"%@VIEW %@ frame=%@ hidden=%d alpha=%.2f opaque=%d bg=%@ sub=%lu | LAYER %@ frame=%@ op=%.2f hidden=%d bg=%@ corner=%.2f mask=%@ filters=%@ comp=%@ sublayers=%lu",
        indent, LG31Class(v), NSStringFromCGRect(v.frame), v.hidden, v.alpha, v.opaque,
        LG31BG(v.backgroundColor), (unsigned long)v.subviews.count,
        LG31Class(l), NSStringFromCGRect(l.frame), l.opacity, l.hidden,
        l.backgroundColor ? [NSString stringWithFormat:@"%@", l.backgroundColor] : @"nil",
        l.cornerRadius, LG31Class(l.mask), l.filters, l.compositingFilter,
        (unsigned long)l.sublayers.count]);
    for (UIView *s in v.subviews) LG31ViewTree(s, depth+1, maxDepth);
}

static void LG31LayerTree(CALayer *l, NSInteger depth, NSInteger maxDepth) {
    if (!l || depth > maxDepth) return;
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i=0;i<depth;i++) [indent appendString:@"  "];
    LG31([NSString stringWithFormat:
        @"%@LAYER %@ frame=%@ op=%.2f hidden=%d bg=%@ corner=%.2f mask=%@ filters=%@ comp=%@ sub=%lu",
        indent, LG31Class(l), NSStringFromCGRect(l.frame), l.opacity, l.hidden,
        l.backgroundColor ? [NSString stringWithFormat:@"%@", l.backgroundColor] : @"nil",
        l.cornerRadius, LG31Class(l.mask), l.filters, l.compositingFilter,
        (unsigned long)l.sublayers.count]);
    for (CALayer *s in l.sublayers) LG31LayerTree(s, depth+1, maxDepth);
}

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (!self.window || !lgHostEnabled(@"DynamicIsland")) return;
        static BOOL dumped = NO;
        if (dumped) return;
        dumped = YES;
        [[NSFileManager defaultManager] removeItemAtPath:kLog error:nil];
        LG31(@"========== TEST31 BEGIN ==========");

        UIView *a1 = self.superview;
        UIView *a2 = a1.superview;
        UIView *a3 = a2.superview;
        UIWindow *w = self.window;

        LG31([NSString stringWithFormat:@"TARGET %@ frame=%@", LG31Class(self), NSStringFromCGRect(self.frame)]);
        LG31([NSString stringWithFormat:@"A1 %@ frame=%@ sub=%lu", LG31Class(a1), NSStringFromCGRect(a1.frame), (unsigned long)a1.subviews.count]);
        LG31([NSString stringWithFormat:@"A2 %@ frame=%@ sub=%lu", LG31Class(a2), NSStringFromCGRect(a2.frame), (unsigned long)a2.subviews.count]);
        LG31([NSString stringWithFormat:@"A3 %@ frame=%@ sub=%lu", LG31Class(a3), NSStringFromCGRect(a3.frame), (unsigned long)a3.subviews.count]);

        LG31(@"--- A2 VIEW TREE depth 7 ---");
        LG31ViewTree(a2, 0, 7);
        LG31(@"--- A2 LAYER TREE depth 9 ---");
        LG31LayerTree(a2.layer, 0, 9);

        LG31(@"--- A3 VIEW TREE depth 6 ---");
        LG31ViewTree(a3, 0, 6);

        LG31([NSString stringWithFormat:@"WINDOW %@ root=%@ frame=%@ level=%.1f",
              LG31Class(w), w.rootViewController ? LG31Class(w.rootViewController) : @"nil",
              NSStringFromCGRect(w.frame), w.windowLevel]);
        LG31(@"========== TEST31 END ==========");
    } @catch (NSException *e) {
        LG31([NSString stringWithFormat:@"EXCEPTION %@", e]);
    }
}

%end

%ctor {
    NSLog(@"[SBLiquidGlass-DI-Test31] compositor probe loaded; UI unchanged");
}
