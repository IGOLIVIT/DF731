//
//  EchoDropGameView.swift
//  DF731
//
//  Main mini-game with physics and interactive controls
//

import SwiftUI
import Combine

struct EchoDropGameView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var gameProgress = GameProgress.shared
    @StateObject private var gameEngine = EchoDropEngine()
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: "#0A0E29")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
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
                    
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                        Text("\(gameProgress.totalCrystals)")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#3CFF8A"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // Game area
                GeometryReader { geometry in
                    ZStack {
                        // Pegs
                        ForEach(gameEngine.pegs) { peg in
                            Circle()
                                .fill(Color(hex: "#3CFF8A").opacity(0.6))
                                .frame(width: 12, height: 12)
                                .position(peg.position)
                                .shadow(color: Color(hex: "#3CFF8A").opacity(0.5), radius: 8, x: 0, y: 0)
                        }
                        
                        // Ball
                        if gameEngine.gameState != .idle {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            Color(hex: "#FFD640"),
                                            Color(hex: "#FFD640").opacity(0.8)
                                        ]),
                                        center: .topLeading,
                                        startRadius: 5,
                                        endRadius: 20
                                    )
                                )
                                .frame(width: 24, height: 24)
                                .position(gameEngine.ballPosition)
                                .shadow(color: Color(hex: "#FFD640").opacity(0.6), radius: 15, x: 0, y: 0)
                        }
                        
                        // Slots at bottom
                        HStack(spacing: 4) {
                            ForEach(gameEngine.slots) { slot in
                                VStack(spacing: 4) {
                                    Text("\(slot.crystalValue)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "#FFD640"))
                                    
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "#3CFF8A"))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            slot.isHighlighted ?
                                            Color(hex: "#3CFF8A").opacity(0.3) :
                                            Color.white.opacity(0.1)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(hex: "#3CFF8A").opacity(0.4), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 40)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear {
                        gameEngine.setupGame(in: geometry.size)
                    }
                }
                
                // Control buttons
                HStack(spacing: 30) {
                    // Left button
                    Button(action: {
                        gameEngine.nudgeBall(direction: .left)
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color(hex: "#0A0E29"))
                            .frame(width: 70, height: 70)
                            .background(
                                Circle()
                                    .fill(Color(hex: "#FFD640"))
                                    .shadow(color: Color(hex: "#FFD640").opacity(0.4), radius: 15, x: 0, y: 5)
                            )
                    }
                    .disabled(gameEngine.gameState == .idle || gameEngine.gameState == .finished)
                    .opacity(gameEngine.gameState == .idle || gameEngine.gameState == .finished ? 0.5 : 1.0)
                    
                    // Play/Replay button
                    Button(action: {
                        if gameEngine.gameState == .idle || gameEngine.gameState == .finished {
                            gameEngine.startGame()
                        }
                    }) {
                        Image(systemName: gameEngine.gameState == .finished ? "arrow.clockwise" : "play.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(Color(hex: "#0A0E29"))
                            .frame(width: 80, height: 80)
                            .background(
                                Circle()
                                    .fill(Color(hex: "#3CFF8A"))
                                    .shadow(color: Color(hex: "#3CFF8A").opacity(0.4), radius: 20, x: 0, y: 5)
                            )
                    }
                    
                    // Right button
                    Button(action: {
                        gameEngine.nudgeBall(direction: .right)
                    }) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color(hex: "#0A0E29"))
                            .frame(width: 70, height: 70)
                            .background(
                                Circle()
                                    .fill(Color(hex: "#FFD640"))
                                    .shadow(color: Color(hex: "#FFD640").opacity(0.4), radius: 15, x: 0, y: 5)
                            )
                    }
                    .disabled(gameEngine.gameState == .idle || gameEngine.gameState == .finished)
                    .opacity(gameEngine.gameState == .idle || gameEngine.gameState == .finished ? 0.5 : 1.0)
                }
                .padding(.vertical, 30)
            }
            
            // Celebration overlay
            if gameEngine.showCelebration {
                CelebrationOverlay(crystalAmount: gameEngine.lastWinAmount)
                    .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
    }
}

class EchoDropEngine: ObservableObject {
    @Published var ballPosition: CGPoint = .zero
    @Published var gameState: GameState = .idle
    @Published var pegs: [Peg] = []
    @Published var slots: [Slot] = []
    @Published var showCelebration = false
    @Published var lastWinAmount = 0
    
    private var ballVelocity: CGPoint = .zero
    private var gameSize: CGSize = .zero
    private var timer: Timer?
    
    enum GameState {
        case idle, playing, finished
    }
    
    struct Peg: Identifiable {
        let id = UUID()
        let position: CGPoint
    }
    
    struct Slot: Identifiable {
        let id = UUID()
        let crystalValue: Int
        var isHighlighted: Bool = false
    }
    
    enum Direction {
        case left, right
    }
    
    func setupGame(in size: CGSize) {
        gameSize = size
        setupPegs()
        setupSlots()
        ballPosition = CGPoint(x: size.width / 2, y: 50)
    }
    
    private func setupPegs() {
        pegs.removeAll()
        let rows = 8
        let spacing: CGFloat = 55
        
        // Calculate safe zone - keep pegs away from bottom 120 pixels (for slots)
        let maxY = gameSize.height - 140
        
        for row in 0..<rows {
            let pegsInRow = 4 + row / 2
            let startX = (gameSize.width - CGFloat(pegsInRow - 1) * spacing) / 2
            let isOffset = row % 2 == 1
            
            for col in 0..<pegsInRow {
                let x = startX + CGFloat(col) * spacing + (isOffset ? spacing / 2 : 0)
                let y: CGFloat = 120 + CGFloat(row) * spacing
                
                // Only add peg if it's in safe zone
                if y < maxY {
                    pegs.append(Peg(position: CGPoint(x: x, y: y)))
                }
            }
        }
    }
    
    private func setupSlots() {
        let slotValues = [5, 10, 15, 25, 15, 10, 5]
        slots = slotValues.map { Slot(crystalValue: $0) }
    }
    
    func startGame() {
        // Ensure we're on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.gameState = .playing
            self.ballPosition = CGPoint(x: self.gameSize.width / 2, y: 50)
            self.ballVelocity = CGPoint(x: 0, y: 3)
            self.showCelebration = false
            
            // Reset slot highlights
            for index in self.slots.indices {
                self.slots[index].isHighlighted = false
            }
            
            self.startPhysicsLoop()
        }
    }
    
    func nudgeBall(direction: Direction) {
        guard gameState == .playing else { return }
        let nudgeForce: CGFloat = 3.0
        ballVelocity.x += direction == .left ? -nudgeForce : nudgeForce
    }
    
    private func startPhysicsLoop() {
        timer?.invalidate()
        
        // Ensure timer runs on main run loop
        timer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePhysics()
            }
        }
        
        // Add to common run loop modes to prevent pausing
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func updatePhysics() {
        guard gameState == .playing else {
            timer?.invalidate()
            return
        }
        
        // Apply gravity
        ballVelocity.y += 0.3
        
        // Apply slight friction
        ballVelocity.x *= 0.98
        
        // Update position
        ballPosition.x += ballVelocity.x
        ballPosition.y += ballVelocity.y
        
        // Check collision with pegs
        for peg in pegs {
            let distance = sqrt(pow(ballPosition.x - peg.position.x, 2) + pow(ballPosition.y - peg.position.y, 2))
            if distance < 18 {
                // Bounce off peg
                let angle = atan2(ballPosition.y - peg.position.y, ballPosition.x - peg.position.x)
                ballVelocity.x = cos(angle) * 4
                ballVelocity.y = abs(sin(angle)) * 4
                
                // Move ball away from peg
                ballPosition.x = peg.position.x + cos(angle) * 18
                ballPosition.y = peg.position.y + sin(angle) * 18
            }
        }
        
        // Boundary check
        if ballPosition.x < 12 {
            ballPosition.x = 12
            ballVelocity.x = abs(ballVelocity.x)
        }
        if ballPosition.x > gameSize.width - 12 {
            ballPosition.x = gameSize.width - 12
            ballVelocity.x = -abs(ballVelocity.x)
        }
        
        // Check if reached bottom
        if ballPosition.y > gameSize.height - 80 {
            finishGame()
        }
    }
    
    private func finishGame() {
        timer?.invalidate()
        timer = nil
        gameState = .finished
        
        // Determine which slot
        let slotWidth = gameSize.width / CGFloat(slots.count)
        let slotIndex = min(max(Int(ballPosition.x / slotWidth), 0), slots.count - 1)
        
        // Highlight slot
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.slots[slotIndex].isHighlighted = true
        }
        
        // Award crystals
        let crystalAmount = slots[slotIndex].crystalValue
        lastWinAmount = crystalAmount
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            GameProgress.shared.addCrystals(crystalAmount)
            GameProgress.shared.incrementGamesPlayed()
            
            withAnimation {
                self.showCelebration = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                withAnimation {
                    self.showCelebration = false
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
}

struct CelebrationOverlay: View {
    let crystalAmount: Int
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(Color(hex: "#FFD640"))
                
                Text("+\(crystalAmount) Crystals")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "#0A0E29"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color(hex: "#3CFF8A"), lineWidth: 2)
                    )
                    .shadow(color: Color(hex: "#3CFF8A").opacity(0.5), radius: 30, x: 0, y: 0)
            )
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

