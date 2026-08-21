/**
 * Pure breathing-cadence math — deliberately free of any React or React Native
 * import so it can be exercised directly in a plain JS runtime.
 *
 * The entire session cadence lives here: phase, countdown and remaining time
 * are functions of elapsed time alone, never of accumulated ticks.
 */

export type BreathingPhase =
  | 'idle'
  | 'pre-start'
  | 'in'
  | 'hold-in'
  | 'out'
  | 'hold-out'
  | 'completed';

export const PRE_START_SECONDS = 8;
export const PHASE_SECONDS = 4;
export const CYCLE_SECONDS = PHASE_SECONDS * 4; // in, hold-in, out, hold-out

export const PHASE_ORDER: BreathingPhase[] = ['in', 'hold-in', 'out', 'hold-out'];

export interface SessionSnapshot {
  phase: BreathingPhase;
  countdown: number;
  currentCycle: number; // 1-based while breathing, 0 otherwise
  remainingSeconds: number; // breathing time left (excludes pre-start)
}

export const IDLE_SNAPSHOT: SessionSnapshot = {
  phase: 'idle',
  countdown: 0,
  currentCycle: 0,
  remainingSeconds: 0,
};

/** Session state at `t` seconds after the user pressed start. */
export function computeSnapshot(t: number, cycles: number): SessionSnapshot {
  const breathingTotal = cycles * CYCLE_SECONDS;
  if (t < PRE_START_SECONDS) {
    return {
      phase: 'pre-start',
      countdown: Math.min(PRE_START_SECONDS, Math.max(1, Math.ceil(PRE_START_SECONDS - t))),
      currentCycle: 0,
      remainingSeconds: breathingTotal,
    };
  }
  const tb = t - PRE_START_SECONDS; // time spent breathing
  if (tb >= breathingTotal) {
    return { phase: 'completed', countdown: 0, currentCycle: 0, remainingSeconds: 0 };
  }
  const cycleIndex = Math.floor(tb / CYCLE_SECONDS);
  const inCycle = tb - cycleIndex * CYCLE_SECONDS;
  const phaseIndex = Math.min(3, Math.floor(inCycle / PHASE_SECONDS));
  const inPhase = inCycle - phaseIndex * PHASE_SECONDS;
  return {
    phase: PHASE_ORDER[phaseIndex],
    countdown: Math.min(PHASE_SECONDS, Math.max(1, Math.ceil(PHASE_SECONDS - inPhase))),
    currentCycle: cycleIndex + 1,
    remainingSeconds: Math.ceil(breathingTotal - tb),
  };
}

/**
 * Where the audio playhead should sit, in the clip's own timeline, given the
 * seconds spent breathing. `rate` stretches the clip so one pass equals one
 * breathing cycle.
 */
export function expectedClipPosition(tb: number, rate: number, clipDuration: number): number {
  if (!(clipDuration > 0)) return 0;
  return ((tb % CYCLE_SECONDS) * rate) % clipDuration;
}

/** Shortest distance between two points on a loop of length `loopLength`. */
export function loopDelta(a: number, b: number, loopLength: number): number {
  const raw = Math.abs(a - b);
  if (!(loopLength > 0)) return raw;
  return Math.min(raw, loopLength - raw);
}
