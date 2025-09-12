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
    @State private var showGamblingHint = false

    private let missionLine = "Stop gambling together — Australians lose over $25B each year. With whistl, mates keep each other on track."

    var body: some View {
        ZStack {
            brand.background()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    brand.missionBanner(missionLine)

                    Group {
                        authorizationSection
                        selectionSection
                        blockedItemsSection
                        weeklyScheduleSection
                        supportSection
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
        .sheet(isPresented: $showingPicker, onDismiss: {
            // After picker closes, hide the hint
            showGamblingHint = false
        }) {
            NavigationStack {
                VStack(spacing: 0) {
                    if showGamblingHint {
                        gamblingHintBanner
                    }
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
            Text("Choose apps and set time windows. We’ll block them during those windows, or block immediately with Block now.")
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

            // Quick add row
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    handleQuickAddGambling()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "suit.club.fill")
                            .foregroundStyle(brand.accent)
                        Text(containsGamblingCategory ? "Gambling category added" : "Quick add: Gambling category")
                            .fontWeight(.semibold)
                        Spacer()
                        if containsGamblingCategory {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(containsGamblingCategory)

                Text("We recommend blocking the Gambling category. If it’s not visible, use the picker to select it.")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }

            Divider().opacity(0.2)

            HStack {
                Text(selectionSummary)
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
                Button {
                    showGamblingHint = false
                    showingPicker = true
                } label: {
                    Text("Choose apps")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var gamblingHintBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundStyle(brand.accent)
            Text("Tip: Scroll to Categories and select “Gambling”.")
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
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
        .padding([.horizontal, .top], 12)
    }

    private var blockedItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Blocked items", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            if model.selection.applicationTokens.isEmpty && model.selection.categoryTokens.isEmpty {
                Text("No apps or categories selected.")
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
            } else {
                if !model.selection.categoryTokens.isEmpty {
                    Text("Categories")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    let categories: [ActivityCategoryToken] = prioritizedCategories(model.selection.categoryTokens)
                    ForEach(categories, id: \.self) { token in
                        HStack(spacing: 8) {
                            if isGambling(token) {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                            Text(categoryDisplayName(for: token))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .font(.callout)
                    }
                }

                if !model.selection.applicationTokens.isEmpty {
                    Text("Apps")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    let apps: [ApplicationToken] = prioritizedApps(model.selection.applicationTokens)
                    ForEach(apps, id: \.self) { token in
                        HStack {
                            Text(appDisplayName(for: token))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    // New: Weekly schedule editor (per-day, multiple ranges)
    private var weeklyScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weekly schedule", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            Toggle(isOn: Binding(
                get: { model.isScheduleEnabled },
                set: { model.setScheduleEnabled($0) }
            )) {
                Text("Enable schedule")
            }

            if model.isScheduleEnabled {
                VStack(spacing: 12) {
                    ForEach(model.weeklyPlan.days.indices, id: \.self) { idx in
                        let day = model.weeklyPlan.days[idx]
                        dayEditor(day.weekday, enabled: day.enabled, ranges: day.ranges)
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
                .padding(.top, 4)
            }
        }
    }

    private func dayEditor(_ weekday: Weekday, enabled: Bool, ranges: [TimeRange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { model.setDayEnabled(weekday, enabled: $0) }
                )) {
                    Text(weekdayDisplayName(weekday))
                        .font(.callout.weight(.semibold))
                }
                .toggleStyle(.switch)
                Spacer()
                Button {
                    // Default 21:00–07:00
                    model.addRange(for: weekday, startMinutes: 21*60, endMinutes: 7*60)
                } label: {
                    Label("Add range", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(!enabled)
                .tint(brand.accent)
            }

            if enabled {
                if ranges.isEmpty {
                    Text("No ranges. Add one to block on this day.")
                        .font(.footnote)
                        .foregroundStyle(brand.secondaryText)
                        .padding(.leading, 2)
                } else {
                    ForEach(ranges.indices, id: \.self) { i in
                        rangeEditor(weekday: weekday, index: i, range: ranges[i])
                    }
                    // Delete support via a simple list-like UI
                    // Since we are not in a List, provide explicit delete buttons in each row.
                }
            }
        }
    }

    private func rangeEditor(weekday: Weekday, index: Int, range: TimeRange) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker(
                    "",
                    selection: Binding<Date>(
                        get: { date(fromMinutes: range.startMinutes) },
                        set: { newDate in
                            let newStart = minutes(from: newDate)
                            model.updateRange(for: weekday, at: index, startMinutes: newStart, endMinutes: range.endMinutes)
                        }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text("End")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker(
                    "",
                    selection: Binding<Date>(
                        get: { date(fromMinutes: range.endMinutes) },
                        set: { newDate in
                            let newEnd = minutes(from: newDate)
                            model.updateRange(for: weekday, at: index, startMinutes: range.startMinutes, endMinutes: newEnd)
                        }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
            }

            Spacer()

            Button(role: .destructive) {
                model.removeRanges(for: weekday, at: IndexSet(integer: index))
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
    }

    // New: Support & accountability section
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Support & accountability", systemImage: "person.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand.accent)

            Text("Whistl works best with a mate. Link accounts to share a private space and keep each other on track.")
                .font(.footnote)
                .foregroundStyle(brand.secondaryText)
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

    // MARK: - Quick add Gambling

    private var containsGamblingCategory: Bool {
        model.selection.categoryTokens.contains(where: isGambling(_:))
    }

    private func handleQuickAddGambling() {
        if containsGamblingCategory { return }
        showGamblingHint = true
        showingPicker = true
    }

    // MARK: - Prioritization helpers

    private func prioritizedCategories(_ set: Set<ActivityCategoryToken>) -> [ActivityCategoryToken] {
        var arr = Array(set)
        arr.sort { (a: ActivityCategoryToken, b: ActivityCategoryToken) -> Bool in
            let ag = isGambling(a)
            let bg = isGambling(b)
            if ag != bg { return ag && !bg }
            return a.hashValue < b.hashValue
        }
        return arr
    }

    private func prioritizedApps(_ set: Set<ApplicationToken>) -> [ApplicationToken] {
        var arr = Array(set)
        arr.sort { (a: ApplicationToken, b: ApplicationToken) -> Bool in
            return a.hashValue < b.hashValue
        }
        return arr
    }

    private func isGambling(_ token: ActivityCategoryToken) -> Bool {
        // Placeholder heuristic: always false to avoid mislabeling.
        return false
    }

    // MARK: - Formatting and conversions

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

    private func date(fromMinutes minutes: Int) -> Date {
        let h = minutes / 60
        let m = minutes % 60
        let comps = DateComponents(hour: h, minute: m)
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return h * 60 + m
    }

    private func appDisplayName(for token: ApplicationToken) -> String {
        "App #\(abs(token.hashValue) % 100000)"
    }

    private func categoryDisplayName(for token: ActivityCategoryToken) -> String {
        if isGambling(token) { return "Gambling" }
        return "Category #\(abs(token.hashValue) % 100000)"
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
}

#Preview {
    NavigationStack { FocusMenuView() }
}
