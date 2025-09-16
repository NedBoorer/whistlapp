import SwiftUI
import FirebaseAuth

struct HomeTabs: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    var body: some View {
        TabView {
            NavigationStack {
                WhisprHomeView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                ReportHostView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Reports", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                SettingsTabView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(brand.accent)
    }
}

private struct SettingsTabView: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    var body: some View {
        ZStack {
            brand.background()

            List {
                Section("Account") {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(displayName)
                            .foregroundStyle(.secondary)
                    }
                    if let email = Auth.auth().currentUser?.email, !email.isEmpty {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(email)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) {
                        do { try appController.signOut() } catch { }
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("Pairing") {
                    if let code = appController.inviteCode, !code.isEmpty {
                        HStack {
                            Text("Invite code")
                            Spacer()
                            Text(code)
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Pair status")
                        Spacer()
                        Text(appController.isPaired ? "Paired" : "Unpaired")
                            .foregroundStyle(appController.isPaired ? .green : .secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("whistl")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(brand.accent)
    }

    private var displayName: String {
        if !appController.currentDisplayName.isEmpty { return appController.currentDisplayName }
        return Auth.auth().currentUser?.email ?? "Unknown"
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }
}

#Preview {
    HomeTabs().environment(AppController())
}
