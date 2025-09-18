import Foundation
import FirebaseFirestore
import UserNotifications
import UIKit

final class PartnerInboxListener {
    static let shared = PartnerInboxListener()
    private init() {}

    private var listener: ListenerRegistration?
    private var seen: Set<String> = []

    private let center = UNUserNotificationCenter.current()

    func start(pairId: String, uid: String) {
        stop()
        requestAuthIfNeeded()
        let db = Firestore.firestore()
        let ref = db.collection("pairSpaces").document(pairId).collection("notifications")
        // Listen for unread notifications addressed to this user, newest first
        listener = ref
            .whereField("toUid", isEqualTo: uid)
            .whereField("unread", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("PartnerInboxListener error: \(error)")
                    return
                }
                guard let snapshot else { return }
                for change in snapshot.documentChanges {
                    if change.type == .added {
                        let doc = change.document
                        let docId = doc.documentID
                        if self.seen.contains(docId) { continue }
                        self.seen.insert(docId)

                        let title = (doc.get("title") as? String) ?? "Notification"
                        let body = (doc.get("body") as? String) ?? ""
                        self.presentLocalNotification(title: title, body: body)
                    }
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        seen.removeAll()
    }

    func markAllAsRead(pairId: String, uid: String) async {
        let db = Firestore.firestore()
        let ref = db.collection("pairSpaces").document(pairId).collection("notifications")
        do {
            let qs = try await ref.whereField("toUid", isEqualTo: uid).whereField("unread", isEqualTo: true).getDocuments()
            let batch = db.batch()
            for doc in qs.documents {
                batch.setData(["unread": false, "readAt": FieldValue.serverTimestamp()], forDocument: doc.reference, merge: true)
            }
            try await batch.commit()
        } catch {
            print("PartnerInboxListener markAllAsRead error: \(error)")
        }
    }

    private func requestAuthIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    // No-op; we can still schedule local notifications if granted.
                    if granted {
                        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                    }
                }
            default:
                break
            }
        }
    }

    private func presentLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: min(99, (UIApplication.shared.applicationIconBadgeNumber + 1)))

        // Immediate fire
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { print("Local notification error: \(error)") }
        }
    }
}
