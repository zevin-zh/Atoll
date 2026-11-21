import AppKit

/// 菜单栏图标：手绘「刘海岛」剪影（平顶、圆底），template image 自动适配深浅色。
enum MenuBarGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let width: CGFloat = 14
        let height: CGFloat = 12
        let x = (size.width - width) / 2
        let top = size.height - 1.5
        let bottom = top - height
        let radius: CGFloat = 4

        let path = NSBezierPath()
        // 平顶（贴着屏幕顶边）
        path.move(to: NSPoint(x: x, y: top))
        path.line(to: NSPoint(x: x + width, y: top))
        // 右侧边下到底部圆角
        path.line(to: NSPoint(x: x + width, y: bottom + radius))
        path.appendArc(
            withCenter: NSPoint(x: x + width - radius, y: bottom + radius),
            radius: radius, startAngle: 0, endAngle: 180, clockwise: true
        )
        // 左侧边回到顶部
        path.line(to: NSPoint(x: x, y: top))
        path.close()

        NSColor.black.setFill()
        path.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
