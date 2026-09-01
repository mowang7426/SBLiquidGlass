#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 灵动岛视图识别

// 检查视图是否在灵动岛的视图层级中
static BOOL diIsInDynamicIslandHierarchy(UIView *view) {
    @try {
        UIView *candidate = view;
        for (NSInteger level = 0; candidate && level < 10; level++, candidate = candidate.superview) {
            NSString *className = NSStringFromClass(candidate.class);
            // 灵动岛相关的视图类名
            if ([className containsString:@"Aperture"] ||
                [className containsString:@"DynamicIsland"] ||
                [className containsString:@"Island"]) {
                return YES;
            }
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

// 检查是否是灵动岛的 MTMaterialView
static BOOL diIsDynamicIslandMaterial(UIView *mat) {
    @try {
        if (!isExactClass(mat, @"MTMaterialView")) return NO;
        if (!diIsInDynamicIslandHierarchy(mat)) return NO;
        // 尺寸检查
        CGFloat w = CGRectGetWidth(mat.bounds), h = CGRectGetHeight(mat.bounds);
        if (w < 10.0 || h < 10.0) return NO;
        return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 液态玻璃效果应用

static void *kDIGlassKey = &kDIGlassKey;

static void diApplyGlassToMaterial(UIView *mat) {
    @try {
        if (!diIsDynamicIslandMaterial(mat)) return;
        if (!lgHostEnabled(@"DynamicIsland")) return;
        
        // 检查是否已经安装了液态玻璃
        LGLiveBackdropView *existing = objc_getAssociatedObject(mat, kDIGlassKey);
        if (existing) {
            existing.hidden = NO;
            existing.frame = mat.bounds;
            return;
        }
        
        // 安装液态玻璃效果
        LGLiveBackdropView *glass = LGInstallRegisteredGlassInMaterial(mat, kDIGlassKey, @"DynamicIsland");
        if (glass) {
            glass.frame = mat.bounds;
            glass.layer.cornerRadius = CGRectGetHeight(mat.bounds) * 0.5;
            glass.layer.cornerCurve = kCACornerCurveContinuous;
            glass.layer.masksToBounds = YES;
        }
    } @catch (__unused NSException *e) {
        // 异常保护，确保不会导致崩溃
    }
}

static void diRemoveGlassFromMaterial(UIView *mat) {
    @try {
        LGLiveBackdropView *existing = objc_getAssociatedObject(mat, kDIGlassKey);
        if (existing) {
            [existing removeFromSuperview];
            objc_setAssociatedObject(mat, kDIGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook

%hook MTMaterialView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToMaterial(self);
        } else {
            diRemoveGlassFromMaterial(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToMaterial(self);
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    // 灵动岛功能初始化
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded");
    } @catch (__unused NSException *e) {}
}
