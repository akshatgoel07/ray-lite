import QuartzCore

@MainActor
public final class SpringCore {
    public static let shared = SpringCore()

    public enum CancellationBehavior {
        case restoreInitialValue
        case keepCurrentValue
    }

    private static let initialValueKey = "rayLite.initialValue"

    public func springAnimation(keyPath: String,
                                from: Any,
                                to: Any,
                                preset: SpringCatalog.Preset) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.damping = preset.damping
        animation.stiffness = preset.stiffness
        animation.mass = preset.mass
        animation.initialVelocity = preset.initialVelocity
        animation.allowsOverdamping = preset.allowsOverdamping
        animation.autoreverses = false
        animation.duration = animation.settlingDuration
        return animation
    }

    public func add(_ animation: CABasicAnimation, to layer: CALayer, key: String) {
        guard let keyPath = animation.keyPath, let target = animation.toValue else {
            preconditionFailure("An animation requires a key path and a target value.")
        }
        let current = layer.presentation()?.value(forKeyPath: keyPath)
            ?? layer.value(forKeyPath: keyPath)
        let transition = animation.copy() as! CABasicAnimation
        transition.fromValue = current
        transition.setValue(current, forKey: Self.initialValueKey)
        transition.fillMode = .removed
        transition.isRemovedOnCompletion = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(target, forKeyPath: keyPath)
        removeAnimations(from: layer, keyPath: keyPath)
        layer.add(transition, forKey: key)
        CATransaction.commit()
    }

    public func fade(_ layer: CALayer, to opacity: Float, duration: CFTimeInterval, key: String) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        add(animation, to: layer, key: key)
    }

    public func cancel(_ layer: CALayer, keyPath: String,
                       behavior: CancellationBehavior) {
        let keys = animationKeys(in: layer, keyPath: keyPath)
        guard let key = keys.first, let animation = layer.animation(forKey: key) else { return }
        let value: Any?
        switch behavior {
        case .restoreInitialValue:
            value = animation.value(forKey: Self.initialValueKey)
        case .keepCurrentValue:
            value = layer.presentation()?.value(forKeyPath: keyPath)
                ?? layer.value(forKeyPath: keyPath)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        removeAnimations(from: layer, keyPath: keyPath)
        CATransaction.commit()
    }

    private func animationKeys(in layer: CALayer, keyPath: String) -> [String] {
        (layer.animationKeys() ?? []).filter {
            (layer.animation(forKey: $0) as? CAPropertyAnimation)?.keyPath == keyPath
        }
    }

    private func removeAnimations(from layer: CALayer, keyPath: String) {
        for key in animationKeys(in: layer, keyPath: keyPath) {
            layer.removeAnimation(forKey: key)
        }
    }

    public func moveItem(_ layer: CALayer, to point: CGPoint,
                         preset: SpringCatalog.Preset) {
        add(springAnimation(keyPath: "position",
                            from: layer.presentation()?.position ?? layer.position,
                            to: point,
                            preset: preset),
            to: layer, key: "rayLite.position")
    }

    public func scaleItem(_ layer: CALayer, to scale: CGFloat,
                          preset: SpringCatalog.Preset) {
        add(springAnimation(keyPath: "transform.scale",
                            from: layer.value(forKeyPath: "transform.scale") as Any,
                            to: scale,
                            preset: preset),
            to: layer, key: "rayLite.scale")
    }

    public func slide(_ layer: CALayer, downBy delta: CGFloat,
                      preset: SpringCatalog.Preset) {
        let from = NSValue(caTransform3D: layer.transform)
        let to = NSValue(caTransform3D: CATransform3DTranslate(layer.transform, 0, delta, 0))
        add(springAnimation(keyPath: "transform", from: from, to: to, preset: preset),
            to: layer, key: "rayLite.slide")
    }
}
