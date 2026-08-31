#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 外部插件联动：为 TrollOpen、BarGesture、Kayoko 等第三方插件的 UI 注入液态玻璃。
// 通过识别这些插件的视图控制器/视图类名来匹配 MTMaterialView。

static NSArray *kExternalPluginClassNames = nil;

static NSArray *externalPluginClassNames(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        kExternalPluginClassNames = @[
            // TrollOpen
            @"TrollOpen", @"TODRootViewController", @"TODApplicationListViewController",
            // BarGesture
            @"BarGesture", @"BGRootViewController", @"BGPreferencesViewController",
            // Kayoko
            @"Kayoko", @"KYKRootViewController", @"KYKHistoryViewController",
            // 其他常见插件
            @"Apollo", @"ApolloRootViewController",
            @"Cream", @"CRRootViewController",
        ];
    });
    return kExternalPluginClassNames;
}

static BOOL isExternalPluginMaterial(UIView *mat) {
    if (!isExactClass(mat, @"MTMaterialView")) return NO;
    if (!lgHostEnabled(@"ExternalPlugins")) return NO;

    for (UIView *ancestor = mat; ancestor; ancestor = ancestor.superview) {
        NSString *className = NSStringFromClass(ancestor.class);
        for (NSString *pluginName in externalPluginClassNames()) {
            if ([className containsString:pluginName]) return YES;
        }
    }

    // 也检查响应链中的视图控制器
    UIResponder *responder = mat.nextResponder;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            NSString *vcName = NSStringFromClass([(UIViewController *)responder class]);
            for (NSString *pluginName in externalPluginClassNames()) {
                if ([vcName containsString:pluginName]) return YES;
            }
            break;
        }
        responder = responder.nextResponder;
    }

    return NO;
}

%ctor {
    LGRegisterMaterialHost(@"ExternalPlugins", 90, ^BOOL(UIView *material) {
        return isExternalPluginMaterial(material);
    }, UIEdgeInsetsZero, ^CGFloat(UIView *material) {
        return material.layer.cornerRadius > 0.0 ? -1.0 : 16.0;
    }, nil, ^(UIView *material, LGLiveBackdropView *glass) {
        glass.alpha = 0.85;
    });
}
