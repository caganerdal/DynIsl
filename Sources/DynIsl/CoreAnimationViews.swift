import AppKit
import SwiftUI

struct CAEqualizer: NSViewRepresentable {
    var color: Color

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.setColor(NSColor(color))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerView, context: Context) -> CGSize? {
        EqualizerView.size
    }
}

final class EqualizerView: NSView {
    static let size = CGSize(width: 18, height: 16)
    private var bars: [CALayer] = []

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        addDecorativeAnimations()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Self.size }

    private func addDecorativeAnimations() {
        if bars.isEmpty {
            for i in 0..<4 {
                let bar = CALayer()
                bar.cornerRadius = 1.5
                bar.frame = CGRect(x: CGFloat(i) * 5, y: 0, width: 3, height: Self.size.height)
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }
        let durations: [CFTimeInterval] = [0.42, 0.58, 0.36, 0.51]
        let now = CACurrentMediaTime()
        for (i, d) in durations.enumerated() {
            let bar = bars[i]
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.25
            a.toValue = 1.0
            a.duration = d
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.beginTime = now + Double(i) * 0.11
            a.isRemovedOnCompletion = false
            bar.add(a, forKey: "eq")
        }
    }

    func setColor(_ color: NSColor) {
        let cg = color.cgColor
        guard bars.first?.backgroundColor != cg else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        bars.forEach { $0.backgroundColor = cg }
        CATransaction.commit()
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
