//
//  Authview.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct Authview: View {
    
    @Environment(AppController.self) private var appController
    
    @State private var isSignUp = false
    
    var body: some View {
        Text("Hello, World!")
        VStack {
            Spacer()
            
            TextField("Email", text: Bindable(appController).email).textFieldStyle(.roundedBorder)
            
            SecureField("Password", text: Bindable(appController).password).textFieldStyle(.roundedBorder)
            
            Button {
                authenticate()
            } label: {
                HStack {
                    Spacer()
                    Text("\(isSignUp ? "Sign up" : "Sign in")")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("\(isSignUp ? "I already have an account" : "I dont have an account")") {
                isSignUp.toggle()
            }

        }
        .padding(20)
    }
    func authenticate(){
        isSignUp ? signUp() : signIn()
        
    }
    
    func signUp(){
        Task {
            do {
                try await appController.signUp()
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    func signIn(){
        Task {
            do {
                try await appController.signIn()
            } catch {
                print(error.localizedDescription)
            }
        }
        
    }
}

#Preview {
    Authview()
}
