// Dynamic Island Native Test7 - 调试版
// 目标：找到灵动岛真正的黑色背景层，并彻底清除它
// 安装后控制台搜 DI-DUMP 查看完整层级结构，搜 DI-Native 看清除日志

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

@interface SBSystemApertureContainerView : UIView
@end
@interface _SBSystemApertureContainerViewContentView : UIView
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

    // 打印这个 view 的 layer 树
    diDumpLayerTree(view.layer, depth + 1, output);

    for (UIView *subview in [view.subviews copy]) {
        diDumpViewTree(subview, depth + 1, output);
    }
}

static void diDumpApertureTree(UIView *root) {
    if (!root) return;
    // 只 dump 一次，避免刷屏
    NSNumber *dumped = objc_getAssociatedObject(root, kDIDumpedKey);
    if (dumped && [dumped boolValue]) return;
    objc_setAssociatedObject(root, kDIDumpedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMutableString *output = [NSMutableString stringWithString:@"\n========== DI-DUMP: Dynamic Island View/Layer Tree ==========\n"];
    diDumpViewTree(root, 0, output);
    [output appendString:@"==============================================================\n"];
    NSLog(@"%@", output);

    // 同时写到文件里，方便用户用 Filza 查看（不需要 syslog）
    @try {
        NSString *filePath = @"/var/mobile/Documents/di_dump.txt";
        [output writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[DI-Native] Dump written to %@", filePath);
    } @catch (__unused NSException *e) {}
}

#pragma mark - 激进的背景清除：递归遍历所有层，隐藏全尺寸背景层

static BOOL diLayerLooksLikeOpaqueBackground(CALayer *layer, CALayer *referenceLayer) {
    if (!layer || !referenceLayer) return NO;
    CGRect refBounds = referenceLayer.bounds;
    if (CGRectIsEmpty(refBounds)) return NO;

    CGRect layerBounds = layer.bounds;
    CGFloat refW = CGRectGetWidth(refBounds);
    CGFloat refH = CGRectGetHeight(refBounds);
    if (refW < 1 || refH < 1) return NO;

    // 尺寸接近参考层（覆盖大部分面积）
    CGFloat ratioW = CGRectGetWidth(layerBounds) / refW;
    CGFloat ratioH = CGRectGetHeight(layerBounds) / refH;
    BOOL coversMost = (ratioW > 0.75 && ratioH > 0.6);

    // 有不透明背景色
    BOOL hasOpaqueBg = NO;
    CGColorRef bg = layer.backgroundColor;
    if (bg) {
        size_t n = CGColorGetNumberOfComponents(bg);
        const CGFloat *c = CGColorGetComponents(bg);
        if (n >= 4 && c[3] > 0.5) {
            hasOpaqueBg = YES;
        } else if (n == 2 && c[1] > 0.5) {
            hasOpaqueBg = YES;
        }
    }

    // 有 contents（预渲染的黑色图片）
    BOOL hasOpaqueContents = layer.contents != nil;

    // 是 CABackdropLayer 或其他私有背景层
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
        // 同时清除背景色和 contents
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
        // 清除 view 自身背景
        view.backgroundColor = UIColor.clearColor;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
        view.opaque = NO;

        // 递归隐藏所有背景层
        diHideBackgroundLayersRecursive(view.layer, view.layer, 0);

        // 递归处理子视图
        for (UIView *subview in [view.subviews copy]) {
            diClearAllBackgroundsInView(subview);
        }
    } @catch (__unused NSException *e) {}
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

        // 第一步：dump 完整层级结构（只 dump 一次）
        diDumpApertureTree(root);

        // 找到 content view
        UIView *content = nil;
        for (UIView *sub in [root.subviews copy]) {
            if ([NSStringFromClass(sub.class) isEqualToString:@"_SBSystemApertureContainerViewContentView"]) {
                content = sub;
                break;
            }
        }
        if (!content) {
            // 如果没找到特殊 content view，就用第一个子 view
            content = root.subviews.firstObject;
        }
        if (!content || CGRectIsEmpty(content.bounds)) return;

        // 第二步：激进清除所有背景（递归遍历所有视图和图层）
        diClearAllBackgroundsInView(root);
        diClearAllBackgroundsInView(content);

        // 第三步：创建或获取玻璃层
        LGLiveBackdropView *glass = objc_getAssociatedObject(root, kDIGlassKey);
        if (!glass) {
            NSString *filterType = LGFilterTypeForHostPrefix(@"DynamicIsland");
            if (!filterType.length) filterType = @"dylv.liquidglass.dynamicisland";
            glass = [[LGLiveBackdropView alloc] initWithFrame:content.bounds
                                                     groupName:nil
                                                    filterType:filterType];
            glass.backgroundColor = UIColor.clearColor;
            glass.userInteractionEnabled = NO;

            // 作为 sibling 插在 content view 下面（不往 content view 里插，避免崩溃）
            NSUInteger idx = [root.subviews indexOfObject:content];
            if (idx == NSNotFound) idx = 0;
            [root insertSubview:glass atIndex:idx];

            objc_setAssociatedObject(root, kDIGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            @try { [glass applyFilters]; } @catch (__unused NSException *e) {}
            NSLog(@"[DI-Native] Glass attached to root=%@ content=%@",
                  NSStringFromClass(root.class), NSStringFromClass(content.class));
        }

        // 确保玻璃在 content 下面
        if (glass.superview != root) {
            [root insertSubview:glass atIndex:0];
        } else {
            NSUInteger contentIndex = [root.subviews indexOfObject:content];
            NSUInteger glassIndex = [root.subviews indexOfObject:glass];
            if (contentIndex != NSNotFound && glassIndex != contentIndex) {
                [root insertSubview:glass atIndex:contentIndex];
            }
        }

        diSyncGlassToContent(content, glass);

        // 再清一次背景（系统可能在 layout 后重新设置）
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

%hook _SBSystemApertureContainerViewContentView
- (void)layoutSubviews {
    %orig;
    if (self.window) {
        diClearAllBackgroundsInView(self);
    }
}
- (void)setBackgroundColor:(UIColor *)color {
    if (self.window) {
        %orig(UIColor.clearColor);
    } else {
        %orig(color);
    }
}
%end
