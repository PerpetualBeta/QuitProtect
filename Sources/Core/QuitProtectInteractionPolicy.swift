import Foundation

public final class StatusItemVisibilityStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public var isVisible: Bool { !defaults.bool(forKey: key) }

    @discardableResult
    public func setVisible(_ visible: Bool) -> Bool {
        guard visible != isVisible else { return false }
        defaults.set(!visible, forKey: key)
        return true
    }
}

public enum QuitProtectMenuContract {
    public static let settingsKeyEquivalent = ","
    public static let quitKeyEquivalent = "q"

    public static func quitTitle(appName: String) -> String { "Quit \(appName)" }
}

public struct PermissionRefreshPolicy {
    public private(set) var isGranted: Bool
    public private(set) var quietUntil: TimeInterval = -.infinity

    public init(isGranted: Bool) {
        self.isGranted = isGranted
    }

    public mutating func announceChange(at time: TimeInterval, settleFor: TimeInterval) {
        quietUntil = time + settleFor
    }

    @discardableResult
    public mutating func reread(at time: TimeInterval, value: Bool) -> Bool {
        guard time >= quietUntil else { return false }
        let changed = value != isGranted
        isGranted = value
        return changed
    }
}

public enum SettingsWindowSizing {
    public static func contentSize(
        fittingWidth: Double,
        fittingHeight: Double,
        visibleWidth: Double,
        visibleHeight: Double,
        minimumWidth: Double = 420,
        minimumHeight: Double = 400,
        displayFraction: Double = 0.8,
        chromeHeight: Double
    ) -> (width: Double, height: Double) {
        let widthCeiling = max(visibleWidth * displayFraction, minimumWidth)
        let heightCeiling = max(visibleHeight * displayFraction - chromeHeight, minimumHeight)
        return (
            min(max(fittingWidth, minimumWidth), widthCeiling),
            min(max(fittingHeight, minimumHeight), heightCeiling)
        )
    }
}
