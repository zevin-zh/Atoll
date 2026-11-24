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

import AVFoundation
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @ObservedObject private var menuBarLayout = MenuBarLayout.shared
    /// Width of the closed-notch content, measured so its left edge can be
    /// compared against the frontmost app's menus. Only the *size* is read --
    /// the offset that follows does not change it, so there is no feedback.
    @State private var closedContentWidth: CGFloat = 0
    @ObservedObject var capsLockManager = CapsLockManager.shared
    @ObservedObject var localSendService = LocalSendService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @Default(.enableCapsLockIndicator) var enableCapsLockIndicator
    @Default(.showStandardMediaControls) var showStandardMediaControls
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover
    
    @Default(.showOnAllDisplays) var showOnAllDisplays
    
    // Dynamic sizing based on view type and graph count with smooth transitions
    var dynamicNotchSize: CGSize {
        let baseSize = Defaults[.enableMinimalisticUI] ? minimalisticOpenNotchSize(isDynamicIslandMode: isDynamicIslandMode) : openNotchSize

        // When inline sneak peek is active in closed notch, use the wider inline width
        // so the outer maxWidth frame doesn't clip the expanded content
        let airPodsListeningModeSneakActive = vm.notchState == .closed
            && coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .bluetoothAudio
            && coordinator.sneakPeek.value < 0
            && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let inlineSneakPeekActive = vm.notchState == .closed
            && (
                coordinator.expandingView.show
                    && coordinator.expandingView.type == .music
                    && Defaults[.sneakPeekStyles] == .inline
                || airPodsListeningModeSneakActive
            )
            && Defaults[.enableSneakPeek]
        if inlineSneakPeekActive {
            let inlineWidth: CGFloat = airPodsListeningModeSneakActive
                ? InlineHUD.airPodsListeningModeWidth(
                    closedNotchWidth: vm.closedNotchSize.width,
                    gestureProgress: gestureProgress,
                    minimalistic: Defaults[.enableMinimalisticUI]
                ) + notchHorizontalPadding * 2
                : 460
            return CGSize(width: max(baseSize.width, inlineWidth), height: baseSize.height)
        }
        return baseSize
    }
    

    @State private var hoverTask: Task<Void, Never>?
    /// 形状动画期间 SwiftUI 会误报 hover 离开，这里延迟复核指针是否真的走了。
    @State private var hoverExitRecheckTask: Task<Void, Never>?
    /// 位置轮询兜底：完全不依赖 SwiftUI 的 onHover 命中测试。
    ///
    /// 现在只在“收不到指针事件”时（没有辅助功能权限）才按高频率跑，
    /// 其余时间交给下面的 `pointerMonitor`，间隔降到 1s 纯做兜底。
    @State private var hoverPollerTask: Task<Void, Never>?
    /// 指针事件监听：全局/本地 `mouseMoved` + `leftMouseDragged`。
    /// 装上之后就不再需要 100ms 的常开轮询——鼠标不动就没有回调。
    @State private var pointerMonitor: Any?
    @State private var pointerLocalMonitor: Any?
    /// 指针事件合并：是否已有一个待执行的 poll，以及上一次 poll 的时间戳。
    @State private var hoverPollPending: Bool = false
    @State private var lastPointerPollAt: CFTimeInterval = 0
    @State private var isHovering: Bool = false
    @State private var lastHapticTime: Date = Date()
    @State private var hoverClickMonitor: Any?
    @State private var hoverClickLocalMonitor: Any?
    @State private var hiddenEdgeHoverPollingTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false


    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation
    @Default(.enableMinimalisticUI) var enableMinimalisticUI


    private func runAfter(_ delay: TimeInterval, _ action: @escaping @Sendable @MainActor () -> Void) {
        guard delay >= 0 else { return }
        Task { @MainActor in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private var dynamicNotchResizeAnimation: Animation? {
        nil
    }
    
    private let zeroHeightHoverPadding: CGFloat = 10
    private let notchAdditionalRowHeadroom: CGFloat = 132

    // MARK: - Tab switch direction for smooth transitions
    
    private var tabSwitchTransition: AnyTransition {
        // 减弱动效时只做淡入淡出，不做横向位移——后者是引起不适的主要来源。
        if Motion.isReduced { return .opacity }

        if coordinator.tabSwitchForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }


    private var interactionsEnabled: Bool {
        !lockScreenManager.isLocked
    }

    private var isIslandMode: Bool {
        isDynamicIslandMode
    }

    private var notchHorizontalPadding: CGFloat {
        guard vm.notchState == .open else {
            return activeCornerRadiusInsets.closed.bottom
        }
        if Defaults[.cornerRadiusScaling] {
            return activeCornerRadiusInsets.opened.top - 5
        }
        return activeCornerRadiusInsets.opened.bottom - 5
    }

    private var bodyHoverAreaPadding: CGFloat {
        if vm.notchState == .open && Defaults[.extendHoverArea] {
            return 0
        }
        return vm.effectiveClosedNotchHeight == 0 ? zeroHeightHoverPadding : 6
    }

    private var notchBottomPadding: CGFloat {
        currentShadowPadding + bodyHoverAreaPadding
    }

    private var pillTopOffset: CGFloat {
        isIslandMode ? dynamicIslandTopOffset : 0
    }


    private var closedLiveActivitySwapTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.965, anchor: .center))
                .animation(Motion.respected(.spring(response: 0.34, dampingFraction: 0.88))),
            removal: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .center))
                .animation(Motion.respected(.smooth(duration: 0.22)))
        )
    }
    
    // Use minimalistic corner radius ONLY when opened, keep normal when closed
    private var activeCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) {
        if enableMinimalisticUI {
            // Keep normal closed corner radius, use minimalistic when opened
            return (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
        }
        return cornerRadiusInsets
    }
    
    private var currentShadowPadding: CGFloat {
        notchShadowPaddingValue(isMinimalistic: enableMinimalisticUI)
    }

    private var currentNotchShape: NotchShape {
        let topRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.top
            : activeCornerRadiusInsets.closed.top
        let bottomRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.bottom
            : activeCornerRadiusInsets.closed.bottom
        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    /// Whether the current screen should render as a Dynamic Island pill
    /// rather than the standard notch shape. Always false on physical notch screens.
    private var isDynamicIslandMode: Bool {
        shouldUseDynamicIslandMode(for: currentScreenName)
    }

    private var currentScreenName: String {
        vm.screen ?? coordinator.selectedScreen
    }

    /// Whether the current screen lacks a physical notch.
    private var isNonNotchScreen: Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return true
        }
        return screen.safeAreaInsets.top <= 0
    }

    /// Whether the global sneak peek is visible on this specific screen.
    private var isSneakPeekVisibleOnCurrentScreen: Bool {
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.showOnAllDisplays] else { return true }
        guard let targetScreenName = coordinator.sneakPeek.targetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    /// Whether the notch/island should hide off-screen when closed on a non-notch display.
    /// Temporarily reveals the notch when a sneakPeek HUD (volume, brightness, music, etc.) is active.
    private var shouldHideUntilHover: Bool {
        hideNonNotchUntilHover
            && isNonNotchScreen
            && vm.notchState == .closed
            && !isSneakPeekVisibleOnCurrentScreen
    }

    /// Whether the fallback top-edge hover detector should run.
    /// This is only needed when the notch is fully hidden off-screen and
    /// regular `.onHover` hit-testing may not trigger reliably.
    private var shouldUseHiddenEdgeHoverPolling: Bool {
        shouldHideUntilHover && !lockScreenManager.isLocked
    }
    
    /// Whether the LocalSend live activity should be shown
    private var localSendLiveActivityActive: Bool {
        localSendService.isSending || 
        localSendService.transferState == .completed ||
        isLocalSendFailedOrRejected
    }
    
    private var isLocalSendFailedOrRejected: Bool {
        if case .failed = localSendService.transferState { return true }
        if case .rejected = localSendService.transferState { return true }
        return false
    }

    /// Pill shape for Dynamic Island mode with animated corner radius transitions.
    private var currentPillShape: DynamicIslandPillShape {
        let radius: CGFloat
        if vm.notchState == .open {
            radius = enableMinimalisticUI
                ? minimalisticCornerRadiusInsets.opened.top
                : dynamicIslandPillCornerRadiusInsets.opened
        } else {
            // Use half the closed height for a true capsule shape
            radius = max(vm.closedNotchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
        }
        return DynamicIslandPillShape(cornerRadius: radius)
    }

    private var isCurrentScreenExpansionVisible: Bool {
        coordinator.expandingView.show
    }

    private var currentScreenExpansionType: SneakContentType? {
        isCurrentScreenExpansionVisible ? coordinator.expandingView.type : nil
    }

    /// Resolves the clip/content shape per-screen: pill on non-notch screens
    /// when dynamic island mode is active, standard notch shape otherwise.
    private var resolvedClipShape: AnyShape {
        if isDynamicIslandMode {
            return AnyShape(currentPillShape)
        }
        return AnyShape(currentNotchShape)
    }

    var body: some View {
        installRootLifecycleHandlers(on: rootBodyView)
    }

    private var mainLayoutBase: some View {
        NotchLayout()
            // 展开态高度钉死：剪贴板清空后内部内容会塌成 0 高，
            // 而 .background(.black) + .clipShape 跟着内容走，不钉住就会
            // 塌成直角矩形。高度来源必须和窗口一致（dynamicNotchSize，
            // 简约模式下是 minimalisticOpenNotchSize），用全局 openNotchSize
            // 会比窗口高出阴影边距，底部被窗口裁掉。
            .frame(height: vm.notchState == .open ? dynamicNotchSize.height : nil,
                   alignment: .top)
            .frame(alignment: .top)
            .padding(.horizontal, notchHorizontalPadding)
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .background(.black)
            .clipShape(resolvedClipShape)
            // Keep the anti-gap fill outside the clipped notch. The window sits
            // this far above screen.maxY, so placing the spacer after clipShape
            // leaves the notch's top corners anchored to the visible screen edge.
            .padding(.top, isIslandMode ? 0 : notchTopScreenBleedAmount)
            .overlay(alignment: .top) {
                if !isIslandMode {
                    Rectangle()
                        .fill(.black)
                        .frame(height: notchTopScreenBleedAmount)
                }
            }
            .compositingGroup()
            .shadow(
                color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                    ? .black.opacity(0.6)
                    : .clear,
                radius: Defaults[.cornerRadiusScaling] ? 10 : 5
            )
            // Extra horizontal inset for Dynamic Island mode so the shadow
            // is not clipped by the outer frame constraint
            .padding(.horizontal, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.bottom, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.top, pillTopOffset)
            .accessibilityIdentifier("AtollNotch")
    }

    private var configuredMainLayout: some View {
        mainLayoutBase
            .conditionalModifier(!useModernCloseAnimation) { view in
                let hoverAnimation = Animation.bouncy.speed(1.2)
                let notchStateAnimation = Animation.spring(response: 0.42, dampingFraction: 1.0, blendDuration: 0)
                return view
                    .animation(Motion.respected(hoverAnimation), value: isHovering)
                    .animation(Motion.respected(notchStateAnimation), value: vm.notchState)
                    .animation(Motion.respected(.smooth), value: gestureProgress)
                    .transition(.blurReplace.animation(Motion.respected(.interactiveSpring(dampingFraction: 1.2))))
            }
            .conditionalModifier(useModernCloseAnimation) { view in
                // 原来 open/close 都是 dampingFraction 1.0（完全不回弹），
                // 收放像被硬切；给一点回弹余量，手感更接近 iOS 灵动岛。
                let hoverAnimation = Animation.spring(response: 0.26, dampingFraction: 0.86)
                let openAnimation = Animation.spring(response: 0.46, dampingFraction: 0.84, blendDuration: 0.2)
                let closeAnimation = Animation.spring(response: 0.36, dampingFraction: 0.94, blendDuration: 0.1)
                let notchAnimation = vm.notchState == .open ? openAnimation : closeAnimation
                return view
                    .animation(Motion.respected(hoverAnimation), value: isHovering)
                    .animation(Motion.respected(notchAnimation), value: vm.notchState)
                    .animation(Motion.respected(.smooth), value: gestureProgress)
            }
            .conditionalModifier(interactionsEnabled) { view in
                view
                    .contentShape(resolvedClipShape)
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        if vm.notchState == .closed && Defaults[.enableHaptics] {
                            triggerHapticIfAllowed()
                        }
                        openNotch()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
            }
            .conditionalModifier((Defaults[.closeGestureEnabled] || Defaults[.reverseScrollGestures]) && Defaults[.enableGestures] && interactionsEnabled) { view in
                view
                    .panGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
            }
            // Shadow bottom padding and hide-until-hover offset applied AFTER
            // interaction modifiers so .contentShape / .onHover only covers
            // the actual notch content, not the shadow clearance below it.
            .padding(.bottom, notchBottomPadding)
            .offset(y: shouldHideUntilHover && !isHovering
                ? -(vm.closedNotchSize.height + pillTopOffset + currentShadowPadding + 10)
                : 0
            )
            .onAppear(perform: {
                startHoverPolling()
                if coordinator.firstLaunch {
                    // Single open during first launch; closeHello() handles the timed close.
                    runAfter(1) {
                        openNotch()
                    }
                }
            })
            .onChange(of: vm.notchState) { _, newState in
                // Reset hover state when notch state changes
                if newState == .closed && isHovering {
                    withAnimation {
                        isHovering = false
                    }
                }
            }
            .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                runAfter(0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: vm.shouldRecheckHover) { _, _ in
                // Recheck hover state when popovers are closed
                runAfter(0.1) {
                    if vm.notchState == .open && !shouldPreventAutoClose() && !isHovering {
                        vm.close()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                runAfter(0.1) {
                    if vm.notchState == .open && !isHovering && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: coordinator.sneakPeek.show) { _, sneakPeekShowing in
                // When sneak peek finishes, check if user is still hovering and open notch if needed
                if !sneakPeekShowing {
                    runAfter(0.2) {
                        if isHovering && vm.notchState == .closed && !coordinator.isHoverOpenSuppressed {
                            openNotch()
                        }
                    }
                }
            }
            .sensoryFeedback(.alignment, trigger: haptics)
    }

    private var rootBodyView: some View {
        ZStack(alignment: .top) {
            configuredMainLayout
        }
        .frame(
            maxWidth: (dynamicNotchSize.width + (vm.notchState == .open ? 24 : 0) + (isDynamicIslandMode ? dynamicIslandShadowInset * 2 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height + (vm.notchState == .open ? 12 : 0) + (isIslandMode ? 0 : notchTopScreenBleedAmount) + (isDynamicIslandMode ? dynamicIslandTopOffset + dynamicIslandShadowInset * 2 : currentShadowPadding)).rounded(),
            alignment: .top
        )
        .animation(nil, value: vm.notchState)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(dragDetector)
        .environmentObject(vm)
    }

    private func installRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        installPrimaryRootLifecycleHandlers(on: view)
    }

    private func installPrimaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onAppear {
                startHiddenEdgeHoverPolling()
                // Deterministic teardown for borderless panels (`.onDisappear` is
                // unreliable); the window-cleanup path calls this before closing.
                vm.onViewTeardown = { performViewTeardown() }
            }
            .onAppear {
                if vm.notchState == .closed { menuBarLayout.startTracking() }
            }
            .onChange(of: vm.notchState) { _, state in
                // An open notch covers the menu bar wholesale and is the user's
                // own doing, so there is nothing to step around while it is up.
                if state == .closed {
                    menuBarLayout.startTracking()
                } else {
                    menuBarLayout.stopTracking()
                }
            }
            .onDisappear {
                performViewTeardown()
            }
    }

    /// How far right the closed-notch content has to move so it stops covering
    /// the frontmost app's menus.
    ///
    /// A live activity's left wing draws into the strip of menu bar beside the
    /// notch, which is where the app's own menus live. macOS lays those out
    /// against `NSScreen.auxiliaryTopLeftArea` and there is no way to tell it
    /// some of that strip is spoken for -- both auxiliary areas are read-only.
    /// So the content moves instead of the menus.
    ///
    /// Zero unless something is actually being covered: no live activity, an
    /// open notch, no accessibility permission, or menus that end before the
    /// content begins all leave the notch centred where it belongs.
    private var menuBarClearanceOffset: CGFloat {
        guard vm.notchState == .closed,
              !vm.hideOnClosed,
              closedContentWidth > 0,
              let menusRightEdge = menuBarLayout.appMenusRightEdge,
              let screenFrame = getScreenFrame(currentScreenName)
        else { return 0 }

        return MenuBarLayout.clearanceOffset(
            contentWidth: closedContentWidth,
            screenFrame: screenFrame,
            menusRightEdge: menusRightEdge,
            gap: MenuBarLayout.clearanceGap
        )
    }

    @ViewBuilder
      func NotchLayout() -> some View {
          VStack(alignment: .leading) {
              VStack(alignment: .leading) {
                  if coordinator.firstLaunch {
                      Spacer()
                      HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
                          vm.closeHello()
                      })
                      .padding(.top, 40)
                      Spacer()
                  } else {
                      let activeSneakPeekStyle = resolvedSneakPeekStyle()
                      let isAirPodsListeningModeSneak = coordinator.sneakPeek.type == .bluetoothAudio
                          && coordinator.sneakPeek.value < 0
                          && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil

                      if isSneakPeekVisibleOnCurrentScreen && (Defaults[.inlineHUD] || isAirPodsListeningModeSneak) && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(
                                  coordinator.sneakPeek.type == .capsLock
                                      ? AnyTransition.move(edge: .trailing).combined(with: .opacity)
                                      : AnyTransition.opacity
                              )
                      } else if vm.notchState == .closed && capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator] && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          InlineHUD(type: .constant(.capsLock), value: .constant(1.0), icon: .constant(""), hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && !shelfState.isEmpty && !vm.hideOnClosed && !lockScreenManager.isLocked && !enableMinimalisticUI {
                          ShelfInlineLiveActivity()
                              .transition(.opacity.animation(Motion.respected(.smooth(duration: 0.25))))
                      } else if !isCurrentScreenExpansionVisible && vm.notchState == .closed && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          DynamicIslandFaceAnimation().animation(Motion.respected(.interactiveSpring), value: vm.notchState)
                      } else if vm.notchState == .open {
                          DynamicIslandHeader()
                              .frame(height: (Defaults[.enableMinimalisticUI] && isDynamicIslandMode) ? nil : max(24, vm.effectiveClosedNotchHeight))
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }
                      
                      if isSneakPeekVisibleOnCurrentScreen {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .capsLock) && !Defaults[.inlineHUD] && !isAirPodsListeningModeSneak && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                              SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                  //
                              })
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                      }
                  }
              }
              .conditionalModifier(shouldFixSizeForSneakPeek()) { view in
                  view
                      .fixedSize()
              }
              .background {
                  GeometryReader { geo in
                      Color.clear
                          .onAppear { closedContentWidth = geo.size.width }
                          .onChange(of: geo.size.width) { _, width in closedContentWidth = width }
                  }
              }
              .offset(x: menuBarClearanceOffset)
              .animation(Motion.respected(.smooth(duration: 0.25)), value: menuBarClearanceOffset)
              .zIndex(2)
              
              ZStack(alignment: .top) {
                  if vm.notchState == .open {
                      Group {
                          switch coordinator.currentView {
                          case .shelf:
                              NotchShelfView()
                          case .clipboard:
                              NotchClipboardView()
                          }
                      }
                      .id(coordinator.currentView)
                      .transition(tabSwitchTransition)
                  }
              }
              .zIndex(1)
              .allowsHitTesting(vm.notchState == .open)
              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
              .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
              .animation(Motion.respected(.smooth(duration: 0.3)), value: coordinator.currentView)
          }
      }

    @ViewBuilder
    func DynamicIslandFaceAnimation() -> some View {
        let sideSize = max(0, vm.effectiveClosedNotchHeight - 12)
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(width: sideSize, height: sideSize)
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                IdleAnimationView()
                    .frame(width: sideSize, height: sideSize)
            }
        }.frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }




    @ViewBuilder
    var dragDetector: some View {
        if lockScreenManager.isLocked {
            EmptyView()
        } else if Defaults[.dynamicShelf] && !Defaults[.enableMinimalisticUI] {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }
                .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                    if isTargeted, vm.notchState == .closed {
                        coordinator.currentView = .shelf
                        openNotch()
                    } else if !isTargeted {
                        if vm.dropEvent {
                            vm.dropEvent = false
                            return
                        }

                        vm.dropEvent = false
                        if !shouldPreventAutoClose() {
                            vm.close()
                        }
                    }
                }
        } else {
            EmptyView()
        }
    }

    // MARK: - Private Methods

    private func openNotch() {
        vm.open()
    }

    private func hiddenHoverActivationContainsMouse(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let horizontalPadding: CGFloat = 8
        let activationWidth = vm.closedNotchSize.width + horizontalPadding * 2
        let activationHeight = max(vm.closedNotchSize.height + zeroHeightHoverPadding, 14)

        // Follows the rendered content: when a live activity has stepped aside
         // from the menus, activating at the old centre would arm the notch where
         // nothing is drawn and refuse the pointer where it is.
        let activationRect = CGRect(
            x: screen.frame.midX - activationWidth / 2 + menuBarClearanceOffset,
            y: screen.frame.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )

        return activationRect.contains(location)
    }

    /// Cancels every long-lived task / event monitor this view owns. Called from
    /// `.onDisappear` and from `vm.onViewTeardown` on window close. Idempotent.
    private func performViewTeardown() {
        menuBarLayout.stopTracking()
        hoverTask?.cancel()
        // 这两个之前没拆：窗口关掉以后轮询和指针监听会一直活着。
        hoverPollerTask?.cancel()
        hoverPollerTask = nil
        stopPointerMonitor()
        stopHoverClickMonitor()
        stopHiddenEdgeHoverPolling()
    }

    private func startHiddenEdgeHoverPolling() {
        guard hiddenEdgeHoverPollingTask == nil else { return }

        hiddenEdgeHoverPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                if self.shouldUseHiddenEdgeHoverPolling {
                    let hovering = self.hiddenHoverActivationContainsMouse()
                    if hovering != self.isHovering {
                        self.handleHover(hovering)
                    }
                } else if self.isHovering && self.interactionsEnabled {
                    let stillInside = self.vm.notchState == .open
                        ? self.isPointInsideNotchWindow()
                        : self.isMouseOverClosedNotchHitArea()
                    if !stillInside {
                        self.hoverTask?.cancel()
                        self.stopHoverClickMonitor()
                        self.finishHoverExit()
                    }
                }

                try? await Task.sleep(for: .milliseconds(self.hiddenEdgeHoverPollingIntervalMs()))
            }

            self.hiddenEdgeHoverPollingTask = nil
        }
    }

    private func hiddenEdgeHoverPollingIntervalMs() -> Int {
        if shouldUseHiddenEdgeHoverPolling {
            return 50
        }
        if isHovering && interactionsEnabled {
            return 100
        }
        return 1_000
    }

    private func stopHiddenEdgeHoverPolling() {
        hiddenEdgeHoverPollingTask?.cancel()
        hiddenEdgeHoverPollingTask = nil
    }

    private func startHoverClickMonitor() {
        guard Defaults[.openNotchOnHover] else { return }
        guard hoverClickMonitor == nil else { return }

        let handleClick: @Sendable () -> Void = { [weak vm, weak lockScreenManager] in
            Task { @MainActor in
                guard let vm, let lockScreenManager else { return }
                guard !lockScreenManager.isLocked else { return }
                guard vm.notchState == .closed else { return }
                guard !self.coordinator.isHoverOpenSuppressed else { return }
                guard self.isHovering else { return }
                if Defaults[.enableHaptics] {
                    self.triggerHapticIfAllowed()
                }
                self.openNotch()
            }
        }

        // Global monitor catches clicks outside the app window (e.g. when
        // the cursor is at the very top screen edge and the click goes to
        // the system rather than our panel).
        hoverClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            handleClick()
        }

        // Local monitor catches clicks that DO hit our window — at the
        // screen edge SwiftUI's .onTapGesture may not fire reliably, but
        // the NSEvent local monitor will.
        hoverClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handleClick()
            return event
        }
    }

    private func stopHoverClickMonitor() {
        if let hoverClickMonitor {
            NSEvent.removeMonitor(hoverClickMonitor)
            self.hoverClickMonitor = nil
        }
        if let hoverClickLocalMonitor {
            NSEvent.removeMonitor(hoverClickLocalMonitor)
            self.hoverClickLocalMonitor = nil
        }
    }

    // MARK: - Hover Management
    
    /// Handle hover state changes with debouncing
    private func handleHover(_ hovering: Bool) {
        // Ignore false hover-exit when the cursor is parked on the screen's top pixel.
        if !hovering, shouldRetainHoverAtScreenTopEdge() {
            return
        }

        if !hovering, isMouseOverClosedNotchHitArea() {
            // 指针其实还停在刘海上，只是内容形状在动画 —— 保留待触发的悬停任务。
            scheduleHoverExitRecheck()
            return
        }

        hoverExitRecheckTask?.cancel()
        hoverTask?.cancel()

        if hovering {
            startHoverClickMonitor()
        } else {
            stopHoverClickMonitor()
        }

        if hovering {
            withAnimation(Motion.respected(.bouncy.speed(1.2))) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            guard vm.notchState == .closed,
                !isSneakPeekVisibleOnCurrentScreen,
                Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.isSneakPeekVisibleOnCurrentScreen,
                          !self.coordinator.isHoverOpenSuppressed else { return }

                    self.openNotch()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if self.shouldRetainHoverAtScreenTopEdge() {
                        return
                    }
                    self.finishHoverExit()
                }
            }
        }
    }

    /// 拖动文件靠近刘海时强制打开暂存架。
    /// 不依赖 `draggingEntered` 的先后顺序 —— 从面板边缘进入时 SwiftUI 会先接管，
    /// 那时页面已经被它按"上次的页面"打开了。
    /// 返回 true 表示当前处于文件拖拽会话，调用方应跳过常规悬停处理。
    private func handleFileDragIfNeeded() -> Bool {
        // 没按着鼠标键就不可能是拖拽。先挡掉：指针事件现在按鼠标移动频率触发，
        // 每次移动都去开 `.drag` 粘贴板读类型太浪费了。
        guard NSEvent.pressedMouseButtons != 0 else {
            if NotchBridge.shared.isFileDragActive {
                NotchBridge.shared.isFileDragActive = false
            }
            return false
        }

        let dragBoard = NSPasteboard(name: .drag)
        // 拖拽结束后 .drag 粘贴板可能还留着类型，所以按着键也要再确认一次类型。
        let isFileDrag = (dragBoard.types ?? []).contains(.fileURL)

        guard isFileDrag else {
            if NotchBridge.shared.isFileDragActive {
                NotchBridge.shared.isFileDragActive = false
            }
            return false
        }

        guard isPointerNearNotchRegion() else { return true }

        NotchBridge.shared.isFileDragActive = true

        // 只在"岛还收着"时强制切暂存架 —— 岛已经展开时用户是在操作标签，
        // 这时切换会导致点其他标签先闪一下暂存架。
        guard vm.notchState == .closed else { return true }

        vm.open()
        if coordinator.currentView != .shelf {
            coordinator.currentView = .shelf
        }
        return true
    }

    /// 指针是否落在"看得见的岛"上：用收起态的刘海尺寸算，不用窗口边框
    /// （窗口带透明边距和阴影，比实际可见区域大一圈）。
    private func isPointerNearNotchRegion() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            return false
        }
        let width = max(vm.closedNotchSize.width, 120)
        let height = max(vm.closedNotchSize.height, 24)
        let rect = NSRect(x: screen.frame.midX - width / 2,
                          y: screen.frame.maxY - height,
                          width: width,
                          height: height)
        return rect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    /// 悬停检测的主驱动。
    ///
    /// 收起态的悬停以前靠一个 100ms 的 while 循环轮询鼠标坐标（见 git 历史），
    /// 等于每秒唤醒 10 次、每次还读一遍 `.drag` 粘贴板，空闲时也在跟 App Nap
    /// 抢 CPU。现在改成监听指针事件：鼠标不动就没有回调，空闲开销归零。
    ///
    /// 事件监听需要辅助功能权限，拿不到时（`pointerMonitor == nil`）
    /// 退回原来那档频率的轮询，行为不变。
    private func startHoverPolling() {
        hoverPollerTask?.cancel()
        startPointerMonitor()

        hoverPollerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(hoverFallbackIntervalMs))
                if Task.isCancelled { break }
                pollHover()
            }
        }
    }

    /// 事件监听在跑的话，轮询只做兜底（防某次事件漏掉把岛卡在展开态）；
    /// 没权限时收不到事件，只能维持高频轮询。
    private var hoverFallbackIntervalMs: Int {
        pointerMonitor != nil ? 1_000 : 100
    }

    private func startPointerMonitor() {
        guard pointerMonitor == nil, pointerLocalMonitor == nil else { return }

        // 全局：指针在别的 app 上移动 / 拖着别的 app 的文件经过刘海。
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { _ in
            scheduleHoverPoll()
        }

        // 本地：指针落在我们自己的窗口上时全局监听收不到事件。
        pointerLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { event in
            scheduleHoverPoll()
            return event
        }
    }

    /// 鼠标移动事件按硬件刷新率触发（ProMotion 屏上 120Hz）。以前每个事件都
    /// 起一个 Task 跳主线程、再从头读一遍拖拽粘贴板；现在合并成“最多一个
    /// 待执行的 poll”，再按 30Hz 上限截断，并且保证连发结束时最后一个事件
    /// 一定会被处理（尾部补一次），不会有事件被丢掉导致悬停不响应。
    private func scheduleHoverPoll() {
        guard !hoverPollPending else { return }

        let elapsed = CACurrentMediaTime() - lastPointerPollAt
        let wait = max(0, Self.pointerPollMinimumInterval - elapsed)
        hoverPollPending = true

        Task { @MainActor in
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            hoverPollPending = false
            lastPointerPollAt = CACurrentMediaTime()
            pollHover()
        }
    }

    /// 30Hz 对悬停检测足够，再高也看不出差别。
    private static let pointerPollMinimumInterval: CFTimeInterval = 1.0 / 30.0

    private func stopPointerMonitor() {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
        if let pointerLocalMonitor {
            NSEvent.removeMonitor(pointerLocalMonitor)
            self.pointerLocalMonitor = nil
        }
    }

    private func pollHover() {
        // 先判文件拖拽：这里用 NSPasteboard(.drag) 全局检测，不依赖谁先收到
        // dragEntered。只要拖着文件靠近刘海，就把页面写死成暂存架。
        if handleFileDragIfNeeded() { return }

        guard Defaults[.openNotchOnHover],
              !coordinator.isHoverOpenSuppressed,
              !lockScreenManager.isLocked,
              !isSneakPeekVisibleOnCurrentScreen,
              vm.notchState == .closed else { return }

        let inside = isMouseOverClosedNotchHitArea()
        if inside, !isHovering {
            handleHover(true)
        } else if !inside, isHovering {
            finishHoverExit()
        }
    }

    /// 悬停离开的延迟复核：300ms 后指针仍不在刘海命中区，才真正退出。
    private func scheduleHoverExitRecheck() {
        hoverExitRecheckTask?.cancel()
        hoverExitRecheckTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !self.isMouseOverClosedNotchHitArea(),
                      !self.shouldRetainHoverAtScreenTopEdge() else { return }
                self.hoverTask?.cancel()
                self.finishHoverExit()
            }
        }
    }

    private func finishHoverExit() {
        withAnimation(Motion.respected(.bouncy.speed(1.2))) {
            isHovering = false
        }

        if vm.notchState == .open && !shouldPreventAutoClose() {
            vm.close()
        }
    }

    private func shouldRetainHoverAtScreenTopEdge(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }
        guard isHovering || vm.notchState == .open else { return false }
        guard location.y >= screen.frame.maxY - 1.5 else { return false }

        if vm.notchState == .open {
            return isPointInsideNotchWindow(location)
        }
        return isMouseOverClosedNotchHitArea(location)
    }

    private func isMouseOverClosedNotchHitArea(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let closedHeight = vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)
        let closedWidth = max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96)
        let height = closedHeight + 6
        let width = closedWidth + 24
        // Same shift the content is drawn with, so the hit area stays under it.
        let minX = screen.frame.midX - width / 2 + menuBarClearanceOffset
        let minY = screen.frame.maxY - height

        return location.x >= minX && location.x <= minX + width
            && location.y >= minY && location.y <= screen.frame.maxY
    }

    private func isPointInsideNotchWindow(_ point: CGPoint = NSEvent.mouseLocation) -> Bool {
        if let appDelegate = AppDelegate.shared {
            if Defaults[.showOnAllDisplays] {
                return appDelegate.windows.values.contains(where: { frameContainsPointIncludingTopEdge($0.frame, point) })
            }
            if let window = appDelegate.window {
                return frameContainsPointIncludingTopEdge(window.frame, point)
            }
        }

        return NSApp.windows.contains(where: { frameContainsPointIncludingTopEdge($0.frame, point) })
    }

    /// `CGRect.contains` is half-open on max edges; the top pixel needs inclusive maxY.
    private func frameContainsPointIncludingTopEdge(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }
    
    // Helper function to check if any popovers are active
    private func hasAnyActivePopovers() -> Bool {
        vm.isMediaOutputPopoverActive
    }

    private func shouldPreventAutoClose() -> Bool {
        // Dragging a shelf item out necessarily takes the cursor off the notch.
        // Without this, the hover-exit timer closes the panel mid-drag, tearing
        // down the NSView that is acting as the drag source and cancelling the
        // session — an independent second cause of "drag-out doesn't work".
        coordinator.firstLaunch || hasAnyActivePopovers() || vm.isAutoCloseSuppressed || shelfState.isDraggingOutItem || ClipboardManager.shared.isDraggingItem || SharingStateManager.shared.preventNotchClose
    }
    
    // Helper to prevent rapid haptic feedback
    private func triggerHapticIfAllowed() {
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 { // Minimum 300ms between haptics
            haptics.toggle()
            lastHapticTime = now
        }
    }
    
    // Estimate the height required for minimalistic overrides (notably web content) and clamp it to the notch bounds.
    
    // MARK: - Gesture Handling
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: true, translation: translation, phase: phase)
    }
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: false, translation: translation, phase: phase)
    }

    private func handleScrollGesture(isDownward: Bool, translation: CGFloat, phase: NSEvent.Phase) {
        let reverse = Defaults[.reverseScrollGestures]
        let shouldOpen = isDownward ? !reverse : reverse

        if shouldOpen {
            handleOpenScrollGesture(translation: translation, phase: phase)
        } else {
            guard Defaults[.closeGestureEnabled] else { return }
            handleCloseScrollGesture(translation: translation, phase: phase)
        }
    }

    private func handleOpenScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        withAnimation(Motion.respected(.smooth)) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if phase == .ended {
            withAnimation(Motion.respected(.smooth)) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
            withAnimation(Motion.respected(.smooth)) {
                gestureProgress = .zero
            }
            openNotch()
        }
    }

    private func handleCloseScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open, !vm.isScrollGestureActive else { return }

        withAnimation(Motion.respected(.smooth)) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(Motion.respected(.smooth)) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(Motion.respected(.smooth)) {
                gestureProgress = .zero
                isHovering = false
            }
            vm.close()

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
        }
    }

    private func shouldFixSizeForSneakPeek() -> Bool {
        guard isSneakPeekVisibleOnCurrentScreen else { return false }
        let style = resolvedSneakPeekStyle()
        
        // Original logic for other types
        let isMusicSneak = coordinator.sneakPeek.type == .music && vm.notchState == .closed && !vm.hideOnClosed && style == .standard
        let isOtherSneak = coordinator.sneakPeek.type != .music && vm.notchState == .closed

        return isMusicSneak || isOtherSneak
    }

    private func resolvedSneakPeekStyle() -> SneakPeekStyle {
        return coordinator.sneakPeek.styleOverride ?? Defaults[.sneakPeekStyles]
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}
