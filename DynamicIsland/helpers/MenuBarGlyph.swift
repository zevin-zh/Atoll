import AppKit

/// 菜单栏图标：直接用 app 图标本身（缩小后保留配色），与应用图标一致。
enum MenuBarGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)

        // 优先读 bundle 里的 app 图标，取不到就退回系统 AppIcon 名称。
        var source: NSImage? = {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                return NSImage(contentsOf: url)
            }
            return NSImage(named: NSImage.applicationIconName)
                ?? NSImage(named: "AppIcon")
        }()

        if source == nil {
            source = NSRunningApplication.current.icon
        }

        guard let icon = source else {
            return NSImage(size: size)
        }

        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: icon.size),
            operation: .copy,
            fraction: 1.0
        )
        output.unlockFocus()
        return output
    }()
}
