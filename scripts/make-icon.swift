// Draws the app icon: a git branch on a near-black tile, in the same style as Process Code's icon
// (off-white glyph, periwinkle accent). Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The tile, inset as macOS icons are, with a faint edge so it holds on dark backgrounds.
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.095, alpha: 1),
    ending: NSColor(srgbRed: 0.04, green: 0.045, blue: 0.04, alpha: 1)
)!.draw(in: shape, angle: -90)
NSColor(white: 1, alpha: 0.10).setStroke()
shape.lineWidth = 6
shape.stroke()

// A branch: trunk on the left, one branch curving off to the right, its tip in Claude Code's periwinkle.
let white = NSColor(srgbRed: 0.90, green: 0.91, blue: 0.905, alpha: 1)
let accent = NSColor(srgbRed: 0.694, green: 0.725, blue: 0.976, alpha: 1)
let stroke: CGFloat = 64
let trunkX: CGFloat = 392, branchX: CGFloat = 632
let top: CGFloat = 700, bottom: CGFloat = 324, branchY: CGFloat = 620

let lines = NSBezierPath()
lines.lineWidth = stroke
lines.lineCapStyle = .round
lines.move(to: NSPoint(x: trunkX, y: bottom))
lines.line(to: NSPoint(x: trunkX, y: top))
lines.move(to: NSPoint(x: branchX, y: branchY))
lines.curve(
    to: NSPoint(x: trunkX, y: 430),
    controlPoint1: NSPoint(x: branchX, y: 500),
    controlPoint2: NSPoint(x: trunkX, y: 540)
)
white.setStroke()
lines.stroke()

func node(_ x: CGFloat, _ y: CGFloat, _ color: NSColor) {
    let r: CGFloat = 70
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
}
node(trunkX, top, white)
node(trunkX, bottom, white)
node(branchX, branchY, accent)

NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
