// 原创矢量构图，生成无透明通道的 iPhone / Watch 图标。
// 仓库根目录执行：swift scripts/generate_app_icons.swift
import AppKit

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSColor(srgbRed: 0.025, green: 0.075, blue: 0.09, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let teal = NSColor(srgbRed: 0.02, green: 0.83, blue: 0.74, alpha: 1)
let muted = NSColor(srgbRed: 0.09, green: 0.23, blue: 0.25, alpha: 1)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
// 表带和表壳；中央进度弧表达剩余额度。
rounded(NSRect(x: 392, y: 124, width: 240, height: 776), 74, muted)
rounded(NSRect(x: 734, y: 530, width: 45, height: 94), 20, teal)
rounded(NSRect(x: 256, y: 250, width: 512, height: 524), 144, teal)
rounded(NSRect(x: 282, y: 276, width: 460, height: 472), 120,
    NSColor(srgbRed: 0.035, green: 0.12, blue: 0.135, alpha: 1))
let ring = NSBezierPath(ovalIn: NSRect(x: 363, y: 363, width: 298, height: 298))
ring.lineWidth = 32
muted.setStroke(); ring.stroke()
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 149,
              startAngle: 90, endAngle: -175, clockwise: true)
arc.lineWidth = 32; arc.lineCapStyle = .round
teal.setStroke(); arc.stroke()
let mark = NSBezierPath()
mark.move(to: NSPoint(x: 457, y: 529)); mark.line(to: NSPoint(x: 502, y: 477))
mark.line(to: NSPoint(x: 569, y: 562))
mark.lineWidth = 27; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
NSColor.white.setStroke(); mark.stroke()
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let png = bitmap.representation(using: .png, properties: [:])!
for target in ["iPhone", "Watch"] {
    let root = URL(fileURLWithPath: "apple/\(target)/Assets.xcassets")
    let icon = root.appendingPathComponent("AppIcon.appiconset")
    try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
    try png.write(to: icon.appendingPathComponent("AppIcon.png"))
    let info: [String: Any] = ["author": "xcode", "version": 1]
    let image: [String: Any] = ["filename": "AppIcon.png", "idiom": "universal",
                               "platform": target == "iPhone" ? "ios" : "watchos", "size": "1024x1024"]
    try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
        .write(to: root.appendingPathComponent("Contents.json"))
    try JSONSerialization.data(withJSONObject: ["images": [image], "info": info], options: [.prettyPrinted, .sortedKeys])
        .write(to: icon.appendingPathComponent("Contents.json"))
}
print("Generated iPhone and Watch AppIcon assets (RGB, 1024 × 1024).")
