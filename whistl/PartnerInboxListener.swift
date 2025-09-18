import Foundation

final class PartnerInboxListener: NSObject {
    static let shared = PartnerInboxListener()

    private override init() {
        super.init()
        // Inbox listener disabled
    }

    // MARK: - Public Interface (no-op)

    func start(pairId: String, uid: String) {
        // No-op: inbox functionality removed
    }

    func stop() {
        // No-op: inbox functionality removed
    }

    @MainActor
    func markAllAsRead(pairId: String, uid: String) async throws {
        // No-op: inbox functionality removed
    }
}
