import AppKit
import SwiftUI

enum PetMood: Equatable {
    case sleeping, dancing, tired, hot
}

struct IslandPet: NSViewRepresentable {
    var mood: PetMood

    func makeNSView(context: Context) -> PetView { PetView() }

    func updateNSView(_ view: PetView, context: Context) { view.set(mood) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PetView, context: Context) -> CGSize? { PetView.size }
}

final class PetView: NSView {
    static let size = CGSize(width: 26, height: 22)

    private let cat = CALayer()
    private let fx = CALayer()
    private var mood: PetMood?

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.masksToBounds = false
        cat.frame = CGRect(x: 5, y: 1, width: 16, height: 16)
        cat.anchorPoint = CGPoint(x: 0.5, y: 0)
        cat.position = CGPoint(x: 13, y: 1)
        cat.contentsGravity = .resizeAspect
        fx.frame = bounds
        fx.masksToBounds = false
        layer?.addSublayer(cat)
        layer?.addSublayer(fx)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Self.size }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let m = mood { mood = nil; set(m) }
    }

    func set(_ new: PetMood) {
        guard new != mood else { return }
        mood = new
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cat.removeAllAnimations()
        fx.sublayers?.forEach { $0.removeFromSuperlayer() }
        cat.transform = CATransform3DIdentity
        let scale = window?.backingScaleFactor ?? 2
        cat.contentsScale = scale

        switch new {
        case .sleeping:
            cat.contents = Self.symbol("cat.fill", color: .white.withAlphaComponent(0.85), size: 15, scale: scale)
            cat.add(Self.loop("transform.scale.y", from: 1, to: 1.07, duration: 1.8), forKey: "breathe")
            for i in 0..<3 { fx.addSublayer(floating(text: "z", index: i, color: .white.withAlphaComponent(0.8), every: 3.0)) }
        case .dancing:
            cat.contents = Self.symbol("cat.fill", color: .white, size: 15, scale: scale)
            cat.add(Self.loop("transform.rotation.z", from: -0.2, to: 0.2, duration: 0.42), forKey: "bob")
            cat.add(Self.loop("transform.translation.y", from: 0, to: 1.5, duration: 0.21), forKey: "hop")
            for i in 0..<2 { fx.addSublayer(floating(symbol: "music.note", index: i, color: .systemPink, every: 1.8)) }
        case .tired:
            cat.contents = Self.symbol("cat.fill", color: .white.withAlphaComponent(0.55), size: 15, scale: scale)
            cat.transform = CATransform3DMakeRotation(-0.25, 0, 0, 1)
            cat.add(Self.loop("transform.scale.y", from: 0.94, to: 1.0, duration: 2.6), forKey: "sigh")
            let b = symbolLayer("battery.25percent", color: .systemRed, size: 9, scale: scale)
            b.position = CGPoint(x: 22, y: 18)
            b.add(Self.loop("opacity", from: 0.25, to: 1, duration: 0.8), forKey: "blink")
            fx.addSublayer(b)
        case .hot:
            cat.contents = Self.symbol("cat.fill", color: NSColor(red: 1, green: 0.55, blue: 0.4, alpha: 1), size: 15, scale: scale)
            cat.add(Self.loop("transform.translation.x", from: -0.9, to: 0.9, duration: 0.07), forKey: "shake")
            for i in 0..<2 { fx.addSublayer(falling(index: i, scale: scale)) }
        }
        CATransaction.commit()
    }

    private func floating(text: String? = nil, symbol: String? = nil, index: Int, color: NSColor, every: CFTimeInterval) -> CALayer {
        let scale = window?.backingScaleFactor ?? 2
        let l: CALayer
        if let symbol {
            l = symbolLayer(symbol, color: color, size: 7, scale: scale)
        } else {
            let t = CATextLayer()
            t.string = text
            t.font = NSFont.systemFont(ofSize: 7, weight: .bold)
            t.fontSize = CGFloat(6 + index)
            t.foregroundColor = color.cgColor
            t.alignmentMode = .center
            t.contentsScale = scale
            t.bounds = CGRect(x: 0, y: 0, width: 8, height: 10)
            l = t
        }
        l.position = CGPoint(x: 19, y: 14)
        l.opacity = 0
        let group = CAAnimationGroup()
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = CGPoint(x: 19, y: 13)
        move.toValue = CGPoint(x: 25 + CGFloat(index) * 2, y: 24)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.2, 0.7, 1]
        group.animations = [move, fade]
        group.duration = every
        group.repeatCount = .infinity
        group.beginTime = CACurrentMediaTime() + every / 3 * Double(index)
        group.isRemovedOnCompletion = false
        l.add(group, forKey: "float")
        return l
    }

    private func falling(index: Int, scale: CGFloat) -> CALayer {
        let d = symbolLayer("drop.fill", color: .systemCyan, size: 6, scale: scale)
        d.opacity = 0
        let x: CGFloat = index == 0 ? 7 : 19
        let group = CAAnimationGroup()
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = CGPoint(x: x, y: 17)
        move.toValue = CGPoint(x: x + (index == 0 ? -3 : 3), y: 4)
        move.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.3, 1]
        group.animations = [move, fade]
        group.duration = 0.9
        group.repeatCount = .infinity
        group.beginTime = CACurrentMediaTime() + 0.45 * Double(index)
        group.isRemovedOnCompletion = false
        d.add(group, forKey: "drip")
        return d
    }

    private func symbolLayer(_ name: String, color: NSColor, size: CGFloat, scale: CGFloat) -> CALayer {
        let l = CALayer()
        l.contents = Self.symbol(name, color: color, size: size, scale: scale)
        l.contentsScale = scale
        l.contentsGravity = .resizeAspect
        l.bounds = CGRect(x: 0, y: 0, width: size + 2, height: size + 2)
        return l
    }

    private static func loop(_ key: String, from: CGFloat, to: CGFloat, duration: CFTimeInterval) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        return a
    }

    private static var cache: [String: CGImage] = [:]

    private static func symbol(_ name: String, color: NSColor, size: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "\(name)|\(color)|\(size)|\(scale)"
        if let c = cache[key] { return c }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        var rect = CGRect(origin: .zero, size: img.size)
        let rep = img.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
        if let rep { cache[key] = rep }
        return rep
    }
}
