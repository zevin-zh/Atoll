import AppKit
import SwiftUI

/// 动效总开关：尊重系统的「减弱动态效果」。
///
/// 这个 app 到处是 bouncy / spring 动画，而对前庭敏感的用户来说，那是一种
/// 生理不适而不是审美偏好。系统设置里「辅助功能 → 显示 → 减弱动态效果」
/// 就是给这件事用的，接上它只需要在这里判断一次。
enum Motion {
    /// 系统是否开启了「减弱动态效果」。每次都读当前值，切换设置立刻生效。
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 系统开了减弱动效就返回 `nil`（SwiftUI 里等于"不做动画，直接到位"）。
    static func respected(_ animation: Animation?) -> Animation? {
        isReduced ? nil : animation
    }
}
