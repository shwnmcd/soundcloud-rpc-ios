import SwiftUI
import UIKit

enum MiniGameTab: String, CaseIterable, Identifiable {
    case chess = "Chess"
    case blackjack = "21 Blackjack"
    var id: String { rawValue }
}

private struct ChessWireState: Codable {
    let board: [String] // 64 squares: uppercase=White (P,N,B,R,Q,K), lowercase=Black, ""=empty
    let turn: String    // "w" or "b"
    let lastFrom: Int?
    let lastTo: Int?
}

struct JamGamesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var jam: JamSessionService

    @State private var selectedGame: MiniGameTab = .chess

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Game", selection: $selectedGame) {
                    ForEach(MiniGameTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)

                ScrollView(showsIndicators: false) {
                    if selectedGame == .chess {
                        ChessMiniGameView()
                            .padding(.horizontal, 14)
                    } else {
                        BlackjackMiniGameView()
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(jam.isActive ? "Jam Games · \(jam.roomCode)" : "CloudWave Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Full Legal Multiplayer & Solo Chess
struct ChessMiniGameView: View {
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var jam: JamSessionService

    @State private var board: [String] = Self.initialBoard()
    @State private var turn: String = "w" // "w" or "b"
    @State private var selectedSquare: Int? = nil
    @State private var legalTargets: Set<Int> = []
    @State private var lastFrom: Int? = nil
    @State private var lastTo: Int? = nil
    @State private var vsBot: Bool = false
    @State private var statusText: String = "White to move"

    private var myColor: String {
        if !jam.isActive || vsBot { return "w" }
        return jam.isHost ? "w" : "b"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(theme.textPrimary)
                    Text(jam.isActive && !vsBot
                         ? "Multiplayer Jam · You are \(myColor == "w" ? "White (Host)" : "Black (Guest)")"
                         : "Solo vs CloudWave Bot (You are White)")
                        .font(.caption)
                        .foregroundColor(theme.textSecondary)
                }
                Spacer()
                Button {
                    resetBoard(broadcast: true)
                } label: {
                    Text("New Game")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(SpringPressButtonStyle())
            }
            .padding(12)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if jam.isActive {
                Toggle("Play Solo vs Bot instead of Jam Opponent", isOn: $vsBot)
                    .font(.caption.weight(.semibold))
                    .tint(theme.accent)
                    .padding(.horizontal, 6)
            }

            // 8x8 Interactive Board
            GeometryReader { geo in
                let side = min(geo.size.width, 400)
                let cell = side / 8.0
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { displayRow in
                        let r = (myColor == "b" && jam.isActive && !vsBot) ? (7 - displayRow) : displayRow
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { displayCol in
                                let c = (myColor == "b" && jam.isActive && !vsBot) ? (7 - displayCol) : displayCol
                                let idx = r * 8 + c
                                let isLight = (r + c) % 2 == 0
                                let piece = board[idx]
                                let isSel = selectedSquare == idx
                                let isTarget = legalTargets.contains(idx)
                                let isLast = (lastFrom == idx || lastTo == idx)

                                ZStack {
                                    Rectangle()
                                        .fill(squareColor(isLight: isLight, isSel: isSel, isLast: isLast))

                                    if isTarget {
                                        if piece.isEmpty {
                                            Circle()
                                                .fill(theme.accent.opacity(0.65))
                                                .frame(width: cell * 0.30, height: cell * 0.30)
                                        } else {
                                            Circle()
                                                .stroke(theme.accent, lineWidth: 3)
                                                .frame(width: cell * 0.84, height: cell * 0.84)
                                        }
                                    }

                                    if !piece.isEmpty {
                                        Text(Self.pieceGlyph(piece))
                                            .font(.system(size: cell * 0.66))
                                            .foregroundColor(Self.isWhite(piece) ? .white : .black)
                                            .shadow(color: Self.isWhite(piece) ? .black.opacity(0.85) : .white.opacity(0.45), radius: 1.5, x: 0, y: 1)
                                    }
                                }
                                .frame(width: cell, height: cell)
                                .contentShape(Rectangle())
                                .onTapGesture { handleTap(idx) }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.divider, lineWidth: 1.5))
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity)
            }
            .frame(height: min(UIScreen.main.bounds.width - 28, 400))
        }
        .onChange(of: jam.latestChessPayload) { newPayload in
            guard let json = newPayload, !vsBot,
                  let data = json.data(using: .utf8),
                  let wire = try? JSONDecoder().decode(ChessWireState.self, from: data),
                  wire.board.count == 64 else { return }
            board = wire.board
            turn = wire.turn
            lastFrom = wire.lastFrom
            lastTo = wire.lastTo
            selectedSquare = nil
            legalTargets = []
            updateStatus()
        }
    }

    private func squareColor(isLight: Bool, isSel: Bool, isLast: Bool) -> Color {
        if isSel { return theme.accent.opacity(0.75) }
        if isLast { return Color.yellow.opacity(isLight ? 0.55 : 0.42) }
        return isLight ? Color(red: 0.82, green: 0.77, blue: 0.68) : Color(red: 0.42, green: 0.34, blue: 0.28)
    }

    private func handleTap(_ idx: Int) {
        let playingMulti = jam.isActive && !vsBot
        if playingMulti && turn != myColor { return }
        if !playingMulti && turn != "w" { return }

        if let from = selectedSquare, legalTargets.contains(idx) {
            applyMove(from: from, to: idx, broadcast: playingMulti)
            if !playingMulti && turn == "b" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    makeBotMove()
                }
            }
            return
        }

        let p = board[idx]
        if !p.isEmpty && ((turn == "w" && Self.isWhite(p)) || (turn == "b" && !Self.isWhite(p))) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedSquare = idx
            legalTargets = Set(Self.legalMoves(from: idx, board: board))
        } else {
            selectedSquare = nil
            legalTargets = []
        }
    }

    private func applyMove(from: Int, to: Int, broadcast: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var next = board
        var moved = next[from]
        next[from] = ""
        // Auto-promote pawns reaching last rank
        let toRow = to / 8
        if moved == "P" && toRow == 0 { moved = "Q" }
        if moved == "p" && toRow == 7 { moved = "q" }
        next[to] = moved
        board = next
        turn = (turn == "w") ? "b" : "w"
        lastFrom = from
        lastTo = to
        selectedSquare = nil
        legalTargets = []
        updateStatus()

        if broadcast {
            let wire = ChessWireState(board: board, turn: turn, lastFrom: from, lastTo: to)
            if let data = try? JSONEncoder().encode(wire), let str = String(data: data, encoding: .utf8) {
                jam.sendChessState(str)
            }
        }
    }

    private func makeBotMove() {
        var allMoves: [(from: Int, to: Int, score: Int)] = []
        for idx in 0..<64 {
            let p = board[idx]
            if !p.isEmpty && !Self.isWhite(p) {
                for target in Self.legalMoves(from: idx, board: board) {
                    let captured = board[target]
                    let score = Self.pieceValue(captured) * 10 + ((target / 8 >= 2 && target / 8 <= 5) ? 2 : 0) + Int.random(in: 0...3)
                    allMoves.append((idx, target, score))
                }
            }
        }
        guard let best = allMoves.max(by: { $0.score < $1.score }) else {
            updateStatus()
            return
        }
        applyMove(from: best.from, to: best.to, broadcast: false)
    }

    private func resetBoard(broadcast: Bool) {
        board = Self.initialBoard()
        turn = "w"
        selectedSquare = nil
        legalTargets = []
        lastFrom = nil
        lastTo = nil
        updateStatus()
        if broadcast && jam.isActive && !vsBot {
            let wire = ChessWireState(board: board, turn: "w", lastFrom: nil, lastTo: nil)
            if let data = try? JSONEncoder().encode(wire), let str = String(data: data, encoding: .utf8) {
                jam.sendChessState(str)
            }
        }
    }

    private func updateStatus() {
        let hasWhiteKing = board.contains("K")
        let hasBlackKing = board.contains("k")
        if !hasWhiteKing { statusText = "Black Wins!"; return }
        if !hasBlackKing { statusText = "White Wins!"; return }
        let sideName = turn == "w" ? "White" : "Black"
        let inCheck = Self.isKingInCheck(white: turn == "w", board: board)
        var anyLegal = false
        for i in 0..<64 {
            let p = board[i]
            if !p.isEmpty && ((turn == "w" && Self.isWhite(p)) || (turn == "b" && !Self.isWhite(p))) {
                if !Self.legalMoves(from: i, board: board).isEmpty { anyLegal = true; break }
            }
        }
        if !anyLegal {
            statusText = inCheck ? "Checkmate! \(turn == "w" ? "Black" : "White") Wins!" : "Stalemate (Draw)"
        } else {
            statusText = inCheck ? "\(sideName) is in Check!" : "\(sideName) to move"
        }
    }

    // MARK: - Chess Rules Engine
    static func initialBoard() -> [String] {
        [
            "r","n","b","q","k","b","n","r",
            "p","p","p","p","p","p","p","p",
            "","","","","","","","",
            "","","","","","","","",
            "","","","","","","","",
            "","","","","","","","",
            "P","P","P","P","P","P","P","P",
            "R","N","B","Q","K","B","N","R"
        ]
    }

    static func isWhite(_ p: String) -> Bool {
        guard let c = p.first else { return false }
        return c.isUppercase
    }

    static func pieceValue(_ p: String) -> Int {
        switch p.lowercased() {
        case "p": return 1
        case "n", "b": return 3
        case "r": return 5
        case "q": return 9
        case "k": return 100
        default: return 0
        }
    }

    static func pieceGlyph(_ p: String) -> String {
        switch p {
        case "K": return "♔"
        case "Q": return "♕"
        case "R": return "♖"
        case "B": return "♗"
        case "N": return "♘"
        case "P": return "♙"
        case "k": return "♚"
        case "q": return "♛"
        case "r": return "♜"
        case "b": return "♝"
        case "n": return "♞"
        case "p": return "♟"
        default: return ""
        }
    }

    static func pseudoMoves(from idx: Int, board: [String]) -> [Int] {
        let p = board[idx]
        guard !p.isEmpty else { return [] }
        let white = isWhite(p)
        let r = idx / 8, c = idx % 8
        var out: [Int] = []

        func inBounds(_ nr: Int, _ nc: Int) -> Bool { nr >= 0 && nr < 8 && nc >= 0 && nc < 8 }
        func isEnemy(_ sq: Int) -> Bool { !board[sq].isEmpty && isWhite(board[sq]) != white }
        func isFriendly(_ sq: Int) -> Bool { !board[sq].isEmpty && isWhite(board[sq]) == white }

        func slide(_ dirs: [(Int, Int)]) {
            for (dr, dc) in dirs {
                var nr = r + dr, nc = c + dc
                while inBounds(nr, nc) {
                    let sq = nr * 8 + nc
                    if isFriendly(sq) { break }
                    out.append(sq)
                    if isEnemy(sq) { break }
                    nr += dr; nc += dc
                }
            }
        }

        switch p.lowercased() {
        case "p":
            let dir = white ? -1 : 1
            let startRow = white ? 6 : 1
            if inBounds(r + dir, c) {
                let fwd = (r + dir) * 8 + c
                if board[fwd].isEmpty {
                    out.append(fwd)
                    if r == startRow && inBounds(r + dir * 2, c) {
                        let fwd2 = (r + dir * 2) * 8 + c
                        if board[fwd2].isEmpty { out.append(fwd2) }
                    }
                }
            }
            for dc in [-1, 1] {
                if inBounds(r + dir, c + dc) {
                    let diag = (r + dir) * 8 + (c + dc)
                    if isEnemy(diag) { out.append(diag) }
                }
            }
        case "n":
            for (dr, dc) in [(-2,-1),(-2,1),(-1,-2),(-1,2),(1,-2),(1,2),(2,-1),(2,1)] {
                if inBounds(r + dr, c + dc) {
                    let sq = (r + dr) * 8 + (c + dc)
                    if !isFriendly(sq) { out.append(sq) }
                }
            }
        case "b": slide([(-1,-1),(-1,1),(1,-1),(1,1)])
        case "r": slide([(-1,0),(1,0),(0,-1),(0,1)])
        case "q": slide([(-1,-1),(-1,1),(1,-1),(1,1),(-1,0),(1,0),(0,-1),(0,1)])
        case "k":
            for dr in -1...1 {
                for dc in -1...1 where !(dr == 0 && dc == 0) {
                    if inBounds(r + dr, c + dc) {
                        let sq = (r + dr) * 8 + (c + dc)
                        if !isFriendly(sq) { out.append(sq) }
                    }
                }
            }
        default: break
        }
        return out
    }

    static func isKingInCheck(white: Bool, board: [String]) -> Bool {
        let kingChar = white ? "K" : "k"
        guard let kingSq = board.firstIndex(of: kingChar) else { return false }
        for i in 0..<64 {
            let p = board[i]
            if !p.isEmpty && isWhite(p) != white {
                if pseudoMoves(from: i, board: board).contains(kingSq) { return true }
            }
        }
        return false
    }

    static func legalMoves(from idx: Int, board: [String]) -> [Int] {
        let p = board[idx]
        guard !p.isEmpty else { return [] }
        let white = isWhite(p)
        return pseudoMoves(from: idx, board: board).filter { target in
            var copy = board
            copy[target] = copy[idx]
            copy[idx] = ""
            return !isKingInCheck(white: white, board: copy)
        }
    }
}

// MARK: - 21 / Blackjack Casino Table (With Live Jam Score Broadcast!)
private struct PlayingCard: Identifiable {
    let id = UUID()
    let rank: String
    let suit: String
    var isRed: Bool { suit == "♥" || suit == "♦" }
    var value: Int {
        switch rank {
        case "A": return 11
        case "K", "Q", "J": return 10
        default: return Int(rank) ?? 0
        }
    }
}

struct BlackjackMiniGameView: View {
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var jam: JamSessionService

    @State private var chips: Int = 1000
    @State private var bet: Int = 50
    @State private var deck: [PlayingCard] = []
    @State private var playerHand: [PlayingCard] = []
    @State private var dealerHand: [PlayingCard] = []
    @State private var roundActive: Bool = false
    @State private var dealerRevealed: Bool = false
    @State private var message: String = "Place your bet & tap Deal!"

    private var playerTotal: Int { Self.handTotal(playerHand) }
    private var dealerTotal: Int {
        if dealerRevealed { return Self.handTotal(dealerHand) }
        return dealerHand.first?.value ?? 0
    }

    var body: some View {
        VStack(spacing: 14) {
            // Bankroll & Current Bet
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHIPS")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(theme.textSecondary)
                    Text("$\(chips)")
                        .font(.title2.weight(.black).monospacedDigit())
                        .foregroundColor(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BET")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(theme.textSecondary)
                    Text("$\(bet)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundColor(theme.accent)
                }
            }
            .padding(14)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Emerald Felt Casino Table
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("DEALER · \(dealerRevealed ? "\(dealerTotal)" : "\(dealerTotal)+?")")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.8))
                    HStack(spacing: -14) {
                        ForEach(Array(dealerHand.enumerated()), id: \.element.id) { idx, card in
                            cardView(card, hidden: idx == 1 && !dealerRevealed)
                        }
                    }
                    .frame(minHeight: 84)
                }

                Text(message)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.42))
                    .clipShape(Capsule())

                VStack(spacing: 8) {
                    HStack(spacing: -14) {
                        ForEach(playerHand) { card in
                            cardView(card, hidden: false)
                        }
                    }
                    .frame(minHeight: 84)

                    Text("YOU · \(playerTotal)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                RadialGradient(
                    colors: [Color(red: 0.07, green: 0.36, blue: 0.22), Color(red: 0.03, green: 0.18, blue: 0.11)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 260
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.yellow.opacity(0.35), lineWidth: 1.5))

            // Controls
            if roundActive {
                HStack(spacing: 10) {
                    Button { hit() } label: {
                        Text("Hit")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(SpringPressButtonStyle())

                    Button { stand() } label: {
                        Text("Stand")
                            .font(.headline.weight(.bold))
                            .foregroundColor(theme.playCircleFg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(theme.playCircleBg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(SpringPressButtonStyle())

                    if playerHand.count == 2 && chips >= bet {
                        Button { doubleDown() } label: {
                            Text("2×")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 13)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(SpringPressButtonStyle())
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach([25, 50, 100, 250], id: \.self) { chipVal in
                        Button {
                            bet = min(max(25, chips), chipVal)
                        } label: {
                            Text("$\(chipVal)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(bet == chipVal ? .white : theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(bet == chipVal ? theme.accent : theme.surfaceElevated)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(SpringPressButtonStyle())
                    }
                }

                Button { deal() } label: {
                    Text(chips < 25 ? "Rebuy $1,000 & Deal" : "Deal Hand ($\(bet))")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(SpringPressButtonStyle())
            }
        }
    }

    private func cardView(_ card: PlayingCard, hidden: Bool) -> some View {
        ZStack {
            if hidden {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [theme.accent, Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                    .overlay(Image(systemName: "waveform").foregroundColor(.white.opacity(0.85)))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                VStack(spacing: 2) {
                    Text(card.rank)
                        .font(.system(size: 20, weight: .black))
                    Text(card.suit)
                        .font(.system(size: 22))
                }
                .foregroundColor(card.isRed ? .red : .black)
            }
        }
        .frame(width: 60, height: 84)
    }

    private func freshDeck() -> [PlayingCard] {
        let ranks = ["A","2","3","4","5","6","7","8","9","10","J","Q","K"]
        let suits = ["♠","♥","♦","♣"]
        return suits.flatMap { s in ranks.map { r in PlayingCard(rank: r, suit: s) } }.shuffled()
    }

    private func drawCard() -> PlayingCard {
        if deck.count < 10 { deck = freshDeck() }
        return deck.removeLast()
    }

    private func deal() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if chips < 25 { chips = 1000 }
        bet = min(bet, chips)
        chips -= bet
        dealerRevealed = false
        roundActive = true
        playerHand = [drawCard(), drawCard()]
        dealerHand = [drawCard(), drawCard()]

        if playerTotal == 21 {
            dealerRevealed = true
            roundActive = false
            let win = Int(Double(bet) * 2.5)
            chips += win
            message = "BLACKJACK! Won $\(win)!"
            broadcastResult("Hit 21 BLACKJACK! ($\(chips))")
        } else {
            message = "Hit or Stand?"
        }
    }

    private func hit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        playerHand.append(drawCard())
        if playerTotal > 21 {
            dealerRevealed = true
            roundActive = false
            message = "Bust (\(playerTotal))! Dealer wins."
            broadcastResult("Busted on \(playerTotal) ($\(chips))")
        } else if playerTotal == 21 {
            stand()
        }
    }

    private func doubleDown() {
        guard chips >= bet else { return }
        chips -= bet
        bet *= 2
        hit()
        if roundActive { stand() }
    }

    private func stand() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dealerRevealed = true
        roundActive = false
        while Self.handTotal(dealerHand) < 17 {
            dealerHand.append(drawCard())
        }
        let d = Self.handTotal(dealerHand)
        let p = playerTotal
        if d > 21 || p > d {
            chips += bet * 2
            message = "You Win! (\(p) vs \(d))"
            broadcastResult("Won Blackjack \(p) vs \(d) ($\(chips))")
        } else if d == p {
            chips += bet
            message = "Push (\(p) vs \(d))"
        } else {
            message = "Dealer Wins (\(d) vs \(p))"
        }
    }

    private func broadcastResult(_ summary: String) {
        guard jam.isActive else { return }
        let dict: [String: Any] = ["summary": summary, "chips": chips]
        if let d = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: d, encoding: .utf8) {
            jam.sendBlackjackUpdate(str)
        }
    }

    private static func handTotal(_ cards: [PlayingCard]) -> Int {
        var total = cards.reduce(0) { $0 + $1.value }
        var aces = cards.filter { $0.rank == "A" }.count
        while total > 21 && aces > 0 {
            total -= 10
            aces -= 1
        }
        return total
    }
}
