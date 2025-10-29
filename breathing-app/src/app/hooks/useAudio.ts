import { useEffect, useRef, useState } from 'react';

type BreathingState = 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';

const audioFile = '/audio/breath-chord-loop-icetinespad.mp3';

export function useAudio(breathingState: BreathingState) {
  const [volume, setVolume] = useState(0.7);
  const [isMuted, setIsMuted] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const isPlayingRef = useRef<boolean>(false);

  // Initialize and preload audio on mount
  useEffect(() => {
    const audio = new Audio(audioFile);
    audio.preload = 'auto';
    audio.loop = false; // Don't auto-loop, let breathing cycle control it
    audio.volume = volume;

    // Set playback rate to match 16-second breathing cycle
    // Once metadata is loaded, calculate the correct playback rate
    audio.addEventListener('loadedmetadata', () => {
      const actualDuration = audio.duration;
      const targetDuration = 16; // 16 seconds for one complete breathing cycle
      audio.playbackRate = actualDuration / targetDuration;
    });

    audioRef.current = audio;

    // Cleanup on unmount
    return () => {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.src = '';
        audioRef.current = null;
      }
    };
  }, []);

  // Handle playback based on breathing state
  useEffect(() => {
    if (!audioRef.current) return;

    const audio = audioRef.current;

    // Start playing from the beginning each time we reach the 'in' phase
    if (breathingState === 'in') {
      audio.currentTime = 0; // Restart from beginning
      audio.play().catch(error => {
        console.error('Error playing audio:', error);
      });
      isPlayingRef.current = true;
    }

    // Stop audio when returning to idle or completed state
    if ((breathingState === 'idle' || breathingState === 'completed') && isPlayingRef.current) {
      audio.pause();
      audio.currentTime = 0;
      isPlayingRef.current = false;
    }
  }, [breathingState]);

  // Handle volume and mute changes
  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = isMuted ? 0 : volume;
    }
  }, [volume, isMuted]);

  const toggleMute = () => {
    setIsMuted(!isMuted);
  };

  const updateVolume = (newVolume: number) => {
    setVolume(Math.max(0, Math.min(1, newVolume)));
  };

  return {
    volume,
    isMuted,
    toggleMute,
    updateVolume,
  };
}
