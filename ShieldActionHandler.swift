import ManagedSettings
import FamilyControls

final class ShieldActionHandler: ShieldActionDelegate {

    override func handle(action: ShieldAction,
                for application: ApplicationToken,
                completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(action == .primaryButtonPressed ? .close : .defer)
    }

    override func handle(action: ShieldAction,
                for category: ActivityCategoryToken,
                completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                for webDomain: WebDomainToken,
                completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
