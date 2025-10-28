import { useEffect, useRef, useState } from 'react';

type BreathingState = 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';

const audioFiles: { [key in BreathingState]?: string } = {
  'in': '/audio/breath-chord-one.mp3',
  'hold-in': '/audio/breath-chord-two.mp3',
  'out': '/audio/breath-chord-three.mp3',
  'hold-out': '/audio/breath-chord-four.mp3',
};

export function useAudio(breathingState: BreathingState) {
  const [volume, setVolume] = useState(0.7);
  const [isMuted, setIsMuted] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const previousStateRef = useRef<BreathingState>('idle');
  const previousMutedRef = useRef<boolean>(false);
  const preloadedAudioRef = useRef<{ [key: string]: HTMLAudioElement }>({});

  // Preload all audio files on mount
  useEffect(() => {
    const preloadAudio = () => {
      Object.entries(audioFiles).forEach(([state, path]) => {
        if (path) {
          const audio = new Audio(path);
          audio.preload = 'auto';
          audio.load();
          preloadedAudioRef.current[state] = audio;
        }
      });
    };

    preloadAudio();

    // Cleanup preloaded audio on unmount
    return () => {
      Object.values(preloadedAudioRef.current).forEach(audio => {
        audio.pause();
        audio.src = '';
      });
      preloadedAudioRef.current = {};
    };
  }, []);

  useEffect(() => {
    // Initialize audio elements for each phase
    const audioPath = audioFiles[breathingState];

    // Stop audio when returning to idle or completed state
    if ((breathingState === 'idle' || breathingState === 'completed') && audioRef.current) {
      audioRef.current.pause();
      audioRef.current = null;
      previousStateRef.current = breathingState;
      return;
    }

    if (audioPath && breathingState !== previousStateRef.current) {
      // Create new audio element
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current = null;
      }

      const audio = new Audio(audioPath);
      audio.volume = isMuted ? 0 : volume;
      audio.loop = true; // Loop audio for the duration of the phase
      audioRef.current = audio;

      // Play the audio
      audio.play().catch(error => {
        console.error('Error playing audio:', error);
      });

      previousStateRef.current = breathingState;
    }

    // Clean up when component unmounts or state changes
    return () => {
      if (audioRef.current && breathingState !== previousStateRef.current) {
        audioRef.current.pause();
      }
    };
  }, [breathingState, volume, isMuted]);

  // Handle unmuting - play audio for current phase immediately
  useEffect(() => {
    const audioPath = audioFiles[breathingState];

    // If we just unmuted (was muted, now not muted) and we have an audio file for this state
    if (previousMutedRef.current && !isMuted && audioPath) {
      // Create and play new audio for current phase
      if (audioRef.current) {
        audioRef.current.pause();
      }

      const audio = new Audio(audioPath);
      audio.volume = volume;
      audio.loop = true;
      audioRef.current = audio;

      audio.play().catch(error => {
        console.error('Error playing audio on unmute:', error);
      });
    }

    // Update volume for existing audio
    if (audioRef.current) {
      audioRef.current.volume = isMuted ? 0 : volume;
    }

    previousMutedRef.current = isMuted;
  }, [volume, isMuted, breathingState]);

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
