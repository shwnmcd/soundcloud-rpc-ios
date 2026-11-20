/**
 * Hardware VFD (Vacuum Fluorescent Display) Retro Spectrum Analyzer Engine
 * Powered by REAL Web Audio API AnalyserNode FFT (with smooth organic fallback)
 * Modes: spectrum | mirror | dotWave | vuBars | vfdTimer
 */
class VFDVisualizerEngine {
  constructor(canvas, getAudioState, getSettings) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.getAudioState = getAudioState;
    this.getSettings = getSettings;

    this.audioCtx = null;
    this.analyser = null;
    this.freqData = null;
    this.sourceConnected = false;

    this.bandLevels = new Float32Array(32).fill(0.05);
    this.peakLevels = new Float32Array(32).fill(0.05);
    this.peakHold = new Int32Array(32);
    this.phase = 0;
    this.rafId = null;
    this.running = false;
  }

  attachAudioElement(audioEl) {
    if (this.sourceConnected || !audioEl) return;
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      this.audioCtx = new AC();
      const src = this.audioCtx.createMediaElementSource(audioEl);
      this.analyser = this.audioCtx.createAnalyser();
      this.analyser.fftSize = 256;
      this.analyser.smoothingTimeConstant = 0.72;
      src.connect(this.analyser);
      this.analyser.connect(this.audioCtx.destination);
      this.freqData = new Uint8Array(this.analyser.frequencyBinCount);
      this.sourceConnected = true;
    } catch {
      this.sourceConnected = false;
    }
  }

  resumeAudioContext() {
    if (this.audioCtx && this.audioCtx.state === 'suspended') {
      this.audioCtx.resume().catch(() => {});
    }
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.resumeAudioContext();
    const tick = () => {
      if (!this.running) return;
      this.stepPhysics();
      this.render();
      this.rafId = requestAnimationFrame(tick);
    };
    this.rafId = requestAnimationFrame(tick);
  }

  stop() {
    this.running = false;
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  getPhosphorRGB(themeName, bandIdx, totalBands, rowRatio) {
    switch (themeName) {
      case 'studioAmber':
        return rowRatio > 0.85 ? 'rgb(255, 232, 140)' : 'rgb(255, 174, 14)';
      case 'cyberCyan':
        return rowRatio > 0.85 ? 'rgb(184, 250, 255)' : 'rgb(10, 224, 255)';
      case 'scFlame':
        return rowRatio > 0.82 ? 'rgb(255, 214, 52)' : 'rgb(255, 85, 0)';
      case 'neonMagenta':
        return rowRatio > 0.85 ? 'rgb(255, 184, 235)' : 'rgb(255, 41, 148)';
      case 'rainbow': {
        const hue = Math.round((bandIdx / Math.max(1, totalBands)) * 360);
        return `hsl(${hue}, 94%, ${rowRatio > 0.85 ? 74 : 56}%)`;
      }
      case 'vfdMint':
      default:
        return rowRatio > 0.86 ? 'rgb(166, 255, 224)' : 'rgb(46, 245, 158)';
    }
  }

  getPrimarySwatch(themeName) {
    return this.getPhosphorRGB(themeName, 3, 12, 0.5);
  }

  stepPhysics() {
    const state = this.getAudioState();
    const settings = this.getSettings();
    const isPlaying = Boolean(state.isPlaying);
    const gain = Number(settings.vizSensitivity || 1.15);
    const cols = Math.min(32, Math.max(12, Number(settings.vizBands || 24)));

    let hasRealSignal = false;
    if (this.analyser && this.freqData && isPlaying) {
      this.analyser.getByteFrequencyData(this.freqData);
      let sum = 0;
      for (let i = 0; i < 48; i++) sum += this.freqData[i];
      hasRealSignal = sum > 25;
    }

    this.phase += isPlaying ? 0.024 : 0.004;
    const seed = ((Number(state.trackId || 42) % 97) * 0.17);
    const beat = isPlaying ? 0.55 + 0.45 * Math.pow(Math.max(0, Math.sin(this.phase * 6.4 + seed)), 2) : 0;

    for (let i = 0; i < 32; i++) {
      let target = 0.04;
      if (isPlaying && hasRealSignal) {
        // Map logarithmic-like frequency bins across bands
        const binIndex = Math.min(this.freqData.length - 1, Math.floor(Math.pow(i / Math.max(1, cols - 1), 1.35) * (this.freqData.length * 0.72)));
        const raw = this.freqData[binIndex] / 255.0;
        target = Math.min(1.0, Math.max(0.05, raw * gain * 1.12));
      } else if (isPlaying) {
        const norm = i / 31;
        const bass = Math.max(0, 1 - norm * 1.9) * beat * 0.65;
        const mid = Math.sin(this.phase * 4.7 + i * 0.55 + seed) * 0.25 + 0.28;
        const high = Math.abs(Math.sin(this.phase * 11.3 + i * 1.37 + seed * 2.1)) * (0.28 + norm * 0.35);
        target = Math.min(1.0, Math.max(0.06, (bass + mid + high * 0.65 + (Math.random() * 0.14 - 0.06)) * gain));
      }

      const cur = this.bandLevels[i];
      const smoothed = target > cur ? cur + (target - cur) * 0.50 : cur + (target - cur) * 0.15;
      this.bandLevels[i] = smoothed;

      if (smoothed >= this.peakLevels[i]) {
        this.peakLevels[i] = smoothed;
        this.peakHold[i] = 18;
      } else if (this.peakHold[i] > 0) {
        this.peakHold[i]--;
      } else {
        this.peakLevels[i] = Math.max(smoothed, this.peakLevels[i] - 0.022);
      }
    }
  }

  render() {
    const canvas = this.canvas;
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(100, Math.floor(rect.width));
    const h = Math.max(100, Math.floor(rect.height));

    if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
      canvas.width = w * dpr;
      canvas.height = h * dpr;
    }

    const ctx = this.ctx;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    // Deep VFD phosphor backing
    ctx.fillStyle = '#060807';
    ctx.fillRect(0, 0, w, h);

    // Subtle filament scanlines
    ctx.fillStyle = 'rgba(255,255,255,0.022)';
    for (let y = 0; y < h; y += 4) {
      ctx.fillRect(0, y, w, 1);
    }

    const settings = this.getSettings();
    const state = this.getAudioState();
    const mode = settings.vizMode || 'spectrum';
    const colorTheme = settings.vizColor || 'vfdMint';
    const cols = Math.min(32, Math.max(12, Number(settings.vizBands || 24)));
    const peakHoldOn = settings.vizPeakHold !== false;

    const padX = 18;
    const padY = 16;
    const drawW = w - padX * 2;
    const drawH = h - padY * 2;

    if (mode === 'vfdTimer') {
      this.renderTimerMode(ctx, padX, padY, drawW, drawH, state, colorTheme);
      return;
    }

    const rows = mode === 'vuBars' ? 16 : 18;
    const colGap = mode === 'vuBars' ? 7 : 4.5;
    const rowGap = 3.2;
    const cellW = Math.max(4, (drawW - (cols - 1) * colGap) / cols);
    const cellH = Math.max(3, (drawH - (rows - 1) * rowGap) / rows);

    for (let c = 0; c < cols; c++) {
      const x = padX + c * (cellW + colGap);
      const lvl = this.bandLevels[c];
      const pk = this.peakLevels[c];
      const activeCount = Math.round(lvl * rows);
      const peakRow = Math.min(rows - 1, Math.max(0, Math.round(pk * (rows - 1))));

      for (let r = 0; r < rows; r++) {
        const y = padY + drawH - (r + 1) * cellH - r * rowGap;
        const rowRatio = r / Math.max(1, rows - 1);
        const segColor = this.getPhosphorRGB(colorTheme, c, cols, rowRatio);

        let isLit = false;
        let isPeakDot = false;
        if (mode === 'spectrum' || mode === 'vuBars') {
          isLit = r < activeCount;
          isPeakDot = peakHoldOn && r === peakRow && pk > 0.08;
        } else if (mode === 'mirror') {
          const mid = (rows - 1) / 2;
          const dist = Math.abs(r - mid) / Math.max(1, mid);
          isLit = dist <= lvl;
          isPeakDot = peakHoldOn && Math.abs(dist - pk) < 1 / rows && pk > 0.1;
        } else if (mode === 'dotWave') {
          const crest = Math.min(rows - 1, Math.max(0, Math.round(lvl * (rows - 1))));
          isLit = r === crest || r === Math.max(0, crest - 1);
          isPeakDot = peakHoldOn && r === peakRow && pk > 0.08;
        }

        // Iconic red-amber baseline strip on bottom row (matches VFD photo!)
        if (r === 0 && (mode === 'spectrum' || mode === 'dotWave')) {
          ctx.fillStyle = isLit ? 'rgba(242, 61, 36, 0.94)' : 'rgba(242, 61, 36, 0.34)';
          ctx.fillRect(x, y, cellW, cellH);
          continue;
        }

        if (isLit || isPeakDot) {
          ctx.save();
          ctx.shadowColor = segColor;
          ctx.shadowBlur = isPeakDot ? 12 : 7;
          ctx.fillStyle = isPeakDot ? 'rgba(255,255,255,0.95)' : segColor;
          ctx.fillRect(x, y, cellW, cellH);
          ctx.restore();
        } else {
          ctx.fillStyle = 'rgba(255,255,255,0.055)';
          ctx.fillRect(x, y, cellW, cellH);
        }
      }
    }
  }

  renderTimerMode(ctx, padX, padY, drawW, drawH, state, colorTheme) {
    const primary = this.getPrimarySwatch(colorTheme);
    const fmt = (sec) => {
      const s = Math.max(0, Math.floor(sec || 0));
      const m = Math.floor(s / 60);
      const r = s % 60;
      return `${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
    };

    const elapsedStr = fmt(state.elapsedSec);
    const remStr = fmt(Math.max(0, (state.durationSec || 0) - (state.elapsedSec || 0)));

    ctx.save();
    ctx.font = '700 13px ui-monospace, Consolas, monospace';
    ctx.fillStyle = primary;
    ctx.fillText(state.isPlaying ? '● PLAY' : '❚❚ PAUSE', padX + 4, padY + 18);
    ctx.textAlign = 'right';
    ctx.fillText(`REM -${remStr}`, padX + drawW - 4, padY + 18);

    const fontSize = Math.min(120, Math.max(48, Math.floor(drawH * 0.48)));
    ctx.font = `900 ${fontSize}px ui-monospace, Consolas, monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = 'rgba(255,255,255,0.06)';
    ctx.fillText('88:88', padX + drawW / 2, padY + drawH * 0.46);

    ctx.shadowColor = primary;
    ctx.shadowBlur = 22;
    ctx.fillStyle = primary;
    ctx.fillText(elapsedStr, padX + drawW / 2, padY + drawH * 0.46);
    ctx.restore();

    // Mini bar equalizer strip along the bottom
    const barCount = 24;
    const gap = 4;
    const bw = (drawW - (barCount - 1) * gap) / barCount;
    const maxBh = drawH * 0.22;
    for (let i = 0; i < barCount; i++) {
      const bh = Math.max(4, this.bandLevels[i] * maxBh);
      ctx.fillStyle = this.getPhosphorRGB(colorTheme, i, barCount, this.bandLevels[i]);
      ctx.fillRect(padX + i * (bw + gap), padY + drawH - bh, bw, bh);
    }
  }
}

window.VFDVisualizerEngine = VFDVisualizerEngine;
