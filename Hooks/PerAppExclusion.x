#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 按应用禁用：用户可指定一组 App Bundle ID，这些 App 运行时不显示液态玻璃效果。
// 通过监听前台 App 变化，全局隐藏/显示所有 LGLiveBackdropView。

static NSSet *sExcludedBundleIDs = nil;
static BOOL sExcludedAppFrontmost = NO;

static void lgEnumerateGlassViewsInView(UIView *view, BOOL hidden);

static NSString *lgPrefString(NSString *key, NSString *fallback) {
    id v = LGGlassPreferenceValue(key);
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    return fallback;
}

static void reloadExcludedBundleIDs(void) {
    NSString *csv = lgPrefString(@"Global.ExcludedAppBundleIDs", @"");
    if (!csv.length) {
        sExcludedBundleIDs = [NSSet set];
        return;
    }
    NSArray *parts = [csv componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",; \n"]];
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *p in parts) {
        NSString *trimmed = [p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) [set addObject:trimmed];
    }
    sExcludedBundleIDs = set;
}

static NSString *frontmostAppBundleID(void) {
    // 通过 SpringBoard 的前台应用接口获取
    Class sbClass = NSClassFromString(@"SBMainDisplaySceneManager");
    if (!sbClass) return nil;
    @try {
        id sceneManager = [sbClass valueForKey:@"sharedInstance"];
        if (!sceneManager) sceneManager = [[sbClass alloc] init];
        id frontmostScene = [sceneManager valueForKey:@"frontmostScene"];
        if (frontmostScene) {
            id application = [frontmostScene valueForKey:@"application"];
            if (application) {
                NSString *bundleID = [application valueForKey:@"bundleIdentifier"];
                if (bundleID) return bundleID;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

static void updateExclusionState(void) {
    if (!sExcludedBundleIDs) reloadExcludedBundleIDs();
    NSString *frontmost = frontmostAppBundleID();
    BOOL excluded = frontmost && [sExcludedBundleIDs containsObject:frontmost];

    if (excluded == sExcludedAppFrontmost) return;
    sExcludedAppFrontmost = excluded;

    // 遍历所有窗口，隐藏/显示 LGLiveBackdropView
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        lgEnumerateGlassViewsInView(window, excluded);
    }
}

static void lgEnumerateGlassViewsInView(UIView *view, BOOL hidden) {
    for (UIView *subview in view.subviews) {
        if ([NSStringFromClass(subview.class) containsString:@"LGLiveBackdropView"]) {
            subview.hidden = hidden;
        }
        lgEnumerateGlassViewsInView(subview, hidden);
    }
}

// 监听前台应用变化
%hook SBMainDisplaySceneManager
- (void)sceneManager:(id)sceneManager didChangeForegroundApplication:(id)application {
    %orig;
    [self performSelector:@selector(lg_updateExclusion) withObject:nil afterDelay:0.3];
}
- (void)lg_updateExclusion {
    updateExclusionState();
}
%end

// 偏好变更时重新加载
%ctor {
    reloadExcludedBundleIDs();
    lgObservePreferenceReload(^{
        reloadExcludedBundleIDs();
        updateExclusionState();
    });
}
