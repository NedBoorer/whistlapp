import SwiftUI
import FirebaseFirestore

struct PartnerInboxView: View {
    let pairId: String
    let uid: String
    let brand: BrandPalette

    @State private var items: [NotificationItem] = []
    @State private var listener: ListenerRegistration?

    var body: some View {
        List {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(brand.accent)
                    Text("No notifications yet")
                        .font(.headline)
                    Text("When your mate requests changes or a break, you’ll see it here.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(brand.fieldBackground)
                                .frame(width: 44, height: 44)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            Image(systemName: item.iconName)
                                .foregroundStyle(brand.accent)
                                .font(.system(size: 20, weight: .medium))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if item.unread {
                                    Text("NEW")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(brand.accent.opacity(0.2)))
                                        .foregroundStyle(brand.accent)
                                }
                                Spacer()
                                Text(item.timeAgo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            brand.background()
                .ignoresSafeArea()
        )
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") {
                    Task { await PartnerInboxListener.shared.markAllAsRead(pairId: pairId, uid: uid) }
                }
                .tint(brand.accent)
            }
        }
        .onAppear { attach() }
        .onDisappear { detach() }
    }

    private func attach() {
        detach()
        let db = Firestore.firestore()
        listener = db.collection("pairSpaces").document(pairId).collection("notifications")
            .whereField("toUid", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snap, error in
                if let error {
                    print("Inbox error: \(error)")
                    return
                }
                guard let docs = snap?.documents else { return }
                self.items = docs.map { NotificationItem(doc: $0) }
            }
    }

    private func detach() {
        listener?.remove()
        listener = nil
    }
}

private struct NotificationItem: Identifiable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date?
    let unread: Bool
    let kind: String

    init(doc: QueryDocumentSnapshot) {
        self.id = doc.documentID
        self.title = (doc.get("title") as? String) ?? "Notification"
        self.body = (doc.get("body") as? String) ?? ""
        self.unread = (doc.get("unread") as? Bool) ?? false
        self.kind = (doc.get("kind") as? String) ?? "generic"
        if let ts = doc.get("createdAt") as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = nil
        }
    }

    var iconName: String {
        switch kind {
        case "scheduleChangeRequest": return "calendar.badge.clock"
        case "breakRequest": return "hand.raised.fill"
        default: return "bell.fill"
        }
    }

    var timeAgo: String {
        guard let d = createdAt else { return "" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return "just now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        let days = hrs / 24
        return "\(days)d"
    }
}

#Preview {
    NavigationStack {
        PartnerInboxView(pairId: "PAIR", uid: "USER", brand: BrandPalette())
    }
}
