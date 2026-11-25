// Draws the DMG window background: a soft backdrop with an arrow from the app to Applications.
// Usage: swift scripts/make-dmg-background.swift <out.png> <scale>
// The DMG script combines the 1x and 2x renders into one HiDPI TIFF.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <out.png> <scale>\n".utf8))
    exit(2)
}

// Must match the window and icon positions in scripts/make-dmg.sh.
let size = NSSize(width: 640, height: 400)
let appCenter = NSPoint(x: 170, y: 190)      // top-left origin, like Finder
let appsCenter = NSPoint(x: 470, y: 190)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Flip to a top-left origin so coordinates match Finder's icon positions.
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)

// Backdrop: gentle vertical gradient.
let gradient = NSGradient(colors: [NSColor(white: 0.985, alpha: 1), NSColor(white: 0.93, alpha: 1)])!
gradient.draw(in: NSRect(origin: .zero, size: size), angle: 90)

// Arrow between the two icons (icons are 128pt; leave room around them).
let arrowColor = NSColor(white: 0.62, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()
let y = appCenter.y
let startX = appCenter.x + 88, endX = appsCenter.x - 88
let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: startX, y: y))
shaft.line(to: NSPoint(x: endX - 14, y: y))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: endX, y: y))
head.line(to: NSPoint(x: endX - 20, y: y - 13))
head.line(to: NSPoint(x: endX - 20, y: y + 13))
head.close()
head.fill()

// Caption under the icons (drawn unflipped so the text isn't mirrored).
ctx.saveGState()
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)
let caption = "Drag Clippy to Applications to install"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(white: 0.42, alpha: 1),
]
let textSize = caption.size(withAttributes: attrs)
caption.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 64), withAttributes: attrs)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
