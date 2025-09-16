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

    // Schedule/Shield VM
    @State private var model = FocusScheduleViewModel()

    // Setup flow (schedule change) sheet routing
    @State private var showingSetupFlow = false
    @State private var isPresentingGuard = false

    private let missionLine = "Stop gambling together — Australians lose over $25B each year. With whistl, mates keep each other on track."

    var body: some View {
        ZStack {
            brand.background()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    brand.missionBanner(missionLine)

                    // Blocking status + selection + schedule (read-only)
                    blockingStatusSection
                    selectionSummarySection
                    scheduleSection

                    blockedTimeCard

                    attemptsCard

                    partnerBreakControls
                    requestBreakControls

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
            ToolbarItem(placement: .topBarLeading) {
                BlockStatusBadge(
                    isAuthorized: SharedConfigStore.loadIsAuthorized(),
                    isShieldActive: model.isShieldActive,
                    isPaused: model.isPaused,
                    pauseUntil: model.pauseUntil,
                    isManual: model.isManualBlockActive,
                    isScheduleEnabled: model.isScheduleEnabled,
                    selection: SharedConfigStore.loadSelection()
                )
            }
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
        .sheet(isPresented: $showingSetupFlow) {
            NavigationStack {
                SharedSetupFlowView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tint(brand.accent)
            .interactiveDismissDisabled(false)
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

    // MARK: - Header

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

    // MARK: - Blocking status + selection + schedule

    private var blockingStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let active = model.isShieldActive
            HStack {
                Label(active ? "Blocking active" : "Blocking inactive",
                      systemImage: active ? "lock.shield.fill" : "lock.shield")
                    .foregroundStyle(active ? .green : .secondary)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.isPaused, let until = model.pauseUntil {
                    Text("Break until \(until.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if model.isManualBlockActive {
                    Text("Manual block")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if model.isScheduleEnabled, let range = todayRangeSummary() {
                    Text("Today: \(range)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isNowBlocked() {
                Label("Now is blocked", systemImage: "stopwatch")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
    }

    private var selectionSummarySection: some View {
        let sel = SharedConfigStore.loadSelection()
        return VStack(alignment: .leading, spacing: 10) {
            Label("What’s blocked", systemImage: "list.bullet.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack {
                Text(selectionSummary(sel))
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Schedule", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            if model.isScheduleEnabled {
                fullScheduleReadOnly
            } else {
                Text("Schedule disabled")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }

            Button {
                presentSetupFlowSafely()
            } label: {
                Label("Request schedule change", systemImage: "arrow.2.circlepath")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!(appController.isPaired))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
    }

    // Full schedule (read-only)
    private var fullScheduleReadOnly: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.weeklyPlan.days.indices, id: \.self) { idx in
                let day = model.weeklyPlan.days[idx]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(weekdayDisplayName(day.weekday))
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text(day.enabled ? "Enabled" : "Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if day.enabled {
                        if day.ranges.isEmpty {
                            Text("No ranges")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(day.ranges.indices, id: \.self) { rIdx in
                                let r = day.ranges[rIdx]
                                HStack {
                                    Text(timeString(minutes: r.startMinutes))
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    Text(timeString(minutes: r.endMinutes))
                                    Spacer()
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(brand.fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(brand.cardStroke, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Existing cards

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

    // MARK: - Helpers

    private func presentSetupFlowSafely() {
        guard appController.isPaired else { return }
        showingSetupFlow = true
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

    private func selectionSummary(_ sel: FamilyActivitySelection) -> String {
        let apps = sel.applicationTokens.count
        let cats = sel.categoryTokens.count
        if apps == 0 && cats == 0 { return "None" }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        return parts.joined(separator: " + ")
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

    private func todayRangeSummary(calendar: Calendar = .current) -> String? {
        guard model.isScheduleEnabled else { return nil }
        let start = SharedConfigStore.loadStartMinutes()
        let end   = SharedConfigStore.loadEndMinutes()
        let f = DateFormatter(); f.timeStyle = .short
        return "\(f.string(from: dateFromMinutes(start, calendar: calendar))) – \(f.string(from: dateFromMinutes(end, calendar: calendar)))"
    }

    private func isNowBlocked(now: Date = Date()) -> Bool {
        guard model.isScheduleEnabled else { return false }
        let today = Weekday.today()
        guard let day = model.weeklyPlan.day(for: today), day.enabled else { return false }
        let insideAny = day.ranges.contains { $0.contains(now) }
        let sel = SharedConfigStore.loadSelection()
        let hasAnyItems = !sel.applicationTokens.isEmpty || !sel.categoryTokens.isEmpty
        return insideAny && hasAnyItems && !model.isPaused
    }

    private func dateFromMinutes(_ minutes: Int, calendar: Calendar = .current) -> Date {
        let h = minutes / 60
        let m = minutes % 60
        let comps = DateComponents(hour: h, minute: m)
        return calendar.date(from: comps) ?? Date()
    }

    private func timeString(minutes: Int) -> String {
        let date = dateFromMinutes(minutes)
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: date)
    }

    private func weekdayDisplayName(_ day: Weekday) -> String {
        switch day {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

// MARK: - Compact status badge for toolbar (duplicated here for Home)

private struct BlockStatusBadge: View {
    let isAuthorized: Bool
    let isShieldActive: Bool
    let isPaused: Bool
    let pauseUntil: Date?
    let isManual: Bool
    let isScheduleEnabled: Bool
    let selection: FamilyActivitySelection

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var iconName: String {
        if !isAuthorized { return "exclamationmark.triangle.fill" }
        if isPaused { return "clock" }
        if isShieldActive { return "lock.shield.fill" }
        return "lock.shield"
    }

    private var iconColor: Color {
        if !isAuthorized { return .yellow }
        if isPaused { return .orange }
        if isShieldActive { return .green }
        return .secondary
    }

    private var title: String {
        if !isAuthorized { return "No access" }
        if isPaused {
            if let until = pauseUntil {
                return "Break until \(until.formatted(date: .omitted, time: .shortened))"
            }
            return "On a break"
        }
        if isShieldActive {
            return isManual ? "Blocking (manual)" : "Blocking (scheduled)"
        }
        return "Blocking inactive"
    }

    private var subtitle: String? {
        if isScheduleEnabled {
            let apps = selection.applicationTokens.count
            let cats = selection.categoryTokens.count
            if apps == 0 && cats == 0 { return "No items selected" }
            var parts: [String] = []
            if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
            if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
            return parts.joined(separator: " + ")
        }
        return nil
    }
}

#Preview {
    NavigationStack { WhisprHomeView() }.environment(AppController())
}
