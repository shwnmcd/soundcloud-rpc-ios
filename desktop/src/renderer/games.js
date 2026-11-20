/**
 * CloudWave Mini-Games Engine — Full Legal Chess & 21 Blackjack
 * Play Solo vs Bot/Dealer OR Live Cross-Platform Multiplayer inside a Jam (Windows ↔ iOS)!
 */
class CloudWaveGames {
  constructor(jam, onRenderNeeded, onToast) {
    this.jam = jam;
    this.onRenderNeeded = onRenderNeeded;
    this.onToast = onToast;

    this.activeTab = 'chess'; // 'chess' | 'blackjack'

    // Chess State (100% wire-compatible with iOS ChessWireState!)
    this.board = CloudWaveGames.initialBoard();
    this.turn = 'w'; // 'w' | 'b'
    this.selectedSq = null;
    this.legalTargets = new Set();
    this.lastFrom = null;
    this.lastTo = null;
    this.vsBot = false;
    this.chessStatus = 'White to move';

    // 21 / Blackjack State
    this.chips = 1000;
    this.bet = 50;
    this.deck = [];
    this.playerHand = [];
    this.dealerHand = [];
    this.roundActive = false;
    this.dealerRevealed = false;
    this.bjMessage = 'Place your bet and deal a hand!';
  }

  // MARK: - Chess Helpers
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

  get myChessColor() {
    if (!this.jam.isActive || this.vsBot) return 'w';
    return this.jam.isHost ? 'w' : 'b';
  }

  resetChess(broadcast = true) {
    this.board = CloudWaveGames.initialBoard();
    this.turn = 'w';
    this.selectedSq = null;
    this.legalTargets = new Set();
    this.lastFrom = null;
    this.lastTo = null;
    this.chessStatus = 'White to move';
    if (broadcast && this.jam.isActive && !this.vsBot) {
      this.broadcastChess();
    }
    this.onRenderNeeded();
  }

  broadcastChess() {
    if (!this.jam.isActive || this.vsBot) return;
    const wire = {
      board: this.board,
      turn: this.turn,
      lastFrom: this.lastFrom,
      lastTo: this.lastTo
    };
    this.jam.sendChessState(JSON.stringify(wire));
  }

  applyRemoteChess(jsonString, senderName) {
    if (this.vsBot) return;
    try {
      const wire = JSON.parse(jsonString);
      if (!Array.isArray(wire.board) || wire.board.length !== 64) return;
      this.board = wire.board;
      this.turn = wire.turn === 'b' ? 'b' : 'w';
      this.lastFrom = typeof wire.lastFrom === 'number' ? wire.lastFrom : null;
      this.lastTo = typeof wire.lastTo === 'number' ? wire.lastTo : null;
      this.selectedSq = null;
      this.legalTargets = new Set();
      this.updateChessStatus();
      if (senderName) this.onToast(`♟ ${senderName} made a Chess move`);
      this.onRenderNeeded();
    } catch {}
  }

  clickSquare(sq) {
    const canMove = !this.jam.isActive || this.vsBot || this.turn === this.myChessColor;
    if (!canMove) {
      this.onToast(`Waiting for ${this.turn === 'w' ? 'White (Host)' : 'Black (Guest)'}`);
      return;
    }

    if (this.selectedSq !== null && this.legalTargets.has(sq)) {
      this.executeChessMove(this.selectedSq, sq);
      return;
    }

    const piece = this.board[sq];
    if (piece && CloudWaveGames.pieceColor(piece) === this.turn) {
      this.selectedSq = sq;
      this.legalTargets = new Set(CloudWaveGames.legalMovesFor(sq, this.board));
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

    if ((!this.jam.isActive || this.vsBot) && this.turn === 'b' && !this.chessStatus.includes('Checkmate') && !this.chessStatus.includes('Stalemate')) {
      setTimeout(() => this.runBotMove(), 380);
    }
  }

  runBotMove() {
    if (this.turn !== 'b') return;
    const moves = [];
    for (let sq = 0; sq < 64; sq++) {
      if (CloudWaveGames.pieceColor(this.board[sq]) === 'b') {
        for (const to of CloudWaveGames.legalMovesFor(sq, this.board)) {
          const cap = this.board[to];
          const centerBonus = (to >= 27 && to <= 28) || (to >= 35 && to <= 36) ? 1.5 : 0;
          const score = (cap ? CloudWaveGames.pieceVal(cap) * 10 : 0) + centerBonus + Math.random();
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
    const hasAny = CloudWaveGames.hasAnyLegalMove(this.turn, this.board);
    const inCheck = CloudWaveGames.isKingInCheck(this.turn, this.board);
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
      if (CloudWaveGames.pieceColor(board[sq]) === color && CloudWaveGames.legalMovesFor(sq, board).length > 0) {
        return true;
      }
    }
    return false;
  }

  static legalMovesFor(sq, board) {
    const p = board[sq];
    const color = CloudWaveGames.pieceColor(p);
    if (!color) return [];
    return CloudWaveGames.pseudoMoves(sq, board).filter((to) => {
      const copy = [...board];
      copy[to] = copy[sq];
      copy[sq] = '';
      return !CloudWaveGames.isKingInCheck(color, copy);
    });
  }

  static isKingInCheck(color, board) {
    const king = color === 'w' ? 'K' : 'k';
    const kingSq = board.indexOf(king);
    if (kingSq < 0) return false;
    const opp = color === 'w' ? 'b' : 'w';
    for (let sq = 0; sq < 64; sq++) {
      if (CloudWaveGames.pieceColor(board[sq]) === opp) {
        if (CloudWaveGames.pseudoMoves(sq, board).includes(kingSq)) return true;
      }
    }
    return false;
  }

  static pseudoMoves(sq, board) {
    const p = board[sq];
    if (!p) return [];
    const color = CloudWaveGames.pieceColor(p);
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
          if (board[t] && CloudWaveGames.pieceColor(board[t]) !== color) out.push(t);
        }
      }
      return out;
    }

    if (upper === 'N') {
      const jumps = [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]];
      for (const [dr, dc] of jumps) {
        if (inside(r + dr, c + dc)) {
          const t = (r + dr) * 8 + (c + dc);
          if (CloudWaveGames.pieceColor(board[t]) !== color) out.push(t);
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
            if (CloudWaveGames.pieceColor(board[t]) !== color) out.push(t);
          }
        }
      }
      return out;
    }

    const dirs = [];
    if (upper === 'B' || upper === 'Q') dirs.push([-1,-1],[-1,1],[1,-1],[1,1]);
    if (upper === 'R' || upper === 'Q') dirs.push([-1,0],[1,0],[0,-1],[0,1]);
    for (const [dr, dc] of dirs) {
      let nr = r + dr;
      let nc = c + dc;
      while (inside(nr, nc)) {
        const t = nr * 8 + nc;
        const targetColor = CloudWaveGames.pieceColor(board[t]);
        if (!targetColor) {
          out.push(t);
        } else {
          if (targetColor !== color) out.push(t);
          break;
        }
        nr += dr;
        nc += dc;
      }
    }
    return out;
  }

  // MARK: - 21 / Blackjack Engine
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
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
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

    const pTotal = CloudWaveGames.handTotal(this.playerHand);
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
    const pTotal = CloudWaveGames.handTotal(this.playerHand);
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
    const pTotal = CloudWaveGames.handTotal(this.playerHand);
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
    while (CloudWaveGames.handTotal(this.dealerHand) < 17) {
      this.dealerHand.push(this.drawCard());
    }
    const d = CloudWaveGames.handTotal(this.dealerHand);
    const p = CloudWaveGames.handTotal(this.playerHand);
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

  // MARK: - Modal HTML Renderer
  renderModalHTML(esc) {
    const isJam = this.jam.isActive;
    return `
      <div class="modal-header">
        <div class="modal-title">🎮 ${isJam ? `Jam Arcade · ${esc(this.jam.roomCode)}` : 'CloudWave Mini-Games'}</div>
        <button id="m-close" class="btn-secondary">Done</button>
      </div>

      <div class="game-tabs">
        <button class="game-tab ${this.activeTab === 'chess' ? 'active' : ''}" data-game-tab="chess">♟ Chess</button>
        <button class="game-tab ${this.activeTab === 'blackjack' ? 'active' : ''}" data-game-tab="blackjack">🃏 21 / Blackjack</button>
      </div>

      ${this.activeTab === 'chess' ? this.renderChessHTML(esc) : this.renderBlackjackHTML(esc)}
    `;
  }

  renderChessHTML(esc) {
    const isJam = this.jam.isActive;
    const flipped = isJam && !this.vsBot && this.myChessColor === 'b';
    const order = [];
    for (let r = 0; r < 8; r++) {
      for (let c = 0; c < 8; c++) {
        const rr = flipped ? 7 - r : r;
        const cc = flipped ? 7 - c : c;
        order.push(rr * 8 + cc);
      }
    }

    return `
      <div class="chess-header">
        <div>
          <div class="chess-status">${esc(this.chessStatus)}</div>
          <div class="tiny muted">${
            isJam && !this.vsBot
              ? `Live Jam Match (Windows ↔ iOS) · You are ${this.myChessColor === 'w' ? 'White (Host)' : 'Black (Guest)'}`
              : 'Solo vs CloudWave Bot · You are White'
          }</div>
        </div>
        <div class="row-gap">
          ${isJam ? `<button id="chess-toggle-bot" class="btn-secondary" style="font-size:12px">${this.vsBot ? '👥 Play Jam Friend' : '🤖 Play Bot'}</button>` : ''}
          <button id="chess-new" class="btn-primary" style="font-size:12px">New Game</button>
        </div>
      </div>

      <div class="chess-board">
        ${order.map((sq) => {
          const r = Math.floor(sq / 8);
          const c = sq % 8;
          const isLight = (r + c) % 2 === 0;
          const p = this.board[sq];
          const isSel = this.selectedSq === sq;
          const isTarget = this.legalTargets.has(sq);
          const isLast = this.lastFrom === sq || this.lastTo === sq;
          const colorCls = p ? (CloudWaveGames.pieceColor(p) === 'w' ? 'white-piece' : 'black-piece') : '';
          return `
            <button class="chess-sq ${isLight ? 'light' : 'dark'} ${isSel ? 'selected' : ''} ${isLast ? 'last-move' : ''}" data-chess-sq="${sq}">
              ${isTarget && !p ? '<span class="chess-dot"></span>' : ''}
              ${isTarget && p ? '<span class="chess-capture-ring"></span>' : ''}
              <span class="chess-piece ${colorCls}">${CloudWaveGames.pieceGlyph(p)}</span>
            </button>
          `;
        }).join('')}
      </div>
    `;
  }

  renderBlackjackHTML(esc) {
    const pTotal = CloudWaveGames.handTotal(this.playerHand);
    const dDisplay = this.dealerRevealed
      ? CloudWaveGames.handTotal(this.dealerHand)
      : (this.dealerHand[0] ? `${this.dealerHand[0].value} + ?` : '0');

    const renderCard = (c, hidden = false) => {
      if (hidden) return `<div class="bj-card back"><span>CW</span></div>`;
      return `
        <div class="bj-card ${c.red ? 'red' : 'black'}">
          <div class="bj-rank">${esc(c.rank)}</div>
          <div class="bj-suit">${esc(c.suit)}</div>
        </div>
      `;
    };

    return `
      <div class="bj-topbar">
        <div class="bj-bank">Chips: <b>$${this.chips}</b></div>
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
              : '<div class="tiny" style="opacity:0.6">Waiting for deal...</div>'}
          </div>
        </div>

        <div class="bj-banner">${esc(this.bjMessage)}</div>

        <div class="bj-zone">
          <div class="bj-zone-label">YOUR HAND · <span>${pTotal}</span></div>
          <div class="bj-cards">
            ${this.playerHand.length
              ? this.playerHand.map((c) => renderCard(c, false)).join('')
              : '<div class="tiny" style="opacity:0.6">Click Deal to start</div>'}
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

    // Chess events
    box.querySelector('#chess-new')?.addEventListener('click', () => this.resetChess(true));
    box.querySelector('#chess-toggle-bot')?.addEventListener('click', () => {
      this.vsBot = !this.vsBot;
      this.resetChess(false);
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

window.CloudWaveGames = CloudWaveGames;
