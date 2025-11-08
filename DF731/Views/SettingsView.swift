//
//  SettingsView.swift
//  DF731
//
//  Settings and statistics
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var gameProgress = GameProgress.shared
    @State private var showResetAlert = false
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: "#0A0E29")
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
                        
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Invisible spacer for centering
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Statistics section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Statistics")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 16) {
                            StatCard(
                                icon: "sparkles",
                                title: "Total Crystals",
                                value: "\(gameProgress.totalCrystals)",
                                color: "#3CFF8A"
                            )
                            
                            StatCard(
                                icon: "gamecontroller.fill",
                                title: "Games Played",
                                value: "\(gameProgress.totalGamesPlayed)",
                                color: "#FFD640"
                            )
                            
                            StatCard(
                                icon: "star.fill",
                                title: "Themes Unlocked",
                                value: "\(gameProgress.unlockedThemes.count) / \(ThemeData.themes.count)",
                                color: "#3CFF8A"
                            )
                            
                            if gameProgress.totalGamesPlayed > 0 {
                                StatCard(
                                    icon: "chart.bar.fill",
                                    title: "Average per Game",
                                    value: String(format: "%.1f", Double(gameProgress.totalCrystals) / Double(gameProgress.totalGamesPlayed)),
                                    color: "#FFD640"
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Actions section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Actions")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        Button(action: {
                            showResetAlert = true
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 30)
                                
                                Text("Reset Progress")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.red.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.red.opacity(0.4), lineWidth: 2)
                                    )
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarHidden(true)
        .alert(isPresented: $showResetAlert) {
            Alert(
                title: Text("Reset Progress"),
                message: Text("Are you sure you want to reset all progress? This will clear all crystals, statistics, and unlocked themes."),
                primaryButton: .destructive(Text("Reset")) {
                    withAnimation {
                        gameProgress.resetProgress()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: color).opacity(0.2))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color(hex: color))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}


