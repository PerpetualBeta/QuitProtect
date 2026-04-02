import SwiftUI

struct QuitProtectSettingsContent: View {
    let delegate: AppDelegate

    var body: some View {
        Section("Quit Mode") {
            Picker("Mode", selection: Binding(
                get: { delegate.quitMode },
                set: { delegate.quitMode = $0 }
            )) {
                Text("Double-press ⌘Q").tag(QuitMode.doublePress)
                Text("Hold ⌘Q").tag(QuitMode.holdToQuit)
            }
            .pickerStyle(.radioGroup)

            if delegate.quitMode == .holdToQuit {
                HStack {
                    Text("Hold duration")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { delegate.holdDuration },
                        set: { delegate.holdDuration = $0 }
                    )) {
                        Text("0.5s").tag(0.5)
                        Text("1.0s").tag(1.0)
                        Text("1.5s").tag(1.5)
                        Text("2.0s").tag(2.0)
                    }
                    .frame(width: 80)
                }
            }

            if delegate.quitMode == .doublePress {
                HStack {
                    Text("Press interval")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { delegate.doublePressInterval },
                        set: { delegate.doublePressInterval = $0 }
                    )) {
                        Text("0.3s").tag(0.3)
                        Text("0.4s").tag(0.4)
                        Text("0.5s").tag(0.5)
                        Text("0.75s").tag(0.75)
                    }
                    .frame(width: 80)
                }
            }
        }

        Section("Permissions") {
            HStack {
                Text("Accessibility")
                Spacer()
                if AXIsProcessTrusted() {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Grant Access") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                    .font(.caption)
                }
            }
        }

        MenuBarPillSettings()
    }
}
