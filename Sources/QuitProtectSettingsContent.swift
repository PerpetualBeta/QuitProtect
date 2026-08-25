import SwiftUI
import QuitProtectCore

struct QuitProtectSettingsContent: View {
    let delegate: AppDelegate
    @State private var showQuitGuidance = QuitToastSettings.isEnabled

    /// Kept current by JorvikKit — see `JorvikPermissionWatcher` for why a permission row
    /// needs a watcher rather than a read, and why reading it more often makes it worse.
    @StateObject private var accessibility = JorvikPermissionWatcher.accessibility()

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
                        ForEach(QuitGestureTiming.holdOptions) { option in
                            Text(L10n.string(option.localizationKey, defaultValue: option.defaultLabel))
                                .tag(option.value)
                        }
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
                        ForEach(QuitGestureTiming.doublePressOptions) { option in
                            Text(L10n.string(option.localizationKey, defaultValue: option.defaultLabel))
                                .tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Toggle(QuitToastSettings.label, isOn: $showQuitGuidance)
                .onChange(of: showQuitGuidance) { _, newValue in
                    QuitToastSettings.isEnabled = newValue
                }
        }

        Section(L10n.string("settings.permissions", defaultValue: "Permissions")) {
            HStack {
                Text(L10n.string("settings.accessibility", defaultValue: "Accessibility"))
                Spacer()
                if accessibility.isGranted {
                    Label(
                        L10n.string("settings.permission_granted", defaultValue: "Granted"),
                        systemImage: "checkmark.circle.fill"
                    )
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button(L10n.string("settings.grant_access", defaultValue: "Grant Access")) {
                        JorvikPermissionWatcher.promptForAccessibility()
                    }
                    .font(.caption)
                }
            }
        }

        MenuBarVisibilitySettings()

        MenuBarPillSettings { delegate.updateIcon() }
    }
}
