/* global registerProcessor, AudioWorkletProcessor, sampleRate, currentTime */
/*
 * The session's sound, generated sample by sample from session time.
 *
 * A line-for-line port of BreathSynth.kt (android-app) and BreathSynth.swift (macos-app),
 * so the web, Android and macOS apps sound the same. Nothing here is a recording: every
 * layer follows the same breath curve the picture uses.
 *
 *  - Pad: a low D drone (D2, D3, A3) under two upper notes from the D major pentatonic
 *    scale. The upper pair changes once per cycle with a slow crossfade and blooms as the
 *    lungs fill.
 *  - Air: soft filtered noise that moves only while air moves: rising and brightening on
 *    the inhale, falling and darkening on the exhale, silent during holds.
 *  - Bells: soft-mallet tones exactly on each phase change, one pitch per side of the box.
 *
 * Loaded with audioWorklet.addModule(). Outside a worklet (tests) it just defines
 * globalThis.BreathSynth.
 */

const SETTLE_SECONDS = 8;
const PHASE_SECONDS = 4;
const CYCLE_SECONDS = PHASE_SECONDS * 4;
const CLOSING_SECONDS = 8;

const CONTROL = 32;
const OUTPUT_GAIN = 1.3;

// Following the device clock.
const SNAP_SECONDS = 0.25;
const CATCH_UP_SECONDS = 2;
const MAX_NUDGE = 0.002;
const STALE_CUE = 0.12;
const START_FADE_FROM_ZERO = 0.03;
const START_FADE_MIDWAY = 0.8;
const FADE_OUT_SECONDS = 0.35;

// Pad. D2 D3 A3 hold the ground; E4 F#4 A4 B4 colour it.
const NOTES = [73.416, 146.832, 220.0, 329.628, 369.994, 440.0, 493.883];
const NOTE_COUNT = NOTES.length;
const PEDAL_COUNT = 3;
const BASE_GAIN = [0.12, 0.085, 0.06, 0.045, 0.045, 0.045, 0.045];
const DETUNE = [0.05, 0.08, 0.09, 0.1, 0.1, 0.1, 0.1];
const PEDAL_HARMONIC = [0.0, 0.22, 0.16];
const SIDE = 0.28;
const VOICINGS = [
  [4, 5], // F#4 A4
  [3, 6], // E4 B4
  [4, 6], // F#4 B4
  [3, 5], // E4 A4
];
const VOICING_FADE = 3.5;
const PAD_FADE_IN = 4.5;
const PAD_FADE_OUT = 6.5;

// Air.
const AIR_LEVEL = 0.5;
const AIR_INHALE = 1.0;
const AIR_EXHALE = 0.9;
const AIR_Q = 0.6;
const AIR_HIGHPASS = 90.0;

// Bells: four partials, the top one slightly stretched for a bell rather than an organ.
const BELL_LEVEL = 0.16;
const MAX_BELLS = 10;
const PARTIALS = 4;
const PARTIAL_RATIO = [1.0, 2.0, 3.0, 4.16];
const PARTIAL_AMP = [1.0, 0.22, 0.06, 0.035];
const PARTIAL_DECAY = [2.4, 1.2, 0.6, 0.35];
const BELL_ATTACK = 0.012;
const BELL_LIFE = 9.0;
const BELL_RELEASE = 1.0;

const WELCOME_AT = 0.3;
const CUE_WELCOME = 4;
const CUE_CLOSING = 5;

// Per cue: (frequency, amplitude, delay seconds) triples. Indexed by phase 0..3, then
// welcome and closing.
const CUE_NOTES = [
  [440.0, 1.0, 0.0], // inhale: A4
  [659.255, 0.32, 0.0], // hold full: E5, quiet
  [293.665, 0.9, 0.0], // exhale: D4
  [220.0, 0.38, 0.0], // hold empty: A3, quiet
  [293.665, 0.55, 0.0, 440.0, 0.35, 0.16], // welcome
  [146.832, 0.5, 0.0, 293.665, 0.8, 0.0, 440.0, 0.6, 0.2, 739.989, 0.4, 0.4], // closing
];

const TABLE_SIZE = 4096;
const SINE = new Float64Array(TABLE_SIZE + 1);
for (let i = 0; i <= TABLE_SIZE; i++) SINE[i] = Math.sin((2 * Math.PI * i) / TABLE_SIZE);

/** Sine of a phase in turns (0..1), from a table with linear interpolation. */
function sine(phase) {
  const x = phase * TABLE_SIZE;
  const i = x | 0;
  const a = SINE[i];
  return a + (SINE[i + 1] - a) * (x - i);
}

const wrap = (x) => (x >= 1 ? x - 1 : x);
const clamp = (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x);
const raised = (x) => 0.5 - 0.5 * Math.cos(Math.PI * clamp(x, 0, 1));

/** Lung level across an inhale, 0 → 1. An exhale is 1 - rise(p). */
function rise(p) {
  const q = Math.pow(clamp(p, 0, 1), 0.8);
  return 0.5 - 0.5 * Math.cos(Math.PI * q);
}

/** How much air is moving across an inhale or exhale: 0 at both ends. */
function flow(p) {
  const q = Math.pow(clamp(p, 0, 1), 0.8);
  return Math.sin(Math.PI * q);
}

/** Gentle limiter: untouched below 0.6, rounds off smoothly towards 1.0 above it. */
function soften(x) {
  const a = Math.abs(x);
  if (a <= 0.6) return x;
  const y = 0.6 + 0.4 * Math.tanh((a - 0.6) / 0.4);
  return x < 0 ? -y : y;
}

function xorshift(x) {
  x ^= x << 13;
  x ^= x >>> 17;
  x ^= x << 5;
  return x | 0;
}

const unit = (x) => (x >>> 8) / 16777216;

/** Pink-ish noise with the rumble taken out. */
class AirChannel {
  constructor(seed, rate) {
    this.state = seed === 0 ? 1 : seed | 0;
    this.b0 = 0;
    this.b1 = 0;
    this.b2 = 0;
    this.hpX = 0;
    this.hpY = 0;
    const rc = 1 / (2 * Math.PI * AIR_HIGHPASS);
    this.hpA = rc / (rc + 1 / rate);
  }

  next() {
    this.state = xorshift(this.state);
    const white = this.state / 2147483648;
    // Paul Kellet's economy pinking filter.
    this.b0 = 0.99765 * this.b0 + white * 0.099046;
    this.b1 = 0.963 * this.b1 + white * 0.2965164;
    this.b2 = 0.57 * this.b2 + white * 1.0526913;
    const pink = (this.b0 + this.b1 + this.b2 + white * 0.1848) * 0.11;
    this.hpY = this.hpA * (this.hpY + pink - this.hpX);
    this.hpX = pink;
    return this.hpY;
  }
}

/** Two-pole low-pass (topology-preserving state-variable filter), one state per ear. */
class Svf {
  constructor() {
    this.a1 = 0;
    this.a2 = 0;
    this.a3 = 0;
    this.l1 = 0;
    this.l2 = 0;
    this.r1 = 0;
    this.r2 = 0;
  }

  tune(cutoff, q, rate) {
    const g = Math.tan((Math.PI * clamp(cutoff, 20, rate * 0.45)) / rate);
    const k = 1 / q;
    this.a1 = 1 / (1 + g * (g + k));
    this.a2 = g * this.a1;
    this.a3 = g * this.a2;
  }

  left(x) {
    const v3 = x - this.l2;
    const v1 = this.a1 * this.l1 + this.a2 * v3;
    const v2 = this.l2 + this.a2 * this.l1 + this.a3 * v3;
    this.l1 = 2 * v1 - this.l1;
    this.l2 = 2 * v2 - this.l2;
    return v2;
  }

  right(x) {
    const v3 = x - this.r2;
    const v1 = this.a1 * this.r1 + this.a2 * v3;
    const v2 = this.r2 + this.a2 * this.r1 + this.a3 * v3;
    this.r1 = 2 * v1 - this.r1;
    this.r2 = 2 * v2 - this.r2;
    return v2;
  }
}

class BreathSynth {
  /**
   * @param {number} rate sample rate
   * @param {number} cycles number of box cycles in the session
   */
  constructor(rate, cycles, seed = 0x5eed) {
    this.rate = rate;
    this.cycles = cycles;
    this.phaseCount = cycles * 4;
    this.breathingSeconds = cycles * CYCLE_SECONDS;
    this.endTime = SETTLE_SECONDS + this.breathingSeconds;
    this.dt = 1 / rate;

    /** 'ambient' | 'bells' | 'silent' */
    this.mode = 'ambient';
    /** 0..1, as on a slider. */
    this.volume = 1;
    this.finished = false;
    this.fadeOutRequested = false;
    /** For tests: hear one layer only (0 pad, 1 air, 2 bells). */
    this.solo = -1;
    /** Called as each cue's bells start: (kind, scheduled, actual). */
    this.onCue = null;

    this.clock = 0;
    this.speed = 1;
    this.anchored = false;
    this.startFadeSeconds = START_FADE_FROM_ZERO;

    this.controlLeft = 0;
    this.noteGain = new Float64Array(NOTE_COUNT);
    this.noteGainStep = new Float64Array(NOTE_COUNT);
    this.harm = new Float64Array(NOTE_COUNT);
    this.harmStep = new Float64Array(NOTE_COUNT);
    this.upperWeight = new Float64Array(NOTE_COUNT);
    this.airGain = 0;
    this.airGainStep = 0;
    this.bellGain = 0;
    this.bellGainStep = 0;
    this.master = 0;
    this.masterStep = 0;
    this.padMix = 0;
    this.airMix = 0;
    this.bellMix = 0;
    this.volMix = -1;
    this.fadeOutGain = 1;
    this.startGain = 0;
    this.airCutoff = 400;
    this.mixCoef = 1 - Math.exp((-CONTROL * this.dt) / 0.25);
    this.volCoef = 1 - Math.exp((-CONTROL * this.dt) / 0.06);

    this.phC = new Float64Array(NOTE_COUNT);
    this.phL = new Float64Array(NOTE_COUNT);
    this.phR = new Float64Array(NOTE_COUNT);
    this.incC = new Float64Array(NOTE_COUNT);
    this.incL = new Float64Array(NOTE_COUNT);
    this.incR = new Float64Array(NOTE_COUNT);
    for (let k = 0; k < NOTE_COUNT; k++) {
      this.incC[k] = NOTES[k] * this.dt;
      this.incL[k] = (NOTES[k] - DETUNE[k]) * this.dt;
      this.incR[k] = (NOTES[k] + DETUNE[k]) * this.dt;
    }

    this.airLeft = new AirChannel(seed ^ 0x1234567, rate);
    this.airRight = new AirChannel(seed ^ 0x7654321, rate);
    this.svf = new Svf();

    this.bellActive = new Uint8Array(MAX_BELLS);
    this.bellDelay = new Int32Array(MAX_BELLS);
    this.bellAge = new Int32Array(MAX_BELLS);
    this.bellAmp = new Float64Array(MAX_BELLS);
    this.bellPhase = new Float64Array(MAX_BELLS * PARTIALS);
    this.bellInc = new Float64Array(MAX_BELLS * PARTIALS);
    this.bellEnv = new Float64Array(MAX_BELLS * PARTIALS);
    this.partialMult = new Float64Array(PARTIALS);
    for (let p = 0; p < PARTIALS; p++) this.partialMult[p] = Math.exp(-1 / (PARTIAL_DECAY[p] * rate));
    this.attackSamples = Math.trunc(BELL_ATTACK * rate);
    this.lifeSamples = Math.trunc(BELL_LIFE * rate);
    this.releaseSamples = Math.trunc(BELL_RELEASE * rate);

    const count = this.phaseCount + 2;
    this.cueTimes = new Float64Array(count);
    this.cueKinds = new Int32Array(count);
    this.cueTimes[0] = WELCOME_AT;
    this.cueKinds[0] = CUE_WELCOME;
    for (let i = 0; i < this.phaseCount; i++) {
      this.cueTimes[i + 1] = SETTLE_SECONDS + i * PHASE_SECONDS;
      this.cueKinds[i + 1] = i % 4;
    }
    this.cueTimes[count - 1] = this.endTime;
    this.cueKinds[count - 1] = CUE_CLOSING;
    this.nextCue = 0;
    this.nextCueTime = this.cueTimes[0];

    // Start the oscillators at scattered phases so the first notes don't all line up.
    let s = seed | 1;
    for (let k = 0; k < NOTE_COUNT; k++) {
      s = xorshift(s);
      this.phC[k] = unit(s);
      s = xorshift(s);
      this.phL[k] = unit(s);
      s = xorshift(s);
      this.phR[k] = unit(s);
    }
  }

  /** Fade to silence over a third of a second; `finished` turns true when done. */
  fadeOut() {
    this.fadeOutRequested = true;
  }

  /**
   * Fills `frames` samples of each channel. `startTime` is the session time at which the
   * first of them will be heard.
   */
  render(left, right, frames, startTime) {
    this.follow(startTime);
    let i = 0;
    while (i < frames) {
      if (this.controlLeft === 0) this.control();
      const n = Math.min(this.controlLeft, frames - i);
      this.renderSamples(left, right, i, n);
      i += n;
      this.controlLeft -= n;
    }
  }

  follow(target) {
    if (!this.anchored) {
      this.anchored = true;
      this.clock = target;
      // Joining mid-session fades in gently rather than starting the pad at full level.
      this.startFadeSeconds = target > 1 ? START_FADE_MIDWAY : START_FADE_FROM_ZERO;
      this.skipCuesBefore(target - STALE_CUE);
      return;
    }
    const drift = target - this.clock;
    if (Math.abs(drift) > SNAP_SECONDS) {
      this.clock = target;
      this.speed = 1;
      this.skipCuesBefore(target - STALE_CUE);
    } else {
      this.speed = 1 + clamp(drift / CATCH_UP_SECONDS, -MAX_NUDGE, MAX_NUDGE);
    }
  }

  skipCuesBefore(t) {
    while (this.nextCue < this.cueTimes.length && this.cueTimes[this.nextCue] < t) this.nextCue++;
    this.nextCueTime = this.nextCue < this.cueTimes.length ? this.cueTimes[this.nextCue] : Infinity;
  }

  control() {
    this.controlLeft = CONTROL;
    const step = CONTROL * this.dt * this.speed;
    const t = this.clock + step; // targets are for the end of this block

    // Where the breath is.
    const tb = t - SETTLE_SECONDS;
    let level = 0;
    let air = 0;
    let cycle = -1;
    if (tb >= 0 && tb < this.breathingSeconds) {
      const index = Math.min(this.phaseCount - 1, Math.floor(tb / PHASE_SECONDS));
      const p = clamp((tb - index * PHASE_SECONDS) / PHASE_SECONDS, 0, 1);
      cycle = Math.trunc(index / 4);
      switch (index % 4) {
        case 0:
          level = rise(p);
          air = flow(p) * AIR_INHALE;
          this.airCutoff = 300 + 1100 * rise(p);
          break;
        case 1:
          level = 1;
          break;
        case 2:
          level = 1 - rise(p);
          air = flow(p) * AIR_EXHALE;
          this.airCutoff = 1150 - 850 * rise(p);
          break;
        default:
          level = 0;
      }
    } else if (tb >= this.breathingSeconds) {
      cycle = this.cycles;
    }

    // Which layers the listener wants.
    const m = this.mode;
    const solo = this.solo;
    const wantPad = solo >= 0 ? solo === 0 : m === 'ambient';
    const wantAir = solo >= 0 ? solo === 1 : m === 'ambient';
    const wantBells = solo >= 0 ? solo === 2 : m !== 'silent';
    this.padMix += ((wantPad ? 1 : 0) - this.padMix) * this.mixCoef;
    this.airMix += ((wantAir ? 1 : 0) - this.airMix) * this.mixCoef;
    this.bellMix += ((wantBells ? 1 : 0) - this.bellMix) * this.mixCoef;
    const v = clamp(this.volume, 0, 1);
    const volTarget = v * v;
    this.volMix = this.volMix < 0 ? volTarget : this.volMix + (volTarget - this.volMix) * this.volCoef;

    // Pad: overall envelope, then which upper voicing is sounding.
    const padEnv = this.padEnvelope(t);
    let voicingStart;
    if (cycle < 0) voicingStart = 0;
    else if (cycle >= this.cycles) voicingStart = this.endTime;
    else voicingStart = SETTLE_SECONDS + cycle * 4 * PHASE_SECONDS;
    const cur = this.voicingFor(cycle);
    const prev = this.voicingFor(cycle - 1);
    const x = clamp((t - voicingStart) / VOICING_FADE, 0, 1);
    const w = this.upperWeight;
    w.fill(0);
    if (cur === prev) {
      for (const k of VOICINGS[cur]) w[k] += 1;
    } else {
      const wCur = Math.sin(0.5 * Math.PI * x);
      const wPrev = Math.cos(0.5 * Math.PI * x);
      for (const k of VOICINGS[cur]) w[k] += wCur;
      for (const k of VOICINGS[prev]) w[k] += wPrev;
    }
    const pedalBloom = 0.86 + 0.14 * level;
    const upperBloom = 0.38 + 0.62 * level;
    const padScale = padEnv * this.padMix;
    for (let k = 0; k < NOTE_COUNT; k++) {
      let target;
      let harmTarget;
      if (k < PEDAL_COUNT) {
        target = padScale * BASE_GAIN[k] * pedalBloom;
        harmTarget = PEDAL_HARMONIC[k] * (0.6 + 0.4 * level);
      } else {
        target = padScale * BASE_GAIN[k] * upperBloom * w[k];
        harmTarget = 0.05 + 0.15 * level;
      }
      this.noteGainStep[k] = (target - this.noteGain[k]) / CONTROL;
      this.harmStep[k] = (harmTarget - this.harm[k]) / CONTROL;
    }

    // Air and bells.
    this.airGainStep = (air * AIR_LEVEL * this.airMix - this.airGain) / CONTROL;
    this.svf.tune(this.airCutoff, AIR_Q, this.rate);
    this.bellGainStep = (this.bellMix * BELL_LEVEL - this.bellGain) / CONTROL;

    // Master: volume, the start fade and any requested fade-out.
    this.startGain = Math.min(1, this.startGain + (CONTROL * this.dt) / this.startFadeSeconds);
    if (this.fadeOutRequested) {
      this.fadeOutGain = Math.max(0, this.fadeOutGain - (CONTROL * this.dt) / FADE_OUT_SECONDS);
    }
    this.masterStep = (this.volMix * this.startGain * this.fadeOutGain - this.master) / CONTROL;

    if (
      (this.fadeOutRequested && this.fadeOutGain === 0 && this.master < 1e-6) ||
      t > this.endTime + CLOSING_SECONDS
    ) {
      this.finished = true;
    }
  }

  padEnvelope(t) {
    const outStart = this.endTime + 1;
    if (t <= 0) return 0;
    if (t < PAD_FADE_IN) return raised(t / PAD_FADE_IN);
    if (t < outStart) return 1;
    if (t < outStart + PAD_FADE_OUT) return 1 - raised((t - outStart) / PAD_FADE_OUT);
    return 0;
  }

  voicingFor(cycle) {
    return cycle < 0 || cycle >= this.cycles ? 0 : cycle % VOICINGS.length;
  }

  renderSamples(left, right, offset, count) {
    const tick = this.dt * this.speed;
    const { phC, phL, phR, incC, incL, incR, noteGain, noteGainStep, harm, harmStep } = this;
    const { bellActive, bellDelay, bellAge, bellAmp, bellPhase, bellInc, bellEnv, partialMult } = this;
    for (let i = 0; i < count; i++) {
      while (this.clock >= this.nextCueTime) {
        if (this.clock - this.nextCueTime <= STALE_CUE) {
          this.startCue(this.cueKinds[this.nextCue]);
          if (this.onCue) this.onCue(this.cueKinds[this.nextCue], this.nextCueTime, this.clock);
        }
        this.nextCue++;
        this.nextCueTime = this.nextCue < this.cueTimes.length ? this.cueTimes[this.nextCue] : Infinity;
      }

      // Pad.
      let padL = 0;
      let padR = 0;
      for (let k = 0; k < NOTE_COUNT; k++) {
        const c = phC[k];
        let c2 = c + c;
        if (c2 >= 1) c2 -= 1;
        const body = sine(c) + harm[k] * sine(c2);
        const g = noteGain[k];
        padL += g * (body + SIDE * sine(phL[k]));
        padR += g * (body + SIDE * sine(phR[k]));
        phC[k] = wrap(c + incC[k]);
        phL[k] = wrap(phL[k] + incL[k]);
        phR[k] = wrap(phR[k] + incR[k]);
        noteGain[k] += noteGainStep[k];
        harm[k] += harmStep[k];
      }

      // Air.
      const airL = this.svf.left(this.airLeft.next()) * this.airGain;
      const airR = this.svf.right(this.airRight.next()) * this.airGain;
      this.airGain += this.airGainStep;

      // Bells.
      let bell = 0;
      for (let b = 0; b < MAX_BELLS; b++) {
        if (!bellActive[b]) continue;
        if (bellDelay[b] > 0) {
          bellDelay[b]--;
          continue;
        }
        let s = 0;
        const base = b * PARTIALS;
        for (let p = 0; p < PARTIALS; p++) {
          const j = base + p;
          s += sine(bellPhase[j]) * bellEnv[j];
          bellPhase[j] = wrap(bellPhase[j] + bellInc[j]);
          bellEnv[j] *= partialMult[p];
        }
        const age = bellAge[b];
        let shape;
        if (age < this.attackSamples) shape = 0.5 - 0.5 * Math.cos((Math.PI * age) / this.attackSamples);
        else if (age > this.lifeSamples - this.releaseSamples) shape = (this.lifeSamples - age) / this.releaseSamples;
        else shape = 1;
        bell += s * bellAmp[b] * shape;
        bellAge[b] = age + 1;
        if (age + 1 >= this.lifeSamples) bellActive[b] = 0;
      }
      bell *= this.bellGain;
      this.bellGain += this.bellGainStep;

      const m = this.master;
      this.master += this.masterStep;
      const j = offset + i;
      if (this.finished) {
        left[j] = 0;
        right[j] = 0;
      } else {
        left[j] = soften((padL + airL + bell) * m * OUTPUT_GAIN);
        right[j] = soften((padR + airR + bell) * m * OUTPUT_GAIN);
      }
      this.clock += tick;
    }
  }

  startCue(kind) {
    const notes = CUE_NOTES[kind];
    for (let n = 0; n < notes.length; n += 3) this.startBell(notes[n], notes[n + 1], notes[n + 2]);
  }

  startBell(freq, amp, delaySeconds) {
    // A free voice, or else the oldest one (by then it is a faint tail).
    let slot = -1;
    let oldest = -1;
    for (let b = 0; b < MAX_BELLS; b++) {
      if (!this.bellActive[b]) {
        slot = b;
        break;
      }
      if (oldest < 0 || this.bellAge[b] > this.bellAge[oldest]) oldest = b;
    }
    if (slot < 0) slot = oldest;
    this.bellActive[slot] = 1;
    this.bellDelay[slot] = Math.trunc(delaySeconds * this.rate);
    this.bellAge[slot] = 0;
    this.bellAmp[slot] = amp;
    const base = slot * PARTIALS;
    for (let p = 0; p < PARTIALS; p++) {
      this.bellPhase[base + p] = 0;
      this.bellInc[base + p] = freq * PARTIAL_RATIO[p] * this.dt;
      this.bellEnv[base + p] = PARTIAL_AMP[p];
    }
  }
}

if (typeof registerProcessor === 'function') {
  /**
   * processorOptions: { cycles, startTime, mode }. startTime is the AudioContext time at
   * which session time is zero. A sample rendered at context time T is heard when the
   * output reaches context time T, so the session time of each block is simply
   * currentTime - startTime; the page works out what is audible now from
   * getOutputTimestamp(), on the same axis.
   *
   * Messages in: { type: 'mode', mode }, { type: 'fadeOut' }. Message out: { type: 'finished' }.
   */
  class BreathSynthProcessor extends AudioWorkletProcessor {
    constructor(options) {
      super();
      const { cycles, startTime, mode } = options.processorOptions;
      this.synth = new BreathSynth(sampleRate, cycles);
      this.synth.mode = mode || 'ambient';
      this.startTime = startTime;
      this.spare = new Float32Array(128);
      this.reported = false;
      this.port.onmessage = (event) => {
        const message = event.data || {};
        if (message.type === 'mode') this.synth.mode = message.mode;
        else if (message.type === 'fadeOut') this.synth.fadeOut();
      };
    }

    process(inputs, outputs) {
      const channels = outputs[0];
      if (!channels || channels.length === 0) return true;
      const left = channels[0];
      let right = channels.length > 1 ? channels[1] : this.spare;
      if (right.length < left.length) right = this.spare = new Float32Array(left.length);
      this.synth.render(left, right, left.length, currentTime - this.startTime);
      if (this.synth.finished && !this.reported) {
        this.reported = true;
        this.port.postMessage({ type: 'finished' });
      }
      return !this.synth.finished;
    }
  }

  registerProcessor('breath-synth', BreathSynthProcessor);
} else {
  globalThis.BreathSynth = BreathSynth;
}
