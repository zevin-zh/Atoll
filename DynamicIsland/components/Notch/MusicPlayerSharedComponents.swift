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

import Combine
import Defaults
import SwiftUI
import AppKit
import AVFoundation

// MARK: - Music Player Components

// MARK: - Main View

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    let isLiveStream: Bool
    var onValueChange: (Double) -> Void
    var labelLayout: TimeLabelLayout = .stacked
    var trailingLabel: TrailingLabel = .duration
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    /// When set, bypasses Defaults[.sliderColor] (used by lock screen appearance).
    var tintOverride: Color? = nil
    /// Greys the track out until it is reached for, the way Apple's transport
    /// sliders do. Opt-in: the notch's own slider is meant to carry the album
    /// colour at rest.
    var desaturatesWhenIdle: Bool = false

    enum TimeLabelLayout {
        case stacked
        case inline
    }

    enum TrailingLabel {
        case duration
        case remaining
    }

    var body: some View {
        Group {
            if isLiveStream {
                liveStreamView
            } else {
                switch labelLayout {
                case .stacked:
                    stackedContent
                case .inline:
                    inlineContent
                }
            }
        }
        .onAppear {
            guard !isLiveStream else { return }
            guard !dragging else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition())
        }
        .onChange(of: currentDate) { newDate in
            guard !isLiveStream else { return }
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition(at: newDate))
        }
        .onChange(of: isPlaying) { _, playing in
            // Snap slider to the exact position when music pauses so
            // the in-flight animation doesn't coast past the true value.
            if !playing {
                sliderValue = MusicManager.shared.estimatedPlaybackPosition()
            }
        }
        .onChange(of: isLiveStream) { isLive in
            if isLive {
                sliderValue = 0
            }
        }
    }

    private func setSliderValueWithoutAnimation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sliderValue = value
        }
    }

    private var stackedContent: some View {
        VStack(spacing: 6) {
            sliderCore
                .frame(height: sliderFrameHeight)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.system(size: 11, weight: .medium, design: .default).monospacedDigit())
        }
    }

    private var inlineContent: some View {
        HStack(spacing: 6) {
            Text(timeString(from: sliderValue))
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 36, alignment: .leading)

            sliderCore
                .frame(height: sliderFrameHeight)
                .frame(maxWidth: .infinity)

            Text(trailingTimeText)
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 42, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var liveStreamView: some View {
        switch labelLayout {
        case .stacked:
            LiveStreamProgressIndicator(tint: sliderTint)
                .frame(maxWidth: .infinity)
                .frame(height: sliderFrameHeight)
                
        case .inline:
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: 36)
                LiveStreamProgressIndicator(tint: sliderTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: sliderFrameHeight)

                Spacer()
                    .frame(width: 42)
            }
        }
    }

    @ViewBuilder
    private var sliderCore: some View {
        if hasUsableDuration {
            CustomSlider(
                value: $sliderValue,
                range: 0 ... duration,
                color: sliderTint,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange,
                restingTrackHeight: restingTrackHeight,
                draggingTrackHeight: draggingTrackHeight,
                desaturatesWhenIdle: desaturatesWhenIdle
            )
        } else {
            // Non-interactive fallback matching CustomSlider's idle appearance:
            // gray track + colored fill at current estimated position. No seeking
            // allowed until hasUsableDuration becomes true.
            // Use estimated playback position and a surrogate duration so the
            // fill renders meaningfully even before the real duration arrives.
            let estimatedPosition: Double = {
                guard isPlaying else { return min(elapsedTime, duration) }
                let timeDifference = currentDate.timeIntervalSince(timestampDate)
                let estimated = elapsedTime + (timeDifference * playbackRate)
                return min(max(0, estimated), duration)
            }()
            let surrogateDuration = max(1, estimatedPosition * 2, elapsedTime * 2)
            let progress = surrogateDuration > 0 ? min(max(estimatedPosition / surrogateDuration, 0), 1) : 0
            GeometryReader { geometry in
                let width = geometry.size.width
                let trackHeight = restingTrackHeight
                let filledWidth = max(1, width) * progress
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                        .transaction { $0.disablesAnimations = true }
                    Rectangle()
                        .fill(sliderTint)
                        .frame(width: filledWidth, height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                        .transaction { $0.disablesAnimations = true }
                }
            }
            .frame(height: restingTrackHeight)
        }
    }

    private var sliderTint: Color {
        if let tintOverride {
            return tintOverride
        }
        switch Defaults[.sliderColor] {
        case .albumArt:
            return Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }

    private var timeLabelColor: Color {
        if let tintOverride {
            return tintOverride
        }
        return Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    /// Whether the reported duration is one a track could actually have.
    ///
    /// Senders do not always report a usable one — a live stream has none to
    /// give, and some hand back a sentinel or an epoch timestamp instead. The
    /// remaining-time label subtracts the position from it and formats the
    /// result as hours, so an epoch came out on screen as `-1732919508:00:54`.
    /// A day is well past any track and well short of those.
    private var hasUsableDuration: Bool {
        duration.isFinite && duration > 0 && duration <= 24 * 60 * 60
    }

    /// Shown in place of a time there is no sensible value for, rather than a
    /// formatted impossibility.
    private static let unknownTime = "--:--"

    private var trailingTimeText: String {
        guard hasUsableDuration else { return Self.unknownTime }

        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            // A position that is not a position cannot be subtracted from
            // anything, and a negative one would inflate what is left rather
            // than reduce it.
            guard sliderValue.isFinite, sliderValue >= 0 else { return Self.unknownTime }

            let remaining = timeString(from: max(duration - sliderValue, 0))
            // The minus belongs to a time, not to the absence of one: prefixing
            // it unconditionally turned --:-- into ---:--.
            return remaining == Self.unknownTime ? remaining : "-" + remaining
        }
    }

    private var inlineLabelFont: Font {
        .system(size: 11, weight: .medium, design: .default).monospacedDigit()
    }

    private var sliderFrameHeight: CGFloat {
        max(restingTrackHeight, draggingTrackHeight)
    }

    func timeString(from seconds: Double) -> String {
        // Int(_:) traps on a value too large to represent, and NaN has no
        // meaning here either; neither belongs on screen as a time.
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else {
            return Self.unknownTime
        }

        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }

}


struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var thumbSize: CGFloat = 12
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    /// See `MusicSliderView.desaturatesWhenIdle`.
    var desaturatesWhenIdle: Bool = false
    
    @State private var isHovering: Bool = false

    private var isEngaged: Bool { dragging || isHovering }

    private var trackSaturation: Double {
        desaturatesWhenIdle && !isEngaged ? 0 : 1
    }

    private var trackOpacity: Double {
        guard desaturatesWhenIdle else { return 1 }
        return isEngaged ? 1 : 0.82
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackHeight = CGFloat(dragging ? draggingTrackHeight : restingTrackHeight)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * max(1, width)
            
            ZStack(alignment: .bottomLeading) {
                // Background track
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: trackHeight)
                    .cornerRadius(trackHeight / 2)
                    .transaction { $0.disablesAnimations = true }

                // Filled track
                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: trackHeight)
                    .cornerRadius(trackHeight / 2)
                    .transaction { $0.disablesAnimations = true }
            }
            // The track swells from its middle, so it grows into the space
            // above and below equally instead of climbing off the baseline --
            // which is also what leaves it level with the times beside it.
            .frame(
                height: max(restingTrackHeight, draggingTrackHeight),
                alignment: .center
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .saturation(trackSaturation)
            // Kept well above the volume bar's resting brightness: a seek bar
            // that fades as far as that one reads as disabled rather than idle.
            .opacity(trackOpacity)
            .animation(.easeOut(duration: 0.2), value: trackSaturation)
            .animation(.easeOut(duration: 0.2), value: trackOpacity)
            .animation(.bouncy.speed(1.4), value: dragging)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
    }
}

final class MediaOutputVolumeViewModel: ObservableObject {
    @Published var level: Float
    @Published var isMuted: Bool

    private let controller: SystemVolumeController
    private var cancellables: Set<AnyCancellable> = []

    init(controller: SystemVolumeController = .shared) {
        self.controller = controller
        controller.start()
        level = controller.currentVolume
        isMuted = controller.isMuted

        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let value = notification.userInfo?["value"] as? Float,
                      let muted = notification.userInfo?["muted"] as? Bool else { return }
                self.level = value
                self.isMuted = muted
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemAudioRouteDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromController()
            }
            .store(in: &cancellables)
    }

    /// How long the volume HUD stays suppressed after a change made from one of
    /// our own controls. Refreshed on every change, so a drag holds it off until
    /// shortly after the last movement.
    private static let ownControlHUDSuppression: TimeInterval = 1.5

    func setVolume(_ value: Float) {
        // The user is already looking at a volume control. Letting the change
        // raise the notch's volume HUD puts a second slider on screen and swaps
        // out the content this one is anchored to, tearing the popover down
        // mid-drag -- which is why the slider could not be dragged at all.
        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        level = value
        if value > 0 {
            isMuted = false
        }
        controller.setVolume(value)
    }

    func toggleMute() {
        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        isMuted.toggle()
        controller.toggleMute()
    }

    private func syncFromController() {
        level = controller.currentVolume
        isMuted = controller.isMuted
    }
}
