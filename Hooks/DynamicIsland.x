#import <UIKit/UIKit.h>
#import "../Shared/LGLiveBackdropView.h"
#import "../Shared/LGGlassKit.h"
#import <objc/runtime.h>

// 灵动岛液态玻璃 — 运行时功能暂时禁用。
// 原因：iOS 17 中灵动岛在 SBStatusBarWindow 内渲染，LGLiveBackdropView 的 CABackdropLayer
// 在 SBStatusBarWindow 环境中初始化时会触发 doesNotRecognizeSelector 崩溃。
// UI 设置项保留，待后续适配后重新启用运行时效果。

%ctor {
    // 暂时禁用灵动岛 glass 注入
}
