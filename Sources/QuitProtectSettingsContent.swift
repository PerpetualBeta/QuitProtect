import SwiftUI

struct QuitProtectSettingsContent: View {
    let delegate: AppDelegate

    var body: some View {
        Section(L10n.string("settings.quit_mode", defaultValue: "Quit Mode")) {
            Picker(L10n.string("settings.mode", defaultValue: "Mode"), selection: Binding(
                get: { delegate.quitMode },
                set: { delegate.quitMode = $0 }
            )) {
                Text(L10n.string("quit_mode.double_press", defaultValue: "Double-press ⌘Q"))
                    .tag(QuitMode.doublePress)
                Text(L10n.string("quit_mode.hold_to_quit", defaultValue: "Hold ⌘Q"))
                    .tag(QuitMode.holdToQuit)
            }
            .pickerStyle(.radioGroup)

            if delegate.quitMode == .holdToQuit {
                HStack {
                    Text(L10n.string("settings.hold_duration", defaultValue: "Hold duration"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { delegate.holdDuration },
                        set: { delegate.holdDuration = $0 }
                    )) {
                        Text(L10n.string("duration.0.5_seconds", defaultValue: "0.5s")).tag(0.5)
                        Text(L10n.string("duration.1.0_seconds", defaultValue: "1.0s")).tag(1.0)
                        Text(L10n.string("duration.1.5_seconds", defaultValue: "1.5s")).tag(1.5)
                        Text(L10n.string("duration.2.0_seconds", defaultValue: "2.0s")).tag(2.0)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if delegate.quitMode == .doublePress {
                HStack {
                    Text(L10n.string("settings.press_interval", defaultValue: "Press interval"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { delegate.doublePressInterval },
                        set: { delegate.doublePressInterval = $0 }
                    )) {
                        Text(L10n.string("duration.0.3_seconds", defaultValue: "0.3s")).tag(0.3)
                        Text(L10n.string("duration.0.4_seconds", defaultValue: "0.4s")).tag(0.4)
                        Text(L10n.string("duration.0.5_seconds", defaultValue: "0.5s")).tag(0.5)
                        Text(L10n.string("duration.0.75_seconds", defaultValue: "0.75s")).tag(0.75)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }

        Section(L10n.string("settings.permissions", defaultValue: "Permissions")) {
            HStack {
                Text(L10n.string("settings.accessibility", defaultValue: "Accessibility"))
                Spacer()
                if AXIsProcessTrusted() {
                    Label(
                        L10n.string("settings.permission_granted", defaultValue: "Granted"),
                        systemImage: "checkmark.circle.fill"
                    )
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button(L10n.string("settings.grant_access", defaultValue: "Grant Access")) {
                        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                    .font(.caption)
                }
            }
        }

        MenuBarVisibilitySettings()

        MenuBarPillSettings { delegate.updateIcon() }
    }
}
