import AppKit

/// 菜单栏图标：与 app 图标同源的 18pt 版本。
/// 由 `scripts/generate_app_icon.swift` 按小尺寸单独重绘（不是把 1024 主图缩小），
/// 生成到 Assets.xcassets/MenuBarIcon.imageset。
enum MenuBarGlyph {
    static let image: NSImage = {
        // 资产目录里的专用小图：18pt（1x/2x）
        if let glyph = NSImage(named: "MenuBarIcon") {
            glyph.size = NSSize(width: 18, height: 18)
            return glyph
        }

        // 兜底：没有资产时退回到 app 图标本身，按目标尺寸重绘
        let size = NSSize(width: 18, height: 18)
        let source = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSRunningApplication.current.icon

        guard let icon = source else { return NSImage(size: size) }

        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: icon.size),
                  operation: .copy, fraction: 1.0)
        output.unlockFocus()
        return output
    }()
}
