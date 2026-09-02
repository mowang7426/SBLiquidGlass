// Dynamic Island Native Test8 - 修复版
// 修复：正确识别 iOS 17 灵动岛视图层级，修复 dump 时机
// 安装后打开灵动岛，等1秒，用 Filza 打开 /var/mobile/Documents/di_dump.txt

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end

static void *kDIGlassKey = &kDIGlassKey;
static void *kDIDumpedKey = &kDIDumpedKey;

#pragma mark - 调试工具：递归打印视图和图层层级

static void diDumpLayerTree(CALayer *layer, NSInteger depth, NSMutableString *output) {
    if (!layer) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@"  " startingAtIndex:0];
    NSString *name = layer.name ?: @"(null)";
    NSString *className = NSStringFromClass([layer class]);
    CGRect frame = layer.frame;
    CGRect bounds = layer.bounds;
    CGFloat alpha = layer.opacity;
    BOOL hidden = layer.hidden;
    CGColorRef bgColor = layer.backgroundColor;
    BOOL hasContents = layer.contents != nil;
    BOOL hasFilters = layer.filters != nil && [layer.filters count] > 0;
    BOOL hasCompositingFilter = layer.compositingFilter != nil;

    NSString *bgDesc = @"";
    if (bgColor) {
        size_t n = CGColorGetNumberOfComponents(bgColor);
        const CGFloat *c = CGColorGetComponents(bgColor);
        if (n >= 4) {
            bgDesc = [NSString stringWithFormat:@" bg=rgba(%.2f,%.2f,%.2f,%.2f)", c[0], c[1], c[2], c[3]];
        } else if (n == 2) {
            bgDesc = [NSString stringWithFormat:@" bg=gray(%.2f,%.2f)", c[0], c[1]];
        }
    }

    [output appendFormat:@"%@LAYER %@ name=%@ frame=%.0f,%.0f,%.0fx%.0f bounds=%.0fx%.0f alpha=%.2f hidden=%d%@%@%@%@ cornerRadius=%.1f\n",
        indent, className, name,
        frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
        bounds.size.width, bounds.size.height,
        alpha, hidden,
        bgDesc,
        hasContents ? @" HAS_CONTENTS" : @"",
        hasFilters ? @" HAS_FILTERS" : @"",
        hasCompositingFilter ? @" HAS_COMPOSITING_FILTER" : @"",
        layer.cornerRadius];

    for (CALayer *sublayer in [layer.sublayers copy]) {
        diDumpLayerTree(sublayer, depth + 1, output);
    }
}

static void diDumpViewTree(UIView *view, NSInteger depth, NSMutableString *output) {
    if (!view) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@"  " startingAtIndex:0];
    NSString *className = NSStringFromClass([view class]);
    CGRect frame = view.frame;
    CGFloat alpha = view.alpha;
    BOOL hidden = view.hidden;
    UIColor *bgColor = view.backgroundColor;
    NSString *bgDesc = @"";
    if (bgColor) {
        bgDesc = [NSString stringWithFormat:@" bg=%@", bgColor];
    }

    [output appendFormat:@"%@VIEW %@ frame=%.0f,%.0f,%.0fx%.0f alpha=%.2f hidden=%d%@ clipsToBounds=%d\n",
        indent, className,
        frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
        alpha, hidden, bgDesc, view.clipsToBounds];

    diDumpLayerTree(view.layer, depth + 1, output);

    for (UIView *subview in [view.subviews copy]) {
        diDumpViewTree(subview, depth + 1, output);
    }
}

static void diDumpApertureTree(UIView *root) {
    if (!root) return;

    NSNumber *dumped = objc_getAssociatedObject(root, kDIDumpedKey);
    if (dumped && [dumped boolValue]) return;

    // 关键：只有 frame 非零时才 dump
    if (CGRectIsEmpty(root.bounds) || CGRectGetWidth(root.bounds) < 10) {
        NSLog(@"[DI-Native] Skip dump: root bounds is empty (%@)", NSStringFromCGRect(root.bounds));
        return;
    }

    objc_setAssociatedObject(root, kDIDumpedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMutableString *output = [NSMutableString stringWithString:@"\n========== DI-DUMP: Dynamic Island View/Layer Tree ==========\n"];

    // 先打印窗口信息
    UIWindow *window = root.window;
    if (window) {
        [output appendFormat:@"WINDOW: %@ frame=%@ windowLevel=%.0f\n",
            NSStringFromClass([window class]),
            NSStringFromCGRect(window.frame),
            window.windowLevel];

        // dump 整个窗口的层级（灵动岛背景可能在窗口的其他子视图里）
        [output appendString:@"\n--- FULL WINDOW TREE ---\n"];
        diDumpViewTree(window, 0, output);
        [output appendString:@"\n--- END FULL WINDOW TREE ---\n\n"];
    }

    // 再打印 root 的层级
    [output appendString:@"\n--- ROOT (SBSystemApertureContainerView) TREE ---\n"];
    diDumpViewTree(root, 0, output);
    [output appendString:@"\n==============================================================\n"];
    NSLog(@"%@", output);

    // 写到文件里
    @try {
        NSString *filePath = @"/var/mobile/Documents/di_dump.txt";
        [output writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[DI-Native] Dump written to %@", filePath);
    } @catch (__unused NSException *e) {}
}

#pragma mark - 背景清除工具

static BOOL diLayerLooksLikeOpaqueBackground(CALayer *layer, CALayer *referenceLayer) {
    if (!layer || !referenceLayer) return NO;
    CGRect refBounds = referenceLayer.bounds;
    if (CGRectIsEmpty(refBounds)) return NO;

    CGRect layerBounds = layer.bounds;
    CGFloat refW = CGRectGetWidth(refBounds);
    CGFloat refH = CGRectGetHeight(refBounds);
    if (refW < 1 || refH < 1) return NO;

    CGFloat ratioW = CGRectGetWidth(layerBounds) / refW;
    CGFloat ratioH = CGRectGetHeight(layerBounds) / refH;
    BOOL coversMost = (ratioW > 0.75 && ratioH > 0.6);

    BOOL hasOpaqueBg = NO;
    CGColorRef bg = layer.backgroundColor;
    if (bg) {
        size_t n = CGColorGetNumberOfComponents(bg);
        const CGFloat *c = CGColorGetComponents(bg);
        if (n >= 4 && c[3] > 0.5) hasOpaqueBg = YES;
        else if (n == 2 && c[1] > 0.5) hasOpaqueBg = YES;
    }

    BOOL hasOpaqueContents = layer.contents != nil;

    NSString *className = NSStringFromClass([layer class]);
    BOOL isBackdropClass = [className rangeOfString:@"Backdrop" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                            [className rangeOfString:@"Material" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                            [className rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound;

    return coversMost && (hasOpaqueBg || hasOpaqueContents || isBackdropClass);
}

static void diHideBackgroundLayersRecursive(CALayer *layer, CALayer *referenceLayer, NSInteger depth) {
    if (!layer || !referenceLayer || depth > 20) return;
    @try {
        if (diLayerLooksLikeOpaqueBackground(layer, referenceLayer)) {
            NSLog(@"[DI-Native] Hiding background layer: %@ name=%@ bounds=%@",
                  NSStringFromClass([layer class]), layer.name ?: @"(null)",
                  NSStringFromCGRect(layer.bounds));
            layer.hidden = YES;
            layer.opacity = 0.0;
        }
        if (layer.backgroundColor) {
            layer.backgroundColor = UIColor.clearColor.CGColor;
        }
        for (CALayer *sublayer in [layer.sublayers copy]) {
            diHideBackgroundLayersRecursive(sublayer, referenceLayer, depth + 1);
        }
    } @catch (__unused NSException *e) {}
}

static void diClearAllBackgroundsInView(UIView *view) {
    if (!view) return;
    @try {
        view.backgroundColor = UIColor.clearColor;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
        view.opaque = NO;
        diHideBackgroundLayersRecursive(view.layer, view.layer, 0);
        for (UIView *subview in [view.subviews copy]) {
            diClearAllBackgroundsInView(subview);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 找到真正的内容视图（iOS 17 适配）

static UIView *diFindActualContentView(UIView *root) {
    if (!root) return nil;

    // iOS 17: SBSystemApertureContainerView → UIView(clipsToBounds) → _SBSystemApertureContainerViewScalingContentView → _SBSystemApertureContainerViewRotatingContentView
    // 递归查找最内层的、有非零 frame 的内容视图
    for (UIView *sub in [root.subviews copy]) {
        NSString *className = NSStringFromClass(sub.class);
        if ([className rangeOfString:@"RotatingContentView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return sub;
        }
        if ([className rangeOfString:@"ScalingContentView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            UIView *inner = diFindActualContentView(sub);
            if (inner) return inner;
            return sub;
        }
    }

    // 如果没找到，递归找最内层的非零 frame 视图
    for (UIView *sub in [root.subviews copy]) {
        if (!CGRectIsEmpty(sub.bounds) && CGRectGetWidth(sub.bounds) > 10) {
            UIView *inner = diFindActualContentView(sub);
            if (inner) return inner;
        }
    }

    // 最后兜底：用第一个有非零 frame 的子视图
    for (UIView *sub in [root.subviews copy]) {
        if (!CGRectIsEmpty(sub.bounds) && CGRectGetWidth(sub.bounds) > 10) {
            return sub;
        }
    }
    return nil;
}

#pragma mark - 液态玻璃应用

static void diSyncGlassToContent(UIView *content, LGLiveBackdropView *glass) {
    if (!content || !glass) return;
    glass.frame = content.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;
    glass.backgroundColor = UIColor.clearColor;
    glass.alpha = 1.0;
    CGFloat radius = content.layer.cornerRadius;
    if (radius <= 0.0)
        radius = MIN(CGRectGetWidth(content.bounds), CGRectGetHeight(content.bounds)) * 0.5;
    glass.layer.cornerRadius = radius;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
}

static void diApplyGlassToRoot(SBSystemApertureContainerView *root) {
    @try {
        if (!root || !root.window || !lgHostEnabled(@"DynamicIsland")) return;
        if (root.subviews.count == 0) return;

        // dump 完整层级结构（只 dump 一次，frame 非零时才 dump）
        NSNumber *dumped = objc_getAssociatedObject(root, kDIDumpedKey);
        if (!dumped || ![dumped boolValue]) {
            if (CGRectIsEmpty(root.bounds) || CGRectGetWidth(root.bounds) < 10) {
                __weak SBSystemApertureContainerView *weakRoot = root;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong SBSystemApertureContainerView *strongRoot = weakRoot;
                    if (strongRoot && strongRoot.window) {
                        diDumpApertureTree(strongRoot);
                    }
                });
            } else {
                diDumpApertureTree(root);
            }
        }

        // 关键修复：找到真正的内容视图（iOS 17 是 RotatingContentView，不是 _SBSystemApertureContainerViewContentView）
        UIView *content = diFindActualContentView(root);
        if (!content) {
            NSLog(@"[DI-Native] ERROR: Could not find actual content view");
            return;
        }
        if (CGRectIsEmpty(content.bounds)) {
            NSLog(@"[DI-Native] Content view bounds is empty, will retry on next layout");
            return;
        }

        NSLog(@"[DI-Native] Found content view: %@ frame=%@",
              NSStringFromClass(content.class), NSStringFromCGRect(content.frame));

        // 清除所有背景
        diClearAllBackgroundsInView(root);
        diClearAllBackgroundsInView(content);

        // 创建或获取玻璃层
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";
            glass = [[LGLiveBackdropView alloc] initWithFrame:content.bounds
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.userInteractionEnabled = NO;

            // 把玻璃插到 content view 的 superview 里，在 content 下面
            UIView *parent = content.superview ?: root;
            NSUInteger idx = [parent.subviews indexOfObject:content];
            if (idx == NSNotFound) idx = 0;
            [parent insertSubview:glass atIndex:idx];

            objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            NSLog(@"[DI-Native] Glass attached to parent=%@ content=%@",
                  NSStringFromClass(parent.class), NSStringFromClass(content.class));
        }

        // 确保玻璃在 content 下面
        UIView *parent = content.superview ?: root;
        if (glass.superview != parent) {
            [parent insertSubview:glass atIndex:0];
        } else {
            NSUInteger contentIndex = [parent.subviews indexOfObject:content];
            NSUInteger glassIndex = [parent.subviews indexOfObject:glass];
            if (contentIndex != NSNotFound && glassIndex != contentIndex) {
                [parent insertSubview:glass atIndex:contentIndex];
            }
        }

        diSyncGlassToContent(content, glass);

        // 再清一次背景
        diClearAllBackgroundsInView(content);

    } @catch (NSException *e) {
        NSLog(@"[DI-Native] Exception: %@", e);
    }
}

static void diRemoveGlass(SBSystemApertureContainerView *root) {
    @try {
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (glass) [glass removeFromSuperview];
        objc_setAssociatedObject(root, kDIGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(root, kDIDumpedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
