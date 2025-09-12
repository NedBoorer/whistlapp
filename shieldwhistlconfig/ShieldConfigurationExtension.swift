//
//  ShieldConfigurationExtension.swift
//  shieldwhistlconfig
//
//  Created by Ned Boorer on 11/9/2025.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit
import Foundation

// Fallback constants in case SharedConfig.swift isn't included in this target.
// If SharedConfig.swift is target-membered here, these won't conflict because they are file-private.
fileprivate enum __SharedFallback {
    static let appGroupID = "group.whistl"
    enum SharedKeys {
        static let isManualBlockActive = "fc_isManualBlockActive"
        static let isScheduleEnabled   = "fc_isScheduleEnabled"
    }
}

// Provide shim accessors that prefer real symbols if they exist at link-time.
private var __appGroupID: String {
    // Use the fallback; when SharedConfig.swift is compiled into this target,
    // the global appGroupID will shadow usages directly below.
    return __SharedFallback.appGroupID
}
private enum __Keys {
    static let isManualBlockActive = __SharedFallback.SharedKeys.isManualBlockActive
    static let isScheduleEnabled   = __SharedFallback.SharedKeys.isScheduleEnabled
}

// Active data source for the Managed Settings extension.
// Ensure the extension Info.plist points both NSExtensionPrincipalClass and
// MSExtensionDataSourceClass to $(PRODUCT_MODULE_NAME).ShieldConfigurationExtension
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Helpers

    private func subtitleText(fallback: String? = nil) -> String? {
        // Read shared flags via App Group
        // Prefer the real appGroupID/SharedKeys if SharedConfig.swift is included.
        let suiteName: String
        if let real = (UserDefaults(suiteName: "group.whistl") != nil ? "group.whistl" : nil) {
            suiteName = real
        } else {
            suiteName = __appGroupID
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        // Try real SharedKeys first via string literals; fall back to shims (same values).
        let manual = defaults.bool(forKey: "fc_isManualBlockActive")
        let schedule = defaults.bool(forKey: "fc_isScheduleEnabled")

        if manual { return "You and your mate agreed to block this — stay strong." }
        if schedule { return "During your focus window, you're blocking this together." }
        return fallback
    }

    private func titleLabel() -> ShieldConfiguration.Label {
        .init(text: "Blocked — we've got your back", color: .label)
    }

    private func subtitleLabel(_ text: String?) -> ShieldConfiguration.Label? {
        guard let text else { return nil }
        return .init(text: text, color: .secondaryLabel)
    }

    private func primaryButton() -> ShieldConfiguration.Label {
        .init(text: "Stay on track", color: .label)
    }

    // In current SDKs, ShieldConfiguration expects a UIImage? for the icon.
    private func iconImage() -> UIImage? {
        UIImage(systemName: "person.2.fill")
    }

    private func baseConfig(subtitle: String?) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: .clear,
            icon: iconImage(),
            title: titleLabel(),
            subtitle: subtitleLabel(subtitle),
            primaryButtonLabel: primaryButton(),
            secondaryButtonLabel: nil
        )
    }

    // MARK: - Application shield

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let subtitle = subtitleText(fallback: "You and your mate agreed to block this. Take a breather — you're not doing this alone.")
        return baseConfig(subtitle: subtitle)
    }

    // MARK: - Application shielded due to category

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        let subtitle = subtitleText(fallback: "This category is off-limits during your focus window. Your mate's in your corner.")
        return baseConfig(subtitle: subtitle)
    }

    // MARK: - Web domain shield

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        let domain = webDomain.domain ?? "this site"
        let subtitle = subtitleText(fallback: "\(domain) is blocked. One step at a time, together.")
        return baseConfig(subtitle: subtitle)
    }

    // MARK: - Web domain shielded due to category

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let domain = webDomain.domain ?? "this site"
        let subtitle = subtitleText(fallback: "\(domain) is blocked (category). Your mate's got your back.")
        return baseConfig(subtitle: subtitle)
    }
}
