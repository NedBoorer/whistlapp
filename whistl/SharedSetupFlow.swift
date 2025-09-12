import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FamilyControls
import ManagedSettings

// MARK: - Firestore models

struct SetupStepID {
    static let appSelection  = "appSelection"   // Step 1
    static let weeklySchedule = "weeklySchedule" // Step 2 (per-day ranges)
}

// Per-day time range for schedule persistence when needed locally
struct BlockSchedule: Codable, Equatable {
    var startMinutes: Int // minutes since midnight
    var endMinutes: Int
}

// Keep this aligned with AppController.SetupPhase raw values
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
    var answers: [String: [String: AnyCodable]]       // answers[uid] = payload
    var approvals: [String: Bool]                     // approvals[uid] = true/false
    var submitted: [String: Bool]                     // submitted[uid] = true/false
    var approvedAnswers: [String: [String: AnyCodable]] // approvedAnswers[uid] = payload snapshot at approval time
    var phase: String                                 // server-controlled phase
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

// AnyCodable-like wrapper for simple Firestore encoding
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
    private let brand = BrandPalette()

    @State private var setup: SetupDoc = SetupDoc()
    @State private var listener: ListenerRegistration?
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Step 1: App selection draft
    @State private var myAppSelection: FamilyActivitySelection = FamilyActivitySelection()
    @State private var showingPicker = false

    // Step 2: Weekly schedule draft
    @State private var myWeeklyPlan: WeeklyBlockPlan = .replicated(startMinutes: 21*60, endMinutes: 7*60)

    // Navigation to home when flow completes
    @State private var navigateToHome = false

    private var db: Firestore { Firestore.firestore() }
    private var pairId: String? { appController.pairId }
    private var uid: String? { Auth.auth().currentUser?.uid }

    // Total steps: 2 (Selection, Weekly schedule)
    private let totalSteps = 2

    var body: some View {
        ZStack {
            brand.background()

            VStack(spacing: 20) {
                HeaderWithProgress(
                    title: "Set up your blocker together",
                    subtitle: "Only one phone is active at a time. First choose apps, then set time windows.",
                    stepIndex: setup.stepIndex,
                    totalSteps: totalSteps,
                    brand: brand
                )

                InfoCarousel(brand: brand)

                HStack(spacing: 8) {
                    Text("Role: \(currentRole) • Step: \(setup.step) • Phase: \(setup.phase)")
                        .font(.caption2)
                        .foregroundStyle(brand.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 20)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(brand.error)
                        .font(.footnote)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }

                Group {
                    if shouldShowWaitingFullScreen {
                        WaitingFullScreen(
                            title: waitingTitle,
                            message: waitingMessageLong,
                            brand: brand
                        )
                        .transition(.opacity)
                        .padding(.horizontal, 20)
                    } else {
                        // Make the step content scrollable so actions are reachable
                        ScrollView {
                            VStack(spacing: 12) {
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
                                        isSaving: isSaving,
                                        brand: brand,
                                        role: currentRole,
                                        phase: currentPhase,
                                        mySubmitted: mySubmitted,
                                        partnerSubmitted: partnerSubmitted
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
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Button {
                        do { try appController.signOut() } catch { }
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .tint(.red)
                }
                .padding(.horizontal, 20)

                NavigationLink(isActive: $navigateToHome) {
                    WhisprHomeView()
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    EmptyView()
                }
                .hidden()
            }
        }
        .navigationTitle("Partner setup")
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
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $myAppSelection)
                    .navigationTitle("Choose activities")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingPicker = false }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showingPicker = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .task {
            await attachListener()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .onChange(of: setup.step) { _ in
            // When step changes, try hydrate local drafts from server answers if present
            hydrateDraftsFromServer()
        }
        .onChange(of: setup.phase) { newPhase in
            if SetupPhaseLocal(rawValue: newPhase) == .complete {
                persistApprovedConfiguration() // now writes selection + weekly plan to shared + enforces
                navigateToHome = true
            }
        }
        .tint(brand.accent)
        .animation(.easeInOut(duration: 0.25), value: setup.step)
        .animation(.easeInOut(duration: 0.25), value: setup.phase)
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

    private var myApproved: Bool {
        guard let uid else { return false }
        return setup.approvals[uid] ?? false
    }

    private var partnerApproved: Bool {
        guard let uid else { return false }
        return setup.approvals.first(where: { $0.key != uid })?.value ?? false
    }

    private var mySubmitted: Bool {
        guard let uid else { return false }
        return setup.submitted[uid] ?? false
    }

    private var partnerSubmitted: Bool {
        guard let uid else { return false }
        return setup.submitted.first(where: { $0.key != uid })?.value ?? false
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
            return currentRole == "A" ? "Your partner is choosing \(stepName). Please look at their phone." : "Waiting…"
        case .awaitingAApproval:
            return currentRole == "B" ? "Waiting for your partner to confirm your proposal." : "Waiting…"
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
                    "step": SetupStepID.appSelection, // start with app selection
                    "stepIndex": 0,
                    "answers": [:],
                    "approvals": [:],
                    "submitted": [:],
                    "approvedAnswers": [:],
                    "phase": SetupPhaseLocal.awaitingASubmission.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            } else {
                if (snap.data()?["step"] as? String) == nil {
                    try await ref.setData(["step": SetupStepID.appSelection, "stepIndex": 0], merge: true)
                }
                if (snap.data()?["submitted"] as? [String: Bool]) == nil {
                    try await ref.setData(["submitted": [:]], merge: true)
                }
                if (snap.data()?["approvedAnswers"] as? [String: Any]) == nil {
                    try await ref.setData(["approvedAnswers": [:]], merge: true)
                }
                if (snap.data()?["phase"] as? String) == nil {
                    try await ref.setData(["phase": SetupPhaseLocal.awaitingASubmission.rawValue], merge: true)
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
                for (dk, dv) in v {
                    dict[dk] = AnyCodable(dv)
                }
                answers[k] = dict
            }

            var approvedAnswers: [String: [String: AnyCodable]] = [:]
            for (k, v) in approvedRaw {
                var dict: [String: AnyCodable] = [:]
                for (dk, dv) in v {
                    dict[dk] = AnyCodable(dv)
                }
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
            }
        }
    }

    private func hydrateDraftsFromServer() {
        // On each step, hydrate local draft with my previous answer if present
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

    // MARK: - Step 1: App selection (Transactional)

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

                    // Move to next step (weeklySchedule) and reset per-step fields; phase returns to awaitingASubmission
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

    // MARK: - Step 2: Weekly schedule (Transactional)

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
                        // Move to B submission
                        data["phase"] = SetupPhaseLocal.awaitingBSubmission.rawValue
                        var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                        submitted[myUid] = false
                        data["submitted"] = submitted
                        approvals[myUid] = false
                        data["approvals"] = approvals
                    } else if role == "A", phase == .awaitingAApproval {
                        // Finish entire setup
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

    // Weekly plan encoding: { days: [ { weekday: Int, enabled: Bool, ranges: [ { startMinutes, endMinutes } ] } ] }
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
        // Try decoding weekly plan from the last approved payload that has "days"
        for payload in setup.approvedAnswers.values.reversed() {
            if let plan = decodeWeeklyPlan(from: payload) {
                return plan
            }
        }
        return nil
    }

    // MARK: - Finalization: persist approved config to Shared + enforce

    private func persistApprovedConfiguration() {
        // Persist union of approved app selections
        let selection = unionApprovedSelections()
        SharedConfigStore.save(selection: selection)

        // Persist weekly plan (if present) to shared and enable schedule
        if let plan = latestApprovedWeeklyPlan() {
            FocusScheduleViewModel.persistWeeklyPlanForShared(plan)
        } else {
            // Fallback: enable schedule with a default single window if none found
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(brand.accent)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(brand.secondaryText)

            ProgressView(value: progress)
                .tint(brand.accent)
                .progressViewStyle(.linear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
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
        ("apps.iphone", "Pick what to block", "Choose categories and apps to keep off-limits."),
        ("calendar.badge.clock", "Set your hours", "Pick days and time windows that work for both of you."),
        ("person.2.fill", "Approve each other", "Only one phone is active at a time. Submit, approve, then swap.")
    ]

    var body: some View {
        TabView(selection: $index) {
            ForEach(slides.indices, id: \.self) { i in
                let slide = slides[i]
                VStack(spacing: 10) {
                    Image(systemName: slide.0)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(brand.accent)

                    Text(slide.1)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(slide.2)
                        .font(.subheadline)
                        .foregroundStyle(brand.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(brand.fieldBackground)
                )
                .padding(.horizontal, 20)
                .tag(i)
            }
        }
        .frame(height: 150)
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
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(brand.accent)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
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
                Text("Not submitted yet")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }
            Spacer()
            if partnerSubmitted {
                Label("Partner submitted", systemImage: "paperplane")
                    .foregroundStyle(brand.accent)
            } else {
                Text("Partner hasn’t submitted")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }
        }
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
        }
        .disabled(disabled || isLoading)
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
            Text("Which apps should be blocked?")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Choose categories and apps below. Submit your selection, then your partner will approve it.")
                .foregroundStyle(brand.secondaryText)
                .font(.footnote)

            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
                Button("Choose apps") { onOpenPicker() }
                    .buttonStyle(.bordered)
            }

            StatusRow(mySubmitted: mySubmitted, partnerSubmitted: partnerSubmitted, brand: brand)

            VStack(alignment: .leading, spacing: 8) {
                if role == "A", phase == .awaitingASubmission {
                    PrimaryActionButton(title: "Submit your selection", isLoading: isSaving, brand: brand, action: onSubmit, disabled: selectionIsEmpty)
                } else if role == "B", phase == .awaitingBApproval {
                    PrimaryActionButton(title: "Approve partner’s selection", isLoading: isSaving, brand: brand, action: onApprove)
                } else if role == "B", phase == .awaitingBSubmission {
                    PrimaryActionButton(title: "Submit your selection", isLoading: isSaving, brand: brand, action: onSubmit, disabled: selectionIsEmpty)
                } else if role == "A", phase == .awaitingAApproval {
                    PrimaryActionButton(title: "Approve partner’s selection", isLoading: isSaving, brand: brand, action: onApprove)
                } else if phase == .complete {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
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

// MARK: - Step 2 UI: Weekly schedule

private struct WeeklyScheduleStepView: View {
    @Binding var plan: WeeklyBlockPlan
    var onSubmit: () -> Void
    var onApprove: () -> Void
    var isSaving: Bool
    let brand: BrandPalette

    let role: String
    let phase: SetupPhaseLocal

    var mySubmitted: Bool
    var partnerSubmitted: Bool

    // Collapsible days state
    @State private var collapsed: [Bool] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When should blocking be active?")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Choose days and add one or more time ranges for each. Your mate will confirm your plan.")
                .foregroundStyle(brand.secondaryText)
                .font(.footnote)

            Toggle(isOn: Binding(
                get: { anyDayEnabled },
                set: { enabled in
                    // Toggle all days at once if user flips this
                    for i in plan.days.indices {
                        plan.days[i].enabled = enabled
                        if enabled && plan.days[i].ranges.isEmpty {
                            plan.days[i].ranges = [TimeRange(startMinutes: 21*60, endMinutes: 7*60)]
                        }
                    }
                }
            )) { Text(anyDayEnabled ? "Schedule enabled" : "Schedule disabled") }

            // Expand/Collapse controls
            if !plan.days.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            collapsed = Array(repeating: false, count: plan.days.count)
                        }
                    } label: { Text("Expand all").font(.footnote.weight(.semibold)) }
                    .buttonStyle(.bordered)

                    Button {
                        withAnimation {
                            collapsed = Array(repeating: true, count: plan.days.count)
                        }
                    } label: { Text("Collapse all").font(.footnote.weight(.semibold)) }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }

            VStack(spacing: 10) {
                ForEach(plan.days.indices, id: \.self) { idx in
                    dayEditor(dayIndex: idx)
                }
            }

            StatusRow(mySubmitted: mySubmitted, partnerSubmitted: partnerSubmitted, brand: brand)

            VStack(alignment: .leading, spacing: 8) {
                if role == "A", phase == .awaitingASubmission {
                    PrimaryActionButton(title: "Submit your schedule", isLoading: isSaving, brand: brand, action: onSubmit, disabled: !isValid)
                } else if role == "B", phase == .awaitingBApproval {
                    PrimaryActionButton(title: "Approve partner’s schedule", isLoading: isSaving, brand: brand, action: onApprove)
                } else if role == "B", phase == .awaitingBSubmission {
                    PrimaryActionButton(title: "Submit your schedule", isLoading: isSaving, brand: brand, action: onSubmit, disabled: !isValid)
                } else if role == "A", phase == .awaitingAApproval {
                    PrimaryActionButton(title: "Approve partner’s schedule", isLoading: isSaving, brand: brand, action: onApprove)
                } else if phase == .complete {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .onAppear {
            // Initialize collapsed states if needed
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

    private func defaultCollapsedStates() -> [Bool] {
        // Collapse all except today to keep UI short
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rangeEditor(dayIndex: Int, rangeIndex: Int) -> some View {
        let range = plan.days[dayIndex].ranges[rangeIndex]
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

            Image(systemName: "arrow.right").foregroundStyle(.secondary)

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

            Button(role: .destructive) {
                plan.days[dayIndex].ranges.remove(at: rangeIndex)
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
}

// Safe subscript to avoid index crashes for collapsed array
private extension Array where Element == Bool {
    subscript(safe index: Int) -> Bool? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
