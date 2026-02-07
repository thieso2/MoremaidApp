import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

struct PreferencesView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("defaultTheme") private var defaultTheme = Constants.defaultTheme
    @AppStorage("defaultTypography") private var defaultTypography = Constants.defaultTypography
    @AppStorage("defaultZoom") private var defaultZoom = Constants.zoomDefault
    @AppStorage("autoReload") private var autoReload = true
    @AppStorage("restoreWindows") private var restoreWindows = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
        }
        .frame(width: 450, height: 350)
    }

    private var generalTab: some View {
        Form {
            Toggle("Auto-reload on file change", isOn: $autoReload)
                .onChange(of: autoReload) {
                    notifySettingsChanged()
                }

            Toggle("Restore windows on launch", isOn: $restoreWindows)

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

    private func adjustZoom(_ delta: Int) {
        defaultZoom = max(Constants.zoomMin, min(Constants.zoomMax, defaultZoom + delta))
        notifySettingsChanged()
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
