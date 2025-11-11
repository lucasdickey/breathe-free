import { useEffect, useRef, useState } from 'react';
import { Audio } from 'expo-av';

type BreathingState = 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';

export function useAudio(breathingState: BreathingState) {
  const [volume, setVolume] = useState(0.7);
  const [isMuted, setIsMuted] = useState(false);
  const soundRef = useRef<Audio.Sound | null>(null);
  const isPlayingRef = useRef<boolean>(false);

  // Initialize audio on mount
  useEffect(() => {
    let sound: Audio.Sound | null = null;

    const setupAudio = async () => {
      try {
        // Set audio mode for playback
        await Audio.setAudioModeAsync({
          playsInSilentModeIOS: true,
          staysActiveInBackground: true,
        });

        // Load the audio file
        const { sound: loadedSound } = await Audio.Sound.createAsync(
          require('../assets/audio/breath-chord-loop-icetinespad.mp3'),
          {
            shouldPlay: false,
            volume: volume,
            rate: 1.0,
            isLooping: false,
          }
        );

        sound = loadedSound;
        soundRef.current = loadedSound;

        // Get the duration and set the playback rate
        const status = await loadedSound.getStatusAsync();
        if (status.isLoaded && status.durationMillis) {
          const actualDuration = status.durationMillis / 1000; // Convert to seconds
          const targetDuration = 16; // 16 seconds for one complete breathing cycle
          const playbackRate = actualDuration / targetDuration;
          await loadedSound.setRateAsync(playbackRate, true);
        }
      } catch (error) {
        console.error('Error setting up audio:', error);
      }
    };

    setupAudio();

    // Cleanup on unmount
    return () => {
      if (sound) {
        sound.unloadAsync();
      }
    };
  }, []);

  // Handle playback based on breathing state
  useEffect(() => {
    const handlePlayback = async () => {
      if (!soundRef.current) return;

      const sound = soundRef.current;

      try {
        // Start playing only when we enter the 'in' phase (actual breathing starts)
        if (breathingState === 'in' && !isPlayingRef.current) {
          await sound.setPositionAsync(0); // Restart from beginning
          await sound.playAsync();
          isPlayingRef.current = true;
        }

        // Stop audio only when returning to idle or completed state
        if ((breathingState === 'idle' || breathingState === 'completed') && isPlayingRef.current) {
          await sound.stopAsync();
          await sound.setPositionAsync(0);
          isPlayingRef.current = false;
        }
      } catch (error) {
        console.error('Error playing audio:', error);
      }
    };

    handlePlayback();
  }, [breathingState]);

  // Handle volume and mute changes
  useEffect(() => {
    const updateVolume = async () => {
      if (soundRef.current) {
        try {
          await soundRef.current.setVolumeAsync(isMuted ? 0 : volume);
        } catch (error) {
          console.error('Error updating volume:', error);
        }
      }
    };

    updateVolume();
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
