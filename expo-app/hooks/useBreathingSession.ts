import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { createAudioPlayer, setAudioModeAsync, type AudioPlayer } from 'expo-audio';

export type { BreathingPhase, SessionSnapshot } from './breathingMath';
export { PRE_START_SECONDS, PHASE_SECONDS, CYCLE_SECONDS } from './breathingMath';

import {
  CYCLE_SECONDS,
  IDLE_SNAPSHOT,
  PRE_START_SECONDS,
  computeSnapshot,
  expectedClipPosition,
  loopDelta,
  type SessionSnapshot,
} from './breathingMath';

// How far the audio loop may drift from the visual clock before we nudge it.
// Below this, a correction would be more audible than the drift itself.
const AUDIO_RESYNC_TOLERANCE = 0.18;

/** Monotonic-ish seconds. performance.now() when available, wall clock otherwise. */
function nowSeconds(): number {
  if (typeof performance !== 'undefined' && typeof performance.now === 'function') {
    return performance.now() / 1000;
  }
  return Date.now() / 1000;
}

/**
 * Drives the whole breathing session from a single clock.
 *
 * Phase, countdown and remaining time are pure functions of elapsed time, so
 * the cadence cannot drift and cannot be corrupted by a state update landing
 * late — unlike a setInterval chain that mutates state on every tick.
 *
 * React Native has no Web Audio API, so the audio loop cannot be scheduled
 * sample-accurately the way the web build does it. Instead the loop is started
 * exactly at the first inhale with its rate scaled so one pass lasts exactly
 * one 16s cycle, and every tick compares the player's position against the
 * position the clock says it should be at, nudging it only when it has drifted
 * past AUDIO_RESYNC_TOLERANCE. Sound and visuals therefore stay locked to the
 * same clock rather than free-running side by side.
 */
export function useBreathingSession() {
  const [snapshot, setSnapshot] = useState<SessionSnapshot>(IDLE_SNAPSHOT);
  const [volume, setVolume] = useState(0.7);
  const [isMuted, setIsMuted] = useState(false);

  const playerRef = useRef<AudioPlayer | null>(null);
  const rateRef = useRef(1);
  const audioStartedRef = useRef(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const runningRef = useRef(false);
  const startedAtRef = useRef(0);
  const cyclesRef = useRef(0);

  const volumeRef = useRef(volume);
  const mutedRef = useRef(isMuted);

  // Create the player once. expo-audio players are native resources, so this
  // is deliberately not tied to session start/stop.
  useEffect(() => {
    let player: AudioPlayer | null = null;
    try {
      player = createAudioPlayer(require('../assets/audio/breath-chord-loop-icetinespad.mp3'));
      player.loop = true;
      player.volume = mutedRef.current ? 0 : volumeRef.current;
      playerRef.current = player;
    } catch (error) {
      console.error('Failed to create breathing audio player:', error);
    }

    setAudioModeAsync({
      playsInSilentMode: true,
      shouldPlayInBackground: false,
    }).catch(() => {
      // Non-fatal: playback still works with the default session config.
    });

    return () => {
      if (player) {
        try {
          player.remove();
        } catch {
          // already released
        }
      }
      playerRef.current = null;
    };
  }, []);

  const stopAudio = useCallback(() => {
    audioStartedRef.current = false;
    const player = playerRef.current;
    if (!player) return;
    try {
      player.pause();
      player.seekTo(0);
    } catch {
      // player may already be released
    }
  }, []);

  const clearTicker = useCallback(() => {
    runningRef.current = false;
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }
  }, []);

  /**
   * Start the loop at the first inhale, or nudge it back if it has drifted.
   * `tb` is seconds spent breathing (pre-start already subtracted).
   */
  const syncAudio = useCallback((tb: number) => {
    const player = playerRef.current;
    if (!player) return;

    try {
      if (!player.isLoaded) return;

      if (!audioStartedRef.current) {
        // Scale the clip so exactly one pass covers one 16s breathing cycle.
        const duration = player.duration;
        if (duration && duration > 0) {
          rateRef.current = duration / CYCLE_SECONDS;
          player.setPlaybackRate(rateRef.current, 'high');
        }
        player.volume = mutedRef.current ? 0 : volumeRef.current;
        player.seekTo(0);
        player.play();
        audioStartedRef.current = true;
        return;
      }

      // Where the clock says the playhead should be, in the clip's own timeline.
      const clipDuration = player.duration || 0;
      const expected = expectedClipPosition(tb, rateRef.current, clipDuration);
      const actual = player.currentTime;
      if (Number.isFinite(expected) && Number.isFinite(actual)) {
        // Near a loop boundary the raw difference is misleading (0.01 vs 14.99),
        // so measure the distance around the loop instead.
        if (loopDelta(actual, expected, clipDuration) > AUDIO_RESYNC_TOLERANCE) {
          player.seekTo(expected);
        }
      }
    } catch {
      // Audio problems must never interrupt the breathing session.
    }
  }, []);

  const tick = useCallback(() => {
    if (!runningRef.current) return;

    const elapsed = nowSeconds() - startedAtRef.current;
    const next = computeSnapshot(elapsed, cyclesRef.current);

    setSnapshot((prev) =>
      prev.phase === next.phase &&
      prev.countdown === next.countdown &&
      prev.currentCycle === next.currentCycle &&
      prev.remainingSeconds === next.remainingSeconds
        ? prev
        : next
    );

    if (next.phase === 'completed') {
      runningRef.current = false;
      stopAudio();
      return;
    }

    if (elapsed >= PRE_START_SECONDS) {
      syncAudio(elapsed - PRE_START_SECONDS);
    }

    // Re-aim at the next whole second of the session clock. Because the target
    // is absolute rather than "now + 1000ms", a late tick cannot accumulate.
    const msIntoSecond = (elapsed * 1000) % 1000;
    const delay = Math.max(16, 1000 - msIntoSecond);
    timeoutRef.current = setTimeout(tick, delay);
  }, [stopAudio, syncAudio]);

  const start = useCallback(
    (cycles: number) => {
      clearTicker();
      stopAudio();

      startedAtRef.current = nowSeconds();
      cyclesRef.current = cycles;
      runningRef.current = true;
      setSnapshot(computeSnapshot(0, cycles));
      tick();
    },
    [clearTicker, stopAudio, tick]
  );

  const stop = useCallback(() => {
    clearTicker();
    stopAudio();
    setSnapshot(IDLE_SNAPSHOT);
  }, [clearTicker, stopAudio]);

  // Coming back from the background, timers may have been frozen. Recompute
  // from the clock immediately so the session is never left showing stale time.
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active' && runningRef.current) {
        if (timeoutRef.current) clearTimeout(timeoutRef.current);
        tick();
      }
    });
    return () => sub.remove();
  }, [tick]);

  useEffect(() => {
    volumeRef.current = volume;
    mutedRef.current = isMuted;
    const player = playerRef.current;
    if (player) {
      try {
        player.volume = isMuted ? 0 : volume;
      } catch {
        // player may already be released
      }
    }
  }, [volume, isMuted]);

  useEffect(() => clearTicker, [clearTicker]);

  const toggleMute = useCallback(() => setIsMuted((m) => !m), []);
  const updateVolume = useCallback(
    (v: number) => setVolume(Math.max(0, Math.min(1, v))),
    []
  );

  return {
    ...snapshot,
    start,
    stop,
    volume,
    isMuted,
    toggleMute,
    updateVolume,
  };
}
