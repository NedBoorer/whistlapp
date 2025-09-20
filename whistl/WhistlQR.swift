import Foundation

enum WhistlQR {
    static func pairingURLString(code: String) -> String {
        // Use a custom URL scheme for compact encoding; could be a https URL with universal links as well.
        // Example: whistl://pair?v=1&code=ABCDE1
        var comps = URLComponents()
        comps.scheme = "whistl"
        comps.host = "pair"
        comps.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "code", value: code)
        ]
        return comps.url?.absoluteString ?? "whistl://pair?v=1&code=\(code)"
    }

    static func parsePairingURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        // Accept whistl://pair or whistl:///pair forms
        guard url.scheme == "whistl" else { return nil }
        let host = url.host ?? ""
        let path = url.path
        guard host == "pair" || path == "/pair" else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return comps?.queryItems?.first(where: { $0.name == "code" })?.value
    }
}
