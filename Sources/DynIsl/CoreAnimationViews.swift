import AppKit
import SwiftUI

enum EqualizerStyle: String, CaseIterable, Identifiable {
    case bars, wave, dots, pulse
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: return String(localized: "Çubuk")
        case .wave: return String(localized: "Dalga")
        case .dots: return String(localized: "Nokta")
        case .pulse: return String(localized: "Nabız")
        }
    }
}

struct CAEqualizer: NSViewRepresentable {
    var color: Color
    var style: EqualizerStyle = .bars

    func makeNSView(context: Context) -> EqualizerView { EqualizerView(style: style) }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.setStyle(style)
        view.setColor(NSColor(color))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerView, context: Context) -> CGSize? {
        EqualizerView.size
    }
}

final class EqualizerView: NSView {
    static let size = CGSize(width: 18, height: 16)
    private var parts: [CALayer] = []
    private var strokes: [CAShapeLayer] = []
    private var style: EqualizerStyle
    private var color: CGColor = NSColor.white.cgColor

    init(style: EqualizerStyle) {
        self.style = style
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.masksToBounds = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Self.size }

    func setStyle(_ s: EqualizerStyle) {
        guard s != style else { return }
        style = s
        build()
    }

    private func build() {
        parts.forEach { $0.removeFromSuperlayer() }
        strokes.forEach { $0.removeFromSuperlayer() }
        parts = []
        strokes = []
        let now = CACurrentMediaTime()
        let w = Self.size.width, h = Self.size.height
        switch style {
        case .bars:
            let durations: [CFTimeInterval] = [0.42, 0.58, 0.36, 0.51]
            for (i, d) in durations.enumerated() {
                let bar = CALayer()
                bar.cornerRadius = 1.5
                bar.frame = CGRect(x: CGFloat(i) * 5, y: 0, width: 3, height: h)
                bar.add(Self.loop("transform.scale.y", 0.25, 1, d, begin: now + Double(i) * 0.11), forKey: "eq")
                add(bar)
            }
        case .wave:
            let line = CAShapeLayer()
            line.frame = bounds
            line.fillColor = nil
            line.lineWidth = 2
            line.lineCap = .round
            let frames = (0..<8).map { k in Self.sine(width: w, height: h, phase: Double(k) / 8 * 2 * .pi) }
            line.path = frames[0]
            let a = CAKeyframeAnimation(keyPath: "path")
            a.values = frames + [frames[0]]
            a.duration = 0.9
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            line.add(a, forKey: "wave")
            layer?.addSublayer(line)
            strokes.append(line)
        case .dots:
            for i in 0..<3 {
                let dot = CALayer()
                dot.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
                dot.cornerRadius = 2
                dot.position = CGPoint(x: 3 + CGFloat(i) * 6, y: 4)
                dot.add(Self.loop("position.y", 3, h - 3, 0.38, begin: now + Double(i) * 0.13), forKey: "hop")
                add(dot)
            }
        case .pulse:
            for i in 0..<2 {
                let ring = CAShapeLayer()
                ring.frame = CGRect(x: (w - 14) / 2, y: (h - 14) / 2, width: 14, height: 14)
                ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 1, dy: 1), transform: nil)
                ring.fillColor = nil
                ring.lineWidth = 1.5
                let g = CAAnimationGroup()
                let sc = CABasicAnimation(keyPath: "transform.scale")
                sc.fromValue = 0.3
                sc.toValue = 1.15
                let op = CABasicAnimation(keyPath: "opacity")
                op.fromValue = 1
                op.toValue = 0
                g.animations = [sc, op]
                g.duration = 1.1
                g.repeatCount = .infinity
                g.beginTime = now + Double(i) * 0.55
                g.timingFunction = CAMediaTimingFunction(name: .easeOut)
                g.isRemovedOnCompletion = false
                ring.add(g, forKey: "pulse")
                layer?.addSublayer(ring)
                strokes.append(ring)
            }
            let core = CALayer()
            core.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
            core.cornerRadius = 2.5
            core.position = CGPoint(x: w / 2, y: h / 2)
            core.add(Self.loop("transform.scale", 0.8, 1.2, 0.55, begin: now), forKey: "beat")
            add(core)
        }
        applyColor()
    }

    private func add(_ l: CALayer) {
        layer?.addSublayer(l)
        parts.append(l)
    }

    private static func loop(_ key: String, _ from: CGFloat, _ to: CGFloat, _ d: CFTimeInterval, begin: CFTimeInterval) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.duration = d
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.beginTime = begin
        a.isRemovedOnCompletion = false
        return a
    }

    private static func sine(width: CGFloat, height: CGFloat, phase: Double) -> CGPath {
        let p = CGMutablePath()
        let steps = 18
        for i in 0...steps {
            let x = width * CGFloat(i) / CGFloat(steps)
            let y = height / 2 + (height / 2 - 2) * CGFloat(sin(Double(i) / Double(steps) * 2 * .pi * 1.5 + phase))
            i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }

    func setColor(_ c: NSColor) {
        let cg = c.cgColor
        guard color != cg else { return }
        color = cg
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        applyColor()
        CATransaction.commit()
    }

    private func applyColor() {
        parts.forEach { $0.backgroundColor = color }
        strokes.forEach { $0.strokeColor = color }
    }
}

struct CAGlow: NSViewRepresentable {
    var color: Color
    var top: CGFloat
    var bottom: CGFloat

    func makeNSView(context: Context) -> GlowView { GlowView() }

    func updateNSView(_ view: GlowView, context: Context) {
        view.update(color: NSColor(color), top: top, bottom: bottom)
    }
}

final class GlowView: NSView {
    private let shape = CAShapeLayer()
    private var top: CGFloat = 6
    private var bottom: CGFloat = 10

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        shape.fillColor = NSColor.black.cgColor
        shape.shadowOffset = .zero
        shape.shadowRadius = 14
        shape.shadowOpacity = 0.3
        let a = CABasicAnimation(keyPath: "shadowOpacity")
        a.fromValue = 0.3
        a.toValue = 0.65
        a.duration = 2.4
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        shape.add(a, forKey: "breathe")
        layer?.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(color: NSColor, top: CGFloat, bottom: CGFloat) {
        let cg = color.cgColor
        if shape.shadowColor != cg {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.6)
            shape.shadowColor = cg
            CATransaction.commit()
        }
        if top != self.top || bottom != self.bottom {
            self.top = top
            self.bottom = bottom
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        let path = NotchShape(topRadius: top, bottomRadius: bottom).path(in: bounds).cgPath
        shape.path = path
        shape.shadowPath = path
        CATransaction.commit()
    }
}
