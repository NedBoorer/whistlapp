import SwiftUI
import FamilyControls
import ManagedSettings

struct WhisprHomeView: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    // Live counters
    @State private var blockedSecondsToday: Int = 0
    @State private var attemptsToday: Int = 0
    @State private var topCulprits: [(identifier: String, count: Int, kind: String)] = []

    // Simple tick to refresh live blocked time while app is visible
    @State private var timer: Timer?

    // Present Screen Time (Device Activity) report
    @State private var showingReport = false

    private let missionLine = "Stop gambling together — Australians lose over $25B each year. With whistl, mates keep each other on track."

    // Access schedule VM for break control and status
    @State private var model = FocusScheduleViewModel()

    var body: some View {
        ZStack {
            brand.background()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    brand.missionBanner(missionLine)

                    blockedTimeCard

                    attemptsCard

                    breakControls

                    // Open your blocking controls
                    NavigationLink {
                        FocusMenuView()
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Open blocking menu", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(brand.accent)
                    .padding(.top, 4)

                    // New: Open Screen Time report (Device Activity report extension)
                    Button {
                        showingReport = true
                    } label: {
                        Label("View Screen Time report", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .tint(brand.accent)

                    // Inline logout button (optional, in addition to toolbar item)
                    Button {
                        do { try appController.signOut() } catch { }
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .padding(.top, 8)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    do { try appController.signOut() } catch { }
                } label: {
                    Text("Log out")
                        .font(.footnote.weight(.semibold))
                }
                .tint(.red)
            }
        }
        .sheet(isPresented: $showingReport) {
            ReportHostView()
                .tint(brand.accent)
        }
        .onAppear {
            refreshAnalytics()
            startTicker()
        }
        .onDisappear {
            stopTicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshAnalytics()
        }
        .tint(brand.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hi \(displayName)")
                .font(.largeTitle.bold())

            Text("Welcome to whistl.")
                .font(.headline)
                .foregroundStyle(brand.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blockedTimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Blocked time today", systemImage: "clock.badge.xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack(spacing: 8) {
                Text(formatSeconds(blockedSecondsToday))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Spacer()
            }

            Text("Time your shield has been active today across manual and scheduled blocks.")
                .font(.footnote)
                .foregroundStyle(brand.secondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
    }

    private var attemptsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Attempts today", systemImage: "hand.tap.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack {
                Text("\(attemptsToday)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Spacer()
            }

            if !topCulprits.isEmpty {
                Text("Top culprits")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(0..<topCulprits.count, id: \.self) { i in
                    let item = topCulprits[i]
                    HStack {
                        Text(displayName(for: item))
                        Spacer()
                        Text("\(item.count)×")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            } else {
                Text("No attempts yet today.")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
    }

    // New: Break controls
    private var breakControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Short break", systemImage: "pause.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            if model.isPaused {
                HStack {
                    Image(systemName: "clock")
                    Text(breakCountdownText)
                        .font(.callout)
                    Spacer()
                    Button {
                        model.cancelBreak()
                    } label: {
                        Text("Cancel break")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    model.startFiveMinuteBreak()
                } label: {
                    Label("Take 5‑minute break", systemImage: "playpause.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(brand.accent)
                .disabled(!model.isAuthorized) // needs Screen Time permission to control shield
            }

            Text("Pauses blocking for five minutes. Use sparingly — your mate’s counting on you.")
                .font(.footnote)
                .foregroundStyle(brand.secondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh pause state when returning to foreground
            model.evaluateAndApplyShield()
        }
    }

    private var breakCountdownText: String {
        guard let until = model.pauseUntil else { return "Break active" }
        let remaining = max(0, Int(until.timeIntervalSince(Date())))
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "Break ends in %d:%02d", m, s)
    }

    private var displayName: String {
        let name = appController.currentDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "there" : name
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func displayName(for item: (identifier: String, count: Int, kind: String)) -> String {
        if item.kind == "category" {
            if item.identifier.lowercased().contains("gambling") { return "Gambling (category)" }
            return "Category (\(item.identifier))"
        } else {
            return item.identifier // best-effort; token descriptions
        }
    }

    private func refreshAnalytics() {
        blockedSecondsToday = AnalyticsStore.blockedSecondsToday()
        attemptsToday = AnalyticsStore.attemptsToday().count
        topCulprits = AnalyticsStore.topCulpritsToday(limit: 5)
    }

    private func startTicker() {
        stopTicker()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            refreshAnalytics()
        }
    }

    private func stopTicker() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    NavigationStack { WhisprHomeView() }.environment(AppController())
}
