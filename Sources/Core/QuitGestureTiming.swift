import Foundation

/// One timing value the Settings pickers offer, paired with the string it renders under.
public struct QuitGestureTimingOption: Identifiable, Hashable, Sendable {
    public let value: TimeInterval
    public let localizationKey: String

    public var id: TimeInterval { value }

    /// Used only when the running bundle has no string for `localizationKey`.
    /// `tools/check-localisation.sh` fails the build when a catalog key has no
    /// `Localizable.strings` entry, so this is a backstop for an unlocalised dev
    /// build. It is deliberately derived rather than stored: a hand-written label
    /// would be a third copy of a string the value and the `.strings` files already
    /// carry, and the copies drift.
    public var fallbackLabel: String { "\(value)s" }

    public init(value: TimeInterval, localizationKey: String) {
        self.value = value
        self.localizationKey = localizationKey
    }
}

/// The single catalog of gesture timings: which values the app supports, what it
/// falls back to, where it persists them, and how it repairs a value that is not
/// one of them. Settings renders this catalog, the coordinator is checked against
/// it, and the preference store is repaired towards it.
public enum QuitGestureTiming {
    /// The UserDefaults keys these settings persist under. They live beside the
    /// catalog so the reader and the writer cannot drift apart.
    public enum DefaultsKey {
        public static let holdDuration = "holdDuration"
        public static let doublePressInterval = "doublePressInterval"
    }

    public static let holdOptions: [QuitGestureTimingOption] = [
        .init(value: 0.5, localizationKey: "duration.0.5_seconds"),
        .init(value: 1.0, localizationKey: "duration.1.0_seconds"),
        .init(value: 1.5, localizationKey: "duration.1.5_seconds"),
        .init(value: 2.0, localizationKey: "duration.2.0_seconds"),
    ]

    public static let doublePressOptions: [QuitGestureTimingOption] = [
        .init(value: 0.3, localizationKey: "duration.0.3_seconds"),
        .init(value: 0.4, localizationKey: "duration.0.4_seconds"),
        .init(value: 0.5, localizationKey: "duration.0.5_seconds"),
        .init(value: 0.75, localizationKey: "duration.0.75_seconds"),
    ]

    public static let supportedHoldDurations: [TimeInterval] = holdOptions.map(\.value)
    public static let supportedDoublePressIntervals: [TimeInterval] = doublePressOptions.map(\.value)

    public static let defaultHoldDuration: TimeInterval = 1.0
    public static let defaultDoublePressInterval: TimeInterval = 0.4

    // MARK: - Normalising

    /// A hold guard gets STRICTER as it gets longer, because command-Q has to stay down
    /// for more time before the quit goes through. An unsupported value therefore snaps
    /// up to the next option, and anything past the top of the catalog snaps to the top.
    /// Snapping towards the default instead would silently weaken a guard that somebody
    /// deliberately set high.
    public static func normalizedHoldDuration(_ value: TimeInterval) -> TimeInterval {
        snapped(
            value,
            to: supportedHoldDurations,
            fallingBackTo: defaultHoldDuration,
            stricterIs: .larger
        )
    }

    /// A double-press window gets STRICTER as it gets shorter, because the second press
    /// has less time to land. An unsupported value therefore snaps down, by the same
    /// argument as `normalizedHoldDuration`.
    public static func normalizedDoublePressInterval(_ value: TimeInterval) -> TimeInterval {
        snapped(
            value,
            to: supportedDoublePressIntervals,
            fallingBackTo: defaultDoublePressInterval,
            stricterIs: .smaller
        )
    }

    /// For a caller that is supposed to be holding a catalog value already: the gesture
    /// coordinator's API, not the preference store. A miss there is a programming error
    /// rather than a tampered plist, so it traps in debug and still corrects in release.
    /// Without this, passing an unsupported value to the coordinator quietly runs the
    /// gesture at some other timing and the test that depends on it fails for no visible
    /// reason.
    public static func checkedHoldDuration(
        _ value: TimeInterval,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> TimeInterval {
        let normalized = normalizedHoldDuration(value)
        if value != normalized {
            assertionFailure(
                "hold duration \(value) is not in the timing catalog; using \(normalized)",
                file: file,
                line: line
            )
        }
        return normalized
    }

    /// The double-press counterpart of `checkedHoldDuration`.
    public static func checkedDoublePressInterval(
        _ value: TimeInterval,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> TimeInterval {
        let normalized = normalizedDoublePressInterval(value)
        if value != normalized {
            assertionFailure(
                "double-press interval \(value) is not in the timing catalog; using \(normalized)",
                file: file,
                line: line
            )
        }
        return normalized
    }

    private enum StricterDirection {
        case larger
        case smaller
    }

    private static func snapped(
        _ value: TimeInterval,
        to options: [TimeInterval],
        fallingBackTo defaultValue: TimeInterval,
        stricterIs direction: StricterDirection
    ) -> TimeInterval {
        // A negative, zero, NaN or infinite duration is not a preference to honour, so
        // it goes to the shipped default rather than to an end of the catalog.
        guard value.isFinite, value > 0 else { return defaultValue }

        let sorted = options.sorted()
        switch direction {
        case .larger:
            return sorted.first { $0 >= value } ?? sorted.last ?? defaultValue
        case .smaller:
            return sorted.last { $0 <= value } ?? sorted.first ?? defaultValue
        }
    }

    // MARK: - Persistence

    /// Reads the persisted hold duration and repairs the stored value when it is not one
    /// the catalog offers.
    ///
    /// Named `resolve` rather than `load` because it WRITES. A value the Settings picker
    /// cannot represent would otherwise sit in the plist for good, so the app and its own
    /// preferences would disagree on every launch and the picker would show something the
    /// engine is not using. An absent key is left absent, so a later change to the shipped
    /// default still reaches anybody who never touched the setting.
    public static func resolveHoldDuration(from defaults: UserDefaults) -> TimeInterval {
        resolve(
            from: defaults,
            key: DefaultsKey.holdDuration,
            defaultValue: defaultHoldDuration,
            normalize: normalizedHoldDuration
        )
    }

    /// The double-press counterpart of `resolveHoldDuration`, with the same write
    /// behaviour and the same reason for it.
    public static func resolveDoublePressInterval(from defaults: UserDefaults) -> TimeInterval {
        resolve(
            from: defaults,
            key: DefaultsKey.doublePressInterval,
            defaultValue: defaultDoublePressInterval,
            normalize: normalizedDoublePressInterval
        )
    }

    private enum StoredTiming {
        case absent
        /// A number the plist already holds as a number.
        case number(TimeInterval)
        /// A number written as text, which is what `defaults write` produces unless the
        /// caller passes `-float`.
        case text(TimeInterval)
        /// Present, but holding nothing a duration can be read out of.
        case unreadable
    }

    private static func storedTiming(in defaults: UserDefaults, key: String) -> StoredTiming {
        guard let object = defaults.object(forKey: key) else { return .absent }
        if let number = object as? NSNumber { return .number(number.doubleValue) }
        // `defaults write cc.jorviksoftware.QuitProtect holdDuration 1.5` writes a STRING,
        // and that is the mistake somebody actually makes at the command line. Read the
        // number they meant instead of throwing the intent away.
        if let text = object as? String, let parsed = Double(text) { return .text(parsed) }
        return .unreadable
    }

    private static func resolve(
        from defaults: UserDefaults,
        key: String,
        defaultValue: TimeInterval,
        normalize: (TimeInterval) -> TimeInterval
    ) -> TimeInterval {
        switch storedTiming(in: defaults, key: key) {
        case .absent:
            return defaultValue

        case let .number(stored):
            let normalized = normalize(stored)
            if stored != normalized { defaults.set(normalized, forKey: key) }
            return normalized

        case let .text(stored):
            // Rewrite even when the value is already supported: leaving it as text means
            // every future reader has to know to parse it.
            let normalized = normalize(stored)
            defaults.set(normalized, forKey: key)
            return normalized

        case .unreadable:
            // A dictionary, a date, a word. There is nothing to snap towards, so replace
            // it with the shipped default rather than fall back silently on every launch.
            defaults.set(defaultValue, forKey: key)
            return defaultValue
        }
    }
}
