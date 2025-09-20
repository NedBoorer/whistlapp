import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import ManagedSettings
import FamilyControls
import CoreLocation

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
                ZStack {
                    Color.black.ignoresSafeArea()
                    Text("AI‑driven reports and insights are coming soon")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .font(.title3.weight(.semibold))
                        .padding()
                }
                .navigationTitle("Reports")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Reports", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                PartnerTabView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("your mates", systemImage: "person.2.fill")
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

    @State private var showResetAlert = false
    @State private var alsoUnlink = false
    @State private var isResetting = false
    @State private var resetError: String?
    
    @State private var showRiskOnboarding = false
    @State private var pendingEnableRisk = false
    
    @MainActor
    private func riskStatus() -> (icon: String, message: String, color: Color) {
        // Toggle state
        if !LocationMonitor.shared.isEnabled {
            return ("location.slash", "Off", .secondary)
        }

        // Pair context
        let hasPair = (appController.pairId?.isEmpty == false) && (appController.partnerUID?.isEmpty == false)

        // Location authorization
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .authorizedAlways:
            if hasPair {
                return ("checkmark.circle.fill", "Ready", .green)
            } else {
                return ("person.crop.circle.badge.exclamationmark", "Missing pair context", .yellow)
            }
        case .authorizedWhenInUse:
            return ("exclamationmark.triangle.fill", "Needs Always Location Access", .yellow)
        case .notDetermined:
            return ("questionmark.circle.fill", "Awaiting permission", .yellow)
        case .denied, .restricted:
            return ("xmark.octagon.fill", "Location access denied", .red)
        @unknown default:
            return ("questionmark.circle", "Unknown state", .secondary)
        }
    }

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

                Section("Risk place alerts") {
                    HStack {
                        Text("Alert partner if I stay at a bar/casino 5+ minutes")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { LocationMonitor.shared.isEnabled },
                            set: { newVal in
                                if newVal {
                                    pendingEnableRisk = true
                                    showRiskOnboarding = true
                                } else {
                                    LocationMonitor.shared.isEnabled = false
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .tint(brand.accent)
                    Text("Sends an alert to your mate with 2‑hour cooldown per venue. Requires Always‑On Location.")
                        .font(.caption)
                        .foregroundStyle(brand.secondaryText)
                    HStack(spacing: 8) {
                        let status = riskStatus()
                        Image(systemName: status.icon)
                            .foregroundStyle(status.color)
                        Text(status.message)
                            .font(.caption)
                            .foregroundStyle(status.color)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }

                Section("Reset") {
                    Toggle(isOn: $alsoUnlink) {
                        Text("Also unlink from my partner")
                    }
                    .tint(brand.accent)
                    .disabled(isResetting)

                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        if isResetting {
                            HStack {
                                ProgressView().tint(.red)
                                Text("Resetting…")
                            }
                        } else {
                            Label("Reset app (keep my account)", systemImage: "trash")
                        }
                    }
                    .disabled(isResetting)
                    .alert("Reset app?", isPresented: $showResetAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            Task { await performReset(alsoUnlink: alsoUnlink) }
                        }
                    } message: {
                        Text("This clears your selections, schedules, pairing context, analytics and local settings on this device. Your sign‑in (name, email, password) remains intact. If you also unlink, your partner will be unlinked too and the pair will be deleted.")
                    }

                    if let resetError {
                        Label(resetError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
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
        .sheet(isPresented: $showRiskOnboarding) {
            RiskLocationOnboardingView(
                onContinue: {
                    LocationMonitor.shared.isEnabled = true
                    LocationMonitor.shared.start()
                    showRiskOnboarding = false
                    pendingEnableRisk = false
                },
                onCancel: {
                    showRiskOnboarding = false
                    pendingEnableRisk = false
                }
            )
        }
    }

    // MARK: - Reset implementation

    private func performReset(alsoUnlink: Bool) async {
        guard !isResetting else { return }
        isResetting = true
        resetError = nil

        let db = Firestore.firestore()
        let currentUID = Auth.auth().currentUser?.uid

        // 1) If unlinking, unlink both users and delete the pair doc (best-effort, in a transaction).
        if alsoUnlink, let uid = currentUID {
            do {
                try await db.runTransaction { txn, errorPtr in
                    do {
                        // Load current user's pairId
                        let userRef = db.collection("users").document(uid)
                        let userSnap = try txn.getDocument(userRef)
                        guard let userData = userSnap.data(),
                              let pairId = userData["pairId"] as? String,
                              !pairId.isEmpty else {
                            // Nothing to unlink
                            return nil
                        }

                        // Load pair doc to find both members
                        let pairRef = db.collection("pairs").document(pairId)
                        let pairSnap = try txn.getDocument(pairRef)
                        guard let pairData = pairSnap.data() else {
                            // Pair doc missing; still clear my pairId
                            txn.setData(["pairId": FieldValue.delete()], forDocument: userRef, merge: true)
                            return nil
                        }

                        let memberA = pairData["memberA"] as? String
                        let memberB = pairData["memberB"] as? String

                        // Clear pairId on both users (if present)
                        if let a = memberA, !a.isEmpty {
                            let aRef = db.collection("users").document(a)
                            txn.setData(["pairId": FieldValue.delete()], forDocument: aRef, merge: true)
                        }
                        if let b = memberB, !b.isEmpty {
                            let bRef = db.collection("users").document(b)
                            txn.setData(["pairId": FieldValue.delete()], forDocument: bRef, merge: true)
                        }

                        // Delete the pair doc
                        txn.deleteDocument(pairRef)

                        // Best-effort: mark in pairSpaces a tombstone so parallel listeners stop gracefully (optional)
                        let spaceRef = db.collection("pairSpaces").document(pairId)
                        txn.setData(["deletedAt": FieldValue.serverTimestamp()], forDocument: spaceRef, merge: true)

                        return nil
                    } catch {
                        errorPtr?.pointee = error as NSError
                        return nil
                    }
                }

                // After transaction: best-effort cleanup of key pairSpaces docs (non-transactional)
                // We only delete known single documents to avoid partial recursive deletes.
                if let uid = currentUID {
                    // Fetch pairId again (it might be gone now)
                    // We can read from appController if available, but safer to attempt known docs with last pairId.
                    // Since we deleted the pair doc, we attempt to clear common docs under pairSpaces if we can infer id.
                    // No reliable pairId now; skip unless appController had one.
                    if let lastPairId = appController.pairId {
                        let space = db.collection("pairSpaces").document(lastPairId)
                        // setup/current
                        await tryDeleteDocument(space.collection("setup").document("current"))
                        // devicePolicies for both users (if we know partner)
                        if let partner = appController.partnerUID {
                            await tryDeleteDocument(space.collection("devicePolicies").document(uid))
                            await tryDeleteDocument(space.collection("devicePolicies").document(partner))
                            // breakRequests for both
                            await tryDeleteDocument(space.collection("breakRequests").document(uid))
                            await tryDeleteDocument(space.collection("breakRequests").document(partner))
                        } else {
                            // Delete mine at least
                            await tryDeleteDocument(space.collection("devicePolicies").document(uid))
                            await tryDeleteDocument(space.collection("breakRequests").document(uid))
                        }
                        // Optionally mark the space itself deleted (already set in txn via deletedAt)
                    }
                }
            } catch {
                await MainActor.run {
                    resetError = (error as NSError).localizedDescription
                }
            }
        }

        // 2) Stop monitoring
        ReportingScheduler.shared.stopAllMonitoring()

        // 3) Clear shared config keys (but keep auth)
        clearSharedConfig()

        // 4) Reset in-memory state for AppController (keeps auth)
        await MainActor.run {
            appController.pairId = nil
            appController.inviteCode = nil
            appController.pairingLoadState = .unpaired
            appController.isMemberA = false
            appController.isMemberB = false
            appController.partnerUID = nil
            appController.currentSetupPhaseRaw = nil
        }

        isResetting = false
    }

    private func tryDeleteDocument(_ ref: DocumentReference) async {
        do {
            try await ref.delete()
        } catch {
            // ignore best-effort failures
        }
    }

    private func clearSharedConfig() {
        let d = SharedConfigStore.defaults

        // Selection tokens
        d.removeObject(forKey: SharedKeys.appTokensDataArray)
        d.removeObject(forKey: SharedKeys.categoryTokensDataArr)

        // Schedule flags and minutes
        d.removeObject(forKey: SharedKeys.isScheduleEnabled)
        d.removeObject(forKey: SharedKeys.isManualBlockActive)
        d.removeObject(forKey: SharedKeys.startMinutes)
        d.removeObject(forKey: SharedKeys.endMinutes)

        // Pause/break
        d.removeObject(forKey: SharedKeys.pauseUntil)

        // Pair context for extensions
        d.removeObject(forKey: SharedKeys.pairId)
        d.removeObject(forKey: SharedKeys.myUID)
        d.removeObject(forKey: SharedKeys.partnerUID)

        // Attempt logging toggle
        d.removeObject(forKey: SharedKeys.attemptLoggingEnabled)

        // Analytics
        d.removeObject(forKey: SharedKeys.attemptsLog)
        d.removeObject(forKey: SharedKeys.blockedAccumulations)
        d.removeObject(forKey: SharedKeys.currentBlockStart)

        // App name cache
        d.removeObject(forKey: SharedKeys.appNameCache)

        // Leave Screen Time authorization as-is; uncomment to clear:
        // d.removeObject(forKey: SharedKeys.isAuthorized)

        // Notify extensions that config changed
        postConfigDidChangeDarwinNotification()
    }

    // MARK: - Helpers

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

private struct PartnerTabView: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    @State private var partnerName: String = ""
    @State private var approvedSelection: FamilyActivitySelection = SharedConfigStore.loadSelection()
    @State private var approvedPlan: WeeklyBlockPlan? = loadWeeklyPlanFromShared()

    var body: some View {
        ZStack {
            brand.background()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    scheduleCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Partner")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPartnerName(); refreshApproved() }
        .onReceive(NotificationCenter.default.publisher(for: .configDidChange)) { _ in
            refreshApproved()
        }
        .tint(brand.accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(brand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(partnerName.isEmpty ? "Your mate" : partnerName)
                    .font(.title3.bold())
                Text("Stats • Schedule")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }
            Spacer()
        }
    }

//    private var categoriesCard: some View {
//        VStack(alignment: .leading, spacing: 8) {
//            HStack(spacing: 8) {
//                Image(systemName: "square.grid.2x2.fill").foregroundStyle(brand.accent)
//                Text("Categories blocked")
//                    .font(.headline)
//                Spacer()
//                Text("\(approvedSelection.categoryTokens.count)")
//                    .font(.subheadline.monospacedDigit())
//                    .foregroundStyle(brand.secondaryText)
//            }
//            if approvedSelection.categoryTokens.isEmpty {
//                Text("No categories approved yet.")
//                    .font(.footnote)
//                    .foregroundStyle(brand.secondaryText)
//            } else {
//                Text(approvedSelection.categoryTokens.map { String(describing: $0) }.sorted().joined(separator: ", "))
//                    .font(.footnote)
//                    .foregroundStyle(brand.secondaryText)
//            }
//        }
//        .padding(16)
//        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(brand.fieldBackground))
//        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(brand.cardStroke, lineWidth: 1))
//    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(brand.accent)
                Text("Schedule")
                    .font(.headline)
                Spacer()
                Text(scheduleOn ? "On" : "Off")
                    .font(.subheadline)
                    .foregroundStyle(scheduleOn ? .green : brand.secondaryText)
            }
            if let plan = approvedPlan {
                ReadOnlyPlanView(plan: plan, brand: brand)
            } else {
                Text("No approved schedule yet.")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(brand.fieldBackground))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(brand.cardStroke, lineWidth: 1))
    }

    private var scheduleOn: Bool {
        guard let approvedPlan else { return SharedConfigStore.loadIsScheduleEnabled() }
        return approvedPlan.days.contains(where: { $0.enabled })
    }

    private func loadPartnerName() async {
        if let partner = appController.partnerUID {
            do {
                let snap = try await Firestore.firestore().collection("users").document(partner).getDocument()
                let name = (snap.data()? ["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                partnerName = (name?.isEmpty == false) ? name! : "Your mate"
            } catch {
                partnerName = "Your mate"
            }
        } else {
            partnerName = "Your mate"
        }
    }

    private func refreshApproved() {
        approvedSelection = SharedConfigStore.loadSelection()
        approvedPlan = loadWeeklyPlanFromShared()
    }

    private func readableAppName(_ token: ApplicationToken) -> String {
        if let id = try? JSONEncoder().encode(token).base64EncodedString(), let cached = SharedConfigStore.appName(for: id) {
            return cached
        }
        return String(describing: token)
    }
}

// MARK: - Local helpers for HomeTabs partner view

private func loadWeeklyPlanFromShared() -> WeeklyBlockPlan? {
    // Mirror FocusScheduleViewModel.loadWeeklyPlan() logic locally
    let key = "fc_weeklyPlan_v1"
    if let data = SharedConfigStore.defaults.data(forKey: key) {
        return try? JSONDecoder().decode(WeeklyBlockPlan.self, from: data)
    }
    return nil
}

private struct ReadOnlyPlanView: View {
    let plan: WeeklyBlockPlan
    let brand: BrandPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(plan.days.indices, id: \.self) { idx in
                let day = plan.days[idx]
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
        }
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

    private func timeString(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let comps = DateComponents(hour: h, minute: m)
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

#Preview {
    HomeTabs().environment(AppController())
}

private extension Notification.Name {
    static let configDidChange = Notification.Name("configDidChange")
}

// ------------------------------------------------
// --- MODIFICATIONS BELOW AS PER INSTRUCTIONS ---
// ------------------------------------------------

private struct MateOverviewCard: View {
    let approvedSelection: FamilyActivitySelection
    let brand: BrandPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selection hint (no app lists or counts shown)
            HStack(spacing: 8) {
                Image(systemName: "apps.iphone")
                    .foregroundStyle(brand.secondaryText)
                Text("App blocking is managed by your mate.")
                    .font(.subheadline)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
            }

            // Schedule and attempts UI below (preserving existing UI as is)
            // ... (Assuming this is the intended place for those UI parts)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(brand.fieldBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(brand.cardStroke))
    }
}

private struct AppSelectionStepView: View {
    let selection: FamilyActivitySelection
    let brand: BrandPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Other UI parts...

            VStack(alignment: .leading, spacing: 6) {
                if !selection.categoryTokens.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill").foregroundStyle(brand.secondaryText)
                        Text(selection.categoryTokens.map { readableCategoryName($0) }.sorted().joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(brand.secondaryText)
                        Spacer()
                    }
                }
                if !selection.applicationTokens.isEmpty {
                    Text("App selections updated.")
                        .font(.footnote)
                        .foregroundStyle(brand.secondaryText)
                }
            }

            // Other UI parts...
        }
    }

    private func readableCategoryName(_ token: ActivityCategoryToken) -> String {
        return String(describing: token)
    }

    private var summary: String {
        let cats = selection.categoryTokens.count
        if cats == 0 && selection.applicationTokens.isEmpty { return "No categories selected yet." }
        if cats > 0 { return "\(cats) categor\(cats == 1 ? "y" : "ies")" }
        return "Apps selected"
    }
}

