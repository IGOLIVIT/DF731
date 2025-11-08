//
//  CrystalChamberView.swift
//  DF731
//
//  Progress and theme display
//

import SwiftUI

struct CrystalChamberView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var gameProgress = GameProgress.shared
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: gameProgress.selectedTheme == "default" ? "#0A0E29" :
                  ThemeData.themes.first(where: { $0.id == gameProgress.selectedTheme })?.backgroundColor ?? "#0A0E29")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(hex: "#FFD640"))
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Crystal count display
                    VStack(spacing: 20) {
                        ZStack {
                            // Glow effect
                            Circle()
                                .fill(Color(hex: "#3CFF8A").opacity(0.2))
                                .frame(width: 180, height: 180)
                                .blur(radius: 40)
                                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            
                            Circle()
                                .fill(Color(hex: "#FFD640").opacity(0.15))
                                .frame(width: 140, height: 140)
                                .blur(radius: 30)
                                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 70, weight: .thin))
                                .foregroundColor(Color(hex: "#3CFF8A"))
                        }
                        
                        VStack(spacing: 8) {
                            Text("Energy Crystals")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("\(gameProgress.totalCrystals)")
                                .font(.system(size: 60, weight: .bold))
                                .foregroundColor(Color(hex: "#FFD640"))
                        }
                    }
                    .padding(.top, 20)
                    
                    // Themes section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Atmospheric Themes")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 16) {
                            ForEach(ThemeData.themes, id: \.id) { theme in
                                ThemeCard(theme: theme)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            startPulseAnimation()
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
    }
}

struct ThemeCard: View {
    let theme: ThemeData
    @ObservedObject var gameProgress = GameProgress.shared
    
    var isUnlocked: Bool {
        gameProgress.unlockedThemes.contains(theme.id)
    }
    
    var isSelected: Bool {
        gameProgress.selectedTheme == theme.id
    }
    
    var body: some View {
        Button(action: {
            if isUnlocked {
                withAnimation {
                    gameProgress.selectedTheme = theme.id
                }
            }
        }) {
            HStack(spacing: 16) {
                // Color preview
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: theme.backgroundColor))
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .fill(Color(hex: theme.accentColor).opacity(0.6))
                        .frame(width: 30, height: 30)
                        .blur(radius: 8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: theme.accentColor).opacity(0.5), lineWidth: 2)
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(theme.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if isUnlocked {
                        if isSelected {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Active")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(Color(hex: "#3CFF8A"))
                        } else {
                            Text("Unlocked")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                            Text("\(theme.requiredCrystals) crystals needed")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "#3CFF8A"))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isSelected ? 0.15 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ?
                                Color(hex: "#3CFF8A").opacity(0.5) :
                                Color.white.opacity(0.1),
                                lineWidth: 2
                            )
                    )
            )
        }
        .disabled(!isUnlocked)
        .opacity(isUnlocked ? 1.0 : 0.6)
    }
}


