import SwiftUI
import FamilyControls
import FirebaseAuth

struct FocusMenuView: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    // Read-only status and plan
    @State private var model = FocusScheduleViewModel()

    // Sheet routing with stable identity
    private enum SheetRoute: Identifiable {
        case setupFlow
        var id: String {
            switch self { case .setupFlow: return "setupFlow" }
        }
    }
    @State private var activeSheet: SheetRoute?
    @State private var isPresentingGuard = false   // prevents re-entrant toggles

    var body: some View {
        ZStack {
            brand.background()

            List {
                Section {
                    statusHeader
                }

                Section("What’s blocked") {
                    let sel = SharedConfigStore.loadSelection()
                    HStack {
                        Text("Selection")
                        Spacer()
                        Text(selectionSummary(sel))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
                }

                Section("Schedule") {
                    if model.isScheduleEnabled {
                        fullScheduleReadOnly
                    } else {
                        Text("Schedule disabled")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        presentSetupFlowSafely()
                    } label: {
                        Label("Request schedule change", systemImage: "arrow.2.circlepath")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!(appController.isPaired))
                    .accessibilityIdentifier("requestScheduleChangeButton")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Blocking")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet, onDismiss: {
            // Do not mutate any state here; leave presentation strictly user-controlled
        }) { route in
            switch route {
            case .setupFlow:
                SetupFlowHost(brand: brand)
            }
        }
        .onAppear {
            // Inject pairing context for accurate status
            model.updatePairContext(
                pairId: appController.pairId,
                myUID: Auth.auth().currentUser?.uid,
                partnerUID: appController.partnerUID
            )
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
        .tint(brand.accent)
    }

    // MARK: - Header

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
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
    }

    // MARK: - Full schedule (read-only)

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

    // MARK: - Helpers

    private func presentSetupFlowSafely() {
        guard appController.isPaired else { return }
        guard !isPresentingGuard else { return }
        isPresentingGuard = true

        // Defer to avoid List button animation conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            activeSheet = .setupFlow
            // Release guard a bit later so re-tap is possible after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isPresentingGuard = false
            }
        }
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

    private func todayRangeSummary(calendar: Calendar = .current) -> String? {
        guard model.isScheduleEnabled else { return nil }
        // Use shared summary (kept in sync by FocusScheduleViewModel)
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

// MARK: - Stable host for the setup flow (prevents auto-dismiss/flicker)

private struct SetupFlowHost: View {
    let brand: BrandPalette
    var body: some View {
        NavigationStack {
            SharedSetupFlowView()
                .navigationBarTitleDisplayMode(.inline)
        }
        .tint(brand.accent)
        // Keep the sheet open unless the user dismisses explicitly
        .interactiveDismissDisabled(false)
    }
}

#Preview { FocusMenuView() }
