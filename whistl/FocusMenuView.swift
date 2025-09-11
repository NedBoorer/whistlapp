//
//  FocusMenuView.swift
//  whistl
//
//  Created by Ned Boorer on 11/9/2025.
//


import SwiftUI
import FamilyControls
import ManagedSettings

struct FocusMenuView: View {
    @State private var model = FocusScheduleViewModel()
    private let brand = BrandPalette()

    @State private var showingPicker = false

    var body: some View {
        ZStack {
            brand.background()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    Group {
                        authorizationSection
                        selectionSection
                        scheduleSection
                        controlsSection
                        statusSection
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(brand.fieldBackground)
                    )
                }
                .padding(20)
            }
        }
        .navigationTitle("Blocking menu")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $model.selection)
                    .navigationTitle("Choose activities")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingPicker = false
                            }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showingPicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .onChange(of: model.selection) { _ in
            model.updateSelection(model.selection)
        }
        .tint(brand.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen Time blocking")
                .font(.title3.bold())
            Text("Choose apps and a time window. We’ll block them during that window each day, or block immediately with Block now.")
                .font(.callout)
                .foregroundStyle(brand.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Authorization", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack {
                Circle()
                    .fill(model.isAuthorized ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(model.isAuthorized ? "Authorized" : "Not authorized")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    Task { await model.requestAuthorization() }
                } label: {
                    Text(model.isAuthorized ? "Recheck" : "Request access")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(brand.accent)
            }
        }
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apps to block", systemImage: "apps.iphone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack {
                Text(selectionSummary)
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
                Button {
                    showingPicker = true
                } label: {
                    Text("Choose apps")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Daily time window", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(
                        get: { date(from: model.startComponents) },
                        set: { model.updateStart(components(from: $0)) }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading) {
                    Text("End")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(
                        get: { date(from: model.endComponents) },
                        set: { model.updateEnd(components(from: $0)) }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(brand.fieldBackground)
            )

            Toggle(isOn: Binding(
                get: { model.isScheduleEnabled },
                set: { model.setScheduleEnabled($0) }
            )) {
                Text("Enable this schedule every day")
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Controls", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack {
                Button {
                    model.activateManualBlock()
                } label: {
                    Label("Block now", systemImage: "play.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(brand.accent)
                .disabled(!model.isAuthorized || (model.selection.applicationTokens.isEmpty && model.selection.categoryTokens.isEmpty))

                Button {
                    model.deactivateManualBlock()
                    model.clearShield()
                } label: {
                    Label("Clear", systemImage: "stop.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Status", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            HStack {
                Circle()
                    .fill(model.isShieldActive ? Color.red : Color.gray.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(model.isShieldActive ? (model.isManualBlockActive ? "Blocking active (manual)" : "Blocking active (scheduled)") : "Blocking inactive")
                    .font(.callout)
                Spacer()
            }

            Text(model.lastStatusMessage)
                .font(.footnote)
                .foregroundStyle(brand.secondaryText)
        }
    }

    private var selectionSummary: String {
        let apps = model.selection.applicationTokens.count
        let cats = model.selection.categoryTokens.count
        if apps == 0 && cats == 0 {
            return "No apps selected."
        }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        return parts.joined(separator: " + ")
    }

    // Helpers to convert DateComponents <-> Date for DatePicker bindings
    private func date(from comps: DateComponents) -> Date {
        let cal = Calendar.current
        return cal.date(from: comps)
            ?? cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: Date())
            ?? Date()
    }

    private func components(from date: Date) -> DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: date)
    }
}
