import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FamilyControls
import ManagedSettings

// MARK: - Firestore models

struct SetupStepID {
    static let blockSchedule = "blockSchedule"
    static let appSelection  = "appSelection"
}

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

    init(step: String = SetupStepID.blockSchedule,
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

    // local draft for A or B before submission (times)
    @State private var myDraftBlock: BlockSchedule = BlockSchedule(startMinutes: 21*60, endMinutes: 7*60)

    // local draft for app selection
    @State private var myAppSelection: FamilyActivitySelection = FamilyActivitySelection()

    // Navigation to home when flow completes
    @State private var navigateToHome = false

    private var db: Firestore { Firestore.firestore() }
    private var pairId: String? { appController.pairId }
    private var uid: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        ZStack {
            brand.background()

            VStack(spacing: 20) {
                // Top header with gradient and progress
                HeaderWithProgress(
                    title: "Set up your blocker together",
                    subtitle: "Only one phone is active at a time. Submit, your mate approves, then swap.",
                    stepIndex: setup.stepIndex,
                    totalSteps: 2,
                    brand: brand
                )

                // Info slides / small carousel
                InfoCarousel(brand: brand)

                // Debug/status banner to verify role/phase on each device
                HStack(spacing: 8) {
                    Text("Role: \(currentRole) • Phase: \(setup.phase)")
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

                // Step content OR Waiting screen (enforce "only one phone active at a time")
                Group {
                    if shouldShowWaitingFullScreen {
                        WaitingFullScreen(
                            title: waitingTitle,
                            message: waitingMessageLong,
                            brand: brand
                        )
                        .transition(.opacity)
                    } else {
                        switch setup.step {
                        case SetupStepID.blockSchedule:
                            BlockScheduleStepView(
                                myAnswer: myBlockAnswer,
                                partnerAnswer: partnerBlockAnswer,
                                myApproved: myApproved,
                                partnerApproved: partnerApproved,
                                mySubmitted: mySubmitted,
                                partnerSubmitted: partnerSubmitted,
                                onDraftChange: { ans in myDraftBlock = ans },
                                onSubmit: { Task { await submitMyBlockProposal_TX() } },
                                onApprove: { Task { await approvePartnerProposal_TX() } },
                                isSaving: isSaving,
                                brand: brand,
                                role: currentRole,
                                phase: currentPhase
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        case SetupStepID.appSelection:
                            AppSelectionStepView(
                                myApproved: myApproved,
                                partnerApproved: partnerApproved,
                                onSubmit: { Task { await submitMyAppSelection_TX() } },
                                onApprove: { Task { await approvePartnerSelection_TX() } },
                                isSaving: isSaving,
                                brand: brand,
                                role: currentRole,
                                phase: currentPhase,
                                selection: $myAppSelection
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        default:
                            VStack(spacing: 8) {
                                Text("Finalizing setup…")
                                ProgressView().tint(brand.accent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                // Inline logout as safe exit
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

                // Hidden navigation to home after completion
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
        .task {
            await attachListener()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .onChange(of: myBlockAnswer) { _ in
            // keep local draft in sync with latest server answer for convenience
            if let mine = myBlockAnswer {
                myDraftBlock = mine
            }
        }
        .onChange(of: setup.phase) { newPhase in
            // Navigate to home when phase turns complete
            if SetupPhaseLocal(rawValue: newPhase) == .complete {
                persistApprovedConfiguration()
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

    private var myBlockAnswer: BlockSchedule? {
        guard let uid else { return nil }
        return decodeBlock(from: setup.answers[uid])
    }

    private var partnerBlockAnswer: BlockSchedule? {
        // Prefer explicit "other uid" when we know mine; otherwise fall back to "only answer present"
        if let uid, let partnerAnswers = setup.answers.first(where: { $0.key != uid })?.value {
            return decodeBlock(from: partnerAnswers)
        }
        if setup.answers.count == 1, let only = setup.answers.values.first {
            return decodeBlock(from: only)
        }
        return nil
    }

    private func decodeBlock(from dict: [String: AnyCodable]?) -> BlockSchedule? {
        guard let dict else { return nil }
        let start = (dict["startMinutes"]?.value as? Int) ?? 0
        let end = (dict["endMinutes"]?.value as? Int) ?? 0
        return BlockSchedule(startMinutes: start, endMinutes: end)
    }

    // MARK: - Active/Waiting gating

    // Decide if this device should be in waiting full-screen state
    private var shouldShowWaitingFullScreen: Bool {
        let role = currentRole
        let phase = currentPhase

        // Active states:
        // A can submit in awaitingASubmission; B approves in awaitingBApproval
        // B can submit in awaitingBSubmission; A approves in awaitingAApproval
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

    private var waitingTitle: String {
        "Waiting for your partner"
    }

    private var waitingMessageLong: String {
        switch currentPhase {
        case .awaitingASubmission:
            return currentRole == "B" ? "Your partner is choosing times. Please look at their phone." : "Waiting…"
        case .awaitingBApproval:
            return currentRole == "A" ? "Waiting for your partner to confirm your proposal." : "Waiting…"
        case .awaitingBSubmission:
            return currentRole == "A" ? "Your partner is choosing times. Please look at their phone." : "Waiting…"
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
                    "step": SetupStepID.blockSchedule,
                    "stepIndex": 0,
                    "answers": [:],
                    "approvals": [:],
                    "submitted": [:],
                    "approvedAnswers": [:],
                    "phase": SetupPhaseLocal.awaitingASubmission.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            } else {
                // Ensure fields exist if migrating
                try await ref.setData([
                    "submitted": FieldValue.delete()
                ], merge: true)
                try await ref.setData([
                    "submitted": [:]
                ], merge: true)
                if (snap.data()?["phase"] as? String) == nil {
                    try await ref.setData([
                        "phase": SetupPhaseLocal.awaitingASubmission.rawValue
                    ], merge: true)
                }
                if (snap.data()?["approvedAnswers"] as? [String: Any]) == nil {
                    try await ref.setData([
                        "approvedAnswers": [:]
                    ], merge: true)
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
            // Lightweight decode
            let step = data["step"] as? String ?? SetupStepID.blockSchedule
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
            }
        }
    }

    // MARK: - Step 1: Block schedule submission/approval (Transactional)

    private func submitMyBlockProposal_TX() async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        defer { isSaving = false }

        let payload: [String: Any] = [
            "startMinutes": myDraftBlock.startMinutes,
            "endMinutes": myDraftBlock.endMinutes
        ]

        let myRole = currentRole

        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    guard var data = snap.data() else { return nil }

                    let phaseRaw = (data["phase"] as? String) ?? SetupPhaseLocal.awaitingASubmission.rawValue
                    guard let phase = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }

                    // Validate allowed submitter based on phase
                    let canSubmitA = (myRole == "A" && phase == .awaitingASubmission)
                    let canSubmitB = (myRole == "B" && phase == .awaitingBSubmission)
                    guard canSubmitA || canSubmitB else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 1, userInfo: [NSLocalizedDescriptionKey: "You can’t submit at this time."])
                        return nil
                    }

                    // Write my answer and submitted flag
                    var answers = (data["answers"] as? [String: Any]) ?? [:]
                    answers[uid] = payload
                    var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                    submitted[uid] = true

                    data["answers"] = answers
                    data["submitted"] = submitted
                    data["updatedAt"] = FieldValue.serverTimestamp()

                    // Advance phase
                    if canSubmitA {
                        data["phase"] = SetupPhaseLocal.awaitingBApproval.rawValue
                    } else if canSubmitB {
                        data["phase"] = SetupPhaseLocal.awaitingAApproval.rawValue
                    }

                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch {
                    errorPtr?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    private func approvePartnerProposal_TXCommon(nextPhase: SetupPhaseLocal, advanceToNextStep: Bool) async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        defer { isSaving = false }

        let myUid = uid

        do {
            try await db.runTransaction { txn, errorPtr in
                do {
                    let snap = try txn.getDocument(ref)
                    guard var data = snap.data() else { return nil }

                    let phaseRaw = (data["phase"] as? String) ?? ""
                    let current = SetupPhaseLocal(rawValue: phaseRaw)

                    // Validate current phase matches what caller expects to approve
                    let expectedPhase: SetupPhaseLocal = (nextPhase == .awaitingBSubmission) ? .awaitingBApproval :
                                                         (nextPhase == .awaitingASubmission) ? .awaitingAApproval :
                                                         (nextPhase == .complete) ? .awaitingAApproval : .awaitingASubmission

                    guard current == expectedPhase else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 2, userInfo: [NSLocalizedDescriptionKey: "Phase changed. Try again."])
                        return nil
                    }

                    // Find partner entry
                    let answers = (data["answers"] as? [String: Any]) ?? [:]
                    guard let partnerEntry = answers.first(where: { key, _ in key != myUid }) else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 3, userInfo: [NSLocalizedDescriptionKey: "No partner proposal to approve yet."])
                        return nil
                    }
                    let partnerUid = partnerEntry.key
                    let partnerPayload = partnerEntry.value as? [String: Any] ?? [:]

                    // Approvals
                    var approvals = (data["approvals"] as? [String: Bool]) ?? [:]
                    approvals[myUid] = true
                    data["approvals"] = approvals

                    // Persist approved snapshot
                    var approvedAnswers = (data["approvedAnswers"] as? [String: Any]) ?? [:]
                    approvedAnswers[partnerUid] = partnerPayload
                    data["approvedAnswers"] = approvedAnswers

                    // Advance phase
                    data["phase"] = nextPhase.rawValue
                    data["updatedAt"] = FieldValue.serverTimestamp()

                    // For mid-step switch (A approved -> B submit), reset my flags to allow B’s turn
                    if nextPhase == .awaitingBSubmission || nextPhase == .awaitingASubmission {
                        var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                        submitted[myUid] = false
                        data["submitted"] = submitted
                        approvals[myUid] = false
                        data["approvals"] = approvals
                    }

                    // If advancing to next setup step (appSelection), reset step-local fields
                    if advanceToNextStep {
                        data["step"] = SetupStepID.appSelection
                        data["stepIndex"] = 1
                        data["answers"] = [:]
                        data["approvals"] = [:]
                        data["submitted"] = [:]
                    }

                    // If finishing flow
                    if nextPhase == .complete {
                        data["completedAt"] = FieldValue.serverTimestamp()
                    }

                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch {
                    errorPtr?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    private func approvePartnerProposal_TX() async {
        // Determine correct next phase and whether we also advance to next step
        let role = currentRole
        let phase = currentPhase

        if role == "B", phase == .awaitingBApproval {
            // B approves A’s proposal -> next is B submission (still in blockSchedule step)
            await approvePartnerProposal_TXCommon(nextPhase: .awaitingBSubmission, advanceToNextStep: false)
        } else if role == "A", phase == .awaitingAApproval {
            // A approves B’s proposal -> move to next step and reset to A submit
            await approvePartnerProposal_TXCommon(nextPhase: .awaitingASubmission, advanceToNextStep: true)
        } else {
            await MainActor.run { self.errorMessage = "You can’t approve at this time." }
        }
    }

    // MARK: - Step 2: App selection submission/approval (Transactional)

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

                    let phaseRaw = (data["phase"] as? String) ?? SetupPhaseLocal.awaitingASubmission.rawValue
                    guard let phase = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }

                    let canSubmitA = (myRole == "A" && phase == .awaitingASubmission)
                    let canSubmitB = (myRole == "B" && phase == .awaitingBSubmission)
                    guard canSubmitA || canSubmitB else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 4, userInfo: [NSLocalizedDescriptionKey: "You can’t submit at this time."])
                        return nil
                    }

                    // Write my answer and submitted flag
                    var answers = (data["answers"] as? [String: Any]) ?? [:]
                    answers[uid] = payload
                    var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                    submitted[uid] = true

                    data["answers"] = answers
                    data["submitted"] = submitted
                    data["updatedAt"] = FieldValue.serverTimestamp()

                    // Advance phase
                    if canSubmitA {
                        data["phase"] = SetupPhaseLocal.awaitingBApproval.rawValue
                    } else if canSubmitB {
                        data["phase"] = SetupPhaseLocal.awaitingAApproval.rawValue
                    }

                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch {
                    errorPtr?.pointee = error as NSError
                    return nil
                }
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

                    let phaseRaw = (data["phase"] as? String) ?? ""
                    guard let current = SetupPhaseLocal(rawValue: phaseRaw) else { return nil }

                    // Expected phase for approver
                    let expected: SetupPhaseLocal = (role == "B") ? .awaitingBApproval : .awaitingAApproval
                    guard current == expected else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 5, userInfo: [NSLocalizedDescriptionKey: "Phase changed. Try again."])
                        return nil
                    }

                    // Partner entry
                    let answers = (data["answers"] as? [String: Any]) ?? [:]
                    guard let partnerEntry = answers.first(where: { key, _ in key != myUid }) else {
                        errorPtr?.pointee = NSError(domain: "whistl", code: 6, userInfo: [NSLocalizedDescriptionKey: "No partner selection to approve yet."])
                        return nil
                    }
                    let partnerUid = partnerEntry.key
                    let partnerPayload = partnerEntry.value as? [String: Any] ?? [:]

                    // Approvals
                    var approvals = (data["approvals"] as? [String: Bool]) ?? [:]
                    approvals[myUid] = true
                    data["approvals"] = approvals

                    // Snapshot approved selection
                    var approvedAnswers = (data["approvedAnswers"] as? [String: Any]) ?? [:]
                    approvedAnswers[partnerUid] = partnerPayload
                    data["approvedAnswers"] = approvedAnswers

                    // Advance phase
                    if role == "B", phase == .awaitingBApproval {
                        // Move to B submission
                        data["phase"] = SetupPhaseLocal.awaitingBSubmission.rawValue
                        // Reset my flags for next turn
                        var submitted = (data["submitted"] as? [String: Bool]) ?? [:]
                        submitted[myUid] = false
                        data["submitted"] = submitted
                        approvals[myUid] = false
                        data["approvals"] = approvals
                    } else if role == "A", phase == .awaitingAApproval {
                        // Finish
                        data["phase"] = SetupPhaseLocal.complete.rawValue
                        data["completedAt"] = FieldValue.serverTimestamp()
                    }

                    data["updatedAt"] = FieldValue.serverTimestamp()
                    txn.setData(data, forDocument: ref, merge: true)
                    return nil
                } catch {
                    errorPtr?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            await MainActor.run { self.errorMessage = (error as NSError).localizedDescription }
        }
    }

    // Convert [String: AnyCodable] to [String: Any] for Firestore setData (kept for completeness)
    private func toPlainMap(_ dict: [String: AnyCodable]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in dict {
            switch v.value {
            case let i as Int: out[k] = i
            case let d as Double: out[k] = d
            case let b as Bool: out[k] = b
            case let s as String: out[k] = s
            case let m as [String: AnyCodable]:
                out[k] = toPlainMap(m)
            case let a as [AnyCodable]:
                out[k] = a.map { $0.value }
            default:
                break
            }
        }
        return out
    }

    // MARK: - Selection encoding/decoding for Firestore

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

    private func unionApprovedSelections() -> FamilyActivitySelection {
        var union = FamilyActivitySelection()
        // Merge all approvedAnswers payloads
        for (_, payload) in setup.approvedAnswers {
            let sel = decodeSelectionFromMap(payload)
            union.applicationTokens.formUnion(sel.applicationTokens)
            union.categoryTokens.formUnion(sel.categoryTokens)
        }
        return union
    }

    // MARK: - Finalization: persist approved config

    private func persistApprovedConfiguration() {
        // Persist the last approved block schedule if available (replicate across week via legacy bridge)
        // We use the last approved block payload present in approvedAnswers (if any).
        let approvedBlocks: [BlockSchedule] = setup.approvedAnswers.values.compactMap { payload in
            // Try parse as schedule payload first (may not exist in appSelection step)
            let start = (payload["startMinutes"]?.value as? Int)
            let end = (payload["endMinutes"]?.value as? Int)
            if let s = start, let e = end {
                return BlockSchedule(startMinutes: s, endMinutes: e)
            }
            return nil
        }
        if let last = approvedBlocks.last {
            SharedConfigStore.save(startMinutes: last.startMinutes, endMinutes: last.endMinutes)
            SharedConfigStore.save(isScheduleEnabled: true)
        } else {
            // If no schedule found (shouldn't happen if step 1 completed), keep defaults.
            SharedConfigStore.save(isScheduleEnabled: true)
        }

        // Persist union of approved app selections
        let selection = unionApprovedSelections()
        SharedConfigStore.save(selection: selection)

        // Notify extension and DeviceActivity monitoring
        postConfigDidChangeDarwinNotification()
        ReportingScheduler.shared.refreshMonitoringFromShared()
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
        ("hands.sparkles.fill", "Two mates. One goal.", "Team up to block gambling apps and keep each other accountable."),
        ("clock.badge.checkmark", "Set your hours", "Pick times that work for both of you. Nights off? Early starts? Your call."),
        ("bell.badge.fill", "Stay in the loop", "Get notified when your mate is active so you can nudge and support.")
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

// MARK: - Step Views

private struct BlockScheduleStepView: View {
    var myAnswer: BlockSchedule?
    var partnerAnswer: BlockSchedule?
    var myApproved: Bool
    var partnerApproved: Bool
    var mySubmitted: Bool
    var partnerSubmitted: Bool
    var onDraftChange: (BlockSchedule) -> Void
    var onSubmit: () -> Void
    var onApprove: () -> Void
    var isSaving: Bool
    let brand: BrandPalette

    // Role and phase to gate UI
    let role: String // "A" or "B"
    let phase: SetupPhaseLocal

    @State private var start = DateComponents(hour: 21, minute: 0) // 9pm default
    @State private var end   = DateComponents(hour: 7, minute: 0)  // 7am default

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card: My chooser
            VStack(alignment: .leading, spacing: 10) {
                Label("Your proposal", systemImage: "clock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(brand.accent)

                TimeRangePicker(title: "", start: $start, end: $end, brand: brand)
                    .onChange(of: start) { _ in onDraftChange(currentAnswer) }
                    .onChange(of: end) { _ in onDraftChange(currentAnswer) }
                    .onAppear {
                        if let my = myAnswer {
                            start = minutesToComponents(my.startMinutes)
                            end   = minutesToComponents(my.endMinutes)
                        }
                    }

                Text("Tip: Choose times when you’re most likely to be tempted — late nights or downtime.")
                    .font(.caption)
                    .foregroundStyle(brand.secondaryText)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(brand.fieldBackground)
            )

            // Submit / Partner status row
            StatusRow(mySubmitted: mySubmitted, partnerSubmitted: partnerSubmitted, brand: brand)

            // Partner preview card
            VStack(alignment: .leading, spacing: 8) {
                Label("Partner’s proposal", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let partnerAnswer {
                    Text("\(formatMinutes(partnerAnswer.startMinutes)) → \(formatMinutes(partnerAnswer.endMinutes))")
                        .font(.callout)
                        .foregroundStyle(brand.secondaryText)
                } else {
                    Text(waitingPartnerText)
                        .font(.callout)
                        .foregroundStyle(brand.secondaryText)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(brand.fieldBackground)
            )

            // Primary action area
            VStack(alignment: .leading, spacing: 10) {
                if role == "A", phase == .awaitingASubmission {
                    PrimaryActionButton(title: "Submit your proposal", isLoading: isSaving, brand: brand, action: onSubmit)
                } else if role == "B", phase == .awaitingBApproval {
                    PrimaryActionButton(title: "Approve partner’s proposal", isLoading: isSaving, brand: brand, action: onApprove, disabled: partnerAnswer == nil)
                } else if role == "B", phase == .awaitingBSubmission {
                    PrimaryActionButton(title: "Submit your proposal", isLoading: isSaving, brand: brand, action: onSubmit)
                } else if role == "A", phase == .awaitingAApproval {
                    PrimaryActionButton(title: "Approve partner’s proposal", isLoading: isSaving, brand: brand, action: onApprove, disabled: partnerAnswer == nil)
                } else if phase == .complete {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var waitingPartnerText: String {
        if role == "A", phase == .awaitingASubmission {
            return "Pick a time range and submit to share with your partner."
        } else if role == "B", phase == .awaitingBSubmission {
            return "Pick a time range and submit to share with your partner."
        } else {
            return "Waiting for your partner to choose…"
        }
    }

    private var currentAnswer: BlockSchedule {
        BlockSchedule(startMinutes: componentsToMinutes(start), endMinutes: componentsToMinutes(end))
    }

    private func componentsToMinutes(_ c: DateComponents) -> Int {
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        return h * 60 + m
    }

    private func minutesToComponents(_ minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let comps = DateComponents(hour: h, minute: m)
        let cal = Calendar.current
        let date = cal.date(from: comps) ?? Date()
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

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

private struct TimeRangePicker: View {
    let title: String
    @Binding var start: DateComponents
    @Binding var end: DateComponents
    let brand: BrandPalette

    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(
                        get: { startDateFromComponents(start) },
                        set: { newDate in
                            start = componentsFromDate(newDate)
                            startDate = newDate
                        }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("End").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(
                        get: { startDateFromComponents(end) },
                        set: { newDate in
                            end = componentsFromDate(newDate)
                            endDate = newDate
                        }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(brand.fieldBackground)
            )
        }
        .onAppear {
            startDate = startDateFromComponents(start)
            endDate = startDateFromComponents(end)
        }
    }

    private func startDateFromComponents(_ comps: DateComponents) -> Date {
        Calendar.current.date(from: comps) ?? Calendar.current.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: Date()) ?? Date()
    }

    private func componentsFromDate(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: date)
    }
}

// A full-screen waiting card for the non-active device
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

private struct AppSelectionStepView: View {
    var myApproved: Bool
    var partnerApproved: Bool
    var onSubmit: () -> Void
    var onApprove: () -> Void
    var isSaving: Bool
    let brand: BrandPalette

    let role: String
    let phase: SetupPhaseLocal

    @Binding var selection: FamilyActivitySelection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which apps should be blocked?")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Choose categories and apps below. Submit your selection, then your partner will approve it.")
                .foregroundStyle(brand.secondaryText)
                .font(.footnote)

            // Minimal inline summary; full picker is in FocusMenu elsewhere
            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                Spacer()
                Button {
                    // Placeholder: selection editing is handled in FocusMenu for now.
                } label: {
                    Text("Edit selection")
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }

            Divider().opacity(0.2)

            // Actions based on role/phase
            VStack(alignment: .leading, spacing: 8) {
                if role == "A", phase == .awaitingASubmission {
                    PrimaryActionButton(title: "Submit your selection", isLoading: isSaving, brand: brand, action: onSubmit)
                } else if role == "B", phase == .awaitingBApproval {
                    PrimaryActionButton(title: "Approve partner’s selection", isLoading: isSaving, brand: brand, action: onApprove)
                } else if role == "B", phase == .awaitingBSubmission {
                    PrimaryActionButton(title: "Submit your selection", isLoading: isSaving, brand: brand, action: onSubmit)
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
