import ServiceManagement
import Sparkle
import SwiftUI

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

struct PreferencesView: View {
    let updater: SPUUpdater
    @Environment(AppState.self) private var appState
    @AppStorage("defaultTheme") private var defaultTheme = Constants.defaultTheme
    @AppStorage("defaultTypography") private var defaultTypography = Constants.defaultTypography
    @AppStorage("defaultZoom") private var defaultZoom = Constants.zoomDefault
    @AppStorage("autoReload") private var autoReload = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cliStatus = CLIInstaller.checkStatus()
    @State private var cliError: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            cliTab
                .tabItem {
                    Label("CLI", systemImage: "terminal")
                }

            updatesTab
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 480, height: 350)
    }

    private var generalTab: some View {
        Form {
            Toggle("Auto-reload on file change", isOn: $autoReload)
                .onChange(of: autoReload) {
                    notifySettingsChanged()
                }

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Failed to update launch at login: \(error)")
                        launchAtLogin = !newValue
                    }
                }

        }
        .formStyle(.grouped)
        .padding()
    }

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: $defaultTheme) {
                ForEach(Constants.availableThemes, id: \.self) { theme in
                    Text(theme.capitalized.replacingOccurrences(of: "-", with: " "))
                        .tag(theme)
                }
            }
            .onChange(of: defaultTheme) {
                notifySettingsChanged()
            }

            Picker("Typography", selection: $defaultTypography) {
                ForEach(Constants.availableTypography, id: \.self) { typo in
                    Text(typo.capitalized)
                        .tag(typo)
                }
            }
            .onChange(of: defaultTypography) {
                notifySettingsChanged()
            }

            HStack {
                Text("Zoom")
                Spacer()
                Button("-") { adjustZoom(-Constants.zoomStep) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text("\(defaultZoom)%")
                    .frame(width: 50, alignment: .center)
                    .monospacedDigit()
                Button("+") { adjustZoom(Constants.zoomStep) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Reset") { defaultZoom = Constants.zoomDefault; notifySettingsChanged() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var cliTab: some View {
        Form {
            HStack {
                Text("Status")
                Spacer()
                switch cliStatus {
                case .notInstalled:
                    Text("Not installed")
                        .foregroundStyle(.secondary)
                case .installed:
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .installedElsewhere(let path):
                    Label("Linked elsewhere", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .conflict:
                    Label("Conflict: not a symlink", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                if cliStatus == .installed {
                    Button("Uninstall") {
                        do {
                            try CLIInstaller.uninstall()
                            cliStatus = CLIInstaller.checkStatus()
                            cliError = nil
                        } catch {
                            cliError = error.localizedDescription
                        }
                    }
                } else {
                    Button("Install") {
                        do {
                            try CLIInstaller.install()
                            cliStatus = CLIInstaller.checkStatus()
                            cliError = nil
                        } catch {
                            cliError = error.localizedDescription
                        }
                    }
                }
            }

            if let cliError {
                Text(cliError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Section {
                Text("Opens files and folders in Moremaid from the terminal:")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    Text("mm README.md")
                    Text("mm ~/Projects")
                }
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            } header: {
                Text("Usage")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var updatesTab: some View {
        Form {
            CheckForUpdatesView(updater: updater)

            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))
        }
        .formStyle(.grouped)
        .padding()
    }

    private func adjustZoom(_ delta: Int) {
        defaultZoom = max(Constants.zoomMin, min(Constants.zoomMax, defaultZoom + delta))
        notifySettingsChanged()
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
