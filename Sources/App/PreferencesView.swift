import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("defaultTheme") private var defaultTheme = Constants.defaultTheme
    @AppStorage("defaultTypography") private var defaultTypography = Constants.defaultTypography
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
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
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

            LabeledContent("Server Port") {
                Text("\(Constants.serverPort)")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appearanceTab: some View {
        Form {
            Picker("Default Theme", selection: $defaultTheme) {
                ForEach(Constants.availableThemes, id: \.self) { theme in
                    Text(theme.capitalized.replacingOccurrences(of: "-", with: " "))
                        .tag(theme)
                }
            }

            Picker("Default Typography", selection: $defaultTypography) {
                ForEach(Constants.availableTypography, id: \.self) { typo in
                    Text(typo.capitalized)
                        .tag(typo)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
