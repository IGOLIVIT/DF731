//
//  GameProgress.swift
//  DF731
//
//  Game progress and persistence
//

import Foundation
import Combine

class GameProgress: ObservableObject {
    static let shared = GameProgress()
    
    @Published var totalCrystals: Int {
        didSet {
            UserDefaults.standard.set(totalCrystals, forKey: "totalCrystals")
        }
    }
    
    @Published var totalGamesPlayed: Int {
        didSet {
            UserDefaults.standard.set(totalGamesPlayed, forKey: "totalGamesPlayed")
        }
    }
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    @Published var unlockedThemes: Set<String> {
        didSet {
            let array = Array(unlockedThemes)
            UserDefaults.standard.set(array, forKey: "unlockedThemes")
        }
    }
    
    @Published var selectedTheme: String {
        didSet {
            UserDefaults.standard.set(selectedTheme, forKey: "selectedTheme")
        }
    }
    
    private init() {
        self.totalCrystals = UserDefaults.standard.integer(forKey: "totalCrystals")
        self.totalGamesPlayed = UserDefaults.standard.integer(forKey: "totalGamesPlayed")
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        let savedThemes = UserDefaults.standard.array(forKey: "unlockedThemes") as? [String] ?? ["default"]
        self.unlockedThemes = Set(savedThemes)
        self.selectedTheme = UserDefaults.standard.string(forKey: "selectedTheme") ?? "default"
        
        // Ensure default theme is always unlocked
        if !self.unlockedThemes.contains("default") {
            self.unlockedThemes.insert("default")
        }
    }
    
    func addCrystals(_ amount: Int) {
        totalCrystals += amount
        checkMilestones()
    }
    
    func incrementGamesPlayed() {
        totalGamesPlayed += 1
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
    
    func resetProgress() {
        totalCrystals = 0
        totalGamesPlayed = 0
        unlockedThemes = ["default"]
        selectedTheme = "default"
    }
    
    private func checkMilestones() {
        // Unlock themes based on crystal milestones
        if totalCrystals >= 100 && !unlockedThemes.contains("aurora") {
            unlockedThemes.insert("aurora")
        }
        if totalCrystals >= 250 && !unlockedThemes.contains("twilight") {
            unlockedThemes.insert("twilight")
        }
        if totalCrystals >= 500 && !unlockedThemes.contains("cosmic") {
            unlockedThemes.insert("cosmic")
        }
    }
}

struct ThemeData {
    let id: String
    let name: String
    let requiredCrystals: Int
    let backgroundColor: String
    let accentColor: String
    
    static let themes: [ThemeData] = [
        ThemeData(id: "default", name: "Deep Ocean", requiredCrystals: 0, backgroundColor: "#0A0E29", accentColor: "#3CFF8A"),
        ThemeData(id: "aurora", name: "Aurora Drift", requiredCrystals: 100, backgroundColor: "#1A0E2E", accentColor: "#B983FF"),
        ThemeData(id: "twilight", name: "Twilight Echo", requiredCrystals: 250, backgroundColor: "#2E1A1E", accentColor: "#FF83C1"),
        ThemeData(id: "cosmic", name: "Cosmic Void", requiredCrystals: 500, backgroundColor: "#0E1A2E", accentColor: "#83D7FF")
    ]
}

