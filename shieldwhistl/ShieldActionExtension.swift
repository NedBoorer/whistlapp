import Foundation

@main
struct ShieldActionExtensionMain {
    static func main() {
        // Keep the extension process alive; the system wires it via Info.plist
        // (NSExtensionPointIdentifier = com.apple.familycontrols.shieldaction).
        RunLoop.current.run()
    }
}
