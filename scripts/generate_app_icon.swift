#!/usr/bin/env swift
//
//  generate_app_icon.swift
//  Z-island 的 app 图标，全部由代码绘制（CoreGraphics），不依赖任何外部素材。
//
//  用法（在 atoll-src 根目录）：
//    swift scripts/generate_app_icon.swift                 # 出一张预览图到 ./icon-out/
//    swift scripts/generate_app_icon.swift ./somewhere     # 指定预览输出目录
//    swift scripts/generate_app_icon.swift --install       # 写进工程（正式图标 + Dev 图标 + icns）
//
//  设计说明：
//    · 1024 画布，主体是苹果那种连续圆角方形（824 见方，超椭圆近似）
//    · 石墨渐变底 + 1px 颗粒，压住大面积渐变的色带
//    · 一枚冷白玻璃岛：上沿高光、下沿蓝色折射，外部辉光用高斯阴影生成
//    · 只有一件主体，其余留白 —— 小尺寸下也能一眼认出
//

import AppKit
import CoreGraphics

// MARK: - 可调参数

private enum Design {
    static let canvas: CGFloat = 1024
    /// 图标主体（macOS 图标网格：1024 画布内 824 见方，留阴影余量）
    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)

    static let bgTop: UInt32 = 0x24282F
    static let bgMid: UInt32 = 0x14171C
    static let bgBottom: UInt32 = 0x0A0B0E
    static let glow: UInt32 = 0x2F72FF    // 岛外的冷光
    static let rim: UInt32 = 0xBFD2F0     // 方形内沿的银色高光

    /// 岛：中心 x、上边缘 y（从图标顶部算）、宽、高
    static let islandTop: CGFloat = 436
    static let islandWidth: CGFloat = 504
    static let islandHeight: CGFloat = 108
}

// MARK: - 基础工具

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: colors as CFArray, locations: locations)!
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat],
            from: CGPoint, to: CGPoint) {
    ctx.drawLinearGradient(gradient(colors, locs), start: from, end: to, options: [])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat],
            center: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(gradient(colors, locs),
                           startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}

/// 设计稿坐标（y 从图标顶部往下）→ CoreGraphics 坐标
func ty(_ topY: CGFloat) -> CGFloat { Design.canvas - topY }

/// 苹果式的连续圆角方形：超椭圆近似，n=5 时与系统 mask 视觉一致
func squircle(_ rect: CGRect, n: CGFloat = 5, steps: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let e = 2 / n
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * pow(abs(c), e) * (c < 0 ? -1 : 1)
        let y = rect.midY + b * pow(abs(s), e) * (s < 0 ? -1 : 1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

// MARK: - 绘制

func renderIcon() -> NSBitmapImageRep {
    let side = Int(Design.canvas)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let ctx = graphics.cgContext
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: Design.canvas, height: Design.canvas))

    let body = squircle(Design.body)

    // 底座投影（macOS 图标自己在画布上带投影）
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -9), blur: 26, color: hex(0x000000, 0.42))
    ctx.addPath(body)
    ctx.setFillColor(hex(0x101216))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    // 1. 石墨底：顶部略亮，底部近黑
    linear(ctx, [hex(Design.bgTop), hex(Design.bgMid), hex(Design.bgBottom)], [0, 0.45, 1],
           from: CGPoint(x: 0, y: Design.canvas), to: CGPoint(x: 0, y: 0))

    // 2. 柔光只聚在岛附近，不把整块底板染成深蓝
    radial(ctx, [hex(Design.glow, 0.20), hex(Design.glow, 0.06), hex(Design.glow, 0)],
           [0, 0.48, 1],
           center: CGPoint(x: 512, y: ty(Design.islandTop + 40)), radius: 560)

    // 3. 细颗粒：近距离看得出质感，也压掉渐变色带
    var seed: UInt64 = 0x5EED_1A7D_C0DE
    func rnd() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
    let grain = CGMutablePath()
    for _ in 0..<70_000 {
        grain.addRect(CGRect(x: 100 + rnd() * 824, y: 100 + rnd() * 824, width: 1, height: 1))
    }
    ctx.saveGState()
    ctx.setAlpha(0.028)
    ctx.addPath(grain)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 4. 暗角
    radial(ctx, [hex(0x000000, 0), hex(0x000000, 0), hex(0x000000, 0.28)], [0, 0.66, 1],
           center: CGPoint(x: 512, y: ty(430)), radius: 760)

    // 5. 方形内沿：上亮下无，像一块有厚度的玻璃
    ctx.saveGState()
    ctx.addPath(body)
    ctx.setLineWidth(2.4)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    linear(ctx, [hex(Design.rim, 0.30), hex(Design.rim, 0.06), hex(Design.rim, 0)],
           [0, 0.38, 0.72],
           from: CGPoint(x: 0, y: Design.canvas), to: CGPoint(x: 0, y: ty(560)))
    ctx.restoreGState()

    // 6. 岛
    let rect = CGRect(x: 512 - Design.islandWidth / 2,
                      y: ty(Design.islandTop) - Design.islandHeight,
                      width: Design.islandWidth, height: Design.islandHeight)
    let island = CGPath(roundedRect: rect,
                        cornerWidth: Design.islandHeight / 2,
                        cornerHeight: Design.islandHeight / 2, transform: nil)

    // 6a. 外部辉光：shadow 本身就是高斯模糊，比堆叠透明层干净
    let haloRect = rect.insetBy(dx: -2, dy: -2)
    let halo = CGPath(roundedRect: haloRect,
                      cornerWidth: haloRect.height / 2, cornerHeight: haloRect.height / 2,
                      transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 64, color: hex(0x2F72FF, 0.55))
    ctx.addPath(halo); ctx.setFillColor(hex(0x2F72FF)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 16, color: hex(0xE8F3FF, 0.55))
    ctx.addPath(halo); ctx.setFillColor(hex(0xF2F8FF)); ctx.fillPath()
    ctx.restoreGState()

    // 6b. 贴地投影：岛浮在石墨面之上
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -9), blur: 22, color: hex(0x000000, 0.45))
    ctx.addPath(island)
    ctx.setFillColor(hex(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    // 6c. 岛面：几乎没有明暗差，只留一点冷调，像一块发光的玻璃
    ctx.saveGState()
    ctx.addPath(island)
    ctx.clip()
    linear(ctx, [hex(0xFFFFFF), hex(0xFCFDFF), hex(0xEEF3FA)], [0, 0.5, 1],
           from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY))
    // 蓝色唇边：光在玻璃下沿折射
    linear(ctx, [hex(0x5B9BFF, 0), hex(0x5B9BFF, 0.30)], [0.78, 1],
           from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY))
    // 上沿一条极细高光
    ctx.saveGState()
    ctx.addPath(island)
    ctx.setLineWidth(2.5)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    linear(ctx, [hex(0xFFFFFF, 0), hex(0xFFFFFF, 0.95), hex(0xFFFFFF, 0)],
           [0.45, 0.62, 0.75],
           from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY))
    ctx.restoreGState()
    ctx.restoreGState()

    // 6d. 极细暗边：浅色背景下也不糊
    ctx.addPath(island)
    ctx.setLineWidth(1.3)
    ctx.setStrokeColor(hex(0x0B0D12, 0.15))
    ctx.strokePath()

    ctx.restoreGState()
    NSGraphicsContext.current = nil
    return rep
}


// MARK: - 菜单栏小图标

/// 菜单栏那枚 18pt 的图标：同款设计，但按小尺寸重新配色和加粗，
/// 不是把 1024 主图缩小（缩小会糊成一团）。
func renderGlyph(px: CGFloat) -> NSBitmapImageRep {
    let side = Int(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let ctx = graphics.cgContext
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))

    let inset = px * 0.09
    let bodyRect = CGRect(x: inset, y: inset, width: px - inset * 2, height: px - inset * 2)
    let body = squircle(bodyRect, steps: 360)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -px * 0.012), blur: px * 0.03,
                  color: hex(0x000000, 0.45))
    ctx.addPath(body)
    ctx.setFillColor(hex(0x14171D))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    linear(ctx, [hex(0x2C323C), hex(0x14171E), hex(0x0B0D11)], [0, 0.45, 1],
           from: CGPoint(x: 0, y: px), to: CGPoint(x: 0, y: 0))

    // 岛：比大图更粗一点，18px 下才站得住
    let w = px * 0.56, h = px * 0.155
    let rect = CGRect(x: (px - w) / 2, y: px * 0.522 - h / 2, width: w, height: h)
    let island = CGPath(roundedRect: rect, cornerWidth: h / 2, cornerHeight: h / 2,
                        transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: px * 0.055, color: hex(0x2F72FF, 0.55))
    ctx.addPath(island)
    ctx.setFillColor(hex(0xBFE0FF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(island)
    ctx.setFillColor(hex(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.current = nil
    return rep
}

// MARK: - 导出

func writeMaster(to path: String) throws {
    let data = renderIcon().representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: path))
}

/// 小尺寸由 1024 主图降采样，比在小画布上重绘更锐利
func scale(_ master: String, to path: String, size: Int) throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = ["-z", "\(size)", "\(size)", master, "--out", path]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { throw NSError(domain: "sips", code: 1) }
}

func run(_ tool: String, _ args: [String]) throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: tool)
    proc.arguments = args
    try proc.run()
    proc.waitUntilExit()
}

let args = Array(CommandLine.arguments.dropFirst())
let install = args.contains("--install")
let outDir = args.first(where: { !$0.hasPrefix("--") }) ?? "./icon-out"

if !install {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let path = "\(outDir)/icon_1024.png"
    try writeMaster(to: path)
    print(path)
    exit(0)
}

let assets = "DynamicIsland/Assets.xcassets"
guard FileManager.default.fileExists(atPath: assets) else {
    print("请在 atoll-src 根目录下执行（找不到 \(assets)）")
    exit(1)
}

let master = NSTemporaryDirectory() + "zisland-icon-master.png"
try? FileManager.default.removeItem(atPath: master)
try writeMaster(to: master)

// 正式图标：资产目录只认一张 1024
let official = "\(assets)/AppIcon.appiconset/icon1024.png"
try? FileManager.default.removeItem(atPath: official)
try FileManager.default.copyItem(atPath: master, toPath: official)

// Debug 配置用的 Dev 图标：补齐全部尺寸
let devSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
try FileManager.default.createDirectory(atPath: "\(assets)/AppIconDev.appiconset",
                                        withIntermediateDirectories: true)
for (name, size) in devSizes {
    try scale(master, to: "\(assets)/AppIconDev.appiconset/\(name)", size: size)
}

// 顺手产一份 .icns，方便在别处直接替换图标
let iconset = NSTemporaryDirectory() + "ZIsland.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try scale(master, to: "\(iconset)/icon_\(s)x\(s).png", size: s)
    try scale(master, to: "\(iconset)/icon_\(s)x\(s)@2x.png", size: s * 2)
}
try FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
try run("/usr/bin/iconutil", ["-c", "icns", iconset, "-o", "build/AppIcon.icns"])
try? FileManager.default.removeItem(atPath: iconset)

// 菜单栏图标：18pt 一套（1x/2x），Design 里的小尺寸重绘版
let menuBarDir = "\(assets)/MenuBarIcon.imageset"
try? FileManager.default.removeItem(atPath: menuBarDir)
try FileManager.default.createDirectory(atPath: menuBarDir, withIntermediateDirectories: true)
for (name, px) in [("glyph_18.png", CGFloat(18)), ("glyph_36.png", CGFloat(36))] {
    let data = renderGlyph(px: px).representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: "\(menuBarDir)/\(name)"))
}
let imagesetJSON = """
{
  "images" : [
    { "filename" : "glyph_18.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "glyph_36.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "original" }
}
"""
try imagesetJSON.write(toFile: "\(menuBarDir)/Contents.json", atomically: true, encoding: .utf8)

print("done: AppIcon.appiconset · AppIconDev.appiconset · MenuBarIcon.imageset · build/AppIcon.icns")
