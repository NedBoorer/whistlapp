//
//  ReportHostView.swift
//  whistl
//
//  Created by You on 2025-09-16.
//

import SwiftUI
import DeviceActivity
import FamilyControls
import FirebaseAuth

struct ReportHostView: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    // Screen Time authorization
    @State private var authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    @State private var showingError: String?

    // Blocking model (for status only; all UI here is read-only)
    @State private var model = FocusScheduleViewModel()

    var body: some View {
        ZStack {
            brand.background()

            NavigationStack {
                List {
                    Section {
                        headerSummary

                        NavigationLink("Home summary") {
                            DeviceActivityReport(.home)
                                .navigationTitle("Summary")
                        }
                        NavigationLink("Total activity") {
                            DeviceActivityReport(.totalActivity)
                                .navigationTitle("Total activity")
                        }
                        NavigationLink("Top apps") {
                            DeviceActivityReport(.topApps)
                                .navigationTitle("Top apps")
                        }
                        NavigationLink("More insights") {
                            DeviceActivityReport(.moreInsights)
                                .navigationTitle("Insights")
                        }
                        NavigationLink("Pickups") {
                            DeviceActivityReport(.totalPickups)
                                .navigationTitle("Pickups")
                        }
                    }
                }
                .navigationTitle("Reports")
                .toolbar {
                    // Keep a compact status badge only; no blocking menu here.
                    ToolbarItem(placement: .topBarLeading) {
                        BlockStatusBadge(
                            isAuthorized: authorized,
                            isShieldActive: model.isShieldActive,
                            isPaused: model.isPaused,
                            pauseUntil: model.pauseUntil,
                            isManual: model.isManualBlockActive,
                            isScheduleEnabled: model.isScheduleEnabled,
                            selection: SharedConfigStore.loadSelection()
                        )
                    }
                }
                .alert("Error", isPresented: Binding(get: { showingError != nil }, set: { _ in showingError = nil })) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(showingError ?? "")
                }
            }
        }
        .task {
            if !authorized {
                await requestAuth()
            }
        }
        .onAppear {
            // Inject pair context so status reflects the correct owner/partner setup
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
    }

    // MARK: - Summary header (read-only)

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.isShieldActive ? "Blocking active" : "Blocking inactive",
                      systemImage: model.isShieldActive ? "lock.shield.fill" : "lock.shield")
                    .foregroundStyle(model.isShieldActive ? brand.accent : .secondary)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !authorized {
                    Button("Authorize") { Task { await requestAuth() } }
                        .buttonStyle(.bordered)
                }
            }

            if model.isPaused, let until = model.pauseUntil {
                Label("On a short break until \(until.formatted(date: .omitted, time: .shortened))",
                      systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.isManualBlockActive {
                Label("Manual block is on", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.isScheduleEnabled {
                if let summary = todayRangeSummary() {
                    Label("Scheduled: \(summary)", systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Schedule enabled", systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            let sel = SharedConfigStore.loadSelection()
            Text(selectionSummary(sel))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func requestAuth() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorized = AuthorizationCenter.shared.authorizationStatus == .approved
            SharedConfigStore.save(isAuthorized: authorized)
            if authorized {
                ReportingScheduler.shared.refreshMonitoringFromShared()
            } else {
                ReportingScheduler.shared.stopAllMonitoring()
            }
        } catch {
            showingError = (error as NSError).localizedDescription
        }
    }

    private func selectionSummary(_ sel: FamilyActivitySelection) -> String {
        let apps = sel.applicationTokens.count
        let cats = sel.categoryTokens.count
        if apps == 0 && cats == 0 { return "No apps or categories selected." }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        return "Blocking: " + parts.joined(separator: " + ")
    }

    private func todayRangeSummary(calendar: Calendar = .current) -> String? {
        let enabled = SharedConfigStore.loadIsScheduleEnabled()
        guard enabled else { return nil }
        let start = SharedConfigStore.loadStartMinutes()
        let end   = SharedConfigStore.loadEndMinutes()
        let startDate = dateFromMinutes(start, calendar: calendar)
        let endDate   = dateFromMinutes(end, calendar: calendar)
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: startDate)) – \(f.string(from: endDate))"
    }

    private func dateFromMinutes(_ minutes: Int, calendar: Calendar) -> Date {
        let h = minutes / 60
        let m = minutes % 60
        let comps = DateComponents(hour: h, minute: m)
        return calendar.date(from: comps) ?? Date()
    }
}

// MARK: - Compact status badge for toolbar

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
