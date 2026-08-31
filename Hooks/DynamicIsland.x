#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 灵动岛液态玻璃：走 LGRegisterMaterialHost 标准路径注入玻璃，避免手动 hook MTMaterialView 导致崩溃。
// 隐藏灵动岛功能保留（%hook SBSystemApertureWindow）。

static void *kDynamicIslandGradientKey = &kDynamicIslandGradientKey;

static CGFloat lgPrefFloat(NSString *key, CGFloat fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v floatValue];
    return fallback;
}

static NSString *lgPrefString(NSString *key, NSString *fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    return fallback;
}

static UIColor *lgColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]] || hex.length < 7) return nil;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex];
    if (![scanner scanHexInt:&rgb]) return nil;
    CGFloat a = (hex.length > 8) ? ((rgb >> 24) & 0xFF) / 255.0 : 1.0;
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat b = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static BOOL isDynamicIslandMaterial(UIView *mat) {
    if (!isExactClass(mat, @"MTMaterialView")) return NO;
    if (hasAncestorOfClassName(mat, @"SBSystemApertureWindow")) return YES;
    if (hasAncestorOfClassName(mat, @"CCSystemApertureBackgroundDriver")) return YES;
    return NO;
}

static void updateDynamicIslandGradient(LGLiveBackdropView *glass) {
    BOOL gradientEnabled = lgPrefFloat(@"DynamicIsland.GradientShadow", 1.0) > 0.5;
    CAGradientLayer *gradient = objc_getAssociatedObject(glass, kDynamicIslandGradientKey);

    if (!gradientEnabled) {
        [gradient removeFromSuperlayer];
        objc_setAssociatedObject(glass, kDynamicIslandGradientKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }

    if (!gradient) {
        gradient = [CAGradientLayer layer];
        gradient.startPoint = CGPointMake(0.0, 0.0);
        gradient.endPoint = CGPointMake(1.0, 1.0);
        gradient.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(glass, kDynamicIslandGradientKey, gradient, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [glass.layer addSublayer:gradient];
    }

    NSArray *hexColors = @[
        lgPrefString(@"DynamicIsland.GradientColor1", @"#FAFDFF"),
        lgPrefString(@"DynamicIsland.GradientColor2", @"#B8E8FF"),
        lgPrefString(@"DynamicIsland.GradientColor3", @"#9EB3FF"),
        lgPrefString(@"DynamicIsland.GradientColor4", @"#D1ABFF"),
        lgPrefString(@"DynamicIsland.GradientColor5", @"#FFC7F0"),
    ];
    NSMutableArray *colors = [NSMutableArray array];
    for (NSString *hex in hexColors) {
        UIColor *c = lgColorFromHex(hex);
        if (c) [colors addObject:(id)c.CGColor];
    }
    gradient.colors = colors;
    gradient.opacity = lgPrefFloat(@"DynamicIsland.GradientOpacity", 0.35);
    gradient.frame = glass.bounds;
    gradient.cornerRadius = glass.layer.cornerRadius;
}

// 注意：不 hook SBSystemApertureWindow，因为 iOS 17 中它与 SBStatusBarWindow 存在类别/子类关系，
// hook 会影响状态栏窗口导致崩溃。隐藏灵动岛功能暂不实现。

%ctor {
    // 走 LGRegisterMaterialHost 标准路径注入灵动岛玻璃
    LGRegisterMaterialHost(@"DynamicIsland", 95, ^BOOL(UIView *material) {
        return isDynamicIslandMaterial(material);
    }, UIEdgeInsetsZero, ^CGFloat(UIView *material) {
        return material.layer.cornerRadius > 0.0 ? -1.0 : 22.0;
    }, nil, ^(UIView *material, LGLiveBackdropView *glass) {
        glass.alpha = 0.9;
        updateDynamicIslandGradient(glass);
    });

    // 偏好变更时刷新渐变
    lgObservePreferenceReload(^{
        // 渐变层的 frame 在 glass layout 时自动更新，这里只刷新颜色
    });
}
