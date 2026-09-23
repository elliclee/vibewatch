// 从已确认的图标母版生成 iPhone / Watch 资源，不重新生成设计。
// 仓库根目录执行：swift scripts/generate_app_icons.swift
import AppKit

let source = URL(fileURLWithPath: "design/app-icon-source.png")
guard let image = NSImage(contentsOf: source),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("无法读取 design/app-icon-source.png")
}
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.interpolationQuality = .high
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
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
