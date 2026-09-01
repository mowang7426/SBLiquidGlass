#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import "../Shared/LGSharedSupport.h"
#import <objc/runtime.h>

#pragma mark - 灵动岛视图识别

// 检查视图是否是 nice 灵动岛的自定义视图
static BOOL diIsNiceApertureView(UIView *view) {
    @try {
        NSString *className = NSStringFromClass(view.class);
        return [className hasPrefix:@"NBXLdd"] ||
               [className hasPrefix:@"NBX"] ||
               [className containsString:@"NiceAperture"] ||
               [className containsString:@"NiceIsland"];
    } @catch (__unused NSException *e) {}
    return NO;
}

// 检查视图是否在灵动岛的视图层级中
static BOOL diIsInDynamicIslandHierarchy(UIView *view) {
    @try {
        UIView *candidate = view;
        for (NSInteger level = 0; candidate && level < 20; level++, candidate = candidate.superview) {
            NSString *className = NSStringFromClass(candidate.class);
            // 系统灵动岛类名
            if ([className containsString:@"Aperture"] ||
                [className containsString:@"DynamicIsland"] ||
                [className containsString:@"Island"]) {
                return YES;
            }
            // nice 灵动岛自定义类名
            if ([className hasPrefix:@"NBX"] ||
                [className containsString:@"NiceAperture"] ||
                [className containsString:@"NiceIsland"]) {
                return YES;
            }
        }
        // 检查 window 的类名
        UIWindow *window = view.window;
        if (window) {
            NSString *windowClass = NSStringFromClass(window.class);
            if ([windowClass containsString:@"Aperture"] ||
                [windowClass containsString:@"DynamicIsland"] ||
                [windowClass containsString:@"Island"]) {
                return YES;
            }
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

// 检查是否是灵动岛的材质视图
static BOOL diIsDynamicIslandMaterial(UIView *mat) {
    @try {
        NSString *className = NSStringFromClass(mat.class);
        // 检查是否是材质视图类（包括系统和 nice 灵动岛的背景视图）
        BOOL isMaterial = [className containsString:@"Material"] ||
                          [className containsString:@"Backdrop"] ||
                          [className containsString:@"Blur"] ||
                          [className containsString:@"Glass"] ||
                          [className containsString:@"VisualEffect"] ||
                          [className containsString:@"KeyLine"];
        if (!isMaterial) return NO;
        if (!diIsInDynamicIslandHierarchy(mat)) return NO;
        // 尺寸检查
        CGFloat w = CGRectGetWidth(mat.bounds), h = CGRectGetHeight(mat.bounds);
        if (w < 10.0 || h < 5.0) return NO;
        return YES;
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 液态玻璃效果应用

static void *kDIGlassKey = &kDIGlassKey;

static void diApplyGlassToView(UIView *view) {
    @try {
        if (!lgHostEnabled(@"DynamicIsland")) return;
        
        // 检查是否已经安装了液态玻璃
        LGLiveBackdropView *existing = objc_getAssociatedObject(view, kDIGlassKey);
        if (existing) {
            existing.hidden = NO;
            existing.frame = view.bounds;
            return;
        }
        
        NSLog(@"[SBLiquidGlass-DI] Applying glass to view: %@ frame=%@",
              NSStringFromClass(view.class), NSStringFromCGRect(view.frame));
        
        // 安装液态玻璃效果
        LGLiveBackdropView *glass = LGInstallRegisteredGlassInMaterial(view, kDIGlassKey, @"DynamicIsland");
        if (glass) {
            glass.frame = view.bounds;
            glass.layer.cornerRadius = CGRectGetHeight(view.bounds) * 0.5;
            glass.layer.cornerCurve = kCACornerCurveContinuous;
            glass.layer.masksToBounds = YES;
            NSLog(@"[SBLiquidGlass-DI] Glass applied successfully to %@", NSStringFromClass(view.class));
        } else {
            NSLog(@"[SBLiquidGlass-DI] Failed to apply glass to %@", NSStringFromClass(view.class));
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[SBLiquidGlass-DI] Exception while applying glass: %@", e);
    }
}

static void diApplyGlassToMaterial(UIView *mat) {
    @try {
        if (!diIsDynamicIslandMaterial(mat)) return;
        diApplyGlassToView(mat);
    } @catch (__unused NSException *e) {}
}

static void diRemoveGlassFromView(UIView *view) {
    @try {
        LGLiveBackdropView *existing = objc_getAssociatedObject(view, kDIGlassKey);
        if (existing) {
            [existing removeFromSuperview];
            objc_setAssociatedObject(view, kDIGlassKey, nil, OBJC_ASSOCIATION_ASSIGN);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Hook 系统灵动岛的材质视图

%hook MTMaterialView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToMaterial(self);
        } else {
            diRemoveGlassFromView(self);
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

#pragma mark - Hook nice 灵动岛的自定义视图

// hook NBXLddClassic2View
%hook NBXLddClassic2View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
    } @catch (__unused NSException *e) {}
}

%end

// hook NBXLddClassic3View
%hook NBXLddClassic3View

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
    } @catch (__unused NSException *e) {}
}

%end

#pragma mark - Hook 系统灵动岛容器视图

%hook SBSystemApertureContainerView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            diApplyGlassToView(self);
        } else {
            diRemoveGlassFromView(self);
        }
    } @catch (__unused NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        diApplyGlassToView(self);
    } @catch (__unused NSException *e) {}
}

%end

%ctor {
    @try {
        NSLog(@"[SBLiquidGlass] DynamicIsland tweak loaded (with NiceAperture support)");
    } @catch (__unused NSException *e) {}
}
