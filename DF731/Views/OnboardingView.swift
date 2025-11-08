//
//  OnboardingView.swift
//  DF731
//
//  Onboarding experience with 3 slides
//

import SwiftUI

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var currentPage = 0
    @State private var animationOffset: CGFloat = 0
    
    let pages: [(title: String, description: String, icon: String)] = [
        ("Echoes Fall Softly", "Experience the serene journey of falling spheres through layered structures", "circle.grid.cross.fill"),
        ("Guide the Path", "Tap left and right to gently shift the sphere's trajectory through the pegs", "hand.tap.fill"),
        ("Collect Energy", "Gather Energy Crystals and unlock beautiful atmospheric themes", "sparkles")
    ]
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: "#0A0E29")
                .ignoresSafeArea()
            
            // Animated background shapes
            AnimatedBackgroundShapes(offset: animationOffset)
            
            VStack(spacing: 0) {
                // Pages
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(
                            title: pages[index].title,
                            description: pages[index].description,
                            icon: pages[index].icon
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                
                // Button
                Button(action: {
                    GameProgress.shared.completeOnboarding()
                    withAnimation(.easeOut(duration: 0.3)) {
                        showOnboarding = false
                    }
                }) {
                    Text(currentPage == pages.count - 1 ? "Begin the Journey" : "Continue")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "#0A0E29"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "#FFD640"))
                                .shadow(color: Color(hex: "#FFD640").opacity(0.4), radius: 20, x: 0, y: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "#3CFF8A").opacity(0.3), lineWidth: 2)
                        )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
                .scaleEffect(currentPage == pages.count - 1 ? 1.0 : 0.95)
                .animation(.spring(response: 0.3), value: currentPage)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            animationOffset = 360
        }
    }
}

struct OnboardingPageView: View {
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon with glow
            ZStack {
                Circle()
                    .fill(Color(hex: "#3CFF8A").opacity(0.1))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                
                Circle()
                    .fill(Color(hex: "#FFD640").opacity(0.1))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                Image(systemName: icon)
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(Color(hex: "#FFD640"))
            }
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
            }
            
            Spacer()
        }
    }
}

struct AnimatedBackgroundShapes: View {
    let offset: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(Color(hex: "#3CFF8A").opacity(0.05))
                        .frame(width: 100, height: 100)
                        .offset(
                            x: cos(Angle(degrees: offset + Double(index * 60)).radians) * 120,
                            y: sin(Angle(degrees: offset + Double(index * 60)).radians) * 120
                        )
                        .blur(radius: 20)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}


