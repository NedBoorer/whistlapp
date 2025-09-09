//
//  AppDelegate.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {

    // Shared reference injected from whistlApp.init()
    // Not weak because App owns the lifecycle via @State; this is just a pass-through.
    static var sharedAppController: AppController?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        FirebaseApp.configure()

        // Start listening to auth changes immediately after Firebase is ready
        if let controller = AppDelegate.sharedAppController {
            Task { @MainActor in
                controller.listenToAuthChanges()
            }
        }

        return true
    }
}
