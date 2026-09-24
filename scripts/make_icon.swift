import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: make_icon.swift OUTPUT_ICONSET")
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let files: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) throws {
    let canvas = NSSize(width: size, height: size)
    let image = NSImage(size: canvas)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let inset = CGFloat(size) * 0.055
    let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    let radius = CGFloat(size) * 0.22
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.07, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.32, green: 0.10, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.96, green: 0.28, blue: 0.10, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -45)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = CGFloat(size) * 0.045
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(size) * 0.018)
    shadow.set()

    let padRect = NSRect(
        x: CGFloat(size) * 0.18,
        y: CGFloat(size) * 0.27,
        width: CGFloat(size) * 0.64,
        height: CGFloat(size) * 0.42
    )
    let pad = NSBezierPath(roundedRect: padRect, xRadius: CGFloat(size) * 0.15, yRadius: CGFloat(size) * 0.15)
    NSColor.white.setFill()
    pad.fill()
    NSGraphicsContext.restoreGraphicsState()

    let lineWidth = max(1, CGFloat(size) * 0.048)
    let centerX = CGFloat(size) * 0.36
    let centerY = CGFloat(size) * 0.48
    NSColor(calibratedRed: 0.28, green: 0.10, blue: 0.42, alpha: 1).setStroke()
    let horizontal = NSBezierPath()
    horizontal.lineWidth = lineWidth
    horizontal.lineCapStyle = .round
    horizontal.move(to: NSPoint(x: centerX - CGFloat(size) * 0.085, y: centerY))
    horizontal.line(to: NSPoint(x: centerX + CGFloat(size) * 0.085, y: centerY))
    horizontal.stroke()
    let vertical = NSBezierPath()
    vertical.lineWidth = lineWidth
    vertical.lineCapStyle = .round
    vertical.move(to: NSPoint(x: centerX, y: centerY - CGFloat(size) * 0.085))
    vertical.line(to: NSPoint(x: centerX, y: centerY + CGFloat(size) * 0.085))
    vertical.stroke()

    NSColor(calibratedRed: 0.96, green: 0.27, blue: 0.10, alpha: 1).setFill()
    for point in [NSPoint(x: 0.64, y: 0.53), NSPoint(x: 0.71, y: 0.45)] {
        let diameter = CGFloat(size) * 0.075
        NSBezierPath(ovalIn: NSRect(
            x: CGFloat(size) * point.x - diameter / 2,
            y: CGFloat(size) * point.y - diameter / 2,
            width: diameter,
            height: diameter
        )).fill()
    }

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    let name = files.first(where: { $0.1 == size })?.0 ?? "icon.png"
    try png.write(to: output.appendingPathComponent(name))
}

for (name, size) in files {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { continue }
    context.setAllowsAntialiasing(true)
    let inset = CGFloat(size) * 0.055
    let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    let background = NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.07, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.48, green: 0.10, blue: 0.40, alpha: 1),
        NSColor(calibratedRed: 0.96, green: 0.28, blue: 0.10, alpha: 1)
    ])!.draw(in: background, angle: -45)
    let padRect = NSRect(x: CGFloat(size) * 0.18, y: CGFloat(size) * 0.27, width: CGFloat(size) * 0.64, height: CGFloat(size) * 0.42)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: padRect, xRadius: CGFloat(size) * 0.15, yRadius: CGFloat(size) * 0.15).fill()
    let lineWidth = max(1, CGFloat(size) * 0.048)
    NSColor(calibratedRed: 0.28, green: 0.10, blue: 0.42, alpha: 1).setStroke()
    for (start, end) in [
        (NSPoint(x: CGFloat(size) * 0.275, y: CGFloat(size) * 0.48), NSPoint(x: CGFloat(size) * 0.445, y: CGFloat(size) * 0.48)),
        (NSPoint(x: CGFloat(size) * 0.36, y: CGFloat(size) * 0.395), NSPoint(x: CGFloat(size) * 0.36, y: CGFloat(size) * 0.565))
    ] {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()
    }
    NSColor(calibratedRed: 0.96, green: 0.27, blue: 0.10, alpha: 1).setFill()
    let dot = CGFloat(size) * 0.075
    for point in [NSPoint(x: 0.64, y: 0.53), NSPoint(x: 0.71, y: 0.45)] {
        NSBezierPath(ovalIn: NSRect(x: CGFloat(size) * point.x - dot / 2, y: CGFloat(size) * point.y - dot / 2, width: dot, height: dot)).fill()
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: output.appendingPathComponent(name))
}
