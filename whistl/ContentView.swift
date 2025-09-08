//
//  ContentView.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppController.self) private var appController
    
    
    var body: some View {
        Group{
            switch appController.authState {
            case .undefined:
                ProgressView()
            case .notAuthenticated:
                Authview()
            case .authenticated:
                ProfileView()
            }
        }
    }
}

#Preview {
    ContentView()
}
