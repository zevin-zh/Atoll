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
import SwiftUI

/// 暂存架左侧的隔空投送入口，60pt 窄条。
///
/// 两种用法：
/// - 点一下：把暂存架里所有能投的条目一次性发出去
/// - 把文件拖上去：只投这次拖进来的文件，不进暂存架
///
/// 只调用系统的 `NSSharingService`，不做设备选择、不做进度环 —— AirDrop 自己会弹面板。
struct AirDropBar: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @StateObject private var shelf = ShelfStateViewModel.shared

    @State private var isSending = false
    @State private var isHovering = false

    /// 只用于鼠标悬停的视觉反馈。
    ///
    /// 这里**不能**挂 `onDrop`：暂存架本体、外层拖拽探测器都往
    /// `dragDetectorTargeting` 写值，多一个视图抢同一个标记，任何一处写 false
    /// 都会让外层以为拖拽离开 → 收起岛 → 条消失 → 拖拽重新命中，来回抽搐。
    /// 所以拖文件仍然交给暂存架接住，这条只负责点击投送。
    private var isTargeted: Bool { isHovering }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(isTargeted ? 0.45 : 0.35),
                            Color.black.opacity(isTargeted ? 0.30 : 0.20),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                        )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isTargeted ? 0.11 : 0.09))
                        .frame(width: 40, height: 40)

                    Image(systemName: "square.and.arrow.up")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.gray)
                        .scaleEffect(isTargeted ? 1.06 : 1.0)
                }

                Text(isSending ? "发送中…" : "隔空投送")
                    .font(.system(.caption2, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
        .onTapGesture {
            sendShelfItems()
        }
        .accessibilityElement()
        .accessibilityLabel("隔空投送")
        .accessibilityHint("点击发送暂存架里的文件，或把文件拖到这里")
    }

    // MARK: - 发送

    /// 点按：把暂存架里所有能解析出 URL 的条目发出去。
    private func sendShelfItems() {
        let items = shelf.items
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }

        isSending = true
        Task {
            let urls = await shelf.resolveFileURLsAsync(for: items)
            await MainActor.run {
                isSending = false
                if urls.isEmpty {
                    NSSound.beep()
                } else {
                    perform(urls)
                }
            }
        }
    }

    private func perform(_ urls: [URL]) {
        // 拖出去的文件可能还在沙盒作用域外，先各自开一次访问。
        urls.forEach { _ = $0.startAccessingSecurityScopedResource() }

        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            NSSound.beep()
            urls.forEach { $0.stopAccessingSecurityScopedResource() }
            return
        }

        vm.dropZoneTargeting = false
        service.perform(withItems: urls)
    }
}
