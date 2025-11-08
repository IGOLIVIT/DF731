//
//  MainMenuView.swift
//  DF731
//
//  Main menu with navigation
//

import SwiftUI

struct MainMenuView: View {
    @ObservedObject var gameProgress = GameProgress.shared
    @State private var particleOffset: CGFloat = 0
    @State private var showEchoDropGame = false
    @State private var showCrystalChamber = false
    @State private var showSettings = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(hex: gameProgress.selectedTheme == "default" ? "#0A0E29" : 
                      ThemeData.themes.first(where: { $0.id == gameProgress.selectedTheme })?.backgroundColor ?? "#0A0E29")
                    .ignoresSafeArea()
                
                // Animated glow particles
                AnimatedGlowParticles(offset: particleOffset)
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // Title area with subtle glow
                    VStack(spacing: 8) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 70, weight: .thin))
                            .foregroundColor(Color(hex: "#FFD640"))
                            .shadow(color: Color(hex: "#FFD640").opacity(0.5), radius: 30, x: 0, y: 0)
                    }
                    .padding(.bottom, 20)
                    
                    // Menu buttons
                    VStack(spacing: 20) {
                        MenuButton(
                            title: "Echo Drop",
                            icon: "circle.circle.fill",
                            color: "#FFD640"
                        ) {
                            showEchoDropGame = true
                        }
                        
                        MenuButton(
                            title: "Crystal Chamber",
                            icon: "sparkles",
                            color: "#3CFF8A"
                        ) {
                            showCrystalChamber = true
                        }
                        
                        MenuButton(
                            title: "Settings",
                            icon: "gearshape.fill",
                            color: "#FFD640"
                        ) {
                            showSettings = true
                        }
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Crystal count indicator
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                        Text("\(gameProgress.totalCrystals)")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#3CFF8A"))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: "#3CFF8A").opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.bottom, 40)
                }
                
                // Navigation destinations
                NavigationLink(destination: EchoDropGameView(), isActive: $showEchoDropGame) {
                    EmptyView()
                }
                
                NavigationLink(destination: CrystalChamberView(), isActive: $showCrystalChamber) {
                    EmptyView()
                }
                
                NavigationLink(destination: SettingsView(), isActive: $showSettings) {
                    EmptyView()
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
            particleOffset = 500
        }
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let color: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color(hex: "#0A0E29"))
                    .frame(width: 30)
                
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "#0A0E29"))
                
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: color))
                    .shadow(color: Color(hex: color).opacity(0.4), radius: isPressed ? 10 : 20, x: 0, y: isPressed ? 5 : 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
    }
}

struct AnimatedGlowParticles: View {
    let offset: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .fill(
                            Color(hex: index % 2 == 0 ? "#3CFF8A" : "#FFD640")
                                .opacity(0.08)
                        )
                        .frame(width: CGFloat(40 + index * 10), height: CGFloat(40 + index * 10))
                        .offset(
                            x: cos(Angle(degrees: offset * 0.5 + Double(index * 45)).radians) * 150,
                            y: sin(Angle(degrees: offset * 0.3 + Double(index * 45)).radians) * 200 + CGFloat(index * 20)
                        )
                        .blur(radius: 25)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}


