import AppKit
import SwiftUI

private enum QuitToastL10n {
    static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Toast",
            bundle: .main,
            value: defaultValue,
            comment: ""
        )
    }

    static func format(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, defaultValue: defaultValue),
            locale: Locale.current,
            arguments: arguments
        )
    }
}

private final class QuitToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct QuitToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
    }
}

@MainActor
final class QuitToastController {
    private let panel: QuitToastPanel
    private var dismissWorkItem: DispatchWorkItem?
    private var displayGeneration = 0

    init() {
        panel = QuitToastPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
    }

    func show(
        mode: QuitMode,
        duration: TimeInterval,
        doublePressInterval: TimeInterval
    ) {
        dismissWorkItem?.cancel()
        displayGeneration += 1
        let generation = displayGeneration

        let message: String
        switch mode {
        case .doublePress:
            let interval = doublePressInterval.formatted(
                .number.precision(.fractionLength(1...2))
            )
            message = QuitToastL10n.format(
                "toast.double_press",
                defaultValue: "Press ⌘Q again within %@ seconds to quit",
                interval
            )
        case .holdToQuit:
            message = QuitToastL10n.string(
                "toast.hold_to_quit",
                defaultValue: "Keep holding ⌘Q to quit"
            )
        }

        let controller = NSHostingController(rootView: QuitToastView(message: message))
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        panel.contentViewController = controller
        panel.setContentSize(size)
        positionPanel(size: size)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hide(generation: generation)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(duration, 0.5),
            execute: workItem
        )
    }

    private func positionPanel(size: NSSize) {
        let pointerLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointerLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 36
        )
        panel.setFrameOrigin(origin)
    }

    private func hide(generation: Int) {
        guard generation == displayGeneration else { return }
        dismissWorkItem = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.displayGeneration else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

enum QuitToastSettings {
    private static let defaultsKey = "showQuitGuidance"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var label: String {
        QuitToastL10n.string(
            "settings.show_quit_guidance",
            defaultValue: "Show quit guidance"
        )
    }
}
