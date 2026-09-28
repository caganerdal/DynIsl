import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let S: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func squircle(_ r: CGRect, n: CGFloat = 4.2) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / n)
        let y = cy + b * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
let space = CGColorSpace(name: CGColorSpace.sRGB)!

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(body)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x0B0D1A)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [color(0x3A3FA0), color(0x161A45), color(0x07080F)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

let glow = CGGradient(colorsSpace: space, colors: [color(0x8A6BFF, 0.70), color(0x3D7BFF, 0.22), color(0x3D7BFF, 0)] as CFArray,
                      locations: [0, 0.45, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 520), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 520), endRadius: 420, options: [])

let shine = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()
ctx.restoreGState()

let island = CGRect(x: 512 - 290, y: 560 - 92, width: 580, height: 184)
let islandPath = CGPath(roundedRect: island, cornerWidth: 92, cornerHeight: 92, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: color(0x000000, 0.7))
ctx.addPath(islandPath); ctx.setFillColor(color(0x000000)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(islandPath); ctx.setLineWidth(4); ctx.replacePathWithStrokedPath(); ctx.clip()
let rim = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0.04)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(rim, start: CGPoint(x: 512, y: island.maxY), end: CGPoint(x: 512, y: island.minY), options: [])
ctx.restoreGState()

let barHeights: [CGFloat] = [46, 86, 62, 100]
let barW: CGFloat = 20, gap: CGFloat = 16
var x = island.minX + 92
ctx.saveGState()
let barsPath = CGMutablePath()
for h in barHeights {
    barsPath.addPath(CGPath(roundedRect: CGRect(x: x, y: island.midY - h / 2, width: barW, height: h),
                            cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    x += barW + gap
}
ctx.addPath(barsPath); ctx.clip()
let barsGrad = CGGradient(colorsSpace: space, colors: [color(0x5EE7FF), color(0x8B6CFF)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(barsGrad, start: CGPoint(x: island.minX + 92, y: island.maxY), end: CGPoint(x: x, y: island.minY), options: [])
ctx.restoreGState()

let dotCenter = CGPoint(x: island.maxX - 118, y: island.midY)
let dotGlow = CGGradient(colorsSpace: space, colors: [color(0x34E89E, 0.55), color(0x34E89E, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(dotGlow, startCenter: dotCenter, startRadius: 0, endCenter: dotCenter, endRadius: 70, options: [])
ctx.setFillColor(color(0x34E89E))
ctx.fillEllipse(in: CGRect(x: dotCenter.x - 24, y: dotCenter.y - 24, width: 48, height: 48))
ctx.setFillColor(color(0xFFFFFF, 0.55))
ctx.fillEllipse(in: CGRect(x: dotCenter.x - 12, y: dotCenter.y + 2, width: 14, height: 14))

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("yazıldı:", outPath)
