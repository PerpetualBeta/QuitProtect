import AppKit
import ApplicationServices

// MARK: - Quit mode

enum QuitMode: Int {
    case doublePress = 0
    case holdToQuit  = 1

    var displayName: String {
        switch self {
        case .doublePress: "Double-press ⌘Q"
        case .holdToQuit:  "Hold ⌘Q"
        }
    }
}

// MARK: - Module-level state for C-compatible CGEvent tap callback

private var _quitMode: QuitMode = .doublePress
private var _holdDuration: Double = 1.0
private var _doublePressInterval: Double = 0.4

// Double-press state
private var _lastQKeyDownTime: CFAbsoluteTime = 0
private var _waitingForSecondPress = false

// Hold state
private var _qKeyDownStart: CFAbsoluteTime = 0
private var _qKeyIsHeld = false
private var _holdConfirmed = false

// Stats
private var _blockedCount: Int = 0

// Tap reference for re-enable
private var _quitProtectTap: CFMachPort?

// Callback to notify UI of blocked quit
private var _onBlocked: (() -> Void)?

// MARK: - CGEvent tap callback

private func quitProtectCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Auto-re-enable if macOS disabled the tap
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = _quitProtectTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
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
    if isQKey && type == .keyUp && (_qKeyIsHeld || _waitingForSecondPress) {
        if _qKeyIsHeld && !_holdConfirmed {
            _blockedCount += 1
        }
        _qKeyIsHeld = false
        _holdConfirmed = false
        return nil
    }

    guard isQKey && isCmdOnly else {
        // If ⌘ was released while holding Q, reset hold state
        if _qKeyIsHeld && type == .flagsChanged {
            if !_holdConfirmed { _blockedCount += 1 }
            _qKeyIsHeld = false
            _holdConfirmed = false
        }
        return Unmanaged.passRetained(event)
    }

    // Don't protect QuitProtect itself
    if let frontApp = NSWorkspace.shared.frontmostApplication,
       frontApp.bundleIdentifier == "cc.jorviksoftware.QuitProtect" {
        return Unmanaged.passRetained(event)
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
        return Unmanaged.passRetained(event)
    }

    // Ignore key repeats (auto-repeat while holding)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if isRepeat {
        return nil // consume repeats
    }

    let now = CFAbsoluteTimeGetCurrent()

    if _waitingForSecondPress && (now - _lastQKeyDownTime) < _doublePressInterval {
        // Second press within window — allow the quit through
        _waitingForSecondPress = false
        _lastQKeyDownTime = 0
        return Unmanaged.passRetained(event)
    }

    // First press — block and start waiting
    _waitingForSecondPress = true
    _lastQKeyDownTime = now

    // Count as blocked only if the user doesn't follow through
    let interval = _doublePressInterval
    DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
        if _waitingForSecondPress && (CFAbsoluteTimeGetCurrent() - _lastQKeyDownTime) >= interval {
            _waitingForSecondPress = false
            _blockedCount += 1
        }
    }

    return nil // consume first press
}

// MARK: - Hold handler

private func handleHold(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .keyDown {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if !_qKeyIsHeld {
            // Initial key down — start the hold timer
            _qKeyIsHeld = true
            _qKeyDownStart = CFAbsoluteTimeGetCurrent()
            _holdConfirmed = false
        } else if isRepeat && !_holdConfirmed {
            // Check if held long enough
            let elapsed = CFAbsoluteTimeGetCurrent() - _qKeyDownStart
            if elapsed >= _holdDuration {
                _holdConfirmed = true
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
        _qKeyIsHeld = false
        _holdConfirmed = false
        return nil // consume the key-up too
    }

    return Unmanaged.passRetained(event)
}

// MARK: - QuitProtectEngine

@MainActor
@Observable
final class QuitProtectEngine {
    var isActive: Bool = false
    var permissionGranted: Bool = false
    var blockedCount: Int { _blockedCount }

    private var eventTap: CFMachPort?
    private var permissionTimer: Timer?
    private var pendingMode: QuitMode = .doublePress
    private var pendingHoldDuration: Double = 1.0
    private var pendingDoublePressInterval: Double = 0.4

    // MARK: - Public API

    func start(mode: QuitMode, holdDuration: Double, doublePressInterval: Double) {
        guard !isActive else { return }

        _quitMode = mode
        _holdDuration = holdDuration
        _doublePressInterval = doublePressInterval
        _waitingForSecondPress = false
        _qKeyIsHeld = false
        _holdConfirmed = false

        pendingMode = mode
        pendingHoldDuration = holdDuration
        pendingDoublePressInterval = doublePressInterval

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permissionGranted = trusted

        if trusted {
            if tryCreateEventTap() {
                isActive = true
            }
        } else {
            // Poll until permission is granted
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    Task { @MainActor in
                        guard let self else { return }
                        self.permissionGranted = true
                        if self.tryCreateEventTap() {
                            self.isActive = true
                        }
                    }
                    timer.invalidate()
                }
            }
        }
    }

    func stop() {
        isActive = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        _quitProtectTap = nil
        _waitingForSecondPress = false
        _qKeyIsHeld = false
        _holdConfirmed = false
    }

    func updateMode(_ mode: QuitMode) {
        _quitMode = mode
        _waitingForSecondPress = false
        _qKeyIsHeld = false
        _holdConfirmed = false
    }

    func updateHoldDuration(_ duration: Double) {
        _holdDuration = duration
    }

    func updateDoublePressInterval(_ interval: Double) {
        _doublePressInterval = interval
    }

    // MARK: - CGEvent tap

    private func tryCreateEventTap() -> Bool {
        if eventTap != nil { return true }

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
        ) else {
            return false
        }

        eventTap = tap
        _quitProtectTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
