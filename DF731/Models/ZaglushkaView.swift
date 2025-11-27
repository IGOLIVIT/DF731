//
//  ZaglushkaView.swift
//  DF731
//
//  Created by IGOR on 18/11/2025.
//

import SwiftUI

struct ZaglushkaView: View {

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
    ZaglushkaView()
}
