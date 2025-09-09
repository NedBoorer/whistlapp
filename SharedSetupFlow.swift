import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firestore models

struct SetupStepID {
    static let blockSchedule = "blockSchedule"
    static let appSelection  = "appSelection"
}

struct BlockSchedule: Codable, Equatable {
    var startMinutes: Int // minutes since midnight
    var endMinutes: Int
}

private struct SetupDoc: Codable {
    var step: String
    var stepIndex: Int
    var answers: [String: [String: AnyCodable]] // answers[uid] = payload
    var approvals: [String: Bool]               // approvals[uid] = true/false
    var updatedAt: Timestamp?
    var completedAt: Timestamp?

    // Helper decode with defaults
    init(step: String = SetupStepID.blockSchedule,
         stepIndex: Int = 0,
         answers: [String: [String: AnyCodable]] = [:],
         approvals: [String: Bool] = [:],
         updatedAt: Timestamp? = nil,
         completedAt: Timestamp? = nil) {
        self.step = step
        self.stepIndex = stepIndex
        self.answers = answers
        self.approvals = approvals
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

// AnyCodable-like wrapper for simple Firestore encoding
struct AnyCodable: Codable, Equatable {
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

    private var db: Firestore { Firestore.firestore() }
    private var pairId: String? { appController.pairId }
    private var uid: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        VStack(spacing: 16) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            switch setup.step {
            case SetupStepID.blockSchedule:
                BlockScheduleStepView(
                    myAnswer: myBlockAnswer,
                    partnerAnswer: partnerBlockAnswer,
                    myApproved: myApproved,
                    partnerApproved: partnerApproved,
                    onChange: { ans in Task { await saveMyBlockAnswer(ans) } },
                    onApprove: { Task { await setMyApproval(true) } },
                    onRevoke: { Task { await setMyApproval(false) } },
                    onContinue: { Task { await advanceIfMutuallyApproved() } },
                    isSaving: isSaving,
                    brand: brand
                )
            case SetupStepID.appSelection:
                AppSelectionStepView(
                    myApproved: myApproved,
                    partnerApproved: partnerApproved,
                    onApprove: { Task { await setMyApproval(true) } },
                    onRevoke: { Task { await setMyApproval(false) } },
                    onContinue: { Task { await advanceIfMutuallyApproved() } },
                    isSaving: isSaving,
                    brand: brand
                )
            default:
                Text("Finalizing setup…")
                ProgressView().tint(brand.accent)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Partner setup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await attachListener()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    // MARK: - Derived values

    private var myApproved: Bool {
        guard let uid else { return false }
        return setup.approvals[uid] ?? false
    }

    private var partnerApproved: Bool {
        guard let uid else { return false }
        return setup.approvals.first(where: { $0.key != uid })?.value ?? false
    }

    private var myBlockAnswer: BlockSchedule? {
        guard let uid else { return nil }
        return decodeBlock(from: setup.answers[uid])
    }

    private var partnerBlockAnswer: BlockSchedule? {
        guard let uid else { return nil }
        let partnerAnswers = setup.answers.first(where: { $0.key != uid })?.value
        return decodeBlock(from: partnerAnswers)
    }

    private func decodeBlock(from dict: [String: AnyCodable]?) -> BlockSchedule? {
        guard let dict else { return nil }
        let start = (dict["startMinutes"]?.value as? Int) ?? 0
        let end = (dict["endMinutes"]?.value as? Int) ?? 0
        return BlockSchedule(startMinutes: start, endMinutes: end)
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
                    "updatedAt": FieldValue.serverTimestamp()
                ])
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

            var answers: [String: [String: AnyCodable]] = [:]
            for (k, v) in answersRaw {
                var dict: [String: AnyCodable] = [:]
                for (dk, dv) in v {
                    dict[dk] = AnyCodable(dv)
                }
                answers[k] = dict
            }

            Task { @MainActor in
                self.setup.step = step
                self.setup.stepIndex = stepIndex
                self.setup.answers = answers
                self.setup.approvals = approvalsRaw
                self.errorMessage = nil
            }
        }
    }

    private func saveMyBlockAnswer(_ answer: BlockSchedule) async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        do {
            try await ref.setData([
                "answers.\(uid)": [
                    "startMinutes": answer.startMinutes,
                    "endMinutes": answer.endMinutes
                ],
                // Reset my approval on change
                "approvals.\(uid)": false,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            await MainActor.run { errorMessage = (error as NSError).localizedDescription }
        }
        isSaving = false
    }

    private func setMyApproval(_ approved: Bool) async {
        guard let ref = setupDocRef(), let uid else { return }
        isSaving = true
        do {
            try await ref.setData([
                "approvals.\(uid)": approved,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            await MainActor.run { errorMessage = (error as NSError).localizedDescription }
        }
        isSaving = false
    }

    private func bothApproved() -> Bool {
        guard let uid else { return false }
        let mine = setup.approvals[uid] ?? false
        let partner = setup.approvals.first(where: { $0.key != uid })?.value ?? false
        return mine && partner
    }

    private func advanceIfMutuallyApproved() async {
        guard bothApproved(), let ref = setupDocRef() else { return }
        isSaving = true
        do {
            if setup.step == SetupStepID.blockSchedule {
                try await ref.setData([
                    "step": SetupStepID.appSelection,
                    "stepIndex": 1,
                    "approvals": [:], // reset approvals for next step
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            } else if setup.step == SetupStepID.appSelection {
                try await ref.setData([
                    "completedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        } catch {
            await MainActor.run { errorMessage = (error as NSError).localizedDescription }
        }
        isSaving = false
    }
}

// MARK: - Step Views

private struct BlockScheduleStepView: View {
    var myAnswer: BlockSchedule?
    var partnerAnswer: BlockSchedule?
    var myApproved: Bool
    var partnerApproved: Bool
    var onChange: (BlockSchedule) -> Void
    var onApprove: () -> Void
    var onRevoke: () -> Void
    var onContinue: () -> Void
    var isSaving: Bool
    let brand: BrandPalette

    @State private var start = DateComponents(hour: 21, minute: 0) // 9pm default
    @State private var end   = DateComponents(hour: 7, minute: 0)  // 7am default

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What time would you like to block gambling apps?")
                .font(.headline)

            // My chooser
            TimeRangePicker(title: "Your proposal", start: $start, end: $end, brand: brand)
                .onChange(of: start) { _ in onChange(currentAnswer) }
                .onChange(of: end) { _ in onChange(currentAnswer) }
                .onAppear {
                    if let my = myAnswer {
                        start = minutesToComponents(my.startMinutes)
                        end   = minutesToComponents(my.endMinutes)
                    }
                }

            // Partner preview
            if let partnerAnswer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Partner’s proposal")
                        .font(.subheadline.weight(.semibold))
                    Text("\(formatMinutes(partnerAnswer.startMinutes)) → \(formatMinutes(partnerAnswer.endMinutes))")
                        .foregroundStyle(brand.secondaryText)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(brand.fieldBackground)
                )
            } else {
                Text("Waiting for your partner to choose…")
                    .font(.footnote)
                    .foregroundStyle(brand.secondaryText)
            }

            HStack {
                if myApproved {
                    Label("You approved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Revoke", action: onRevoke).buttonStyle(.bordered)
                } else {
                    Button("Approve partner’s proposal", action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .disabled(partnerAnswer == nil || isSaving)
                }

                Spacer()

                if partnerApproved {
                    Label("Partner approved", systemImage: "checkmark.seal").foregroundStyle(.green)
                } else {
                    Text("Partner has not approved yet")
                        .font(.footnote)
                        .foregroundStyle(brand.secondaryText)
                }
            }

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .disabled(!(myApproved && partnerApproved) || isSaving)
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

private struct TimeRangePicker: View {
    let title: String
    @Binding var start: DateComponents
    @Binding var end: DateComponents
    let brand: BrandPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack {
                DatePicker("Start", selection: .constant(Calendar.current.date(from: start) ?? Date()), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .onChange(of: start) { _ in }
                Text("→")
                DatePicker("End", selection: .constant(Calendar.current.date(from: end) ?? Date()), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .onChange(of: end) { _ in }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(brand.fieldBackground)
            )
        }
    }
}

private struct AppSelectionStepView: View {
    var myApproved: Bool
    var partnerApproved: Bool
    var onApprove: () -> Void
    var onRevoke: () -> Void
    var onContinue: () -> Void
    var isSaving: Bool
    let brand: BrandPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which apps should be blocked?")
                .font(.headline)

            Text("App selection UI goes here (list of installed apps, suggested gambling apps, etc.).")
                .foregroundStyle(brand.secondaryText)
                .font(.footnote)

            HStack {
                if myApproved {
                    Label("You approved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Revoke", action: onRevoke).buttonStyle(.bordered)
                } else {
                    Button("Approve partner’s selection", action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                }

                Spacer()

                if partnerApproved {
                    Label("Partner approved", systemImage: "checkmark.seal").foregroundStyle(.green)
                } else {
                    Text("Partner has not approved yet")
                        .font(.footnote)
                        .foregroundStyle(brand.secondaryText)
                }
            }

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .disabled(!(myApproved && partnerApproved) || isSaving)
        }
    }
}
