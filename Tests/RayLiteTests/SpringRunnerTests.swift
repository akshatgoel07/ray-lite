import QuartzCore
import Testing
@testable import RayLite

@MainActor
struct SpringRunnerTests {
    private let runner = SpringCore.shared

    @Test func moveCommitsTargetAndRemovalKeepsIt() throws {
        let layer = CALayer()
        let initial = CGPoint(x: 12, y: 24)
        let target = CGPoint(x: 120, y: 240)
        layer.position = initial

        runner.moveItem(layer, to: target, preset: SpringCatalog.itemSnap)

        let animation = try #require(layer.animation(forKey: "rayLite.position") as? CASpringAnimation)
        #expect(layer.position == target)
        #expect((animation.fromValue as? NSValue)?.pointValue == initial)
        #expect((animation.toValue as? NSValue)?.pointValue == target)
        #expect(animation.isRemovedOnCompletion)
        #expect(animation.fillMode == .removed)

        layer.removeAnimation(forKey: "rayLite.position")

        #expect(layer.position == target)
    }

    @Test func scaleUsesModelValueWhenPresentationIsMissing() throws {
        let layer = CALayer()
        layer.setValue(0.6, forKeyPath: "transform.scale")

        runner.scaleItem(layer, to: 1.4, preset: SpringCatalog.containerTransform)

        let animation = try #require(layer.animation(forKey: "rayLite.scale") as? CASpringAnimation)
        let start = try #require(animation.fromValue as? NSNumber).doubleValue
        let target = try #require(layer.value(forKeyPath: "transform.scale") as? NSNumber).doubleValue
        #expect(abs(start - 0.6) < 0.000001)
        #expect(abs(target - 1.4) < 0.000001)
    }

    @Test func replacementKeepsOneAnimationForEachProperty() throws {
        CATransaction.begin()
        defer { CATransaction.commit() }
        let layer = CALayer()
        runner.moveItem(layer, to: CGPoint(x: 10, y: 20), preset: SpringCatalog.itemSnap)
        runner.scaleItem(layer, to: 0.5, preset: SpringCatalog.itemSnap)
        let target = CGPoint(x: 30, y: 40)

        runner.moveItem(layer, to: target, preset: SpringCatalog.itemSnap)

        let animation = try #require(layer.animation(forKey: "rayLite.position") as? CASpringAnimation)
        #expect(Set(layer.animationKeys() ?? []) == Set(["rayLite.position", "rayLite.scale"]))
        #expect((animation.toValue as? NSValue)?.pointValue == target)
        #expect(layer.position == target)
    }

    @Test func replacementWithAnotherKeyStillReplacesTheProperty() throws {
        CATransaction.begin()
        defer { CATransaction.commit() }
        let layer = CALayer()
        let first = runner.springAnimation(keyPath: "opacity", from: 0, to: 0.4,
                                           preset: SpringCatalog.itemSnap)
        runner.add(first, to: layer, key: "first")
        let second = runner.springAnimation(keyPath: "opacity", from: 0, to: 0.8,
                                            preset: SpringCatalog.itemSnap)
        #expect(second.duration > 0)

        runner.add(second, to: layer, key: "second")

        let animation = try #require(layer.animation(forKey: "second") as? CASpringAnimation)
        #expect(animation.duration > 0)
        #expect(layer.animationKeys() == ["second"])
        #expect(layer.opacity == 0.8)
    }

    @Test func restoreCancelRestoresInitialValueAndLeavesOtherProperties() {
        let layer = CALayer()
        let initial = CGPoint(x: 8, y: 16)
        layer.position = initial
        runner.moveItem(layer, to: CGPoint(x: 80, y: 160), preset: SpringCatalog.itemSnap)
        runner.scaleItem(layer, to: 0.7, preset: SpringCatalog.itemSnap)

        runner.cancel(layer, keyPath: "position", behavior: .restoreInitialValue)

        #expect(layer.position == initial)
        #expect(layer.animationKeys() == ["rayLite.scale"])
    }

    @Test func keepCancelUsesModelValueWhenPresentationIsMissing() {
        let layer = CALayer()
        let target = CGPoint(x: 80, y: 160)
        runner.moveItem(layer, to: target, preset: SpringCatalog.itemSnap)

        runner.cancel(layer, keyPath: "position", behavior: .keepCurrentValue)

        #expect(layer.position == target)
        #expect(layer.animationKeys()?.isEmpty ?? true)
    }

    @Test func replacementStartsAtPresentationValue() throws {
        let layer = PresentedLayer()
        let visible = PresentedLayer()
        layer.position = CGPoint(x: 1, y: 2)
        runner.moveItem(layer, to: CGPoint(x: 100, y: 200), preset: SpringCatalog.itemSnap)
        visible.position = CGPoint(x: 30, y: 60)
        layer.visibleLayer = visible

        runner.moveItem(layer, to: CGPoint(x: 300, y: 600), preset: SpringCatalog.itemSnap)

        let animation = try #require(layer.animation(forKey: "rayLite.position") as? CASpringAnimation)
        #expect((animation.fromValue as? NSValue)?.pointValue == visible.position)

        runner.cancel(layer, keyPath: "position", behavior: .restoreInitialValue)

        #expect(layer.position == visible.position)
    }

    @Test func keepCancelHoldsPresentationValue() {
        CATransaction.begin()
        defer { CATransaction.commit() }
        let layer = PresentedLayer()
        let visible = PresentedLayer()
        runner.scaleItem(layer, to: 0.5, preset: SpringCatalog.itemSnap)
        visible.setValue(0.75, forKeyPath: "transform.scale")
        layer.visibleLayer = visible

        #expect(layer.animationKeys() == ["rayLite.scale"])
        #expect((layer.presentation()?.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue == 0.75)
        runner.cancel(layer, keyPath: "transform.scale", behavior: .keepCurrentValue)

        #expect((layer.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue == 0.75)
        #expect(layer.animationKeys()?.isEmpty ?? true)
    }

    @Test func scaleReplacementStartsAtPresentationValue() throws {
        let layer = PresentedLayer()
        let visible = PresentedLayer()
        runner.scaleItem(layer, to: 0.5, preset: SpringCatalog.itemSnap)
        visible.setValue(0.75, forKeyPath: "transform.scale")
        layer.visibleLayer = visible

        runner.scaleItem(layer, to: 1.5, preset: SpringCatalog.itemSnap)

        let animation = try #require(layer.animation(forKey: "rayLite.scale") as? CASpringAnimation)
        #expect((animation.fromValue as? NSNumber)?.doubleValue == 0.75)
        #expect((layer.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue == 1.5)
        #expect(layer.animationKeys() == ["rayLite.scale"])
    }

    @Test func slideCommitsTargetTransform() throws {
        let layer = CALayer()
        layer.transform = CATransform3DMakeScale(0.5, 0.5, 1)
        let target = CATransform3DTranslate(layer.transform, 0, 30, 0)

        runner.slide(layer, downBy: 30, preset: SpringCatalog.slideIn)

        let animation = try #require(layer.animation(forKey: "rayLite.slide") as? CASpringAnimation)
        #expect(CATransform3DEqualToTransform(layer.transform, target))
        #expect(CATransform3DEqualToTransform(
            try #require(animation.toValue as? NSValue).caTransform3DValue, target))
    }

    @Test func opacityReplacementAndCancelRetainTheVisibleValue() throws {
        let layer = PresentedLayer()
        let visible = PresentedLayer()
        layer.opacity = 0
        visible.opacity = 0.43
        layer.visibleLayer = visible
        runner.fade(layer, to: 1, duration: 0.14, key: "rayLite.noteFade")
        runner.cancel(layer, keyPath: "opacity", behavior: .keepCurrentValue)
        #expect(layer.opacity == 0.43)
        #expect(layer.animationKeys()?.isEmpty ?? true)
        runner.fade(layer, to: 1, duration: 0.1, key: "rayLite.inputOpacity")
        let animation = try #require(layer.animation(forKey: "rayLite.inputOpacity") as? CABasicAnimation)
        #expect(abs(try #require(animation.fromValue as? NSNumber).floatValue - 0.43) < 0.00001)
        #expect(animation.duration == 0.1)
        #expect(layer.opacity == 1)
        layer.removeAllAnimations()
        #expect(layer.opacity == 1)
    }

    @Test func cameraCancelRetainsScaleAndTranslationTogether() throws {
        let layer = PresentedLayer()
        let visible = PresentedLayer()
        visible.sublayerTransform = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: 0.7, b: 0, c: 0, d: 0.7, tx: 80, ty: -40))
        layer.visibleLayer = visible
        let target = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: 1.5, b: 0, c: 0, d: 1.5, tx: -100, ty: 200))
        let animation = runner.springAnimation(keyPath: "sublayerTransform",
            from: NSValue(caTransform3D: CATransform3DIdentity), to: NSValue(caTransform3D: target),
            preset: SpringCatalog.containerTransform)
        runner.add(animation, to: layer, key: "rayLite.camera")
        #expect(CATransform3DEqualToTransform(layer.sublayerTransform, target))
        runner.cancel(layer, keyPath: "sublayerTransform", behavior: .keepCurrentValue)
        #expect(CATransform3DEqualToTransform(layer.sublayerTransform, visible.sublayerTransform))
        #expect(layer.animationKeys()?.isEmpty ?? true)
    }

    @Test func cancellationWithoutAnAnimationKeepsTheModel() {
        let layer = CALayer()
        layer.position = CGPoint(x: 12, y: 24)

        runner.cancel(layer, keyPath: "position", behavior: .restoreInitialValue)
        runner.cancel(layer, keyPath: "position", behavior: .keepCurrentValue)

        #expect(layer.position == CGPoint(x: 12, y: 24))
        #expect(layer.animationKeys()?.isEmpty ?? true)
    }
}

private final class PresentedLayer: CALayer {
    var visibleLayer: PresentedLayer?

    override func presentation() -> Self? {
        visibleLayer as? Self
    }
}
