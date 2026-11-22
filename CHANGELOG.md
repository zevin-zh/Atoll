# Changelog

All notable changes to Z-island will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-22

Z-island 是从 Atoll 精简出来的个人自用版本：只留刘海上的文件暂存、剪贴板和几组 HUD。

### 刘海面板
- 鼠标悬停展开黑岛，岛内提供文件暂存架与剪贴板两个页面
- 两套布局（默认 / 简约），在菜单栏下拉里切换；简约布局把剪贴板做成岛内独立页

### 文件暂存架
- 把文件拖到刘海上自动展开并接收，也可以点开暂存架手动添加
- 文件以 26pt 卡片网格排列，隔空投送入口为 60pt 窄条
- 每项右键菜单：打开、打开方式（含默认应用）、在访达中显示、快速查看、共享、图像操作（移除背景 / 转换图像 / 存储为 PDF）、压缩、重命名、拷贝、拷贝路径、移除

### 剪贴板历史
- 文本、图片、文件三类条目，卡片可直接拖出到访达或其他 app
- 随 app 启动开始监控，可一键清空历史

### HUD
- 音量、亮度、键盘背光、AirPods 聆听模式、大写锁定，随系统状态在岛内内联显示

### 菜单栏
- 布局切换、开机自启（按系统真实状态显示，待系统允许时给出提示）、一键授权全部权限、显示/隐藏菜单栏图标、检查更新、重启、退出
- 菜单栏图标按 18pt 单独绘制，与 app 图标同一套设计语言

### 自动更新
- Sparkle 自建 appcast（仓库 Updates/appcast.xml，经 raw 地址分发），每日自动检查，也可手动「检查更新…」

### 相对上游 Atoll 移除的功能
- 音乐播放与歌词、锁屏面板、日历、计时器、提醒、专注模式、录屏与隐私指示、电池活动、下载监控、网络 HUD、插件（Extensions）宿主、设置窗口

### 分发
- ad-hoc 签名，不需要 Apple 开发者账号；首次打开需右键 → 打开，或 `xattr -dr com.apple.quarantine /Applications/Z-island.app`


## [2.3.3] - 2026-07-24

### Added

### Changed

### Fixed
- Fixed an issue where `BluetoothHUDAnimations` (.mov files) were missing in release builds.
- Improved the GitHub Actions release workflow to use a monotonic build number allocator and automated patch versioning for stable releases.
- Fixed Cursor quota parsing and display to show the current Cursor Models and Other Models billing buckets with readable long reset durations.
- Fixed files dropped onto the Shelf silently disappearing on macOS 26 (Tahoe) by storing plain bookmarks instead of security-scoped ones, which a non-sandboxed app cannot create (#646).
- Fixed the AirPods pause gesture opening Siri instead of pausing Spotify: the real-time waveform no longer process-taps Spotify while a Bluetooth output route is active, and the tap is rebuilt whenever the output route changes.
- Fixed Noise Cancellation, Adaptive Audio, and Conversation Awareness labels being clipped behind the notch in the AirPods listening-mode HUD; every mode is now trailing-aligned and scales down instead of scrolling.
- Fix crash when Apple Notes sync encounters duplicate remote note IDs
- Stopped sending the track title and artist to LRCLIB on every track change while lyrics are switched off; the setting now gates the request, not just the placeholder text (#694).
- Fixed the Shelf freezing for seconds on every drop, and dragging items out delivering the file name as plain text instead of the file itself. Four call sites bridged to `@MainActor` members of `ShelfItem` with a `Task.detached` plus `DispatchSemaphore.wait`, which deadlocks by construction when called from the main actor and always burned its full 5-second timeout: the deduplication pass in `add()` paid that cost once per existing *and* incoming item, and `createPasteboardItem` timed out to a `nil` URL and fell through to writing plain text. Resolved paths are now cached on the item at drop time (and backfilled off the main actor for items persisted earlier), so deduplication, drag-out, and the context menu need no main-actor disk I/O (#682).
- Fixed Open, Open With, Show in Finder, Quick Look, Compress, Copy Path, and the image actions all missing from the Shelf file context menu, caused by `ShelfItem.fileURL` returning a hard-coded `nil` for files (#682).
- Fixed the notch auto-closing in the middle of a drag and cancelling the session: dragging an item out necessarily takes the cursor off the pointer, which tore down the view acting as the drag source (#682).
- Fixed an issue where scrolling a long note inside the Dynamic Island returned the view to the home view instead of scrolling the note. (`#636`)
- Fixed Dynamic Island window pinning so it stays anchored while switching macOS Spaces.
- Fixed Atoll being terminated by macOS when starting a voice recording in the Screen Assistant: the app now declares a microphone usage description, which it was missing entirely.
- Closed the extension RPC port to the local network. It was documented as listening on localhost but bound the wildcard address, so anything on the same Wi-Fi could reach port 9020 and drive the extension API — a client identifies itself simply by stating a bundle identifier. It now binds the loopback address of each family, and any connection from elsewhere is refused before it can send anything.
- Stopped the Bluetooth battery refresh from stalling the interface. It ran `system_profiler` and `pmset` on the main thread — about 200 ms each time — at launch and again on every connect, disconnect and refresh, four times in the first twenty seconds of a session here. Those two now run in the background, and the `system_profiler` reading is shared for 30 seconds instead of being taken separately for battery levels and for each device's model lookup, so a connect no longer spawns it twice. Battery levels are unchanged; on a cold start the percentage can arrive a moment after the device does, which the existing brief wait before showing the connection already covers.
- Fixed Notch expansion FPS stutter. Music and Timer managers now cache `NSHostingView` fitting sizes and reuse them for hover-only updates. When the panel size is unchanged, the window moves with `setFrameOrigin` instead of `setFrame`; `FlyoutFrameCalculator.swift` centralizes the flyout placement calculation (#741).
- Fixed Canvas desync during Notch transitions. Static artwork is rendered by SwiftUI, while Spotify Canvas uses an `AVPlayerLayer` hosted in an `NSViewRepresentable`. During close, the video layer implicitly animated its own frame in a separate Core Animation transaction, creating a second, slower slide-out that conflicted with SwiftUI’s transition (#741).

- Fixed the clipboard history shortcut being registered as Cmd+Shift+C while Settings documented Cmd+Shift+V ("similar to Windows+V on PC"). The default is now Cmd+Shift+V, and a one-time migration moves persisted Cmd+Shift+C values, since `KeyboardShortcuts` persists a default on first launch and would otherwise keep the old key forever, and a stored value does not record whether it came from that default or from a deliberate Cmd+Shift+C choice. Every other custom shortcut is left alone.

### Removed

## [2.3.2] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.1] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.0] - 2026-07-20

### Added
- **Lock Screen & Live Activities**: Full support for Lock Screen widgets, Live Activities, and expanding lock screen music players with flip animations.
- **Screen Assistant (AI)**: Introducing Screen Assistant with snipping capabilities and Gemini API integration.
- **Advanced System HUDs**: Dynamic polling HUDs for Volume (mute/unmute), Brightness, Bluetooth, and Privacy Access Indicators.
- **Clipboard Manager**: New floating clipboard manager panel with customizable settings and quick access.
- **System Stats Panel**: Real-time tracking of CPU usage, Memory, Disk Read/Write, and Network usage with circular progress graphs.
- **Custom Timer**: Dedicated Timer UI with custom timer capabilities.
- **Multi-channel Updates**: Switch seamlessly between Nightly, Alpha, Beta, and Stable update channels directly from Settings.
- **Automated CI/CD**: Full automated release pipeline via GitHub Actions using Sparkle.

### Changed
- **UI & Aesthetics**: Major overhaul to support a new Minimalistic UI option, as well as a Frutiger Aero aesthetic option.
- **Onboarding & Settings**: Revamped the onboarding experience and Settings window layout for a cleaner, native macOS feel.
- **Media Player**: Refined NowPlaying detection, expanded the Lock Screen music player, and smoothed out slider behavior.
- **Performance**: Disabled `OSDUIHelper` polling in favor of event-driven system HUD monitoring to drastically reduce CPU footprint.

### Fixed
- Fixed timeline reset and playback jumping issues in the Media Player.
- Fixed jittering animations on brightness and volume HUDs.
- Fixed corner radius clipping and window alignment bugs across multiple popup panels.
- Fixed double conversion network errors and memory usage spikes in the System Stats panel.
- Fixed lock screen GIF tracking via Git LFS.

### ❤️ Special Thanks to Our Contributors
A massive shoutout to everyone who contributed to this milestone release:
Hariharan Mudaliar, Jis G Jacob, Felipe Giacomini Cocco, delli, Federico Imberti, Dan Querido, Soham Sharma, 杨锟, DanFQ, Amir Zarrinkafsh, HerbJul, StellarSea, XiNian-dada, AkhilKonduru1, createthisnl, fatih ozdil, Santiago Quihui, Venkatesh, A-Akhil, Alex, JoelVR2k, Ninzorn, SSylvain1989, landuoduo, and dozens of others!

## [2.2.0] - 2026-05-30
### Added
- Initial release on the new update pipeline
