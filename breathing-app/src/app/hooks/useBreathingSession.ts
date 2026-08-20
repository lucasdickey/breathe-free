"use client";

import { useCallback, useEffect, useRef, useState } from 'react';

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

const AUDIO_FILE = '/audio/breath-chord-loop-icetinespad.mp3';
const PHASE_ORDER: BreathingPhase[] = ['in', 'hold-in', 'out', 'hold-out'];

interface SessionSnapshot {
  phase: BreathingPhase;
  countdown: number;
  currentCycle: number; // 1-based while breathing, 0 otherwise
  remainingSeconds: number; // breathing time left (excludes pre-start)
}

const IDLE_SNAPSHOT: SessionSnapshot = {
  phase: 'idle',
  countdown: 0,
  currentCycle: 0,
  remainingSeconds: 0,
};

/**
 * Drives the whole breathing session off a single monotonic clock.
 *
 * Phase, countdown and remaining time are pure functions of elapsed time, so
 * there is no setInterval drift and no state-transition side effects. When the
 * audio buffer is available, the AudioContext's own clock is the master clock
 * and the looped audio source is scheduled on it — the loop period is scaled
 * to exactly one 16s breathing cycle, so sound and visuals cannot diverge.
 */
export function useBreathingSession() {
  const [snapshot, setSnapshot] = useState<SessionSnapshot>(IDLE_SNAPSHOT);
  const [volume, setVolume] = useState(0.7);
  const [isMuted, setIsMuted] = useState(false);

  const audioCtxRef = useRef<AudioContext | null>(null);
  const bufferRef = useRef<AudioBuffer | null>(null);
  const bufferPromiseRef = useRef<Promise<AudioBuffer | null> | null>(null);
  const sourceRef = useRef<AudioBufferSourceNode | null>(null);
  const masterGainRef = useRef<GainNode | null>(null);
  const fadeGainRef = useRef<GainNode | null>(null);
  const rafRef = useRef<number>(0);
  const runningRef = useRef(false);

  const volumeRef = useRef(volume);
  const mutedRef = useRef(isMuted);

  const getContext = useCallback((): AudioContext | null => {
    if (typeof window === 'undefined') return null;
    if (!audioCtxRef.current) {
      try {
        audioCtxRef.current = new AudioContext();
      } catch {
        return null;
      }
    }
    return audioCtxRef.current;
  }, []);

  const loadBuffer = useCallback((ctx: AudioContext): Promise<AudioBuffer | null> => {
    if (bufferRef.current) return Promise.resolve(bufferRef.current);
    if (!bufferPromiseRef.current) {
      bufferPromiseRef.current = fetch(AUDIO_FILE)
        .then((res) => res.arrayBuffer())
        .then((data) => ctx.decodeAudioData(data))
        .then((buffer) => {
          bufferRef.current = buffer;
          return buffer;
        })
        .catch((error) => {
          console.error('Failed to load breathing audio:', error);
          bufferPromiseRef.current = null;
          return null;
        });
    }
    return bufferPromiseRef.current;
  }, []);

  const stopAudio = useCallback(() => {
    if (sourceRef.current) {
      try {
        sourceRef.current.stop();
      } catch {
        // already stopped
      }
      sourceRef.current.disconnect();
      sourceRef.current = null;
    }
    if (fadeGainRef.current) {
      fadeGainRef.current.disconnect();
      fadeGainRef.current = null;
    }
  }, []);

  const stopTicker = useCallback(() => {
    runningRef.current = false;
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = 0;
    }
  }, []);

  /** Pure time → session state math. t is seconds since session start. */
  const computeSnapshot = useCallback((t: number, cycles: number): SessionSnapshot => {
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
  }, []);

  const start = useCallback(async (cycles: number) => {
    stopTicker();
    stopAudio();

    const ctx = getContext();
    if (ctx && ctx.state === 'suspended') {
      // Must be called from a user gesture; ignore failures.
      ctx.resume().catch(() => {});
    }

    // Try to have audio ready before the clock starts so the schedule is exact.
    const buffer = ctx ? await loadBuffer(ctx) : null;

    const useAudioClock = !!(ctx && buffer);
    const now = () => (useAudioClock ? ctx.currentTime : performance.now() / 1000);
    const t0 = now() + 0.05; // small lead so the first audio sample isn't in the past
    const breathingStart = t0 + PRE_START_SECONDS;
    const sessionEnd = breathingStart + cycles * CYCLE_SECONDS;

    if (ctx && buffer) {
      if (!masterGainRef.current) {
        masterGainRef.current = ctx.createGain();
        masterGainRef.current.connect(ctx.destination);
      }
      masterGainRef.current.gain.value = mutedRef.current ? 0 : volumeRef.current;

      const fadeGain = ctx.createGain();
      fadeGain.connect(masterGainRef.current);
      // Gentle fade in at the first inhale and fade out at session end,
      // so the loop never starts or stops with a click.
      fadeGain.gain.setValueAtTime(0, breathingStart);
      fadeGain.gain.linearRampToValueAtTime(1, breathingStart + 0.5);
      fadeGain.gain.setValueAtTime(1, sessionEnd - 0.75);
      fadeGain.gain.linearRampToValueAtTime(0, sessionEnd);
      fadeGainRef.current = fadeGain;

      const source = ctx.createBufferSource();
      source.buffer = buffer;
      source.loop = true;
      // Stretch (or squeeze) the clip so one loop lasts exactly one 16s cycle.
      source.playbackRate.value = buffer.duration / CYCLE_SECONDS;
      source.connect(fadeGain);
      source.start(breathingStart);
      source.stop(sessionEnd + 0.05);
      source.onended = () => {
        source.disconnect();
        if (sourceRef.current === source) sourceRef.current = null;
      };
      sourceRef.current = source;
    }

    runningRef.current = true;
    let last: SessionSnapshot | null = null;
    const tick = () => {
      if (!runningRef.current) return;
      const next = computeSnapshot(now() - t0, cycles);
      if (
        !last ||
        next.phase !== last.phase ||
        next.countdown !== last.countdown ||
        next.remainingSeconds !== last.remainingSeconds ||
        next.currentCycle !== last.currentCycle
      ) {
        last = next;
        setSnapshot(next);
      }
      if (next.phase === 'completed') {
        runningRef.current = false;
        return;
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    tick();
  }, [computeSnapshot, getContext, loadBuffer, stopAudio, stopTicker]);

  const stop = useCallback(() => {
    stopTicker();
    stopAudio();
    setSnapshot(IDLE_SNAPSHOT);
  }, [stopAudio, stopTicker]);

  const reset = useCallback(() => {
    stopTicker();
    stopAudio();
    setSnapshot(IDLE_SNAPSHOT);
  }, [stopAudio, stopTicker]);

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
      if (sourceRef.current) {
        try {
          sourceRef.current.stop();
        } catch {
          // already stopped
        }
      }
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
    start,
    stop,
    reset,
    volume,
    isMuted,
    toggleMute,
    updateVolume,
  };
}
