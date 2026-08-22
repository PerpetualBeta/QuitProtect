import AppKit
import ApplicationServices
import QuitProtectCore

// MARK: - Quit mode

enum QuitMode: Int {
    case doublePress = 0
    case holdToQuit  = 1

    var displayName: String {
        switch self {
        case .doublePress:
            L10n.string("quit_mode.double_press", defaultValue: "Double-press ⌘Q")
        case .holdToQuit:
            L10n.string("quit_mode.hold_to_quit", defaultValue: "Hold ⌘Q")
        }
    }
}

enum QuitGuidanceEvent {
    case began(QuitMode)
    case resolved
}

// MARK: - Module-level state for C-compatible CGEvent tap callback

private var _quitMode: QuitMode = .doublePress
private var _holdDuration: Double = 1.0
private var _doublePressInterval: Double = 0.4

// Double-press state
// Stats
private var _gestureState = QuitGestureStateMachine()

// Callback to keep optional UI guidance aligned with the active quit gesture
private var _onQuitGuidanceEvent: ((QuitGuidanceEvent) -> Void)?

// The C callback requests recovery; the engine changes tap/source ownership on the main run loop
// after the callback returns.
private var _requestEventTapRecovery: (() -> Void)?

private func notifyQuitGuidance(_ event: QuitGuidanceEvent) {
    DispatchQueue.main.async {
        _onQuitGuidanceEvent?(event)
    }
}

// MARK: - CGEvent tap callback

private func quitProtectCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Auto-re-enable if macOS disabled the tap
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        notifyQuitGuidance(.resolved)
        _requestEventTapRecovery?()
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    // Q key = keyCode 12, check for ⌘ modifier (and not ⌘⇧Q which is log out)
    let isQKey = keyCode == 12
    let isCmdOnly = flags.contains(.maskCommand)
        && !flags.contains(.maskShift)
        && !flags.contains(.maskControl)
        && !flags.contains(.maskAlternate)

    // If Q key released while we're in an active hold/wait state, reset even if
    // ⌘ was released first (keyUp won't have .maskCommand in that case)
    if isQKey && type == .keyUp && (_gestureState.holding || _gestureState.waitingForSecondPress) {
        if _gestureState.holding {
            _ = _gestureState.holdReleased()
            notifyQuitGuidance(.resolved)
        }
        return nil
    }

    guard isQKey && isCmdOnly else {
        // If ⌘ was released while holding Q, reset hold state
        if _gestureState.holding && type == .flagsChanged {
            _ = _gestureState.holdReleased()
            notifyQuitGuidance(.resolved)
        }
        return Unmanaged.passUnretained(event)
    }

    // Don't protect QuitProtect itself
    if let frontApp = NSWorkspace.shared.frontmostApplication,
       frontApp.bundleIdentifier == "cc.jorviksoftware.QuitProtect" {
        return Unmanaged.passUnretained(event)
    }

    switch _quitMode {
    case .doublePress:
        return handleDoublePress(type: type, event: event)
    case .holdToQuit:
        return handleHold(type: type, event: event)
    }
}

// MARK: - Double-press handler

private func handleDoublePress(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    // Repeat-ness is a key-transition fact like any other, so the machine
    // consumes auto-repeats itself — every gesture decision in one place.
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let now = CFAbsoluteTimeGetCurrent()

    let action = _gestureState.doublePressKeyDown(
        now: now, interval: _doublePressInterval, isRepeat: isRepeat
    )
    if action == .consume { return nil }
    if action == .passThrough {
        // Second press within window — allow the quit through
        notifyQuitGuidance(.resolved)
        return Unmanaged.passUnretained(event)
    }

    // First press — block and start waiting
    notifyQuitGuidance(.began(.doublePress))

    // Count as blocked only if the user doesn't follow through
    let interval = _doublePressInterval
    DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
        let action = _gestureState.doublePressExpired(
            now: CFAbsoluteTimeGetCurrent(), interval: interval
        )
        if action == .blocked { notifyQuitGuidance(.resolved) }
    }

    return nil // consume first press
}

// MARK: - Hold handler

private func handleHold(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .keyDown {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if !_gestureState.holding {
            // Initial key down — start the hold timer
            _ = _gestureState.holdKeyDown(now: CFAbsoluteTimeGetCurrent())
            notifyQuitGuidance(.began(.holdToQuit))
        } else if isRepeat && !_gestureState.holdConfirmed {
            // Check if held long enough
            let action = _gestureState.holdDurationReached(
                now: CFAbsoluteTimeGetCurrent(), duration: _holdDuration
            )
            if action == .quit {
                notifyQuitGuidance(.resolved)
                // Synthesise ⌘Q to actually quit the app
                if let qDown = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true),
                   let qUp = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false) {
                    qDown.flags = .maskCommand
                    qUp.flags = .maskCommand
                    qDown.post(tap: .cgAnnotatedSessionEventTap)
                    qUp.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }
        return nil // consume all key-down events while holding
    }

    if type == .keyUp {
        // State reset and blocked count handled by the early Q-keyUp guard above
        _ = _gestureState.holdReleased()
        return nil // consume the key-up too
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - QuitProtectEngine

@MainActor
@Observable
final class QuitProtectEngine {
    private struct EventTapResources {
        let tap: CFMachPort
        let source: CFRunLoopSource
    }

    /// We *believe* protection is up: permission was granted and the tap was created.
    var isActive: Bool = false
    var blockedCount: Int { _gestureState.blockedCount }

    /// Is protection ACTUALLY in force, this instant?
    ///
    /// `isActive` records that we started successfully. It is not evidence that we still are. macOS
    /// invalidates the event tap the moment Accessibility permission is revoked, and nothing tells the
    /// app — the callback simply stops being called. Until this existed, revoking permission left the
    /// menu bar showing a filled icon and a ticked "Protection Active" over a dead tap, which is the
    /// one lie an app like this must never tell.
    ///
    /// Probed rather than remembered, so it stays honest even if the notification below never arrives.
    var isProtecting: Bool {
        isActive && eventTapLifecycle.isProtecting
    }

    /// Fired when protection comes up or goes down without the user asking — permission granted while
    /// we were waiting for it, or revoked mid-session. Neither is user-initiated, so the menu-bar icon
    /// has no other way to find out.
    @ObservationIgnored var onProtectionChanged: (() -> Void)?

    /// How often to re-check for a permission grant. There is no push notification for the grant
    /// itself, only for the database changing, so this is the floor on how long a user waits after
    /// ticking the box in System Settings.
    private static let permissionPollInterval: TimeInterval = 2.0

    private var permissionTimer: Timer?
    @ObservationIgnored private var trustObserver: NSObjectProtocol?
    @ObservationIgnored private lazy var eventTapLifecycle = EventTapLifecycleController<EventTapResources>(
        create: { [weak self] in self?.createEventTapResources() },
        isValid: { CFMachPortIsValid($0.tap) && CFRunLoopSourceIsValid($0.source) },
        isEnabled: { CGEvent.tapIsEnabled(tap: $0.tap) },
        enable: { CGEvent.tapEnable(tap: $0.tap, enable: true) },
        destroy: { [weak self] in self?.destroyEventTapResources($0) }
    )

    // MARK: - Lifecycle

    /// Registered for the life of the process — the engine is owned by the app delegate and outlives
    /// every other object here, so there is no teardown to pair this with.
    init() {
        _requestEventTapRecovery = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.recoverEventTapAfterDisable()
            }
        }
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrustChange() }
        }
    }

    /// React to the Accessibility permission database changing.
    ///
    /// `com.apple.accessibility.api` is undocumented but long-standing, and is the only push signal
    /// macOS offers here. It is treated as a prompt to go and look rather than as truth in itself:
    /// `isProtecting` probes the tap directly, so if this notification ever stopped arriving the UI
    /// would still tell the truth the next time it drew.
    private func handleTrustChange() {
        guard isActive, !AXIsProcessTrusted() else { return }

        // Revoked mid-session. The tap is already dead — clear the rest of the state and go back to
        // watching, so protection restores itself if the user grants permission again.
        stop()
        beginPollingForPermission()
        onProtectionChanged?()
    }

    // MARK: - Public API

    func setQuitGuidanceHandler(_ handler: @escaping (QuitGuidanceEvent) -> Void) {
        _onQuitGuidanceEvent = handler
    }

    func start(mode: QuitMode, holdDuration: Double, doublePressInterval: Double) {
        // A tap can die without a permission change. Clear the stale state first, or this becomes a
        // no-op and the user is left staring at an inactive icon they just clicked.
        if isActive && !isProtecting { stop() }
        guard !isActive else { return }

        _quitMode = mode
        _holdDuration = holdDuration
        _doublePressInterval = doublePressInterval
        _gestureState.reset()

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary

        if AXIsProcessTrustedWithOptions(options), eventTapLifecycle.start() {
            isActive = true
        } else {
            // Either permission is missing, or it is granted and the tap would not create anyway.
            // Both want the same treatment: keep watching. The second case used to fall through to
            // nothing at all, leaving the app inert with no protection and no path back to it.
            beginPollingForPermission()
        }
    }

    /// Watch for permission to appear, then bring protection up.
    ///
    /// Stands the old timer down first. `start()` guards only on `!isActive`, so before this every
    /// toggle of the menu item while unpermitted left another live timer behind — five toggles, five
    /// timers, all polling forever.
    private func beginPollingForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(
            withTimeInterval: Self.permissionPollInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard AXIsProcessTrusted(), self.eventTapLifecycle.start() else { return }

                // Retire the timer only once the tap genuinely exists. Retiring it on trust alone left
                // no retry if creation then failed — and because creation was deferred onto the main
                // actor, the timer had already gone by the time the answer was known.
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.isActive = true
                self.onProtectionChanged?()
            }
        }
    }

    func stop() {
        notifyQuitGuidance(.resolved)
        isActive = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        eventTapLifecycle.stop()
        _gestureState.reset()
    }

    func updateMode(_ mode: QuitMode) {
        notifyQuitGuidance(.resolved)
        _quitMode = mode
        _gestureState.reset()
    }

    func updateHoldDuration(_ duration: Double) {
        _holdDuration = duration
    }

    func updateDoublePressInterval(_ interval: Double) {
        _doublePressInterval = interval
    }

    // MARK: - CGEvent tap

    private func createEventTapResources() -> EventTapResources? {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)
                              | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: quitProtectCallback,
            userInfo: nil
        ) else { return nil }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return EventTapResources(tap: tap, source: source)
    }

    private func destroyEventTapResources(_ resources: EventTapResources) {
        if CFMachPortIsValid(resources.tap) {
            CGEvent.tapEnable(tap: resources.tap, enable: false)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), resources.source, .commonModes)
        CFRunLoopSourceInvalidate(resources.source)
        if CFMachPortIsValid(resources.tap) {
            CFMachPortInvalidate(resources.tap)
        }
    }

    private func recoverEventTapAfterDisable() {
        guard isActive else { return }

        if eventTapLifecycle.recoverAfterDisable() { return }

        isActive = false
        beginPollingForPermission()
        onProtectionChanged?()
    }
}
