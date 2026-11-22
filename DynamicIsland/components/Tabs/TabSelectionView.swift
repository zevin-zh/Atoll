/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, accentColor: Color? = nil) {
        self.id = "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Namespace var animation
    
    private var tabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "暂存", icon: "tray.fill", view: .shelf))
        }

        // 剪贴板在默认布局和简约布局下都是独立页签。
        if Defaults[.enableClipboardManager] {
            tabsArray.append(TabModel(label: "剪贴板", icon: "doc.on.clipboard", view: .clipboard))
        }

        return tabsArray
    }
    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? .white

                // Render the tab button
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    // 方向必须按"看得见的标签顺序"算：内部 tabOrder 和实际
                    // 渲染顺序不同（中间有被关掉的模块），用它判断会左右颠倒。
                    let oldIndex = tabs.firstIndex(where: { $0.view == coordinator.currentView }) ?? 0
                    let newIndex = tabs.firstIndex(where: { $0.id == tab.id }) ?? 0
                    coordinator.pendingTabDirectionOverride = newIndex >= oldIndex
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? activeAccent : .gray)
                .background {
                    // 只让选中项持有这个胶囊：同一 id 出现多个视图时，
                    // matchedGeometryEffect 的插值起点会跳到错误位置。
                    if isSelected {
                        Capsule()
                            .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                            .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }

                
            }
        }
        .clipShape(Capsule())
        .onAppear {
            ensureValidSelection(with: tabs)
        }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
