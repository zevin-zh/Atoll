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
import KeyboardShortcuts
import Lottie
import Foundation

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

struct CustomAppIcon: Codable, Hashable, Equatable, Defaults.Serializable, Identifiable {
    let id: UUID
    var name: String
    var fileName: String
    var addedAt: Date

    init(id: UUID = UUID(), name: String, fileName: String, addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.addedAt = addedAt
    }

    static let iconDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("AppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var fileURL: URL {
        Self.iconDirectory.appendingPathComponent(fileName)
    }
}

// MARK: - Custom Idle Animation Models
struct CustomIdleAnimation: Codable, Hashable, Equatable, Defaults.Serializable, Identifiable {
    let id: UUID
    var name: String
    var source: AnimationSource
    var speed: CGFloat = 1.0
    var isBuiltIn: Bool = false  // Track if it's bundled vs user-added
    
    init(id: UUID = UUID(), name: String, source: AnimationSource, speed: CGFloat = 1.0, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.source = source
        self.speed = speed
        self.isBuiltIn = isBuiltIn
    }
    
    /// Get the effective transform config (override or default)
    func getTransformConfig() -> AnimationTransformConfig {
        let override = Defaults[.animationTransformOverrides][id.uuidString]
        if let override = override {
            print("📋 [CustomIdleAnimation] Found override for '\(name)': \(override)")
        } else {
            print("📋 [CustomIdleAnimation] No override for '\(name)', using default")
        }
        return override ?? .default
    }
}

struct AnimationTransformConfig: Codable, Hashable, Equatable, Defaults.Serializable {
    var scale: CGFloat = 1.0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var cropWidth: CGFloat = 30
    var cropHeight: CGFloat = 20
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1.0
    var paddingBottom: CGFloat = 0  // Allow adjustment to fill notch from bottom
    var expandWithAnimation: Bool = false  // Whether notch should expand horizontally with animation
    var loopMode: AnimationLoopMode = .loop  // Loop mode for animation
    
    static let `default` = AnimationTransformConfig()
}

enum AnimationLoopMode: String, Codable, CaseIterable {
    case loop = "Loop"
    case playOnce = "Play Once"
    case autoReverse = "Auto Reverse"
    
    var lottieLoopMode: LottieLoopMode {
        switch self {
        case .loop: return .loop
        case .playOnce: return .playOnce
        case .autoReverse: return .autoReverse
        }
    }
}

enum AnimationSource: Codable, Hashable, Equatable {
    case lottieFile(URL)        // Local file (in app support or bundle)
    case lottieURL(URL)         // Remote URL
    
    var displayType: String {
        switch self {
        case .lottieFile: return "Local"
        case .lottieURL: return "Remote"
        }
    }
}

// MARK: - Extension Authorization Models

enum ExtensionPermissionScope: String, CaseIterable, Codable, Defaults.Serializable {
    case liveActivities
    case lockScreenWidgets
    case notchExperiences
    case fileSharing

    var displayName: String {
        switch self {
        case .liveActivities: return String(localized: "Live Activities")
        case .lockScreenWidgets: return String(localized: "Lock Screen Widgets")
        case .notchExperiences: return String(localized: "Notch Experiences")
        case .fileSharing: return String(localized: "File Sharing")
        }
    }
}

enum ExtensionAuthorizationStatus: String, CaseIterable, Codable, Defaults.Serializable {
    case pending
    case authorized
    case denied
    case revoked

    var isActive: Bool {
        switch self {
        case .authorized: return true
        case .pending, .denied, .revoked: return false
        }
    }
}

struct ExtensionAuthorizationEntry: Codable, Defaults.Serializable, Identifiable, Hashable {
    let bundleIdentifier: String
    var appName: String
    var status: ExtensionAuthorizationStatus
    var allowedScopes: Set<ExtensionPermissionScope>
    var requestedAt: Date
    var grantedAt: Date?
    var lastActivityAt: Date?
    var lastDeniedReason: String?
    var notes: String?

    var id: String { bundleIdentifier }

    init(
        bundleIdentifier: String,
        appName: String,
        status: ExtensionAuthorizationStatus,
        allowedScopes: Set<ExtensionPermissionScope> = Set(ExtensionPermissionScope.allCases),
        requestedAt: Date = .now,
        grantedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        lastDeniedReason: String? = nil,
        notes: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.status = status
        self.allowedScopes = allowedScopes
        self.requestedAt = requestedAt
        self.grantedAt = grantedAt
        self.lastActivityAt = lastActivityAt
        self.lastDeniedReason = lastDeniedReason
        self.notes = notes
    }

    var isAuthorized: Bool { status.isActive }
}

struct ExtensionRateLimitRecord: Codable, Defaults.Serializable, Hashable, Identifiable {
    let bundleIdentifier: String
    var activityTimestamps: [Date]
    var widgetTimestamps: [Date]
    var notchExperienceTimestamps: [Date]

    var id: String { bundleIdentifier }

    init(
        bundleIdentifier: String,
        activityTimestamps: [Date] = [],
        widgetTimestamps: [Date] = [],
        notchExperienceTimestamps: [Date] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.activityTimestamps = activityTimestamps
        self.widgetTimestamps = widgetTimestamps
        self.notchExperienceTimestamps = notchExperienceTimestamps
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case activityTimestamps
        case widgetTimestamps
        case notchExperienceTimestamps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        activityTimestamps = try container.decodeIfPresent([Date].self, forKey: .activityTimestamps) ?? []
        widgetTimestamps = try container.decodeIfPresent([Date].self, forKey: .widgetTimestamps) ?? []
        notchExperienceTimestamps = try container.decodeIfPresent([Date].self, forKey: .notchExperienceTimestamps) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(activityTimestamps, forKey: .activityTimestamps)
        try container.encode(widgetTimestamps, forKey: .widgetTimestamps)
        try container.encode(notchExperienceTimestamps, forKey: .notchExperienceTimestamps)
    }
}

enum ClipboardDisplayMode: String, CaseIterable, Codable, Defaults.Serializable {
    case popover = "popover"     // Traditional popover attached to button
    case panel = "panel"         // Floating panel near notch
    case separateTab = "separateTab" // Separate tab in Dynamic Island (merges with Notes)
    case notchTab = "notchTab"   // Dedicated clipboard tab inside the notch (draggable items)

    var displayName: String {
        switch self {
        case .popover: return String(localized: "Popover")
        case .panel: return String(localized: "Panel")
        case .separateTab: return String(localized: "Separate Tab")
        case .notchTab: return String(localized: "Notch Tab")
        }
    }
    
    var description: String {
        switch self {
        case .popover: return "Shows clipboard as a dropdown attached to the clipboard button"
        case .panel: return "Shows clipboard in a floating panel near the notch"
        case .separateTab: return "Shows copied items in a separate tab within the Dynamic Island (merges with Notes if enabled)"
        case .notchTab: return "Shows copied items in a dedicated clipboard tab inside the notch; drag items straight out to other apps"
        }
    }
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
/// How the line being sung is picked out from the rest.

enum LyricHighlightStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case sweep = "Sweep"
    case gradient = "Gradient"
    case solid = "Solid"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .sweep: return String(localized: "Sweep")
        case .gradient: return String(localized: "Gradient")
        case .solid: return String(localized: "Solid")
        }
    }

    var explanation: String {
        switch self {
        case .sweep:
            return String(localized: "The highlight travels across the line word by word, in reading order.")
        case .gradient:
            return String(localized: "The current line is lit by one fixed gradient that does not move, the way lyrics were marked before the sweep.")
        case .solid:
            return String(localized: "The current line is lit in one flat colour, with nothing crossing it.")
        }
    }
}

enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case youtubeMusic = "Youtube Music"
    case amazonMusic = "Amazon Music"
    case tidal = "TIDAL"
    case cider = "Cider"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .nowPlaying: return String(localized: "Now Playing")
        case .youtubeMusic: return String(localized: "Youtube Music")
        case .amazonMusic: return String(localized: "Amazon Music")
        case .tidal: return String(localized: "TIDAL")
        case .cider: return String(localized: "Cider")
        }
    }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .standard: return String(localized: "Default")
        case .inline: return String(localized: "Inline")
        }
    }
}

enum LogLevel: Int, CaseIterable, Identifiable, Defaults.Serializable {
    case none = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    
    var id: Int { self.rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "No Logging"
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }
}

enum CapsLockIndicatorTintMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case green
    case accent
    case white

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .green:
            return String(localized: "Green")
        case .accent:
            return String(localized: "Accent")
        case .white:
            return String(localized: "White")
        }
    }

    var color: Color {
        switch self {
        case .green:
            return .green
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }
}

enum ProgressBarStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case hierarchical = "Hierarchical"
    case gradient = "Gradient"
    case segmented = "Segmented"
    
    var id: String { self.rawValue }
}

enum MusicSkipBehavior: String, CaseIterable, Identifiable, Defaults.Serializable {
    case track
    case tenSecond

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .track:
            return String(localized: "Track Skip")
        case .tenSecond:
            return String(localized: "±10 Seconds")
        }
    }

    var description: String {
        switch self {
        case .track:
            return String(localized: "Standard previous/next track controls")
        case .tenSecond:
            return String(localized: "Skip forward or backward by ten seconds")
        }
    }
}

enum SiriResponsivenessMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automatic
    case highPerformance
    case balanced
    case powerSaver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .highPerformance: return String(localized: "High Performance")
        case .balanced: return String(localized: "Balanced")
        case .powerSaver: return String(localized: "Power Saver")
        }
    }

    var description: String {
        switch self {
        case .automatic: return String(localized: "Adapts based on power source and battery level.")
        case .highPerformance: return String(localized: "Ultra-fast detection (30Hz) for near-instant hiding.")
        case .balanced: return String(localized: "Standard detection (16Hz) for smooth responsiveness.")
        case .powerSaver: return String(localized: "Slower detection (4Hz) to maximize battery life.")
        }
    }
}

// AI Model types for screen assistant

enum ColorExtractionMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case legacy, vibrant
    var id: Self { self }
}

enum LockScreenLiveActivityIconStyle: String, Defaults.Serializable {
    case lock
    case fingerprint
    case both

    var showsLock: Bool { self == .lock || self == .both }
    var showsFingerprint: Bool { self == .fingerprint || self == .both }
}

extension Defaults.Keys {
        // MARK: General
    static let updateChannel = Key<UpdateChannel>("updateChannel", default: .stable)
    static let logLevel = Key<LogLevel>("logLevel", default: .none)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let hideDynamicIslandFromScreenCapture = Key<Bool>("hideDynamicIslandFromScreenCapture", default: false)
    
        // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
	static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let externalDisplayStyle = Key<ExternalDisplayStyle>(
        "externalDisplayStyle",
        default: .notch
    )
    static let hideNonNotchUntilHover = Key<Bool>("hideNonNotchUntilHover", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let openNotchWidth = Key<CGFloat>("openNotchWidth", default: 640)
    static let closedNotchWidth = Key<CGFloat>("closedNotchWidth", default: 150)
    static let customizePhysicalNotchWidth = Key<Bool>("customizePhysicalNotchWidth", default: false)
        //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    
        // MARK: Appearance
        //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let selectedCameraID = Key<String>("selectedCameraID", default: "")
    static let accentColor = Key<Color>("accentColor", default: Color.blue)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)
    static let useModernCloseAnimation = Key<Bool>("useModernCloseAnimation", default: true)
    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let customIdleAnimations = Key<[CustomIdleAnimation]>("customIdleAnimations", default: [])
    static let selectedIdleAnimation = Key<CustomIdleAnimation?>("selectedIdleAnimation", default: nil)
    static let animationTransformOverrides = Key<[String: AnimationTransformConfig]>("animationTransformOverrides", default: [:])
    static let colorExtractionMode = Key<ColorExtractionMode>("colorExtractionMode", default: .vibrant)
    static let customAppIcons = Key<[CustomAppIcon]>("customAppIcons", default: [])
    static let selectedAppIconID = Key<String?>("selectedAppIconID", default: nil)
    
        // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    static let reverseScrollGestures = Key<Bool>("reverseScrollGestures", default: false)
    
        // MARK: Media playback
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    /// Whether the lock screen panel keeps a volume slider under the transport
    /// row, rather than leaving volume behind the output button.
    ///
    /// Off by default and named after the setting it copies: iOS puts "Always
    /// Show Volume Control" in Accessibility rather than showing the slider to
    /// everybody, because a Lock Screen that is mostly artwork is the point for
    /// most people and a permanent slider is a preference, not an improvement.
    static let showStandardMediaControls = Key<Bool>("showStandardMediaControls", default: true)
    // Enable lock screen media widget (shows the standalone panel when screen is locked)
    
    
        // MARK: Downloads
    
        // MARK: HUD
    static let inlineHUD = Key<Bool>("inlineHUD", default: true)
    static let progressBarStyle = Key<ProgressBarStyle>("progressBarStyle", default: .hierarchical)
    // Legacy support - keeping for backward compatibility
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showProgressPercentages = Key<Bool>("showProgressPercentages", default: true)
    
        // MARK: Shelf
    static let dynamicShelf = Key<Bool>("dynamicShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
        static let quickShareProvider = Key<String>("quickShareProvider", default: "AirDrop")
        static let localSendSelectedDeviceID = Key<String>("localSendSelectedDeviceID", default: "")
        static let localSendDevicePickerGlassMode = Key<LockScreenGlassCustomizationMode>("localSendDevicePickerGlassMode", default: .standard)
        static let localSendDevicePickerLiquidGlassVariant = Key<LiquidGlassVariant>("localSendDevicePickerLiquidGlassVariant", default: .v11)
        static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
        // Off by default: offering `.move` to another app lets Finder move the
        // original out from under the user when the destination is on the same
        // volume, which reads as data loss.
        static let allowMoveOnDrag = Key<Bool>("allowMoveOnDrag", default: false)
        static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    
        // MARK: Fullscreen Media Detection
    
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Wobble Animation
    
    // MARK: Media Controller

    /// Token for Cider's external-application API, from
    /// Settings > Connectivity > Manage External Application Access in Cider.
    /// Empty is a valid setting: Cider can also run that API with
    /// authentication switched off, and then no header is wanted at all.
    /// Superseded by `CiderTokenStore`, which keeps the token in the Keychain.
    /// Kept only so an existing value can be migrated out of the preferences
    /// plist on first launch; nothing reads it to make a request.
    /// Named `legacy…` so nothing new reaches for it by the old name; the
    /// stored key string is unchanged so existing values still migrate.
    /// A `@available(*, deprecated)` attribute would have been the obvious
    /// alternative, but it fires on `CiderTokenStore` -- the one place that is
    /// supposed to read this -- and a warning at the sanctioned use site is
    /// worse than none.
    // The OAuth token pair lives in the Keychain (see KeychainSpotifyTokenStore);
    // these two keys remain only for the one-time migration of early builds.
    
    // MARK: Bluetooth Audio Devices
    static let showBluetoothDeviceConnections = Key<Bool>("showBluetoothDeviceConnections", default: true)
    static let useColorCodedBatteryDisplay = Key<Bool>("useColorCodedBatteryDisplay", default: true)
    static let useColorCodedVolumeDisplay = Key<Bool>("useColorCodedVolumeDisplay", default: true)
    static let useSmoothColorGradient = Key<Bool>("useSmoothColorGradient", default: true)
    static let useCircularBluetoothBatteryIndicator = Key<Bool>("useCircularBluetoothBatteryIndicator", default: true)
    static let showBluetoothBatteryPercentageText = Key<Bool>("showBluetoothBatteryPercentageText", default: false)
    static let showBluetoothDeviceNameMarquee = Key<Bool>("showBluetoothDeviceNameMarquee", default: false)
    static let useBluetoothHUD3DIcon = Key<Bool>("useBluetoothHUD3DIcon", default: true)
    static let showAirPodsListeningModeChanges = Key<Bool>("showAirPodsListeningModeChanges", default: true)
    
    // MARK: Clipboard Feature
    static let enableClipboardManager = Key<Bool>("enableClipboardManager", default: true)
    static let clipboardHistorySize = Key<Int>("clipboardHistorySize", default: 3)
    /// Whether clipboard history is written to disk and restored on launch.
    /// Off keeps it in memory for the session only — nothing survives a quit.
    /// Defaults to true so existing installs keep the behaviour they have.
    static let persistClipboardHistory = Key<Bool>("persistClipboardHistory", default: true)
    static let clipboardDisplayMode = Key<ClipboardDisplayMode>("clipboardDisplayMode", default: .panel)
    
    // MARK: Third-Party Extensions
    
    // MARK: Keyboard Shortcuts
    static let enableShortcuts = Key<Bool>("enableShortcuts", default: true)
    
    // MARK: System HUD Feature
    static let enableSystemHUD = Key<Bool>("enableSystemHUD", default: true)
    static let enableVolumeHUD = Key<Bool>("enableVolumeHUD", default: true)
    static let enableBrightnessHUD = Key<Bool>("enableBrightnessHUD", default: true)
    static let enableKeyboardBacklightHUD = Key<Bool>("enableKeyboardBacklightHUD", default: true)
    static let playVolumeChangeFeedback = Key<Bool>("playVolumeChangeFeedback", default: false)

    // Step sizes for hardware media keys (percent of full range, 1-25)
    static let volumeStepPercent = Key<Int>("volumeStepPercent", default: 6)
    static let volumeFineStepPercent = Key<Int>("volumeFineStepPercent", default: 2)
    static let brightnessStepPercent = Key<Int>("brightnessStepPercent", default: 6)
    static let brightnessFineStepPercent = Key<Int>("brightnessFineStepPercent", default: 2)
    
    // MARK: Custom OSD Window Feature
    
    // Vertical HUD Customization
    
    // Circular HUD Customization

    // MARK: Third-Party DDC Integration

    // Legacy keys retained for migration/backward compatibility
    
    
    // MARK: Lock Screen Features
    
    // MARK: Caps Lock Indicator
    static let enableCapsLockIndicator = Key<Bool>("enableCapsLockIndicator", default: true)
    static let capsLockIndicatorTintMode = Key<CapsLockIndicatorTintMode>("capsLockIndicatorTintMode", default: .white)
    static let showCapsLockLabel = Key<Bool>("showCapsLockLabel", default: false)
    
    // MARK: ImageService
    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCacheV1", default: false)
    
    // MARK: Minimalistic UI Mode
    static let enableMinimalisticUI = Key<Bool>("enableMinimalisticUI", default: false)
    
}
