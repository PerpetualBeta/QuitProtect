import Foundation

public enum QuitGestureTiming {
    // These are the discrete values exposed by QuitProtectSettingsContent. Additions to the
    // settings UI and this validation policy must remain in sync.
    public static let supportedHoldDurations: [TimeInterval] = [0.5, 1.0, 1.5, 2.0]
    public static let supportedDoublePressIntervals: [TimeInterval] = [0.3, 0.4, 0.5, 0.75]

    public static let defaultHoldDuration: TimeInterval = 1.0
    public static let defaultDoublePressInterval: TimeInterval = 0.4

    public static func normalizedHoldDuration(_ value: TimeInterval) -> TimeInterval {
        supportedHoldDurations.contains(value) ? value : defaultHoldDuration
    }

    public static func normalizedDoublePressInterval(_ value: TimeInterval) -> TimeInterval {
        supportedDoublePressIntervals.contains(value) ? value : defaultDoublePressInterval
    }

    public static func loadHoldDuration(from defaults: UserDefaults, key: String) -> TimeInterval {
        loadNormalized(
            from: defaults,
            key: key,
            defaultValue: defaultHoldDuration,
            normalize: normalizedHoldDuration
        )
    }

    public static func loadDoublePressInterval(
        from defaults: UserDefaults,
        key: String
    ) -> TimeInterval {
        loadNormalized(
            from: defaults,
            key: key,
            defaultValue: defaultDoublePressInterval,
            normalize: normalizedDoublePressInterval
        )
    }

    private static func loadNormalized(
        from defaults: UserDefaults,
        key: String,
        defaultValue: TimeInterval,
        normalize: (TimeInterval) -> TimeInterval
    ) -> TimeInterval {
        let stored = defaults.object(forKey: key) as? TimeInterval
        let normalized = normalize(stored ?? defaultValue)
        if stored != normalized { defaults.set(normalized, forKey: key) }
        return normalized
    }
}
