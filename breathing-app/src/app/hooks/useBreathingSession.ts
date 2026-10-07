"use client";

import { useCallback, useEffect, useRef, useState } from 'react';
import { useMotionValue } from 'framer-motion';

export type BreathingPhase =
  | 'idle'
  | 'pre-start'
  | 'in'
  | 'hold-in'
  | 'out'
  | 'hold-out'
  | 'completed';

export type SoundMode = 'ambient' | 'bells' | 'silent';

export const PRE_START_SECONDS = 8;
export const PHASE_SECONDS = 4;
export const CYCLE_SECONDS = PHASE_SECONDS * 4; // in, hold-in, out, hold-out

const WORKLET_URL = '/worklets/breath-synth.js';
const PHASE_ORDER: BreathingPhase[] = ['in', 'hold-in', 'out', 'hold-out'];
// A short lead so the first frame and the first sample both land after "now".
const LEAD_SECONDS = 0.35;
/** How long the words take to cross from one phase's to the next. */
const WORDS_FADE_SECONDS = 0.35;

interface SessionSnapshot {
  phase: BreathingPhase;
  /** The phase before this one, whose words fade out as this one's fade in. */
  previousPhase: BreathingPhase;
  countdown: number;
  currentCycle: number; // 1-based while breathing, 0 otherwise
  remainingSeconds: number; // breathing time left (excludes pre-start)
}

const IDLE_SNAPSHOT: SessionSnapshot = {
  phase: 'idle',
  previousPhase: 'idle',
  countdown: 0,
  currentCycle: 0,
  remainingSeconds: 0,
};

/**
 * Lung level across an inhale, 0 → 1 (an exhale is 1 - rise). The same curve the
 * macOS and Android apps use for the orb and for the sound's swell.
 */
function rise(p: number): number {
  const q = Math.pow(Math.min(Math.max(p, 0), 1), 0.8);
  return 0.5 - 0.5 * Math.cos(Math.PI * q);
}

/** Pure time → session state. t is seconds since session start; since is the seconds since the phase began. */
function computeFrame(t: number, cycles: number): SessionSnapshot & { level: number; since: number } {
  const breathingTotal = cycles * CYCLE_SECONDS;
  if (t < PRE_START_SECONDS) {
    return {
      phase: 'pre-start',
      previousPhase: 'idle',
      countdown: Math.min(PRE_START_SECONDS, Math.max(1, Math.ceil(PRE_START_SECONDS - Math.max(0, t) - 1e-9))),
      currentCycle: 0,
      remainingSeconds: breathingTotal,
      level: 0,
      since: Math.max(0, t),
    };
  }
  const tb = t - PRE_START_SECONDS; // time spent breathing
  if (tb >= breathingTotal) {
    return {
      phase: 'completed',
      previousPhase: 'hold-out',
      countdown: 0,
      currentCycle: 0,
      remainingSeconds: 0,
      level: 0,
      since: tb - breathingTotal,
    };
  }
  const index = Math.min(cycles * 4 - 1, Math.floor(tb / PHASE_SECONDS));
  const inPhase = tb - index * PHASE_SECONDS;
  const p = Math.min(1, inPhase / PHASE_SECONDS);
  const phase = PHASE_ORDER[index % 4];
  const level = phase === 'in' ? rise(p) : phase === 'hold-in' ? 1 : phase === 'out' ? 1 - rise(p) : 0;
  return {
    phase,
    previousPhase: index === 0 ? 'pre-start' : PHASE_ORDER[(index - 1) % 4],
    countdown: Math.min(PHASE_SECONDS, Math.max(1, Math.ceil(PHASE_SECONDS - inPhase - 1e-9))),
    currentCycle: Math.floor(index / 4) + 1,
    remainingSeconds: Math.ceil(breathingTotal - tb - 1e-9),
    level,
    since: inPhase,
  };
}

/** How far the words have crossed, 0 → 1, a moment after a phase begins. */
function wordsFade(since: number): number {
  const x = Math.min(Math.max(since / WORDS_FADE_SECONDS, 0), 1);
  return x * x * (3 - 2 * x);
}

/**
 * Drives the whole breathing session off one clock.
 *
 * Phase, countdown, remaining time and breath level are pure functions of elapsed time,
 * so nothing drifts. With sound on, the clock is the AudioContext's: the synth (an
 * AudioWorklet, the same generator the native apps use) renders each block for the
 * session time at which it will be heard, and the picture shows the session time that is
 * audible now (getOutputTimestamp), so the bells land as the words change even over
 * Bluetooth.
 */
export function useBreathingSession() {
  const [snapshot, setSnapshot] = useState<SessionSnapshot>(IDLE_SNAPSHOT);
  const [volume, setVolume] = useState(0.7);
  const [isMuted, setIsMuted] = useState(false);
  /** How full the lungs are right now, 0..1; updated every frame without re-rendering. */
  const level = useMotionValue(0);
  /** How far the words have crossed from the last phase's to this one's, 0..1; also per frame. */
  const fade = useMotionValue(1);

  const audioCtxRef = useRef<AudioContext | null>(null);
  const workletRef = useRef<Promise<boolean> | null>(null);
  const nodeRef = useRef<AudioWorkletNode | null>(null);
  const masterGainRef = useRef<GainNode | null>(null);
  const rafRef = useRef<number>(0);
  const runningRef = useRef(false);

  const volumeRef = useRef(volume);
  const mutedRef = useRef(isMuted);

  const getContext = useCallback((): AudioContext | null => {
    if (typeof window === 'undefined') return null;
    if (!audioCtxRef.current) {
      try {
        audioCtxRef.current = new AudioContext({ latencyHint: 'playback' });
      } catch {
        return null;
      }
    }
    return audioCtxRef.current;
  }, []);

  const loadWorklet = useCallback((ctx: AudioContext): Promise<boolean> => {
    if (!workletRef.current) {
      workletRef.current = ctx.audioWorklet
        ? ctx.audioWorklet.addModule(WORKLET_URL).then(
            () => true,
            (error) => {
              console.error('Failed to load breathing sound:', error);
              workletRef.current = null;
              return false;
            },
          )
        : Promise.resolve(false);
    }
    return workletRef.current;
  }, []);

  /**
   * Call straight from the click that starts a session. Browsers (Safari especially)
   * only let audio start inside the user's gesture, and starting a session may first
   * wait on the network.
   */
  const prime = useCallback(() => {
    const ctx = getContext();
    if (!ctx) return;
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    loadWorklet(ctx);
  }, [getContext, loadWorklet]);

  const stopAudio = useCallback(() => {
    const node = nodeRef.current;
    nodeRef.current = null;
    if (!node) return;
    // Fade out, then let go once the synth reports silence (or after a second regardless).
    let released = false;
    const release = () => {
      if (released) return;
      released = true;
      node.port.onmessage = null;
      node.disconnect();
    };
    node.port.onmessage = (event) => {
      if (event.data?.type === 'finished') release();
    };
    node.port.postMessage({ type: 'fadeOut' });
    setTimeout(release, 1000);
  }, []);

  const stopTicker = useCallback(() => {
    runningRef.current = false;
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = 0;
    }
  }, []);

  const start = useCallback(async (cycles: number, mode: SoundMode = 'ambient') => {
    stopTicker();
    stopAudio();

    // Without sound the session runs on the page's own clock.
    let now = () => performance.now() / 1000;
    let t0 = now() + LEAD_SECONDS;

    const ctx = mode === 'silent' ? null : getContext();
    if (ctx) {
      if (ctx.state === 'suspended') {
        // Give the browser a moment to start audio; if it won't, carry on silently.
        await Promise.race([ctx.resume().catch(() => {}), new Promise((r) => setTimeout(r, 800))]);
      }
      const ready = ctx.state === 'running' && (await loadWorklet(ctx));
      const startTime = ctx.currentTime + LEAD_SECONDS;
      let node: AudioWorkletNode | null = null;
      if (ready) {
        try {
          node = new AudioWorkletNode(ctx, 'breath-synth', {
            numberOfInputs: 0,
            numberOfOutputs: 1,
            outputChannelCount: [2],
            processorOptions: { cycles, startTime, mode },
          });
        } catch (error) {
          console.error('Breathing sound unavailable:', error);
        }
      }
      if (node) {
        if (!masterGainRef.current) {
          masterGainRef.current = ctx.createGain();
          masterGainRef.current.connect(ctx.destination);
        }
        masterGainRef.current.gain.value = mutedRef.current ? 0 : volumeRef.current;
        node.connect(masterGainRef.current);
        const playing = node;
        playing.port.onmessage = (event) => {
          if (event.data?.type === 'finished') {
            playing.disconnect();
            if (nodeRef.current === playing) nodeRef.current = null;
          }
        };
        nodeRef.current = playing;

        // The context time being heard right now. getOutputTimestamp() pairs the frame
        // reaching the speakers with performance.now(); where it isn't available, allow
        // for the reported output delay instead.
        const audible = () => {
          const stamp = typeof ctx.getOutputTimestamp === 'function' ? ctx.getOutputTimestamp() : null;
          if (stamp && stamp.contextTime !== undefined && stamp.performanceTime && stamp.contextTime > 0) {
            return stamp.contextTime + (performance.now() - stamp.performanceTime) / 1000;
          }
          return ctx.currentTime - (ctx.outputLatency || ctx.baseLatency || 0);
        };
        // Audio time arrives in steps; glide on the page clock and let the audio clock
        // steer it, so motion stays smooth but cannot wander off the sound.
        let offset = audible() - performance.now() / 1000;
        now = () => {
          const page = performance.now() / 1000;
          offset += (audible() - page - offset) * 0.1;
          return page + offset;
        };
        t0 = startTime;
      }
    }

    runningRef.current = true;
    let last: SessionSnapshot | null = null;
    // Session time never steps back, even when the audio clock steering it does, so the
    // words can't flip back to a phase that has just ended.
    let latest = -Infinity;
    const tick = () => {
      if (!runningRef.current) return;
      latest = Math.max(latest, now() - t0);
      const frame = computeFrame(latest, cycles);
      level.set(frame.level);
      fade.set(frame.phase === 'completed' ? 1 : wordsFade(frame.since));
      if (
        !last ||
        frame.phase !== last.phase ||
        frame.countdown !== last.countdown ||
        frame.remainingSeconds !== last.remainingSeconds ||
        frame.currentCycle !== last.currentCycle
      ) {
        last = {
          phase: frame.phase,
          previousPhase: frame.previousPhase,
          countdown: frame.countdown,
          currentCycle: frame.currentCycle,
          remainingSeconds: frame.remainingSeconds,
        };
        setSnapshot(last);
      }
      if (frame.phase === 'completed') {
        // The closing chord rings on; the synth lets go of the output when it fades.
        runningRef.current = false;
        return;
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    tick();
  }, [fade, getContext, level, loadWorklet, stopAudio, stopTicker]);

  const stop = useCallback(() => {
    stopTicker();
    stopAudio();
    level.set(0);
    fade.set(1);
    setSnapshot(IDLE_SNAPSHOT);
  }, [fade, level, stopAudio, stopTicker]);

  const reset = useCallback(() => {
    stopTicker();
    level.set(0);
    fade.set(1);
    setSnapshot(IDLE_SNAPSHOT);
  }, [fade, level, stopTicker]);

  // Keep the gain node - and the refs the audio graph reads from - in step
  // with volume / mute. Mirroring into refs happens here rather than during
  // render, so concurrent re-renders can never leave the graph mid-update.
  useEffect(() => {
    volumeRef.current = volume;
    mutedRef.current = isMuted;
    const ctx = audioCtxRef.current;
    const gain = masterGainRef.current;
    if (ctx && gain) {
      gain.gain.setTargetAtTime(isMuted ? 0 : volume, ctx.currentTime, 0.05);
    }
  }, [volume, isMuted]);

  // Cleanup on unmount.
  useEffect(() => {
    return () => {
      runningRef.current = false;
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      nodeRef.current?.disconnect();
      nodeRef.current = null;
      workletRef.current = null;
      if (audioCtxRef.current) {
        audioCtxRef.current.close().catch(() => {});
        audioCtxRef.current = null;
      }
    };
  }, []);

  const toggleMute = useCallback(() => setIsMuted((m) => !m), []);
  const updateVolume = useCallback((v: number) => setVolume(Math.max(0, Math.min(1, v))), []);

  return {
    ...snapshot,
    level,
    fade,
    prime,
    start,
    stop,
    reset,
    volume,
    isMuted,
    toggleMute,
    updateVolume,
  };
}
