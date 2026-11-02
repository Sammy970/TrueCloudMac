#!/usr/bin/env swift
// Draws TrueCloud.icns: a white cloud with a play triangle on a teal-to-indigo tile. Original artwork.
// Usage: swift scripts/make-icon.swift   (writes TrueCloud.icns and .github/icon.png)
import AppKit

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // Tile (macOS icon grid: 824 square centred in 1024).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); tilePath.fill()
    ctx.restoreGState()
    ctx.saveGState()
    tilePath.addClip()
    let colors = [NSColor(red: 0.25, green: 0.82, blue: 0.74, alpha: 1).cgColor,
                  NSColor(red: 0.07, green: 0.58, blue: 0.62, alpha: 1).cgColor,
                  NSColor(red: 0.30, green: 0.30, blue: 0.82, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 160, y: 924), end: CGPoint(x: 864, y: 100), options: [])
    // Soft top highlight.
    let hi = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hi, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Cloud: three overlapping circles on a rounded base.
    let cloud = NSBezierPath()
    cloud.append(NSBezierPath(roundedRect: CGRect(x: 230, y: 330, width: 564, height: 230), xRadius: 115, yRadius: 115))
    cloud.append(NSBezierPath(ovalIn: CGRect(x: 292, y: 420, width: 280, height: 280)))
    cloud.append(NSBezierPath(ovalIn: CGRect(x: 436, y: 468, width: 330, height: 330)))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(red: 0.02, green: 0.12, blue: 0.2, alpha: 0.35).cgColor)
    NSColor.white.setFill(); cloud.fill()
    ctx.restoreGState()

    // Play triangle, cut out in the tile's deep teal.
    let play = NSBezierPath()
    play.move(to: CGPoint(x: 458, y: 410)); play.line(to: CGPoint(x: 458, y: 640)); play.line(to: CGPoint(x: 650, y: 525)); play.close()
    play.lineJoinStyle = .round
    NSColor(red: 0.07, green: 0.50, blue: 0.58, alpha: 1).setFill(); play.fill()
    NSColor(red: 0.07, green: 0.50, blue: 0.58, alpha: 1).setStroke(); play.lineWidth = 34; play.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let set = "build/TrueCloud.iconset"
try? fm.removeItem(atPath: set)
try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    write(render(size: base), to: "\(set)/icon_\(base)x\(base).png")
    write(render(size: base * 2), to: "\(set)/icon_\(base)x\(base)@2x.png")
}
try? fm.createDirectory(atPath: ".github", withIntermediateDirectories: true)
write(render(size: 1024), to: ".github/icon.png")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "TrueCloud.icns"]
try! p.run(); p.waitUntilExit()
print("Wrote TrueCloud.icns and .github/icon.png")
