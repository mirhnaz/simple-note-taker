import AppKit

let outDir = "/Users/mir/dev/SimpleNoteTaker/SimpleNoteTaker/Assets.xcassets/AppIcon.appiconset"

let sizes: [(file: String, pixels: Int)] = [
    ("icon_16.png", 16),
    ("icon_16@2x.png", 32),
    ("icon_32.png", 32),
    ("icon_32@2x.png", 64),
    ("icon_128.png", 128),
    ("icon_128@2x.png", 256),
    ("icon_256.png", 256),
    ("icon_256@2x.png", 512),
    ("icon_512.png", 512),
    ("icon_512@2x.png", 1024)
]

func renderIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let savedContext = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer {
        NSGraphicsContext.current = savedContext
    }

    // Background — soft warm gradient (paper feel)
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgPath.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.94, blue: 0.78, alpha: 1.0),
        NSColor(calibratedRed: 0.99, green: 0.86, blue: 0.55, alpha: 1.0)
    ])!
    gradient.draw(in: bgRect, angle: -90)

    // Reset clip for further drawing
    NSGraphicsContext.current?.saveGraphicsState()

    // Paper card
    let pad = s * 0.18
    let paperRect = NSRect(x: pad, y: pad * 0.85, width: s - pad * 2, height: s - pad * 1.7)
    let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: s * 0.05, yRadius: s * 0.05)

    // Subtle drop shadow
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
    shadow.set()
    NSColor.white.setFill()
    paperPath.fill()
    NSShadow().set() // clear

    // Top "binding" stripe
    let stripeHeight = s * 0.045
    let stripeRect = NSRect(x: paperRect.minX, y: paperRect.maxY - stripeHeight, width: paperRect.width, height: stripeHeight)
    let stripeClip = NSBezierPath(roundedRect: paperRect, xRadius: s * 0.05, yRadius: s * 0.05)
    stripeClip.setClip()
    NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.42, alpha: 1.0).setFill()
    NSBezierPath(rect: stripeRect).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.current?.saveGraphicsState()

    // Ruled horizontal lines
    let lineColor = NSColor(white: 0.78, alpha: 1.0)
    lineColor.setStroke()
    let topMargin = s * 0.12
    let topY = paperRect.maxY - stripeHeight - topMargin
    let lineSpacing = paperRect.height * 0.13
    for i in 0..<3 {
        let y = topY - CGFloat(i) * lineSpacing
        let line = NSBezierPath()
        line.lineWidth = max(1, s * 0.012)
        line.move(to: NSPoint(x: paperRect.minX + paperRect.width * 0.12, y: y))
        line.line(to: NSPoint(x: paperRect.maxX - paperRect.width * (i == 0 ? 0.12 : 0.30), y: y))
        line.stroke()
    }

    // Scribble (wavy line) toward the bottom of the paper
    let scribbleY = paperRect.minY + paperRect.height * 0.28
    let scribbleColor = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)
    scribbleColor.setStroke()
    let scribble = NSBezierPath()
    scribble.lineWidth = max(1.2, s * 0.022)
    scribble.lineCapStyle = .round
    let scribbleStart = paperRect.minX + paperRect.width * 0.13
    let scribbleEnd = paperRect.maxX - paperRect.width * 0.13
    let scribbleWidth = scribbleEnd - scribbleStart
    let bumps = 4
    let segWidth = scribbleWidth / CGFloat(bumps)
    let amp = paperRect.height * 0.07
    scribble.move(to: NSPoint(x: scribbleStart, y: scribbleY))
    for i in 0..<bumps {
        let x0 = scribbleStart + CGFloat(i) * segWidth
        let x1 = x0 + segWidth
        let goingUp = i % 2 == 0
        let cp1 = NSPoint(x: x0 + segWidth * 0.25, y: scribbleY + (goingUp ? amp : -amp) * 1.6)
        let cp2 = NSPoint(x: x1 - segWidth * 0.25, y: scribbleY + (goingUp ? amp : -amp) * 1.6)
        scribble.curve(to: NSPoint(x: x1, y: scribbleY), controlPoint1: cp1, controlPoint2: cp2)
    }
    scribble.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()

    // Mic badge — red circle with white mic glyph at bottom-right corner
    let badgeDiameter = s * 0.42
    let badgeRect = NSRect(
        x: s - badgeDiameter - s * 0.06,
        y: s * 0.04,
        width: badgeDiameter,
        height: badgeDiameter
    )
    // Soft shadow under badge
    let badgeShadow = NSShadow()
    badgeShadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
    badgeShadow.shadowBlurRadius = s * 0.04
    badgeShadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    badgeShadow.set()
    NSColor(calibratedRed: 0.95, green: 0.27, blue: 0.30, alpha: 1.0).setFill()
    NSBezierPath(ovalIn: badgeRect).fill()
    NSShadow().set()

    // Mic glyph (SF Symbol with palette color = white)
    let micConfig = NSImage.SymbolConfiguration(pointSize: badgeDiameter * 0.55, weight: .heavy)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(micConfig) {
        let micSize = mic.size
        let micRect = NSRect(
            x: badgeRect.midX - micSize.width / 2,
            y: badgeRect.midY - micSize.height / 2,
            width: micSize.width,
            height: micSize.height
        )
        mic.draw(in: micRect)
    }

    return bitmap.representation(using: .png, properties: [:])!
}

for (file, pixels) in sizes {
    let data = renderIcon(size: pixels)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(file)
    try! data.write(to: url)
    print("wrote \(file) (\(pixels)x\(pixels), \(data.count) bytes)")
}

// Update Contents.json to reference the new files
let contentsJSON = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
let contentsURL = URL(fileURLWithPath: outDir).appendingPathComponent("Contents.json")
try! contentsJSON.write(to: contentsURL, atomically: true, encoding: .utf8)
print("wrote Contents.json")
