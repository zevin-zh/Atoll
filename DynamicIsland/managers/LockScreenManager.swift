/*
 * Z-island
 *
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Combine

/// 只回答一个问题：屏幕现在锁着没有。
///
/// 这个状态影响两件事，缺一件都会出问题：
///
/// 1. 锁屏时刘海不在屏幕上，我们自己的 HUD 不该再拦按键去画；
/// 2. 解锁状态下会主动压制 macOS 自带的 OSD（否则一次音量出现两个指示器），
///    而这个压制是全局单通道的 —— 锁屏时如果不把系统 OSD 让回去，
///    调亮度、按键盘背光会完全没有提示。
///
/// 所以只需要锁 / 解锁两个通知，加一次启动时的兜底查询。
@MainActor
final class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()

    /// 给非 MainActor 的调用点用的快照（按键回调不一定在主线程）。
    nonisolated(unsafe) private static var cachedLocked = false
    nonisolated static var isLockedSnapshot: Bool { cachedLocked }

    @Published private(set) var isLocked: Bool

    private var observers: [NSObjectProtocol] = []

    private init() {
        isLocked = Self.readSessionLockState()
        Self.cachedLocked = isLocked

        let center = DistributedNotificationCenter.default()
        let events: [(String, Bool)] = [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false),
        ]

        for (name, locked) in events {
            let token = center.addObserver(
                forName: NSNotification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.apply(locked: locked)
                }
            }
            observers.append(token)
        }
    }

    /// 保留旧调用点（AppDelegate 启动时调用），状态由通知自行维护。
    func configure(viewModel: DynamicIslandViewModel) {}

    private func apply(locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
        Self.cachedLocked = locked
    }

    /// 启动时 App 可能在锁屏状态下被拉起，通知不会补发，所以查一次当前会话。
    private static func readSessionLockState() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
