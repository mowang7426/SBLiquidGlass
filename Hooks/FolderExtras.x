#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 文件夹收纳态玻璃增强：为文件夹图标（未展开时）的玻璃效果添加圆角控制。
// 作为 Folder.x 的补充，调整已注入的文件夹图标玻璃视图的圆角。

static CGFloat lgPrefFloat(NSString *key, CGFloat fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [v floatValue];
    return fallback;
}

static BOOL folderIconExtrasEnabled(void) {
    return lgHostEnabled(@"FolderIcon");
}

static void adjustFolderIconGlassCornerRadius(UIView *iconView) {
    if (!folderIconExtrasEnabled()) return;

    CGFloat customRadius = lgPrefFloat(@"FolderIcon.CornerRadius", -1.0);
    if (customRadius < 0.0) return; // -1 表示使用默认圆角

    // 遍历子视图，找到 LGLiveBackdropView 并调整圆角
    for (UIView *subview in iconView.subviews) {
        if ([NSStringFromClass(subview.class) containsString:@"LGLiveBackdropView"]) {
            subview.layer.cornerRadius = customRadius;
            subview.layer.cornerCurve = kCACornerCurveContinuous;
            subview.layer.masksToBounds = YES;
        }
    }
}

%hook SBFolderIconImageView
- (void)layoutSubviews {
    %orig;
    adjustFolderIconGlassCornerRadius(self);
}
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        adjustFolderIconGlassCornerRadius(self);
    }
}
%end

// 也处理 SBIconView 中的文件夹图标
%hook SBIconView
- (void)layoutSubviews {
    %orig;
    // 检查是否是文件夹图标
    for (UIView *subview in self.subviews) {
        if ([NSStringFromClass(subview.class) containsString:@"FolderIconImageView"]) {
            adjustFolderIconGlassCornerRadius(subview);
        }
    }
}
%end
