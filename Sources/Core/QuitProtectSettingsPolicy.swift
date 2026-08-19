public enum QuitProtectSettingsPolicy {
    public static let defaultHoldDuration = 1.0
    public static let defaultDoublePressInterval = 0.4
    public static let holdDurations = [0.5, 1.0, 1.5, 2.0]
    public static let doublePressIntervals = [0.3, 0.4, 0.5, 0.75]

    public static func validHoldDuration(_ value: Double) -> Bool {
        holdDurations.contains(value)
    }

    public static func validDoublePressInterval(_ value: Double) -> Bool {
        doublePressIntervals.contains(value)
    }
}
