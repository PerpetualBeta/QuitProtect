import Foundation

public struct QuitGestureTimingOption: Identifiable, Hashable, Sendable {
    public let value: TimeInterval
    public let localizationKey: String
    public let defaultLabel: String

    public var id: TimeInterval { value }

    public init(value: TimeInterval, localizationKey: String, defaultLabel: String) {
        self.value = value
        self.localizationKey = localizationKey
        self.defaultLabel = defaultLabel
    }
}

public enum QuitGestureTiming {
    public static let holdOptions: [QuitGestureTimingOption] = [
        .init(value: 0.5, localizationKey: "duration.0.5_seconds", defaultLabel: "0.5s"),
        .init(value: 1.0, localizationKey: "duration.1.0_seconds", defaultLabel: "1.0s"),
        .init(value: 1.5, localizationKey: "duration.1.5_seconds", defaultLabel: "1.5s"),
        .init(value: 2.0, localizationKey: "duration.2.0_seconds", defaultLabel: "2.0s"),
    ]

    public static let doublePressOptions: [QuitGestureTimingOption] = [
        .init(value: 0.3, localizationKey: "duration.0.3_seconds", defaultLabel: "0.3s"),
        .init(value: 0.4, localizationKey: "duration.0.4_seconds", defaultLabel: "0.4s"),
        .init(value: 0.5, localizationKey: "duration.0.5_seconds", defaultLabel: "0.5s"),
        .init(value: 0.75, localizationKey: "duration.0.75_seconds", defaultLabel: "0.75s"),
    ]

    public static var supportedHoldDurations: [TimeInterval] { holdOptions.map(\.value) }
    public static var supportedDoublePressIntervals: [TimeInterval] {
        doublePressOptions.map(\.value)
    }

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
