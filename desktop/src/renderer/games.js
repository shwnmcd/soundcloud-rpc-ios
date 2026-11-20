/**
 * SoundCloud S Multiplayer Arcade — Connect Four, Chess & 21 Blackjack
 * Play Solo vs Bot OR live against ANY participant connected to your Jam (Windows ↔ iOS)!
 */
class SoundCloudSGames {
  constructor(jam, onRenderNeeded, onToast) {
    this.jam = jam;
    this.onRenderNeeded = onRenderNeeded;
    this.onToast = onToast;

    this.activeTab = 'connect4'; // 'connect4' | 'chess' | 'blackjack'

    // ===== Connect Four State (7 cols x 6 rows = 42 cells) =====
    this.c4Board = Array(42).fill(0); // 0=empty, 1=Red, 2=Gold
    this.c4Turn = 1;
    this.c4LastMove = null;
    this.c4Winner = 0; // 0=playing, 1=Red, 2=Gold, 3=Draw
    this.c4WinCells = [];
    this.c4HoverCol = -1;
    this.c4VsBot = false;
    this.c4RedId = null;
    this.c4RedName = 'Red';
    this.c4GoldId = '*'; // '*' = Open Jam Table (anyone in Jam can play!)
    this.c4GoldName = 'Anyone in Jam';
    this.c4Scores = { red: 0, gold: 0 };

    // ===== Chess State (8x8 = 64 squares) =====
    this.board = SoundCloudSGames.initialBoard();
    this.turn = 'w';
    this.selectedSq = null;
    this.legalTargets = new Set();
    this.lastFrom = null;
    this.lastTo = null;
    this.vsBot = false;
    this.chessStatus = 'White to move';
    this.whiteId = null;
    this.whiteName = 'White';
    this.blackId = '*';
    this.blackName = 'Anyone in Jam';

    // ===== 21 / Blackjack State =====
    this.chips = 1000;
    this.bet = 50;
    this.deck = [];
    this.playerHand = [];
    this.dealerHand = [];
    this.roundActive = false;
    this.dealerRevealed = false;
    this.bjMessage = 'Place your bet and deal a hand!';
  }

  // =========================================================================
  // MARK: - CONNECT FOUR (7x6 Interactive + Jam Any-Opponent Multiplayer)
  // =========================================================================
  get c4IsMultiplayer() {
    return this.jam.isActive && !this.c4VsBot;
  }

  get c4MySeat() {
    if (!this.c4IsMultiplayer) return 1;
    const me = this.jam.myId;
    if (this.c4RedId === me) return 1;
    if (this.c4GoldId === me) return 2;
    if (!this.c4RedId) return 1;
    if (!this.c4GoldId || this.c4GoldId === '*') return 2;
    return 0; // Spectating two other Jam members
  }

  startConnect4Match(opponentId = '*', opponentName = 'Anyone in Jam', vsBot = false) {
    this.c4VsBot = vsBot;
    this.c4Board = Array(42).fill(0);
    this.c4Turn = 1;
    this.c4LastMove = null;
    this.c4Winner = 0;
    this.c4WinCells = [];

    if (this.c4IsMultiplayer) {
      this.c4RedId = this.jam.myId;
      this.c4RedName = this.jam.myName;
      this.c4GoldId = opponentId || '*';
      this.c4GoldName = opponentId === '*' ? 'Anyone in Jam' : opponentName;
      this.broadcastConnect4();
      if (opponentId && opponentId !== '*') {
        this.onToast(`Challenged ${opponentName} to Connect Four!`);
      }
    } else {
      this.c4RedId = this.jam.myId;
      this.c4RedName = this.jam.myName || 'You';
      this.c4GoldId = 'bot';
      this.c4GoldName = 'SoundCloud S Bot';
    }
    this.onRenderNeeded();
  }

  broadcastConnect4() {
    if (!this.c4IsMultiplayer) return;
    const wire = {
      board: this.c4Board,
      turn: this.c4Turn,
      lastMove: this.c4LastMove,
      winner: this.c4Winner,
      winCells: this.c4WinCells,
      redId: this.c4RedId,
      redName: this.c4RedName,
      goldId: this.c4GoldId,
      goldName: this.c4GoldName
    };
    this.jam.sendConnect4State(JSON.stringify(wire));
  }

  applyRemoteConnect4(jsonString, senderName, senderId) {
    if (this.c4VsBot) return;
    try {
      const w = JSON.parse(jsonString);
      if (!Array.isArray(w.board) || w.board.length !== 42) return;
      const wasEmpty = this.c4Board.every((v) => v === 0);
      this.c4Board = w.board.map((v) => Number(v) || 0);
      this.c4Turn = w.turn === 2 ? 2 : 1;
      this.c4LastMove = typeof w.lastMove === 'number' ? w.lastMove : null;
      this.c4Winner = Number(w.winner) || 0;
      this.c4WinCells = Array.isArray(w.winCells) ? w.winCells : [];
      this.c4RedId = w.redId || senderId || null;
      this.c4RedName = w.redName || senderName || 'Red';
      this.c4GoldId = w.goldId ?? '*';
      this.c4GoldName = w.goldName || 'Anyone in Jam';

      if (this.c4Winner === 1) this.c4Scores.red++;
      else if (this.c4Winner === 2) this.c4Scores.gold++;

      if (wasEmpty && w.goldId === this.jam.myId) {
        this.onToast(`${senderName || 'A friend'} challenged you to Connect Four!`);
      } else if (senderName) {
        this.onToast(`Connect Four · ${senderName} dropped a disc`);
      }
      this.onRenderNeeded();
    } catch {}
  }

  dropConnect4(col) {
    if (this.c4Winner !== 0 || col < 0 || col > 6) return;

    if (this.c4IsMultiplayer) {
      const seat = this.c4MySeat;
      if (seat === 0) {
        this.onToast(`Spectating ${this.c4RedName} vs ${this.c4GoldName}`);
        return;
      }
      if (seat !== this.c4Turn) {
        const waiter = this.c4Turn === 1 ? this.c4RedName : this.c4GoldName;
        this.onToast(`Waiting for ${waiter}'s move`);
        return;
      }
      // Claim seat if open table
      if (seat === 1 && !this.c4RedId) {
        this.c4RedId = this.jam.myId;
        this.c4RedName = this.jam.myName;
      } else if (seat === 2 && (!this.c4GoldId || this.c4GoldId === '*')) {
        this.c4GoldId = this.jam.myId;
        this.c4GoldName = this.jam.myName;
      }
    } else if (this.c4Turn !== 1) {
      return;
    }

    const row = SoundCloudSGames.lowestEmptyRow(this.c4Board, col);
    if (row < 0) return;

    this.applyConnect4Move(row * 7 + col, this.c4Turn, this.c4IsMultiplayer);

    if (!this.c4IsMultiplayer && this.c4Winner === 0 && this.c4Turn === 2) {
      setTimeout(() => this.runConnect4Bot(), 360);
    }
  }

  applyConnect4Move(idx, player, broadcast) {
    this.c4Board[idx] = player;
    this.c4LastMove = idx;

    const win = SoundCloudSGames.checkConnect4Win(this.c4Board, player);
    if (win) {
      this.c4Winner = player;
      this.c4WinCells = win;
      if (player === 1) this.c4Scores.red++;
      else this.c4Scores.gold++;
    } else if (this.c4Board.every((c) => c !== 0)) {
      this.c4Winner = 3;
      this.c4WinCells = [];
    } else {
      this.c4Turn = player === 1 ? 2 : 1;
    }

    if (broadcast) this.broadcastConnect4();
    this.onRenderNeeded();
  }

  runConnect4Bot() {
    if (this.c4Winner !== 0 || this.c4Turn !== 2) return;
    const validCols = [];
    for (let c = 0; c < 7; c++) {
      if (SoundCloudSGames.lowestEmptyRow(this.c4Board, c) >= 0) validCols.push(c);
    }
    if (!validCols.length) return;

    // 1. Immediate winning drop
    for (const c of validCols) {
      const r = SoundCloudSGames.lowestEmptyRow(this.c4Board, c);
      const copy = [...this.c4Board];
      copy[r * 7 + c] = 2;
      if (SoundCloudSGames.checkConnect4Win(copy, 2)) {
        this.applyConnect4Move(r * 7 + c, 2, false);
        return;
      }
    }
    // 2. Block player's immediate winning drop
    for (const c of validCols) {
      const r = SoundCloudSGames.lowestEmptyRow(this.c4Board, c);
      const copy = [...this.c4Board];
      copy[r * 7 + c] = 1;
      if (SoundCloudSGames.checkConnect4Win(copy, 1)) {
        this.applyConnect4Move(r * 7 + c, 2, false);
        return;
      }
    }
    // 3. Heuristic: prefer center & avoid setting up opponent above
    let bestCol = validCols[0];
    let bestScore = -1e9;
    for (const c of validCols) {
      const r = SoundCloudSGames.lowestEmptyRow(this.c4Board, c);
      let score = (3 - Math.abs(3 - c)) * 4 + Math.random() * 2;
      if (r > 0) {
        const copy = [...this.c4Board];
        copy[r * 7 + c] = 2;
        copy[(r - 1) * 7 + c] = 1;
        if (SoundCloudSGames.checkConnect4Win(copy, 1)) score -= 40;
      }
      if (score > bestScore) { bestScore = score; bestCol = c; }
    }
    const r = SoundCloudSGames.lowestEmptyRow(this.c4Board, bestCol);
    this.applyConnect4Move(r * 7 + bestCol, 2, false);
  }

  static lowestEmptyRow(board, col) {
    for (let r = 5; r >= 0; r--) {
      if (board[r * 7 + col] === 0) return r;
    }
    return -1;
  }

  static checkConnect4Win(board, player) {
    const dirs = [[0, 1], [1, 0], [1, 1], [1, -1]];
    for (let r = 0; r < 6; r++) {
      for (let c = 0; c < 7; c++) {
        if (board[r * 7 + c] !== player) continue;
        for (const [dr, dc] of dirs) {
          const cells = [r * 7 + c];
          for (let k = 1; k < 4; k++) {
            const nr = r + dr * k;
            const nc = c + dc * k;
            if (nr < 0 || nr >= 6 || nc < 0 || nc >= 7 || board[nr * 7 + nc] !== player) break;
            cells.push(nr * 7 + nc);
          }
          if (cells.length === 4) return cells;
        }
      }
    }
    return null;
  }

  // =========================================================================
  // MARK: - CHESS (Full Legal Rules + Coordinates + Captured + Any Jam Opponent)
  // =========================================================================
  static initialBoard() {
    return [
      'r','n','b','q','k','b','n','r',
      'p','p','p','p','p','p','p','p',
      '','','','','','','','',
      '','','','','','','','',
      '','','','','','','','',
      '','','','','','','','',
      'P','P','P','P','P','P','P','P',
      'R','N','B','Q','K','B','N','R'
    ];
  }

  static pieceGlyph(p) {
    const map = {
      K: '♔', Q: '♕', R: '♖', B: '♗', N: '♘', P: '♙',
      k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟'
    };
    return map[p] || '';
  }

  static pieceColor(p) {
    if (!p) return null;
    return p === p.toUpperCase() ? 'w' : 'b';
  }

  static pieceVal(p) {
    const u = p.toUpperCase();
    return u === 'P' ? 1 : u === 'N' || u === 'B' ? 3 : u === 'R' ? 5 : u === 'Q' ? 9 : u === 'K' ? 100 : 0;
  }

  get chessIsMultiplayer() {
    return this.jam.isActive && !this.vsBot;
  }

  get myChessColor() {
    if (!this.chessIsMultiplayer) return 'w';
    const me = this.jam.myId;
    if (this.whiteId === me) return 'w';
    if (this.blackId === me) return 'b';
    if (!this.whiteId) return this.jam.isHost ? 'w' : 'b';
    if (!this.blackId || this.blackId === '*') return 'b';
    return null; // Spectating
  }

  capturedPieces() {
    const start = { P: 8, N: 2, B: 2, R: 2, Q: 1, p: 8, n: 2, b: 2, r: 2, q: 1 };
    for (const sq of this.board) {
      if (sq && start[sq] !== undefined) start[sq]--;
    }
    const lostWhite = [];
    const lostBlack = [];
    for (const k of ['Q', 'R', 'B', 'N', 'P']) {
      for (let i = 0; i < Math.max(0, start[k]); i++) lostWhite.push(SoundCloudSGames.pieceGlyph(k));
    }
    for (const k of ['q', 'r', 'b', 'n', 'p']) {
      for (let i = 0; i < Math.max(0, start[k]); i++) lostBlack.push(SoundCloudSGames.pieceGlyph(k));
    }
    return { lostWhite, lostBlack };
  }

  startChessMatch(opponentId = '*', opponentName = 'Anyone in Jam', vsBot = false) {
    this.vsBot = vsBot;
    this.board = SoundCloudSGames.initialBoard();
    this.turn = 'w';
    this.selectedSq = null;
    this.legalTargets = new Set();
    this.lastFrom = null;
    this.lastTo = null;
    this.chessStatus = 'White to move';

    if (this.chessIsMultiplayer) {
      this.whiteId = this.jam.myId;
      this.whiteName = this.jam.myName;
      this.blackId = opponentId || '*';
      this.blackName = opponentId === '*' ? 'Anyone in Jam' : opponentName;
      this.broadcastChess();
      if (opponentId && opponentId !== '*') {
        this.onToast(`Challenged ${opponentName} to Chess!`);
      }
    } else {
      this.whiteId = this.jam.myId;
      this.whiteName = this.jam.myName || 'You';
      this.blackId = 'bot';
      this.blackName = 'SoundCloud S Bot';
    }
    this.onRenderNeeded();
  }

  broadcastChess() {
    if (!this.chessIsMultiplayer) return;
    const wire = {
      board: this.board,
      turn: this.turn,
      lastFrom: this.lastFrom,
      lastTo: this.lastTo,
      whiteId: this.whiteId,
      whiteName: this.whiteName,
      blackId: this.blackId,
      blackName: this.blackName
    };
    this.jam.sendChessState(JSON.stringify(wire));
  }

  applyRemoteChess(jsonString, senderName, senderId) {
    if (this.vsBot) return;
    try {
      const wire = JSON.parse(jsonString);
      if (!Array.isArray(wire.board) || wire.board.length !== 64) return;
      this.board = wire.board;
      this.turn = wire.turn === 'b' ? 'b' : 'w';
      this.lastFrom = typeof wire.lastFrom === 'number' ? wire.lastFrom : null;
      this.lastTo = typeof wire.lastTo === 'number' ? wire.lastTo : null;
      if (wire.whiteId !== undefined) this.whiteId = wire.whiteId;
      else if (!this.whiteId) this.whiteId = senderId || null;
      if (wire.whiteName) this.whiteName = wire.whiteName;
      if (wire.blackId !== undefined) this.blackId = wire.blackId;
      if (wire.blackName) this.blackName = wire.blackName;
      this.selectedSq = null;
      this.legalTargets = new Set();
      this.updateChessStatus();
      if (senderName) this.onToast(`Chess · ${senderName} moved`);
      this.onRenderNeeded();
    } catch {}
  }

  clickSquare(sq) {
    const myColor = this.myChessColor;
    if (this.chessIsMultiplayer) {
      if (!myColor) {
        this.onToast(`Spectating ${this.whiteName} vs ${this.blackName}`);
        return;
      }
      if (this.turn !== myColor) {
        const waiter = this.turn === 'w' ? this.whiteName : this.blackName;
        this.onToast(`Waiting for ${waiter}`);
        return;
      }
      if (myColor === 'w' && !this.whiteId) {
        this.whiteId = this.jam.myId;
        this.whiteName = this.jam.myName;
      } else if (myColor === 'b' && (!this.blackId || this.blackId === '*')) {
        this.blackId = this.jam.myId;
        this.blackName = this.jam.myName;
      }
    } else if (this.turn !== 'w') {
      return;
    }

    if (this.selectedSq !== null && this.legalTargets.has(sq)) {
      this.executeChessMove(this.selectedSq, sq);
      return;
    }

    const piece = this.board[sq];
    if (piece && SoundCloudSGames.pieceColor(piece) === this.turn) {
      this.selectedSq = sq;
      this.legalTargets = new Set(SoundCloudSGames.legalMovesFor(sq, this.board));
    } else {
      this.selectedSq = null;
      this.legalTargets = new Set();
    }
    this.onRenderNeeded();
  }

  executeChessMove(from, to) {
    const next = [...this.board];
    let p = next[from];
    next[from] = '';
    const toRow = Math.floor(to / 8);
    if (p === 'P' && toRow === 0) p = 'Q';
    if (p === 'p' && toRow === 7) p = 'q';
    next[to] = p;

    this.board = next;
    this.lastFrom = from;
    this.lastTo = to;
    this.selectedSq = null;
    this.legalTargets = new Set();
    this.turn = this.turn === 'w' ? 'b' : 'w';
    this.updateChessStatus();
    this.broadcastChess();
    this.onRenderNeeded();

    if (!this.chessIsMultiplayer && this.turn === 'b' && !this.chessStatus.includes('Checkmate') && !this.chessStatus.includes('Stalemate')) {
      setTimeout(() => this.runBotMove(), 380);
    }
  }

  runBotMove() {
    if (this.turn !== 'b') return;
    const moves = [];
    for (let sq = 0; sq < 64; sq++) {
      if (SoundCloudSGames.pieceColor(this.board[sq]) === 'b') {
        for (const to of SoundCloudSGames.legalMovesFor(sq, this.board)) {
          const cap = this.board[to];
          const centerBonus = (to >= 27 && to <= 28) || (to >= 35 && to <= 36) ? 1.5 : 0;
          const score = (cap ? SoundCloudSGames.pieceVal(cap) * 10 : 0) + centerBonus + Math.random();
          moves.push({ from: sq, to, score });
        }
      }
    }
    if (!moves.length) {
      this.updateChessStatus();
      this.onRenderNeeded();
      return;
    }
    moves.sort((a, b) => b.score - a.score);
    this.executeChessMove(moves[0].from, moves[0].to);
  }

  updateChessStatus() {
    const hasAny = SoundCloudSGames.hasAnyLegalMove(this.turn, this.board);
    const inCheck = SoundCloudSGames.isKingInCheck(this.turn, this.board);
    const side = this.turn === 'w' ? 'White' : 'Black';
    if (!hasAny) {
      this.chessStatus = inCheck
        ? `Checkmate! ${this.turn === 'w' ? 'Black' : 'White'} wins`
        : 'Stalemate · Draw';
    } else if (inCheck) {
      this.chessStatus = `${side} is in Check!`;
    } else {
      this.chessStatus = `${side} to move`;
    }
  }

  static hasAnyLegalMove(color, board) {
    for (let sq = 0; sq < 64; sq++) {
      if (SoundCloudSGames.pieceColor(board[sq]) === color && SoundCloudSGames.legalMovesFor(sq, board).length > 0) {
        return true;
      }
    }
    return false;
  }

  static legalMovesFor(sq, board) {
    const p = board[sq];
    const color = SoundCloudSGames.pieceColor(p);
    if (!color) return [];
    return SoundCloudSGames.pseudoMoves(sq, board).filter((to) => {
      const copy = [...board];
      copy[to] = copy[sq];
      copy[sq] = '';
      return !SoundCloudSGames.isKingInCheck(color, copy);
    });
  }

  static isKingInCheck(color, board) {
    const king = color === 'w' ? 'K' : 'k';
    const kingSq = board.indexOf(king);
    if (kingSq < 0) return false;
    const opp = color === 'w' ? 'b' : 'w';
    for (let sq = 0; sq < 64; sq++) {
      if (SoundCloudSGames.pieceColor(board[sq]) === opp) {
        if (SoundCloudSGames.pseudoMoves(sq, board).includes(kingSq)) return true;
      }
    }
    return false;
  }

  static pseudoMoves(sq, board) {
    const p = board[sq];
    if (!p) return [];
    const color = SoundCloudSGames.pieceColor(p);
    const r = Math.floor(sq / 8);
    const c = sq % 8;
    const out = [];
    const inside = (rr, cc) => rr >= 0 && rr < 8 && cc >= 0 && cc < 8;
    const upper = p.toUpperCase();

    if (upper === 'P') {
      const dir = color === 'w' ? -1 : 1;
      const startRow = color === 'w' ? 6 : 1;
      const r1 = r + dir;
      if (inside(r1, c) && !board[r1 * 8 + c]) {
        out.push(r1 * 8 + c);
        const r2 = r + dir * 2;
        if (r === startRow && inside(r2, c) && !board[r2 * 8 + c]) out.push(r2 * 8 + c);
      }
      for (const dc of [-1, 1]) {
        if (inside(r1, c + dc)) {
          const t = r1 * 8 + (c + dc);
          if (board[t] && SoundCloudSGames.pieceColor(board[t]) !== color) out.push(t);
        }
      }
      return out;
    }
    if (upper === 'N') {
      for (const [dr, dc] of [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]) {
        if (inside(r + dr, c + dc)) {
          const t = (r + dr) * 8 + (c + dc);
          if (SoundCloudSGames.pieceColor(board[t]) !== color) out.push(t);
        }
      }
      return out;
    }
    if (upper === 'K') {
      for (let dr = -1; dr <= 1; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          if (dr === 0 && dc === 0) continue;
          if (inside(r + dr, c + dc)) {
            const t = (r + dr) * 8 + (c + dc);
            if (SoundCloudSGames.pieceColor(board[t]) !== color) out.push(t);
          }
        }
      }
      return out;
    }
    const dirs = [];
    if (upper === 'B' || upper === 'Q') dirs.push([-1,-1],[-1,1],[1,-1],[1,1]);
    if (upper === 'R' || upper === 'Q') dirs.push([-1,0],[1,0],[0,-1],[0,1]);
    for (const [dr, dc] of dirs) {
      let nr = r + dr, nc = c + dc;
      while (inside(nr, nc)) {
        const t = nr * 8 + nc;
        const targetColor = SoundCloudSGames.pieceColor(board[t]);
        if (!targetColor) out.push(t);
        else { if (targetColor !== color) out.push(t); break; }
        nr += dr; nc += dc;
      }
    }
    return out;
  }

  // =========================================================================
  // MARK: - 21 / BLACKJACK
  // =========================================================================
  buildDeck() {
    const ranks = ['A','2','3','4','5','6','7','8','9','10','J','Q','K'];
    const suits = ['♠','♥','♦','♣'];
    const deck = [];
    for (let d = 0; d < 2; d++) {
      for (const s of suits) {
        for (const r of ranks) {
          const val = r === 'A' ? 11 : ['K','Q','J'].includes(r) ? 10 : Number(r);
          deck.push({ rank: r, suit: s, value: val, red: s === '♥' || s === '♦' });
        }
      }
    }
    for (let i = deck.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
  }

  drawCard() {
    if (this.deck.length < 12) this.deck = this.buildDeck();
    return this.deck.pop();
  }

  static handTotal(cards) {
    let total = cards.reduce((sum, c) => sum + c.value, 0);
    let aces = cards.filter((c) => c.rank === 'A').length;
    while (total > 21 && aces > 0) { total -= 10; aces--; }
    return total;
  }

  dealBlackjack() {
    if (this.chips <= 0) this.chips = 1000;
    const wager = Math.min(this.bet, this.chips);
    this.bet = wager;
    this.chips -= wager;
    this.playerHand = [this.drawCard(), this.drawCard()];
    this.dealerHand = [this.drawCard(), this.drawCard()];
    this.dealerRevealed = false;
    this.roundActive = true;
    this.bjMessage = 'Hit, Stand, or Double Down!';

    const pTotal = SoundCloudSGames.handTotal(this.playerHand);
    if (pTotal === 21) {
      this.dealerRevealed = true;
      this.roundActive = false;
      const win = Math.floor(wager * 2.5);
      this.chips += win;
      this.bjMessage = `BLACKJACK! You won $${win}!`;
      this.broadcastBJ(`Hit BLACKJACK! ($${this.chips})`);
    }
    this.onRenderNeeded();
  }

  hitBlackjack() {
    if (!this.roundActive) return;
    this.playerHand.push(this.drawCard());
    const pTotal = SoundCloudSGames.handTotal(this.playerHand);
    if (pTotal > 21) {
      this.dealerRevealed = true;
      this.roundActive = false;
      this.bjMessage = `Bust (${pTotal})! Dealer wins.`;
      this.broadcastBJ(`Busted on ${pTotal} ($${this.chips})`);
      this.onRenderNeeded();
    } else if (pTotal === 21) {
      this.standBlackjack();
    } else {
      this.onRenderNeeded();
    }
  }

  doubleBlackjack() {
    if (!this.roundActive || this.chips < this.bet) return;
    this.chips -= this.bet;
    this.bet *= 2;
    this.playerHand.push(this.drawCard());
    const pTotal = SoundCloudSGames.handTotal(this.playerHand);
    if (pTotal > 21) {
      this.dealerRevealed = true;
      this.roundActive = false;
      this.bjMessage = `Bust (${pTotal}) on Double Down!`;
      this.broadcastBJ(`Busted on Double Down ($${this.chips})`);
      this.onRenderNeeded();
    } else {
      this.standBlackjack();
    }
  }

  standBlackjack() {
    if (!this.roundActive) return;
    this.dealerRevealed = true;
    this.roundActive = false;
    while (SoundCloudSGames.handTotal(this.dealerHand) < 17) {
      this.dealerHand.push(this.drawCard());
    }
    const d = SoundCloudSGames.handTotal(this.dealerHand);
    const p = SoundCloudSGames.handTotal(this.playerHand);
    if (d > 21 || p > d) {
      this.chips += this.bet * 2;
      this.bjMessage = `You Win! (${p} vs ${d})`;
      this.broadcastBJ(`Won 21 Blackjack ${p} vs ${d} ($${this.chips})`);
    } else if (d === p) {
      this.chips += this.bet;
      this.bjMessage = `Push (${p} vs ${d}) · Bet returned`;
    } else {
      this.bjMessage = `Dealer Wins (${d} vs ${p})`;
    }
    this.onRenderNeeded();
  }

  broadcastBJ(summary) {
    if (!this.jam.isActive) return;
    this.jam.sendBlackjackUpdate(JSON.stringify({ summary, chips: this.chips }));
  }

  // =========================================================================
  // MARK: - MODAL RENDERERS
  // =========================================================================
  renderOpponentBar(esc, gameKey, vsBotFlag, activeOppId) {
    const others = this.jam.otherParticipants || [];
    if (!this.jam.isActive) {
      return `
        <div class="opponent-bar">
          <span class="opponent-label">${window.ic('bot', 14)} Solo vs Bot</span>
          <span class="tiny muted">Start or join a Jam to play against anyone connected!</span>
        </div>
      `;
    }
    return `
      <div class="opponent-bar">
        <span class="opponent-label">${window.ic('users', 14)} Play vs:</span>
        <div class="opponent-pills">
          <button class="opp-pill ${!vsBotFlag && activeOppId === '*' ? 'active' : ''}" data-opp-game="${gameKey}" data-opp-id="*" data-opp-name="Anyone in Jam">Open Jam Table</button>
          ${others.map((p) => `
            <button class="opp-pill ${!vsBotFlag && activeOppId === p.id ? 'active' : ''}" data-opp-game="${gameKey}" data-opp-id="${esc(p.id)}" data-opp-name="${esc(p.name)}">
              ${p.isHost ? '★ ' : ''}${esc(p.name)}
            </button>
          `).join('')}
          <button class="opp-pill ${vsBotFlag ? 'active' : ''}" data-opp-game="${gameKey}" data-opp-id="bot" data-opp-name="Bot">${window.ic('bot', 13)} Bot</button>
        </div>
      </div>
    `;
  }

  renderModalHTML(esc) {
    const isJam = this.jam.isActive;
    return `
      <div class="modal-header">
        <div class="modal-title row-gap">${window.ic('gamepad', 19)} <span>${isJam ? `Jam Arcade · ${esc(this.jam.roomCode)}` : 'SoundCloud S Arcade'}</span></div>
        <button id="m-close" class="btn-secondary">Done</button>
      </div>

      <div class="game-tabs">
        <button class="game-tab ${this.activeTab === 'connect4' ? 'active' : ''}" data-game-tab="connect4">Connect Four</button>
        <button class="game-tab ${this.activeTab === 'chess' ? 'active' : ''}" data-game-tab="chess">Chess</button>
        <button class="game-tab ${this.activeTab === 'blackjack' ? 'active' : ''}" data-game-tab="blackjack">21 Blackjack</button>
      </div>

      ${this.activeTab === 'connect4'
        ? this.renderConnect4HTML(esc)
        : this.activeTab === 'chess'
          ? this.renderChessHTML(esc)
          : this.renderBlackjackHTML(esc)}
    `;
  }

  renderConnect4HTML(esc) {
    const redLabel = this.c4IsMultiplayer ? (this.c4RedName || 'Red') : (this.jam.myName || 'You');
    const goldLabel = this.c4IsMultiplayer ? (this.c4GoldName || 'Anyone in Jam') : 'SoundCloud S Bot';
    const statusLine =
      this.c4Winner === 1 ? `${redLabel} wins Connect Four!` :
      this.c4Winner === 2 ? `${goldLabel} wins Connect Four!` :
      this.c4Winner === 3 ? 'Draw game — board full!' :
      `${this.c4Turn === 1 ? redLabel : goldLabel} to drop`;

    const winSet = new Set(this.c4WinCells);
    const activeOpp = this.c4GoldId === this.jam.myId ? this.c4RedId : this.c4GoldId;

    return `
      ${this.renderOpponentBar(esc, 'connect4', this.c4VsBot, activeOpp)}

      <div class="game-scoreboard">
        <div class="score-pill ${this.c4Turn === 1 && this.c4Winner === 0 ? 'turn' : ''}">
          <span class="disc-swatch red"></span>
          <span class="score-name">${esc(redLabel)}</span>
          <span class="score-num">${this.c4Scores.red}</span>
        </div>
        <div class="score-status">${esc(statusLine)}</div>
        <div class="score-pill ${this.c4Turn === 2 && this.c4Winner === 0 ? 'turn' : ''}">
          <span class="disc-swatch gold"></span>
          <span class="score-name">${esc(goldLabel)}</span>
          <span class="score-num">${this.c4Scores.gold}</span>
        </div>
      </div>

      <div class="c4-shell">
        <div class="c4-drop-row">
          ${[0,1,2,3,4,5,6].map((c) => `
            <button class="c4-drop-btn ${this.c4Turn === 1 ? 'red' : 'gold'}" data-c4-col="${c}" title="Drop in column ${c + 1}">
              ${window.ic('chevronDown', 16)}
            </button>
          `).join('')}
        </div>
        <div class="c4-board">
          ${this.c4Board.map((val, idx) => {
            const col = idx % 7;
            const isWin = winSet.has(idx);
            const isLast = this.c4LastMove === idx;
            const cls = val === 1 ? 'red' : val === 2 ? 'gold' : 'empty';
            return `
              <button class="c4-slot" data-c4-col="${col}">
                <span class="c4-disc ${cls} ${isWin ? 'win' : ''} ${isLast ? 'last' : ''}"></span>
              </button>
            `;
          }).join('')}
        </div>
      </div>

      <div class="row-between" style="margin-top:2px">
        <span class="tiny muted">${this.c4IsMultiplayer ? 'Live Jam table · Synced across Windows & iOS' : 'Solo match vs smart AI'}</span>
        <button id="c4-new" class="btn-primary" style="font-size:12px">New Game</button>
      </div>
    `;
  }

  renderChessHTML(esc) {
    const flipped = this.chessIsMultiplayer && this.myChessColor === 'b';
    const order = [];
    for (let r = 0; r < 8; r++) {
      for (let c = 0; c < 8; c++) {
        const rr = flipped ? 7 - r : r;
        const cc = flipped ? 7 - c : c;
        order.push(rr * 8 + cc);
      }
    }
    const files = flipped ? ['h','g','f','e','d','c','b','a'] : ['a','b','c','d','e','f','g','h'];
    const cap = this.capturedPieces();
    const wLabel = this.chessIsMultiplayer ? (this.whiteName || 'White') : (this.jam.myName || 'You');
    const bLabel = this.chessIsMultiplayer ? (this.blackName || 'Anyone in Jam') : 'SoundCloud S Bot';
    const activeOpp = this.blackId === this.jam.myId ? this.whiteId : this.blackId;

    return `
      ${this.renderOpponentBar(esc, 'chess', this.vsBot, activeOpp)}

      <div class="chess-header">
        <div>
          <div class="chess-status">${esc(this.chessStatus)}</div>
          <div class="tiny muted">♔ ${esc(wLabel)} vs ♚ ${esc(bLabel)}</div>
        </div>
        <button id="chess-new" class="btn-primary" style="font-size:12px">New Game</button>
      </div>

      <div class="captured-strip">
        <span>Captured by White: <b>${cap.lostBlack.join('') || '—'}</b></span>
        <span>Captured by Black: <b>${cap.lostWhite.join('') || '—'}</b></span>
      </div>

      <div class="chess-board-frame">
        <div class="chess-board">
          ${order.map((sq, dispIdx) => {
            const r = Math.floor(sq / 8);
            const c = sq % 8;
            const isLight = (r + c) % 2 === 0;
            const p = this.board[sq];
            const isSel = this.selectedSq === sq;
            const isTarget = this.legalTargets.has(sq);
            const isLast = this.lastFrom === sq || this.lastTo === sq;
            const colorCls = p ? (SoundCloudSGames.pieceColor(p) === 'w' ? 'white-piece' : 'black-piece') : '';
            const showRank = dispIdx % 8 === 0;
            const showFile = dispIdx >= 56;
            const rankLbl = String(8 - r);
            const fileLbl = files[dispIdx % 8];
            return `
              <button class="chess-sq ${isLight ? 'light' : 'dark'} ${isSel ? 'selected' : ''} ${isLast ? 'last-move' : ''}" data-chess-sq="${sq}">
                ${showRank ? `<span class="sq-coord rank">${rankLbl}</span>` : ''}
                ${showFile ? `<span class="sq-coord file">${fileLbl}</span>` : ''}
                ${isTarget && !p ? '<span class="chess-dot"></span>' : ''}
                ${isTarget && p ? '<span class="chess-capture-ring"></span>' : ''}
                <span class="chess-piece ${colorCls}">${SoundCloudSGames.pieceGlyph(p)}</span>
              </button>
            `;
          }).join('')}
        </div>
      </div>
    `;
  }

  renderBlackjackHTML(esc) {
    const pTotal = SoundCloudSGames.handTotal(this.playerHand);
    const dDisplay = this.dealerRevealed
      ? SoundCloudSGames.handTotal(this.dealerHand)
      : (this.dealerHand[0] ? `${this.dealerHand[0].value} + ?` : '0');

    const renderCard = (c, hidden = false) => {
      if (hidden) return `<div class="bj-card back"><span>S</span></div>`;
      return `
        <div class="bj-card ${c.red ? 'red' : 'black'}">
          <div class="bj-corner tl">${esc(c.rank)}<br>${esc(c.suit)}</div>
          <div class="bj-center-suit">${esc(c.suit)}</div>
          <div class="bj-corner br">${esc(c.rank)}</div>
        </div>
      `;
    };

    return `
      <div class="bj-topbar">
        <div class="bj-bank">Bankroll: <b>$${this.chips}</b></div>
        <div class="bj-bet-chips">
          ${[25, 50, 100, 250].map((amt) =>
            `<button class="chip ${this.bet === amt ? 'active' : ''}" data-bj-bet="${amt}" ${this.roundActive ? 'disabled' : ''}>$${amt}</button>`
          ).join('')}
        </div>
      </div>

      <div class="bj-table">
        <div class="bj-zone">
          <div class="bj-zone-label">DEALER · <span>${esc(dDisplay)}</span></div>
          <div class="bj-cards">
            ${this.dealerHand.length
              ? this.dealerHand.map((c, i) => renderCard(c, !this.dealerRevealed && i === 1)).join('')
              : '<div class="tiny" style="opacity:0.65">Ready to deal</div>'}
          </div>
        </div>

        <div class="bj-banner">${esc(this.bjMessage)}</div>

        <div class="bj-zone">
          <div class="bj-zone-label">YOUR HAND · <span>${pTotal}</span></div>
          <div class="bj-cards">
            ${this.playerHand.length
              ? this.playerHand.map((c) => renderCard(c, false)).join('')
              : '<div class="tiny" style="opacity:0.65">Choose a chip bet and click Deal</div>'}
          </div>
        </div>

        <div class="bj-controls">
          ${this.roundActive ? `
            <button id="bj-hit" class="btn-primary" style="flex:1">Hit</button>
            <button id="bj-stand" class="btn-secondary" style="flex:1">Stand</button>
            <button id="bj-double" class="btn-secondary" style="flex:1" ${this.chips < this.bet ? 'disabled' : ''}>Double</button>
          ` : `
            <button id="bj-deal" class="btn-primary big" style="width:100%">Deal Hand ($${Math.min(this.bet, Math.max(1, this.chips))})</button>
          `}
        </div>
      </div>

      ${this.jam.blackjackFeed.length ? `
        <div class="card-box">
          <span class="field-label">Live Jam Table Feed</span>
          ${this.jam.blackjackFeed.map((f) => `<div class="tiny muted">${esc(f.time)} · ${esc(f.text)}</div>`).join('')}
        </div>
      ` : ''}
    `;
  }

  wireModalEvents(box, closeModal) {
    box.querySelector('#m-close')?.addEventListener('click', closeModal);
    box.querySelectorAll('[data-game-tab]').forEach((b) => {
      b.addEventListener('click', () => {
        this.activeTab = b.dataset.gameTab;
        this.onRenderNeeded();
      });
    });

    // Opponent picker pills (Connect Four & Chess)
    box.querySelectorAll('[data-opp-game]').forEach((b) => {
      b.addEventListener('click', () => {
        const gameKey = b.dataset.oppGame;
        const oppId = b.dataset.oppId;
        const oppName = b.dataset.oppName;
        const isBot = oppId === 'bot';
        if (gameKey === 'connect4') this.startConnect4Match(oppId, oppName, isBot);
        else if (gameKey === 'chess') this.startChessMatch(oppId, oppName, isBot);
      });
    });

    // Connect Four events
    box.querySelector('#c4-new')?.addEventListener('click', () => {
      this.startConnect4Match(this.c4GoldId || '*', this.c4GoldName || 'Anyone in Jam', this.c4VsBot);
    });
    box.querySelectorAll('[data-c4-col]').forEach((el) => {
      el.addEventListener('click', () => this.dropConnect4(Number(el.dataset.c4Col)));
    });

    // Chess events
    box.querySelector('#chess-new')?.addEventListener('click', () => {
      this.startChessMatch(this.blackId || '*', this.blackName || 'Anyone in Jam', this.vsBot);
    });
    box.querySelectorAll('[data-chess-sq]').forEach((el) => {
      el.addEventListener('click', () => this.clickSquare(Number(el.dataset.chessSq)));
    });

    // Blackjack events
    box.querySelectorAll('[data-bj-bet]').forEach((b) => {
      b.addEventListener('click', () => {
        if (this.roundActive) return;
        this.bet = Number(b.dataset.bjBet);
        this.onRenderNeeded();
      });
    });
    box.querySelector('#bj-deal')?.addEventListener('click', () => this.dealBlackjack());
    box.querySelector('#bj-hit')?.addEventListener('click', () => this.hitBlackjack());
    box.querySelector('#bj-stand')?.addEventListener('click', () => this.standBlackjack());
    box.querySelector('#bj-double')?.addEventListener('click', () => this.doubleBlackjack());
  }
}

window.SoundCloudSGames = SoundCloudSGames;
window.CloudWaveGames = SoundCloudSGames;
