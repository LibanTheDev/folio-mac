import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
ctx.saveGState()
path.addClip()
NSGradient(colors: [NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.20, alpha: 1),
                    NSColor(calibratedRed: 0.85, green: 0.22, blue: 0.36, alpha: 1)])!
    .draw(in: rect, angle: -60)
ctx.restoreGState()
// Open book
func page(_ flip: Bool) {
    let p = NSBezierPath()
    let cx: CGFloat = 512, y0: CGFloat = 330, w: CGFloat = 270, h: CGFloat = 340
    let s: CGFloat = flip ? -1 : 1
    p.move(to: NSPoint(x: cx, y: y0))
    p.curve(to: NSPoint(x: cx + s * w, y: y0 + 30), controlPoint1: NSPoint(x: cx + s * 90, y: y0 + 40), controlPoint2: NSPoint(x: cx + s * 180, y: y0 + 10))
    p.line(to: NSPoint(x: cx + s * w, y: y0 + h + 30))
    p.curve(to: NSPoint(x: cx, y: y0 + h), controlPoint1: NSPoint(x: cx + s * 180, y: y0 + h + 10), controlPoint2: NSPoint(x: cx + s * 90, y: y0 + h + 40))
    p.close()
    NSColor.white.withAlphaComponent(flip ? 0.88 : 1).setFill()
    p.fill()
}
page(true); page(false)
// Bookmark ribbon
let r = NSBezierPath()
r.move(to: NSPoint(x: 600, y: 700)); r.line(to: NSPoint(x: 600, y: 560)); r.line(to: NSPoint(x: 630, y: 590))
r.line(to: NSPoint(x: 660, y: 560)); r.line(to: NSPoint(x: 660, y: 705)); r.close()
NSColor(calibratedRed: 0.85, green: 0.22, blue: 0.36, alpha: 1).setFill(); r.fill()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
