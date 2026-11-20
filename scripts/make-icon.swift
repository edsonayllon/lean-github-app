// Draws the app icon and writes it as a 1024 px PNG. Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The standard macOS icon plate: 824 px rounded square centred on a 1024 px canvas.
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: plate, xRadius: 186, yRadius: 186)
NSGradient(
    starting: NSColor(srgbRed: 0.16, green: 0.19, blue: 0.24, alpha: 1),
    ending: NSColor(srgbRed: 0.05, green: 0.07, blue: 0.09, alpha: 1)
)!.draw(in: shape, angle: -90)

// A branch: trunk on the left, one branch curving off to the right.
let white = NSColor.white
let green = NSColor(srgbRed: 0.25, green: 0.73, blue: 0.31, alpha: 1)
let stroke: CGFloat = 56
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
node(branchX, branchY, green)

NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
