import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FamilyControls
import ManagedSettings

// MARK: - Firestore models

struct SetupStepID {
    static let appSelection  = "appSelection"
    static let weeklySchedule = "weeklySchedule"
}

struct BlockSchedule: Codable, Equatable {
    var startMinutes: Int
    var endMinutes: Int
}

enum SetupPhaseLocal: String {
    case awaitingASubmission
    case awaitingBApproval
    case awaitingBSubmission
    case awaitingAApproval
    case complete
}

private struct SetupDoc: Codable {
    var step: String
    var stepIndex: Int
    var answers: [String: [String: AnyCodable]]
    var approvals: [String: Bool]
    var submitted: [String: Bool]
    var approvedAnswers: [String: [String: AnyCodable]]
    var phase: String
    var updatedAt: Timestamp?
    var completedAt: Timestamp?

    init(step: String = SetupStepID.appSelection,
         stepIndex: Int = 0,
         answers: [String: [String: AnyCodable]] = [:],
         approvals: [String: Bool] = [:],
         submitted: [String: Bool] = [:],
         approvedAnswers: [String: [String: AnyCodable]] = [:],
         phase: String = SetupPhaseLocal.awaitingASubmission.rawValue,
         updatedAt: Timestamp? = nil,
         completedAt: Timestamp? = nil) {
        self.step = step
        self.stepIndex = stepIndex
        self.answers = answers
        self.approvals = approvals
        self.submitted = submitted
        self.approvedAnswers = approvedAnswers
        self.phase = phase
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int; return }
        if let dbl = try? container.decode(Double.self) { value = dbl; return }
        if let bool = try? container.decode(Bool.self) { value = bool; return }
        if let str = try? container.decode(String.self) { value = str; return }
        if let dict = try? container.decode([String: AnyCodable].self) { value = dict; return }
        if let arr = try? container.decode([AnyCodable].self) { value = arr; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int: try container.encode(int)
        case let dbl as Double: try container.encode(dbl)
        case let bool as Bool: try container.encode(bool)
        case let str as String: try container.encode(str)
        case let dict as [String: AnyCodable]: try container.encode(dict)
        case let arr as [AnyCodable]: try container.encode(arr)
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type")
            throw EncodingError.invalidValue(value, context)
        }
    }
}

// MARK: - Flow View

struct SharedSetupFlowView: View {
    @Environment(AppController.self) private var appController
    @Environment(\.dismiss) private var dismiss
    private let brand = BrandPalette()

    @State private var setup: SetupDoc = SetupDoc()
    @State private var listener: ListenerRegistration?
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var myAppSelection: FamilyActivitySelection = FamilyActivitySelection()
    @State private var showingPicker = false

    // Default range crosses midnight by design; supported by enforcement logic.
    @State private var myWeeklyPlan: WeeklyBlockPlan = .replicated(startMinutes: 21*60, endMinutes: 7*60)

    // Track revision lifecycle during this presentation
    @State private var revisionActive = false
    @State private var didCheckForAutoStart = false

    // Partner display name (fetched locally)
    @State private var partnerDisplayName: String = ""

    private var db: Firestore { Firestore.firestore() }
    private var pairId: String? { appController.pairId }
    private var uid: String? { Auth.auth().currentUser?.uid }

    private let totalSteps = 2

    var body: some View {
        ZStack {
            brand.background()

            VStack(spacing: 0) {
                // Top header
                VStack(spacing: 12) {
                    HeaderWithProgress(
                        title: "Mate setup",
                        subtitle: "Pick gambling apps, set your hours, approve each other.",
                        stepIndex: setup.stepIndex,
                        totalSteps: totalSteps,
                        brand: brand,
                        partnerName: partnerDisplayName
                    )
                    InfoCarousel(brand: brand)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 8)
                .padding(.bottom, 6)

                // Status strip
                HStack(spacing: 8) {
                    roleBadge
                    Divider().frame(height: 12)
                    Text(stepTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("Gambling prevention", systemImage: "shield.lefthalf.filled")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(brand.accent)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(brand.error)
                        .font(.footnote)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }

                // Content
                Group {
                    if shouldShowWaitingFullScreen {
                        WaitingFullScreen(
                            title: waitingTitle,
                            message: waitingMessageLong,
                            brand: brand
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.opacity)
                    } else {
                        ScrollView {
                            VStack(spacing: 14) {
                                // Mate overview card is always visible at top for context
                                MateOverviewCard(
                                    brand: brand,
                                    partnerName: partnerDisplayName,
                                    approvedSelection: unionApprovedSelections(),
                                    approvedPlan: latestApprovedWeeklyPlan(),
                                    attemptsToday: AnalyticsStore.attemptsToday()
                                )
                                .padding(.horizontal, 20)

                                switch setup.step {
                                case SetupStepID.appSelection:
                                    AppSelectionStepView(
                                        selection: $myAppSelection,
                                        onOpenPicker: { showingPicker = true },
                                        onSubmit: { Task { await submitMyAppSelection_TX() } },
                                        onApprove: { Task { await approvePartnerSelection_TX() } },
                                        isSaving: isSaving,
                                        brand: brand,
                                        role: currentRole,
                                        phase: currentPhase,
                                        mySubmitted: mySubmitted,
                                        partnerSubmitted: partnerSubmitted
                                    )
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .padding(.horizontal, 20)

                                case SetupStepID.weeklySchedule:
                                    WeeklyScheduleStepView(
                                        plan: $myWeeklyPlan,
                                        onSubmit: { Task { await submitMyWeeklyPlan_TX() } },
                                        onApprove: { Task { await approvePartnerWeeklyPlan_TX() } },
                                        onReject: { Task { await rejectPartnerWeeklyPlan_TX() } },
                                        isSaving: isSaving,
                                        brand: brand,
                                        role: currentRole,
                                        phase: currentPhase,
                                        mySubmitted: mySubmitted,
                                        partnerSubmitted: partnerSubmitted,
                                        partnerPlanForApproval: partnerSubmittedPlanForApproval
                                    )
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .padding(.horizontal, 20)

                                default:
                                    VStack(spacing: 8) {
                                        Text("Finalizing setup…")
                                        ProgressView().tint(brand.accent)
                                    }
                                    .padding(.horizontal, 20)
                                }
                                Spacer(minLength: 100) // space for sticky bar
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Sticky action bar (shows log out and contextual info)
                bottomBar
            }
        }
        .navigationTitle("Mate setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    do { try appController.signOut() } catch { }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.body.weight(.semibold))
                }
                .tint(.red)
                .accessibilityLabel("Log out")
            }
        }
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $myAppSelection)
                    .navigationTitle("Choose activities")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showingPicker = false } }
                        ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingPicker = false } }
                    }
            }
            .presentationDetents([.large])
        }
        .task {
            await attachListener()
            await fetchPartnerDisplayName()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .onChange(of: setup.step) { _ in
            hydrateDraftsFromServer()
        }
        .onChange(of: setup.phase) { newPhase in
            // If we started a revision in this presentation and it completes, persist and dismiss.
            if revisionActive, SetupPhaseLocal(rawValue: newPhase) == .complete {
                persistApprovedConfiguration()
                revisionActive = false
                dismiss()
            }
        }
        .tint(brand.accent)
        .animation(.easeInOut(duration: 0.25), value: setup.step)
        .animation(.easeInOut(duration: 0.25), value: setup.phase)
    }

    // MARK: - Partner name fetch

    private func fetchPartnerDisplayName() async {
        guard let partner = appController.partnerUID, !partner.isEmpty else {
            await MainActor.run { self.partnerDisplayName = "Your mate" }
            return
        }
        do {
            let snap = try await db.collection("users").document(partner).getDocument()
            let name = (snap.data()?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.partnerDisplayName = (name?.isEmpty == false) ? name! : "Your mate"
            }
        } catch {
            await MainActor.run { self.partnerDisplayName = "Your mate" }
        }
    }

    // MARK: - Compact header helpers

    private var roleBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: currentRole == "A" ? "a.circle.fill" : "b.circle.fill")
                .foregroundStyle(brand.accent)
            Text("Role \(currentRole)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(brand.fieldBackground)
        )
    }

    private var stepTitle: String {
        switch setup.step {
        case SetupStepID.appSelection: return "Step 1 • Choose apps"
        case SetupStepID.weeklySchedule: return "Step 2 • Set schedule"
        default: return "Setup"
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.25)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phaseHintTitle)
                        .font(.footnote.weight(.semibold))
                    Text(phaseHintSubtitle)
                        .font(.caption2)
                        .foregroundStyle(brand.secondaryText)
                }
                Spacer()
                Button {
                    do { try appController.signOut() } catch { }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var phaseHintTitle: String {
        switch currentPhase {
        case .awaitingASubmission:
            return currentRole == "A" ? "Your turn to submit" : "Waiting for your partner"
        case .awaitingBApproval:
            return currentRole == "B" ? "Please review and approve" : "Awaiting partner approval"
        case .awaitingBSubmission:
            return currentRole == "B" ? "Your turn to submit" : "Waiting for your partner"
        case .awaitingAApproval:
            return currentRole == "A" ? "Please review and approve" : "Awaiting partner approval"
        case .complete:
            return "Setup complete"
        }
    }

    private var phaseHintSubtitle: String {
        switch currentPhase {
        case .awaitingASubmission, .awaitingBSubmission:
            return "Make your proposal and send it over."
        case .awaitingBApproval, .awaitingAApproval:
            return "Review your partner’s proposal."
        case .complete:
            return "You can request changes from Home later."
        }
    }

    // MARK: - Derived values

    private var currentPhase: SetupPhaseLocal {
        SetupPhaseLocal(rawValue: setup.phase) ?? .awaitingASubmission
    }

    private var currentRole: String {
        if appController.isMemberA { return "A" }
        if appController.isMemberB { return "B" }
        return "-"
    }

    private var mySubmitted: Bool {
        guard let uid else { return false }
        return setup.submitted[uid] ?? false
    }

    private var partnerSubmitted: Bool {
        guard let uid else { return false }
        return setup.submitted.first(where: { $0.key != uid })?.value ?? false
    }

    private var partnerSubmittedPlanForApproval: WeeklyBlockPlan? {
        guard setup.step == SetupStepID.weeklySchedule, let uid else { return nil }
        if let partnerPayload = setup.answers.first(where: { $0.key != uid })?.value {
            return decodeWeeklyPlan(from: partnerPayload)
        }
        return nil
    }

    // MARK: - Active/Waiting gating

    private var shouldShowWaitingFullScreen: Bool {
        let role = currentRole
        let phase = currentPhase

        switch (role, phase) {
        case ("A", .awaitingASubmission),
             ("B", .awaitingBApproval),
             ("B", .awaitingBSubmission),
             ("A", .awaitingAApproval):
            return false
        case (_, .complete):
            return false
        default:
            return true
        }
    }

    private var waitingTitle: String { "Waiting for your partner" }

    private var waitingMessageLong: String {
        let stepName = setup.step == SetupStepID.appSelection ? "apps" : "times"
        switch currentPhase {
        case .awaitingASubmission:
            return currentRole == "B" ? "Your partner is choosing \(stepName). Please look at their phone." : "Waiting…"
        case .awaitingBApproval:
            return currentRole == "A" ? "Waiting for your partner to confirm your proposal." : "Waiting…"
        case .awaitingBSubmission:
            return currentRole == "B" ? "Your turn to submit." : "Waiting…"
        case .awaitingAApproval:
            return currentRole == "A" ? "Please review and approve." : "Waiting…"
        case .complete:
            return "Setup complete."
        }
    }

    // MARK: - Firestore ops

    private func setupDocRef() -> DocumentReference? {
        guard let pairId else { return nil }
        return db.collection("pairSpaces").document(pairId).collection("setup").document("current")
    }

    private func ensureInitialDoc() async {
        guard let ref = setupDocRef() else { return }
        do {
            let snap = try await ref.getDocument()
            if !snap.exists {
                try await ref.setData([
                    "step": SetupStepID.appSelection,
                    "stepIndex": 0,
                    "answers": [:],
                    "approvals": [:],
                    "submitted": [:],
                    "approvedAnswers": [:],
                    "phase": SetupPhaseLocal.awaitingASubmission.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            } else {
                var writes: [String: Any] = [:]
                if (snap.data()?["step"] as? String) == nil {
                    writes["step"] = SetupStepID.appSelection
                    writes["stepIndex"] = 0
                }
                if (snap.data()?["submitted"] as? [String: Bool]) == nil {
                    writes["submitted"] = [:]
                }
                if (snap.data()?["approvedAnswers"] as? [String: Any]) == nil {
                    writes["approvedAnswers"] = [:]
                }
                if (snap.data()?["phase"] as? String) == nil {
                    writes["phase"] = SetupPhaseLocal.awaitingASubmission.rawValue
                }
                if !writes.isEmpty {
                    writes["updatedAt"] = FieldValue.serverTimestamp()
                    try await ref.setData(writes, merge: true)
                }
            }
        } catch {
            await MainActor.run { errorMessage = (error as NSError).localizedDescription }
        }
    }

    private func attachListener() async {
        await ensureInitialDoc()
        guard let ref = setupDocRef(), listener == nil else { return }
        listener = ref.addSnapshotListener { snapshot, error in
            if let error {
                Task { @MainActor in self.errorMessage = (error as NSError).localizedDescription }
                return
            }
            guard let data = snapshot?.data() else { return }
            let step = data["step"] as? String ?? SetupStepID.appSelection
            let stepIndex = data["stepIndex"] as? Int ?? 0
            let answersRaw = (data["answers"] as? [String: [String: Any]]) ?? [:]
            let approvalsRaw = (data["approvals"] as? [String: Bool]) ?? [:]
            let submittedRaw = (data["submitted"] as? [String: Bool]) ?? [:]
            let approvedRaw = (data["approvedAnswers"] as? [String: [String: Any]]) ?? [:]
            let phaseRaw = data["phase"] as? String ?? SetupPhaseLocal.awaitingASubmission.rawValue

            var answers: [String: [String: AnyCodable]] = [:]
            for (k, v) in answersRaw {
                var dict: [String: AnyCodable] = [:]
                for (dk, dv) in v { dict[dk] = AnyCodable(dv) }
                answers[k] = dict
            }

            var approvedAnswers: [String: [String: AnyCodable]] = [:]
            for (k, v) in approvedRaw {
                var dict: [String: AnyCodable] = [:]
                for (dk, dv) in v { dict[dk] = AnyCodable(dv) }
                approvedAnswers[k] = dict
            }

            Task { @MainActor in
                self.setup.step = step
                self.setup.stepIndex = stepIndex
                self.setup.answers = answers
                self.setup.approvals = approvalsRaw
                self.setup.submitted = submittedRaw
                self.setup.approvedAnswers = approvedAnswers
                self.setup.phase = phaseRaw
                self.errorMessage = nil
                self.hydrateDraftsFromServer()

                // On first load only: if doc is complete, persist and dismiss (do NOT auto-start a revision).
                if !self.didCheckForAutoStart {
                    self.didCheckForAutoStart = true
                    if SetupPhaseLocal(rawValue: phaseRaw) == .complete {
                        self.persistApprovedConfiguration()
                        self.revisionActive = false
                        self.dismiss()
                    }
                }
            }
        }
    }

    private func hydrateDraftsFromServer() {
        guard let uid else { return }
        if setup.step == SetupStepID.appSelection {
            if let payload = setup.answers[uid] {
                myAppSelection = decodeSelectionFromMap(payload)
            }
        } else if setup.step == SetupStepID.weeklySchedule {
            if let payload = setup.answers[uid] {
                myWeeklyPlan = decodeWeeklyPlan(from: payload) ?? myWeeklyPlan
            }
        }
    }

    // MARK: - Step 1: App selection

    private func submitMyAppSelection_TX() async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        defer { isSaving = false }

        let payload = encodeSelectionToMap(myAppSelection)
        let myRole = currentRole

        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    guard var data = snap.data() else { return nil }

                    guard (data["step"] as? String) == SetupStepID.appSelection else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 40, userInfo: [NSLocalizedDescriptionKey: "Not in app selection step."])
                        return nil
                    }

                    let phaseRaw = (data["phase"] as? String) ?? SetupPhaseLocal.awaitingASubmission.rawValue
                    guard let phase = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }

                    let canSubmitA = (myRole == "A" && phase == .awaitingASubmission)
                    let canSubmitB = (myRole == "B" && phase == .awaitingBSubmission)
                    guard canSubmitA || canSubmitB else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 41, userInfo: [NSLocalizedDescriptionKey: "You can’t submit at this time."])
                        return nil
                    }

                    var answers = (data["answers"] as? [String: Any]) ?? [:]
                    answers[uid] = payload
                    var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                    submitted[uid] = true

                    data["answers"] = answers
                    data["submitted"] = submitted
                    data["updatedAt"] = FieldValue.serverTimestamp()
                    data["phase"] = canSubmitA ? SetupPhaseLocal.awaitingBApproval.rawValue : SetupPhaseLocal.awaitingAApproval.rawValue

                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch { errorPtr?.pointee = error as NSError; return nil }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    private func approvePartnerSelection_TX() async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        defer { isSaving = false }

        let myUid = uid
        let role = currentRole
        let phase = currentPhase

        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    guard var data = snap.data() else { return nil }

                    guard (data["step"] as? String) == SetupStepID.appSelection else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 42, userInfo: [NSLocalizedDescriptionKey: "Not in app selection step."])
                        return nil
                    }

                    let phaseRaw = (data["phase"] as? String) ?? ""
                    guard let current = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }
                    let expected: SetupPhaseLocal = (role == "B") ? .awaitingBApproval : .awaitingAApproval
                    guard current == expected else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 43, userInfo: [NSLocalizedDescriptionKey: "Phase changed. Try again."])
                        return nil
                    }

                    let answers = (data["answers"] as? [String: Any]) ?? [:]
                    guard let partnerEntry = answers.first(where: { key, _ in key != myUid }) else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 44, userInfo: [NSLocalizedDescriptionKey: "No partner selection to approve yet."])
                        return nil
                    }
                    let partnerUid = partnerEntry.key
                    let partnerPayload = partnerEntry.value as? [String: Any] ?? [:]

                    var approvals = (data["approvals"] as? [String: Bool]) ?? [:]
                    approvals[myUid] = true
                    data["approvals"] = approvals

                    var approvedAnswers = (data["approvedAnswers"] as? [String: Any]) ?? [:]
                    approvedAnswers[partnerUid] = partnerPayload
                    data["approvedAnswers"] = approvedAnswers

                    data["step"] = SetupStepID.weeklySchedule
                    data["stepIndex"] = 1
                    data["answers"] = [:]
                    data["approvals"] = [:]
                    data["submitted"] = [:]
                    data["phase"] = SetupPhaseLocal.awaitingASubmission.rawValue
                    data["updatedAt"] = FieldValue.serverTimestamp()

                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch { errorPtr?.pointee = error as NSError; return nil }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    // MARK: - Step 2: Weekly schedule

    private func submitMyWeeklyPlan_TX() async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        defer { isSaving = false }

        let payload = encodeWeeklyPlan(myWeeklyPlan)
        let myRole = currentRole

        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    guard var data = snap.data() else { return nil }

                    guard (data["step"] as? String) == SetupStepID.weeklySchedule else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 50, userInfo: [NSLocalizedDescriptionKey: "Not in weekly schedule step."])
                        return nil
                    }

                    let phaseRaw = (data["phase"] as? String) ?? SetupPhaseLocal.awaitingASubmission.rawValue
                    guard let phase = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }

                    let canSubmitA = (myRole == "A" && phase == .awaitingASubmission)
                    let canSubmitB = (myRole == "B" && phase == .awaitingBSubmission)
                    guard canSubmitA || canSubmitB else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 51, userInfo: [NSLocalizedDescriptionKey: "You can’t submit at this time."])
                        return nil
                    }

                    var answers = (data["answers"] as? [String: Any]) ?? [:]
                    answers[uid] = payload
                    var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                    submitted[uid] = true

                    data["answers"] = answers
                    data["submitted"] = submitted
                    data["updatedAt"] = FieldValue.serverTimestamp()
                    data["phase"] = canSubmitA ? SetupPhaseLocal.awaitingBApproval.rawValue : SetupPhaseLocal.awaitingAApproval.rawValue

                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch { errorPtr?.pointee = error as NSError; return nil }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    private func approvePartnerWeeklyPlan_TX() async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        defer { isSaving = false }

        let myUid = uid
        let role = currentRole
        let phase = currentPhase

        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    guard var data = snap.data() else { return nil }

                    guard (data["step"] as? String) == SetupStepID.weeklySchedule else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 52, userInfo: [NSLocalizedDescriptionKey: "Not in weekly schedule step."])
                        return nil
                    }

                    let phaseRaw = (data["phase"] as? String) ?? ""
                    guard let current = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }
                    let expected: SetupPhaseLocal = (role == "B") ? .awaitingBApproval : .awaitingAApproval
                    guard current == expected else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 53, userInfo: [NSLocalizedDescriptionKey: "Phase changed. Try again."])
                        return nil
                    }

                    let answers = (data["answers"] as? [String: Any]) ?? [:]
                    guard let partnerEntry = answers.first(where: { key, _ in key != myUid }) else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 54, userInfo: [NSLocalizedDescriptionKey: "No partner schedule to approve yet."])
                        return nil
                    }
                    let partnerUid = partnerEntry.key
                    let partnerPayload = partnerEntry.value as? [String: Any] ?? [:]

                    var approvals = (data["approvals"] as? [String: Bool]) ?? [:]
                    approvals[myUid] = true
                    data["approvals"] = approvals

                    var approvedAnswers = (data["approvedAnswers"] as? [String: Any]) ?? [:]
                    approvedAnswers[partnerUid] = partnerPayload
                    data["approvedAnswers"] = approvedAnswers

                    if role == "B", phase == .awaitingBApproval {
                        data["phase"] = SetupPhaseLocal.awaitingBSubmission.rawValue
                        var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                        submitted[myUid] = false
                        data["submitted"] = submitted
                        approvals[myUid] = false
                        data["approvals"] = approvals
                    } else if role == "A", phase == .awaitingAApproval {
                        data["phase"] = SetupPhaseLocal.complete.rawValue
                        data["completedAt"] = FieldValue.serverTimestamp()
                    }

                    data["updatedAt"] = FieldValue.serverTimestamp()
                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch { errorPtr?.pointee = error as NSError; return nil }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    private func rejectPartnerWeeklyPlan_TX() async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        defer { isSaving = false }

        let myUid = uid
        let role = currentRole
        let phase = currentPhase

        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    guard var data = snap.data() else { return nil }

                    guard (data["step"] as? String) == SetupStepID.weeklySchedule else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 60, userInfo: [NSLocalizedDescriptionKey: "Not in weekly schedule step."])
                        return nil
                    }

                    let phaseRaw = (data["phase"] as? String) ?? ""
                    guard let current = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }
                    let expected: SetupPhaseLocal = (role == "B") ? .awaitingBApproval : .awaitingAApproval
                    guard current == expected else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 61, userInfo: [NSLocalizedDescriptionKey: "Phase changed. Try again."])
                        return nil
                    }

                    let answers = (data["answers"] as? [String: Any]) ?? [:]
                    guard let partnerEntry = answers.first(where: { key, _ in key != myUid }) else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 62, userInfo: [NSLocalizedDescriptionKey: "No partner schedule to reject."])
                        return nil
                    }
                    let partnerUid = partnerEntry.key

                    var approvals = (data["approvals"] as? [String: Bool]) ?? [:]
                    approvals.removeAll()
                    data["approvals"] = approvals

                    var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                    submitted[partnerUid] = false
                    data["submitted"] = submitted

                    if role == "B" && phase == .awaitingBApproval {
                        data["phase"] = SetupPhaseLocal.awaitingASubmission.rawValue
                    } else if role == "A" && phase == .awaitingAApproval {
                        data["phase"] = SetupPhaseLocal.awaitingBSubmission.rawValue
                    }

                    data["updatedAt"] = FieldValue.serverTimestamp()
                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch { errorPtr?.pointee = error as NSError; return nil }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    func startScheduleRevision_TX() async {
        guard let ref = setupDocRef() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    var data = snap.data() ?? [:]
                    // Start a full revision at Step 1 (appSelection), then proceed to weeklySchedule.
                    data["step"] = SetupStepID.appSelection
                    data["stepIndex"] = 0
                    data["answers"] = [:]
                    data["approvals"] = [:]
                    data["submitted"] = [:]
                    data["approvedAnswers"] = [:]
                    data["phase"] = SetupPhaseLocal.awaitingASubmission.rawValue
                    data["updatedAt"] = FieldValue.serverTimestamp()
                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch { errorPtr?.pointee = error as NSError; return nil }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    // MARK: - Encoding helpers

    private func encodeSelectionToMap(_ sel: FamilyActivitySelection) -> [String: Any] {
        let encoder = JSONEncoder()
        let appBase64: [String] = sel.applicationTokens.compactMap { token in
            guard let data = try? encoder.encode(token) else { return nil }
            return data.base64EncodedString()
        }
        let catBase64: [String] = sel.categoryTokens.compactMap { token in
            guard let data = try? encoder.encode(token) else { return nil }
            return data.base64EncodedString()
        }
        return [
            "appTokens": appBase64,
            "categoryTokens": catBase64
        ]
    }

    private func decodeSelectionFromMap(_ map: [String: AnyCodable]?) -> FamilyActivitySelection {
        var sel = FamilyActivitySelection()
        guard let map else { return sel }
        let decoder = JSONDecoder()
        if let appArr = map["appTokens"]?.value as? [Any] {
            let tokens: [ApplicationToken] = appArr.compactMap { any in
                guard let s = any as? String, let data = Data(base64Encoded: s) else { return nil }
                return try? decoder.decode(ApplicationToken.self, from: data)
            }
            sel.applicationTokens = Set(tokens)
        }
        if let catArr = map["categoryTokens"]?.value as? [Any] {
            let tokens: [ActivityCategoryToken] = catArr.compactMap { any in
                guard let s = any as? String, let data = Data(base64Encoded: s) else { return nil }
                return try? decoder.decode(ActivityCategoryToken.self, from: data)
            }
            sel.categoryTokens = Set(tokens)
        }
        return sel
    }

    private func encodeWeeklyPlan(_ plan: WeeklyBlockPlan) -> [String: Any] {
        var daysArr: [[String: Any]] = []
        for d in plan.days {
            let ranges: [[String: Any]] = d.ranges.map { ["startMinutes": $0.startMinutes, "endMinutes": $0.endMinutes] }
            daysArr.append([
                "weekday": d.weekdayRaw,
                "enabled": d.enabled,
                "ranges": ranges
            ])
        }
        return ["days": daysArr]
    }

    private func decodeWeeklyPlan(from map: [String: AnyCodable]?) -> WeeklyBlockPlan? {
        guard let map, let anyDays = map["days"]?.value as? [Any] else { return nil }
        var days: [DaySchedule] = []
        for anyDay in anyDays {
            guard let d = anyDay as? [String: Any] else { continue }
            let wd = (d["weekday"] as? Int) ?? Weekday.sunday.rawValue
            let enabled = (d["enabled"] as? Bool) ?? false
            let anyRanges = (d["ranges"] as? [Any]) ?? []
            var ranges: [TimeRange] = []
            for anyR in anyRanges {
                if let r = anyR as? [String: Any] {
                    let s = (r["startMinutes"] as? Int) ?? 0
                    let e = (r["endMinutes"] as? Int) ?? 0
                    ranges.append(TimeRange(startMinutes: s, endMinutes: e))
                }
            }
            days.append(DaySchedule(weekday: Weekday(rawValue: wd) ?? .sunday, enabled: enabled, ranges: ranges))
        }
        return WeeklyBlockPlan(days: days)
    }

    private func unionApprovedSelections() -> FamilyActivitySelection {
        var union = FamilyActivitySelection()
        for (_, payload) in setup.approvedAnswers {
            let sel = decodeSelectionFromMap(payload)
            union.applicationTokens.formUnion(sel.applicationTokens)
            union.categoryTokens.formUnion(sel.categoryTokens)
        }
        return union
    }

    private func latestApprovedWeeklyPlan() -> WeeklyBlockPlan? {
        for payload in setup.approvedAnswers.values.reversed() {
            if let plan = decodeWeeklyPlan(from: payload) {
                return plan
            }
        }
        return nil
    }

    private func persistApprovedConfiguration() {
        let selection = unionApprovedSelections()
        SharedConfigStore.save(selection: selection)

        if let plan = latestApprovedWeeklyPlan() {
            FocusScheduleViewModel.persistWeeklyPlanForShared(plan)
        } else {
            SharedConfigStore.save(isScheduleEnabled: true)
            postConfigDidChangeDarwinNotification()
            ReportingScheduler.shared.refreshMonitoringFromShared()
        }
    }
}

// MARK: - Header + Info

private struct HeaderWithProgress: View {
    let title: String
    let subtitle: String
    let stepIndex: Int
    let totalSteps: Int
    let brand: BrandPalette
    var partnerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.bold())
                    Text("\(subtitle) • With \(partnerName.isEmpty ? "your mate" : partnerName)")
                        .font(.callout)
                        .foregroundStyle(brand.secondaryText)
                }
                Spacer()
            }

            ProgressView(value: progress)
                .tint(brand.accent)
                .progressViewStyle(.linear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        let clampedIndex = max(0, min(stepIndex, totalSteps - 1))
        return Double(clampedIndex + 1) / Double(totalSteps)
    }
}

private struct InfoCarousel: View {
    let brand: BrandPalette
    @State private var index = 0

    private let slides: [(String, String, String)] = [
        ("shield.lefthalf.filled", "Block gambling temptations", "Pick betting, casino and other risky apps."),
        ("clock.badge.checkmark", "Agree on hours", "Choose windows that support each other."),
        ("person.2.fill", "Approve each other", "Only one phone is active at a time. Submit, approve, then swap.")
    ]

    var body: some View {
        TabView(selection: $index) {
            ForEach(slides.indices, id: \.self) { i in
                let slide = slides[i]
                HStack(spacing: 14) {
                    Image(systemName: slide.0)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(brand.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(slide.1)
                            .font(.headline)
                        Text(slide.2)
                            .font(.subheadline)
                            .foregroundStyle(brand.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(brand.fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(brand.cardStroke, lineWidth: 1)
                )
                .tag(i)
            }
        }
        .frame(height: 80)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }
}

// MARK: - Waiting card

private struct WaitingFullScreen: View {
    let title: String
    let message: String
    let brand: BrandPalette

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hourglass")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(brand.accent)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(brand.secondaryText)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Status row

private struct StatusRow: View {
    var mySubmitted: Bool
    var partnerSubmitted: Bool
    let brand: BrandPalette

    var body: some View {
        HStack(spacing: 10) {
            if mySubmitted {
                Label("You submitted", systemImage: "paperplane.fill")
                    .foregroundStyle(brand.accent)
            } else {
                Label("Not submitted yet", systemImage: "paperplane")
                    .foregroundStyle(brand.secondaryText)
            }
            Spacer()
            if partnerSubmitted {
                Label("Partner submitted", systemImage: "person.fill.checkmark")
                    .foregroundStyle(brand.accent)
            } else {
                Label("Partner hasn’t submitted", systemImage: "person")
                    .foregroundStyle(brand.secondaryText)
            }
        }
        .font(.footnote)
    }
}

private struct PrimaryActionButton: View {
    let title: String
    var isLoading: Bool
    let brand: BrandPalette
    var action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView().tint(.white)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(brand.primaryGradient())
            )
            .foregroundStyle(.white)
            .opacity(disabled || isLoading ? 0.7 : 1.0)
        }
        .disabled(disabled || isLoading)
    }
}

// MARK: - Mate Overview Card

private struct MateOverviewCard: View {
    let brand: BrandPalette
    let partnerName: String
    let approvedSelection: FamilyActivitySelection
    let approvedPlan: WeeklyBlockPlan?
    let attemptsToday: [AttemptEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .font(.system(size: 24))
                    .foregroundStyle(brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(partnerName.isEmpty ? "Your mate" : partnerName)")
                        .font(.headline)
                    Text("Overview • Activity and restrictions")
                        .font(.footnote)
                        .foregroundStyle(brand.secondaryText)
                }
                Spacer()
                Image(systemName: "shield")
                    .foregroundStyle(brand.accent)
            }

            // Selection summary
            HStack(spacing: 8) {
                Image(systemName: "apps.iphone")
                    .foregroundStyle(brand.secondaryText)
                Text(selectionSummary)
                    .font(.subheadline)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
            }

            // Plan summary
            if let plan = approvedPlan {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(brand.secondaryText)
                    Text(planSummary(plan))
                        .font(.subheadline)
                        .foregroundStyle(brand.secondaryText)
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(brand.secondaryText)
                    Text("No approved schedule yet")
                        .font(.subheadline)
                        .foregroundStyle(brand.secondaryText)
                    Spacer()
                }
            }

            Divider().opacity(0.25)

            // Lightweight activity today (from local analytics as placeholder)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(brand.accent)
                    Text("Today’s attempts")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                if attemptsToday.isEmpty {
                    Text("No blocked attempts recorded today.")
                        .font(.footnote)
                        .foregroundStyle(brand.secondaryText)
                } else {
                    let top = AnalyticsStore.topCulpritsToday(limit: 3)
                    ForEach(Array(top.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Image(systemName: entry.kind == "app" ? "app.fill" : "square.grid.2x2.fill")
                                .foregroundStyle(brand.secondaryText)
                            Text("\(readableIdentifier(entry.identifier))")
                                .font(.footnote)
                            Spacer()
                            Text("\(entry.count)×")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(brand.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var selectionSummary: String {
        let apps = approvedSelection.applicationTokens.count
        let cats = approvedSelection.categoryTokens.count
        if apps == 0 && cats == 0 { return "No approved apps or categories yet." }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        return parts.joined(separator: " + ")
    }

    private func planSummary(_ plan: WeeklyBlockPlan) -> String {
        let enabledDays = plan.days.filter { $0.enabled }
        if enabledDays.isEmpty { return "Schedule disabled" }
        // Show count of enabled days and first range as a hint
        if let first = enabledDays.first?.ranges.first {
            return "\(enabledDays.count) day\(enabledDays.count == 1 ? "" : "s") • \(timeString(minutes: first.startMinutes))–\(timeString(minutes: first.endMinutes))"
        }
        return "\(enabledDays.count) day\(enabledDays.count == 1 ? "" : "s")"
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

    private func readableIdentifier(_ raw: String) -> String {
        if let cached = SharedConfigStore.appName(for: raw) {
            return cached
        }
        return raw
    }
}

// MARK: - Step 1 UI: App selection

private struct AppSelectionStepView: View {
    @Binding var selection: FamilyActivitySelection
    var onOpenPicker: () -> Void
    var onSubmit: () -> Void
    var onApprove: () -> Void
    var isSaving: Bool
    let brand: BrandPalette

    let role: String
    let phase: SetupPhaseLocal

    var mySubmitted: Bool
    var partnerSubmitted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "dice.fill")
                    .foregroundStyle(brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Which gambling apps should be blocked?")
                        .font(.headline)
                    Text("Choose categories and apps. Submit your selection, then your mate will approve it.")
                        .foregroundStyle(brand.secondaryText)
                        .font(.footnote)
                }
                Spacer()
            }

            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
                Button {
                    onOpenPicker()
                } label: {
                    Label("Choose apps", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(!canEdit)
            }

            StatusRow(mySubmitted: mySubmitted, partnerSubmitted: partnerSubmitted, brand: brand)

            VStack(alignment: .leading, spacing: 8) {
                if role == "A", phase == .awaitingASubmission {
                    PrimaryActionButton(title: "Submit your selection", isLoading: isSaving, brand: brand, action: onSubmit, disabled: selectionIsEmpty)
                } else if role == "B", phase == .awaitingBApproval {
                    PrimaryActionButton(title: "Approve mate’s selection", isLoading: isSaving, brand: brand, action: onApprove)
                } else if role == "B", phase == .awaitingBSubmission {
                    PrimaryActionButton(title: "Submit your selection", isLoading: isSaving, brand: brand, action: onSubmit, disabled: selectionIsEmpty)
                } else if role == "A", phase == .awaitingAApproval {
                    PrimaryActionButton(title: "Approve mate’s selection", isLoading: isSaving, brand: brand, action: onApprove)
                } else if phase == .complete {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
    }

    private var canEdit: Bool {
        switch (role, phase) {
        case ("A", .awaitingASubmission), ("B", .awaitingBSubmission):
            return true
        default:
            return false
        }
    }

    private var selectionIsEmpty: Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
    }

    private var summary: String {
        let apps = selection.applicationTokens.count
        let cats = selection.categoryTokens.count
        if apps == 0 && cats == 0 { return "No selection yet." }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if cats > 0 { parts.append("\(cats) categor\(cats == 1 ? "y" : "ies")") }
        return parts.joined(separator: " + ")
    }
}

// MARK: - Step 2 UI: Weekly schedule (with range sliders)

private struct WeeklyScheduleStepView: View {
    @Binding var plan: WeeklyBlockPlan
    var onSubmit: () -> Void
    var onApprove: () -> Void
    var onReject: () -> Void
    var isSaving: Bool
    let brand: BrandPalette

    let role: String
    let phase: SetupPhaseLocal

    var mySubmitted: Bool
    var partnerSubmitted: Bool

    var partnerPlanForApproval: WeeklyBlockPlan?

    @State private var collapsed: [Bool] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("When should blocking be active?")
                        .font(.headline)
                    Text("Choose days and add one or more time ranges for each. Your mate will confirm your plan.")
                        .foregroundStyle(brand.secondaryText)
                        .font(.footnote)
                }
                Spacer()
            }

            if isApprovalPhase, let partnerPlanForApproval {
                ReadOnlyPlanView(plan: partnerPlanForApproval, brand: brand)
                    .padding(.vertical, 6)
            } else {
                Toggle(isOn: Binding(
                    get: { anyDayEnabled },
                    set: { enabled in
                        for i in plan.days.indices {
                            plan.days[i].enabled = enabled
                            if enabled && plan.days[i].ranges.isEmpty {
                                plan.days[i].ranges = [TimeRange(startMinutes: 21*60, endMinutes: 7*60)]
                            }
                        }
                    }
                )) { Text(anyDayEnabled ? "Schedule enabled" : "Schedule disabled") }
                .disabled(isApprovalPhase)

                if !plan.days.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation { collapsed = Array(repeating: false, count: plan.days.count) }
                        } label: { Text("Expand all").font(.footnote.weight(.semibold)) }
                        .buttonStyle(.bordered)
                        .disabled(isApprovalPhase)

                        Button {
                            withAnimation { collapsed = Array(repeating: true, count: plan.days.count) }
                        } label: { Text("Collapse all").font(.footnote.weight(.semibold)) }
                        .buttonStyle(.bordered)
                        .disabled(isApprovalPhase)

                        Spacer()
                    }
                }

                VStack(spacing: 10) {
                    ForEach(plan.days.indices, id: \.self) { idx in
                        dayEditor(dayIndex: idx)
                            .opacity(isApprovalPhase ? 0.6 : 1.0)
                            .allowsHitTesting(!isApprovalPhase)
                    }
                }
            }

            StatusRow(mySubmitted: mySubmitted, partnerSubmitted: partnerSubmitted, brand: brand)

            VStack(alignment: .leading, spacing: 8) {
                if role == "A", phase == .awaitingASubmission {
                    PrimaryActionButton(title: "Submit your schedule", isLoading: isSaving, brand: brand, action: onSubmit, disabled: !isValid)
                } else if role == "B", phase == .awaitingBApproval {
                    approvalButtons
                } else if role == "B", phase == .awaitingBSubmission {
                    PrimaryActionButton(title: "Submit your schedule", isLoading: isSaving, brand: brand, action: onSubmit, disabled: !isValid)
                } else if role == "A", phase == .awaitingAApproval {
                    approvalButtons
                } else if phase == .complete {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
        .onAppear {
            if collapsed.count != plan.days.count {
                collapsed = defaultCollapsedStates()
            }
        }
        .onChange(of: plan.days.count) { _ in
            if collapsed.count != plan.days.count {
                collapsed = defaultCollapsedStates()
            }
        }
    }

    private var isApprovalPhase: Bool {
        return (role == "B" && phase == .awaitingBApproval) || (role == "A" && phase == .awaitingAApproval)
    }

    private var approvalButtons: some View {
        HStack(spacing: 10) {
            PrimaryActionButton(title: "Approve", isLoading: isSaving, brand: brand, action: onApprove)
            Button(role: .destructive, action: onReject) {
                Label("Reject", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func defaultCollapsedStates() -> [Bool] {
        let today = Weekday.today()
        return plan.days.map { $0.weekday != today }
    }

    private var anyDayEnabled: Bool {
        plan.days.contains(where: { $0.enabled })
    }

    private var isValid: Bool {
        plan.days.contains { $0.enabled && !$0.ranges.isEmpty }
    }

    @ViewBuilder
    private func dayEditor(dayIndex: Int) -> some View {
        let day = plan.days[dayIndex]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation { collapsed[dayIndex].toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: collapsed[safe: dayIndex] == true ? "chevron.right" : "chevron.down")
                            .foregroundStyle(.secondary)
                        Text(weekdayDisplayName(Weekday(rawValue: day.weekdayRaw) ?? .sunday))
                            .font(.callout.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Toggle(isOn: Binding(
                    get: { day.enabled },
                    set: { plan.days[dayIndex].enabled = $0 }
                )) {
                    Text(day.enabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)

                Button {
                    plan.days[dayIndex].enabled = true
                    plan.days[dayIndex].ranges.append(TimeRange(startMinutes: 21*60, endMinutes: 7*60))
                    if collapsed[safe: dayIndex] == true {
                        withAnimation { collapsed[dayIndex] = false }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!day.enabled)
            }

            if day.enabled && (collapsed[safe: dayIndex] == false) {
                if day.ranges.isEmpty {
                    Text("No ranges. Add one to block on this day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(day.ranges.indices, id: \.self) { rIdx in
                        rangeEditor(dayIndex: dayIndex, rangeIndex: rIdx)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rangeEditor(dayIndex: Int, rangeIndex: Int) -> some View {
        let range = plan.days[dayIndex].ranges[rangeIndex]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(timeString(minutes: range.startMinutes)) – \(timeString(minutes: range.endMinutes))", systemImage: "clock")
                    .foregroundStyle(.primary)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    plan.days[dayIndex].ranges.remove(at: rangeIndex)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            // Dual-ended slider for 0...1439 minutes
            RangeSlider(
                start: Binding(
                    get: { Double(range.startMinutes) },
                    set: { newVal in plan.days[dayIndex].ranges[rangeIndex].startMinutes = Int(newVal) }
                ),
                end: Binding(
                    get: { Double(range.endMinutes) },
                    set: { newVal in plan.days[dayIndex].ranges[rangeIndex].endMinutes = Int(newVal) }
                ),
                minValue: 0,
                maxValue: 1439,
                minGap: 15, // at least 15 minutes
                accent: brand.accent
            )

            // Accessibility fallback: tap to edit precise times
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Start").font(.caption).foregroundStyle(.secondary)
                    DatePicker(
                        "",
                        selection: Binding<Date>(
                            get: { date(fromMinutes: range.startMinutes) },
                            set: { newDate in
                                plan.days[dayIndex].ranges[rangeIndex].startMinutes = minutes(from: newDate)
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("End").font(.caption).foregroundStyle(.secondary)
                    DatePicker(
                        "",
                        selection: Binding<Date>(
                            get: { date(fromMinutes: range.endMinutes) },
                            set: { newDate in
                                plan.days[dayIndex].ranges[rangeIndex].endMinutes = minutes(from: newDate)
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                }
                Spacer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
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

private extension Array where Element == Bool {
    subscript(safe index: Int) -> Bool? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

// MARK: - RangeSlider (dual-ended) for minutes 0...1439

private struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let minValue: Double
    let maxValue: Double
    let minGap: Double
    let accent: Color

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let startX = x(for: start, width: width)
            let endX = x(for: end, width: width)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)

                Capsule().fill(accent)
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)

                // Start thumb
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(accent, lineWidth: 2))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: startX - thumbSize/2, y: -(thumbSize - trackHeight)/2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let clamped = value.location.x.clamped(to: 0...width)
                                let minutes = valueToMinutes(clamped, width: width)
                                let limited = min(maxValue - minGap, max(minValue, minutes))
                                start = min(limited, end - minGap)
                            }
                    )

                // End thumb
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(accent, lineWidth: 2))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: endX - thumbSize/2, y: -(thumbSize - trackHeight)/2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let clamped = value.location.x.clamped(to: 0...width)
                                let minutes = valueToMinutes(clamped, width: width)
                                let limited = max(minValue + minGap, min(maxValue, minutes))
                                end = max(limited, start + minGap)
                            }
                    )
            }
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time range")
        .accessibilityValue("\(minutesToTimeString(Int(start))) to \(minutesToTimeString(Int(end)))")
    }

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        let t = (value - minValue) / (maxValue - minValue)
        return CGFloat(t) * width
    }

    private func valueToMinutes(_ x: CGFloat, width: CGFloat) -> Double {
        let t = max(0, min(1, x / max(1, width)))
        return minValue + (maxValue - minValue) * Double(t)
    }

    private func minutesToTimeString(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let comps = DateComponents(hour: h, minute: m)
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
