#!/usr/bin/env swift
import AppKit

// Draws the QuitProtect icon: a shield with a power symbol on a brand-blue background.
// CG coordinate origin: bottom-left.
func drawIcon(ctx: CGContext, s: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()

    // ── 1. Background: brand blue gradient rounded rect ──────────────────────
    let bgRadius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: bgRadius, cornerHeight: bgRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [CGColor(red: 0.05, green: 0.32, blue: 0.58, alpha: 1),
                 CGColor(red: 0.00, green: 0.25, blue: 0.50, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: s / 2, y: s),
                           end:   CGPoint(x: s / 2, y: 0),
                           options: [])
    ctx.restoreGState()

    // ── 2. Shield shape ──────────────────────────────────────────────────────
    let cx = s / 2
    let shieldTop    = s * 0.85
    let shieldBottom = s * 0.12
    let shieldW      = s * 0.56
    let shoulderY    = s * 0.60

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02),
                  blur: s * 0.05,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))

    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx, y: shieldTop))
    // Right shoulder curve
    ctx.addCurve(to: CGPoint(x: cx + shieldW / 2, y: shoulderY),
                 control1: CGPoint(x: cx + shieldW * 0.35, y: shieldTop),
                 control2: CGPoint(x: cx + shieldW / 2, y: shieldTop * 0.9))
    // Right side down to point
    ctx.addCurve(to: CGPoint(x: cx, y: shieldBottom),
                 control1: CGPoint(x: cx + shieldW / 2, y: shoulderY * 0.6),
                 control2: CGPoint(x: cx + shieldW * 0.2, y: shieldBottom + s * 0.05))
    // Left side up from point
    ctx.addCurve(to: CGPoint(x: cx - shieldW / 2, y: shoulderY),
                 control1: CGPoint(x: cx - shieldW * 0.2, y: shieldBottom + s * 0.05),
                 control2: CGPoint(x: cx - shieldW / 2, y: shoulderY * 0.6))
    // Left shoulder curve back to top
    ctx.addCurve(to: CGPoint(x: cx, y: shieldTop),
                 control1: CGPoint(x: cx - shieldW / 2, y: shieldTop * 0.9),
                 control2: CGPoint(x: cx - shieldW * 0.35, y: shieldTop))
    ctx.closePath()

    // Shield fill: white with slight transparency
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.fillPath()
    ctx.restoreGState()

    // ── 3. Power symbol (⏻) inside the shield ────────────────────────────────
    let powerColor = CGColor(red: 0.00, green: 0.25, blue: 0.50, alpha: 1)
    let powerCX = cx
    let powerCY = s * 0.46
    let powerR  = s * 0.14

    // Arc (open at top)
    ctx.setStrokeColor(powerColor)
    ctx.setLineWidth(s * 0.04)
    ctx.setLineCap(.round)
    let startAngle = CGFloat.pi * 0.2     // ~36° from top-right
    let endAngle   = CGFloat.pi * 0.8     // ~144° (top-left)
    ctx.addArc(center: CGPoint(x: powerCX, y: powerCY),
               radius: powerR,
               startAngle: startAngle,
               endAngle: endAngle,
               clockwise: true)
    ctx.strokePath()

    // Vertical line (stem)
    let stemTop = powerCY + powerR * 1.15
    let stemBottom = powerCY + powerR * 0.15
    ctx.move(to: CGPoint(x: powerCX, y: stemTop))
    ctx.addLine(to: CGPoint(x: powerCX, y: stemBottom))
    ctx.strokePath()
}

// ── Render at given pixel size ───────────────────────────────────────────────
func renderIcon(pixels: Int) -> Data? {
    guard let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: NSColorSpaceName.deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: bmp)?.cgContext else { return nil }
    drawIcon(ctx: ctx, s: CGFloat(pixels))
    return bmp.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
}

// ── Main ─────────────────────────────────────────────────────────────────────
let destDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let sizes: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

for (filename, pixels) in sizes {
    if let data = renderIcon(pixels: pixels) {
        let url = URL(fileURLWithPath: destDir).appendingPathComponent(filename)
        try! data.write(to: url)
        print("✓  \(filename)  (\(pixels)px)")
    } else {
        print("✗  Failed: \(filename)")
    }
}
print("Done.")
