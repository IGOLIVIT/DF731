//
//  ContentView.swift
//  DF731
//
//  Main entry point for the app
//

import SwiftUI

struct ContentView: View {
    @StateObject private var gameProgress = GameProgress.shared
    @State private var showOnboarding = false
    
    var body: some View {
        ZStack {
            if !gameProgress.hasCompletedOnboarding || showOnboarding {
                OnboardingView(showOnboarding: $showOnboarding)
                    .transition(.opacity)
            } else {
                MainMenuView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showOnboarding)
        .animation(.easeInOut(duration: 0.3), value: gameProgress.hasCompletedOnboarding)
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
