import Foundation

public enum SpringCatalog {
    public static let criticalDamping = Double.greatestFiniteMagnitude

    public struct Preset: Sendable {
        public let stiffness: Double
        public let damping: Double
        public let mass: Double
        public let initialVelocity: Double
        public let allowsOverdamping: Bool

        public init(stiffness: Double, damping: Double, mass: Double = 1,
                    initialVelocity: Double = 0, allowsOverdamping: Bool = false) {
            self.stiffness = stiffness
            self.damping = damping
            self.mass = mass
            self.initialVelocity = initialVelocity
            self.allowsOverdamping = allowsOverdamping
        }
    }

    public static func itemMoveLadder(_ probe: Double?) -> Preset {
        let stiffness = (probe ?? 1) * 400 + 400
        return Preset(stiffness: min(stiffness, 800),
                      damping: criticalDamping)
    }

    public static let containerTransform = Preset(stiffness: 100, damping: criticalDamping)
    public static let itemSnap = Preset(stiffness: 400, damping: criticalDamping)
    public static let nudgeSettle = Preset(stiffness: 600, damping: 62)
    public static let slideIn = Preset(stiffness: 100, damping: criticalDamping)

    public static func lidMass(_ probe: Double? = nil) -> Double {
        let ladder = (probe ?? 1) * 0.32 + 0.24
        return min(ladder, 0.56)
    }
}
