import AppKit
import QuartzCore
import CoreGraphics

@MainActor
public final class FolderTile: NSView {
    public let entryDescriptor: BoardEntry
    public private(set) var containedItems: [BoardEntry]
    let lidContainer = CALayer()
    let itemLayer = CALayer()

    public init(item: BoardEntry, contained: [BoardEntry]) {
        entryDescriptor = item
        containedItems = contained
        super.init(frame: .zero)
        wantsLayer = true
        lidContainer.name = "lidContainer"
        layer?.addSublayer(itemLayer)
        layer?.addSublayer(lidContainer)
        redrawShape()
        for entry in contained.reversed() {
            let v = EntryTile(item: entry)
            v.layer?.frame = CGRect(origin: dropPoint(for: entry), size: entry.size)
            itemLayer.addSublayer(v.layer ?? CALayer())
        }
    }

    required init?(coder: NSCoder) { nil }

    override public func layout() {
        super.layout()
        redrawShape()
    }

    private func redrawShape() {
        let path = CGMutablePath()
        let w = bounds.width, h = bounds.height
        path.move(to: CGPoint(x: 8, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.86),
                          control: CGPoint(x: w * 0.5, y: h))
        path.addQuadCurve(to: CGPoint(x: w - 8, y: h),
                          control: CGPoint(x: w * 0.5, y: h))
        path.closeSubpath()
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = NSColor.systemGray.withAlphaComponent(0.30).cgColor
        lidContainer.sublayers?.forEach { if $0 != shape { $0.removeFromSuperlayer() } }
        lidContainer.addSublayer(shape)
    }

    private func dropPoint(for entry: BoardEntry) -> CGPoint {
        let pedestal = bounds.width
        var scale = min((pedestal - 64) / max(entry.size.width, 1),
                        250 / max(entry.size.height, 1), 1)
        _ = scale
        scale = max(scale, 0.3)
        let cx = bounds.midX + CGFloat.random(in: -12...12)
        let cy = bounds.height - 24
            + CGFloat.random(in: -4...4)
            + (1 - scale) * entry.size.height * 0.5
        let sz = CGSize(width: entry.size.width * scale,
                        height: entry.size.height * scale)
        return CGPoint(x: cx - sz.width / 2, y: cy - sz.height / 2)
    }

    public func dropIntoFolder(_ item: BoardEntry) async {
        containedItems.append(item)
        let pedestalWidth = max(bounds.width, 1)
        let scale = min(max((pedestalWidth - 64) / max(item.size.width, 1),
                            250 / max(item.size.height, 1)), 1)
        let jitter = (2 + Double.random(in: -4...4)) * .pi / 180
        let mass = SpringCatalog.lidMass()

        let guest = EntryTile(item: item)
        let guestLayer = guest.layer ?? CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guestLayer.frame = CGRect(
            origin: CGPoint(x: bounds.midX + CGFloat.random(in: -12...12) - item.size.width / 2,
                            y: bounds.height - 24 + (1 - scale) * item.size.height * 0.5),
            size: item.size)
        guestLayer.transform = CATransform3DRotate(CATransform3DMakeScale(scale, scale, 1),
                                                   jitter, 0, 0, 1)
        layer?.insertSublayer(guestLayer, below: lidContainer)
        CATransaction.commit()

        SpringCore.shared.scaleItem(guestLayer, to: scale,
                                    preset: SpringCatalog.groupMotion)
        let lid = SpringCore.shared.animateResponse(
            keyPath: "opacity",
            from: NSNumber(value: Double.leastNormalMagnitude),
            to: NSNumber(value: 1),
            preset: SpringCatalog.Preset(stiffness: 100, damping: SpringCatalog.criticalDamping,
                                         mass: mass))
        SpringCore.shared.add(lid, to: lidContainer, key: "rayLite.lidIn")
    }
}
