import SwiftUI
import FamilyControls
import ManagedSettings
import FirebaseAuth

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

    // Schedule/Shield VM
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

                    partnerBreakControls
                    requestBreakControls

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

                    // Screen Time report
                    Button {
                        showingReport = true
                    } label: {
                        Label("View Screen Time report", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .tint(brand.accent)

                    // Logout
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
            // Inject pairing context into VM
            model.updatePairContext(
                pairId: appController.pairId,
                myUID: Auth.auth().currentUser?.uid,
                partnerUID: appController.partnerUID
            )
            refreshAnalytics()
            startTicker()
        }
        .onChange(of: appController.pairId) { _ in
            model.updatePairContext(
                pairId: appController.pairId,
                myUID: Auth.auth().currentUser?.uid,
                partnerUID: appController.partnerUID
            )
        }
        .onChange(of: appController.partnerUID) { _ in
            model.updatePairContext(
                pairId: appController.pairId,
                myUID: Auth.auth().currentUser?.uid,
                partnerUID: appController.partnerUID
            )
        }
        .onDisappear {
            stopTicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshAnalytics()
            model.evaluateAndApplyShield()
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

    // Partner-controlled break controls (approve partner's request and grant break)
    private var partnerBreakControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Partner requests", systemImage: "bell.and.waves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            if model.hasPendingPartnerRequest {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your partner requested a 5‑minute break.")
                        .font(.callout)

                    HStack {
                        Button {
                            Task {
                                await model.grantFiveMinuteBreakToPartner()
                            }
                        } label: {
                            Label("Approve and grant break", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(brand.accent)

                        Button(role: .destructive) {
                            Task { await model.rejectPartnerBreakRequest() }
                        } label: {
                            Label("Reject", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(brand.fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(brand.cardStroke, lineWidth: 1)
                )
            } else {
                Text("No pending requests from your partner.")
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

    // Owner-facing request controls (request a break and show pending)
    private var requestBreakControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Request a break", systemImage: "paperplane.circle")
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
                        Text("Cancel my break")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                }
            } else if model.isMyBreakRequestPending {
                HStack {
                    Image(systemName: "paperplane")
                    Text("Request sent — waiting for your partner to approve")
                        .font(.callout)
                    Spacer()
                    Button(role: .destructive) {
                        Task { await model.cancelBreakRequest() }
                    } label: {
                        Text("Cancel request")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    Task { await model.requestBreak() }
                } label: {
                    Label("Request 5‑minute break", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .disabled(!(appController.isPaired && appController.partnerUID != nil))
            }

            if let err = model.lastBreakRequestError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
    }

    private var breakCountdownText: String {
        guard let until = model.pauseUntil else { return "Break active" }
        let remaining = max(0, Int(until.timeIntervalSince(Date())))
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "Break ends in %d:%02d", m, s)
    }

    private var partnerDisplayName: String? {
        // If you later cache partner’s name in AppController, return it here.
        return "your partner"
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
            return item.identifier
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
