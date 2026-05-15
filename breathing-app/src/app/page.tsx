"use client";

import { useState, useEffect, useCallback } from 'react';
import Balloon from './components/Balloon';
import AudioControls from './components/AudioControls';
import CloudBackground from './components/CloudBackground';
import CycleDropdown from './components/CycleDropdown';
import { useAudio } from './hooks/useAudio';
import { motion, AnimatePresence } from 'framer-motion';

type BreathingState = 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';

const defaultPrompts: { [key: string]: string } = {
  'idle': '',
  'pre-start': 'Settle your mind',
  'in': 'Breathe in',
  'hold_in': 'Hold',
  'out': 'Breathe out',
  'hold_out': 'Hold',
  'completed': 'Be easy, breathe deeply',
};

export default function Home() {
  const [cycles, setCycles] = useState(6);
  const [breathingState, setBreathingState] = useState<BreathingState>('idle');
  const [countdown, setCountdown] = useState(0);
  const [currentCycle, setCurrentCycle] = useState(0);
  const [totalDuration, setTotalDuration] = useState(0);
  const [mood, setMood] = useState('');
  const [prompts, setPrompts] = useState(defaultPrompts);
  const [isLoadingPrompts, setIsLoadingPrompts] = useState(false);

  // Audio management
  const { volume, isMuted, toggleMute, updateVolume } = useAudio(breathingState);

  useEffect(() => {
    let intervalId: NodeJS.Timeout | null = null;
    let isCancelled = false;

    const checkCompletion = () => {
      if (currentCycle >= cycles && breathingState !== 'pre-start' && !isCancelled) {
        // Use a microtask to update state safely
        Promise.resolve().then(() => {
          if (!isCancelled) {
            setBreathingState('completed');
            setCurrentCycle(0);
          }
        });
        return true;
      }
      return false;
    };

    // Start interval only if not idle
    if (breathingState !== 'idle') {
      // Check initial completion before starting interval
      if (checkCompletion()) {
        return () => { isCancelled = true; };
      }

      // Start interval
      intervalId = setInterval(() => {
        // Only start total duration tracking after first breath loop
        if (breathingState !== 'pre-start') {
          setTotalDuration((prev) => prev + 1);
        }
        
        setCountdown((prevCountdown) => {
          if (prevCountdown > 1) {
            return prevCountdown - 1;
          }

          switch (breathingState) {
            case 'pre-start':
              setBreathingState('in');
              return 4;
            case 'in':
              setBreathingState('hold-in');
              return 4;
            case 'hold-in':
              setBreathingState('out');
              return 4;
            case 'out':
              setBreathingState('hold-out');
              return 4;
            case 'hold-out':
              const newCycle = currentCycle + 1;
              setCurrentCycle(newCycle);
              if (newCycle < cycles) {
                setBreathingState('in');
              } else {
                // Use a microtask to update state safely
                Promise.resolve().then(() => {
                  if (!isCancelled) {
                    setBreathingState('completed');
                  }
                });
              }
              return 4;
            default:
              return 0;
          }
        });

        // Check for completion after state updates
        checkCompletion();
      }, 1000);
    }

    // Cleanup function
    return () => {
      isCancelled = true;
      if (intervalId) clearInterval(intervalId);
      if (breathingState === 'idle') {
        setTotalDuration(0);
      }
    };
  }, [breathingState, cycles, currentCycle]);


  const startExercise = async () => {
    setIsLoadingPrompts(true);
    try {
      if (mood.trim()) {
        const response = await fetch('/api/generate-prompt', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ mood }),
        });
        const data = await response.json();
        setPrompts({
          ...defaultPrompts,
          'in': data.in,
          'hold_in': data.hold_in,
          'out': data.out,
          'hold_out': data.hold_out,
          'completed': data.completed,
        });
      } else {
        setPrompts(defaultPrompts);
      }
    } catch (error) {
      console.error('Failed to fetch personalized prompts', error);
      setPrompts(defaultPrompts);
    } finally {
      setIsLoadingPrompts(false);
      setCurrentCycle(0);
      setBreathingState('pre-start');
      setCountdown(8);
      setTotalDuration(0);
    }
  };

  const stopExercise = () => {
    setBreathingState('idle');
    setCurrentCycle(0);
    setTotalDuration(0);
  };

  const mainContainerClasses =
    breathingState === 'idle' || breathingState === 'completed'
      ? 'flex w-full max-w-lg flex-col items-center justify-center rounded-3xl bg-gradient-to-b from-white/90 to-blue-50/90 backdrop-blur-xl p-10 shadow-2xl sm:p-12 relative z-10 border border-white/50'
      : 'flex w-full flex-col items-center justify-center min-h-screen relative z-10';

  const topContainerClasses =
    'flex min-h-screen flex-col items-center justify-center p-4 bg-gradient-to-br from-[#f0f9ff] via-[#e6f2ff] to-[#cce6ff]';

  // Calculate total session duration and remaining time
  const totalSessionDuration = cycles * 16; // 4 seconds * 4 phases * number of cycles
  const remainingTime = totalSessionDuration - totalDuration;
  const minutesRemaining = Math.floor(remainingTime / 60);
  const secondsRemaining = remainingTime % 60;

  const getPrompt = useCallback((state: BreathingState) => {
    const key = state.replace('-', '_');
    return prompts[key] || prompts[state] || '';
  }, [prompts]);

  return (
    <div className={topContainerClasses}>
      <CloudBackground />
      <main className={mainContainerClasses}>
        <AnimatePresence mode="wait">
          {breathingState === 'idle' ? (
            <motion.div
              key="idle"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              className="w-full flex flex-col items-center"
            >
              <div className="mb-8 flex justify-center">
                <motion.svg
                  width="64" height="64" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg"
                  animate={{ scale: [1, 1.1, 1] }}
                  transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
                >
                  <circle cx="32" cy="32" r="8" stroke="#8B9DC3" strokeWidth="1.5" opacity="0.9" />
                  <circle cx="32" cy="32" r="16" stroke="#8B9DC3" strokeWidth="1.2" opacity="0.6" />
                  <circle cx="32" cy="32" r="24" stroke="#8B9DC3" strokeWidth="1" opacity="0.4" />
                  <circle cx="32" cy="32" r="30" stroke="#8B9DC3" strokeWidth="0.8" opacity="0.2" />
                </motion.svg>
              </div>
              <h1 className="mb-3 text-4xl font-medium text-gray-800 text-center tracking-wide">
                Breathe
              </h1>
              <p className="mb-8 text-lg text-gray-600 text-center">
                Find your calm through guided breathing
              </p>

              <div className="mb-6 w-full max-w-sm">
                <label htmlFor="mood" className="block text-sm font-medium text-gray-700 mb-2 text-center">
                  How are you feeling? (Optional)
                </label>
                <input
                  type="text"
                  id="mood"
                  placeholder="Anxious, tired, stressed..."
                  value={mood}
                  onChange={(e) => setMood(e.target.value)}
                  className="w-full rounded-xl border border-gray-200 bg-white/50 px-4 py-3 text-gray-800 backdrop-blur-sm focus:border-cyan-500 focus:outline-none focus:ring-2 focus:ring-cyan-500/20 transition-all"
                />
              </div>

              <div className="mb-8 w-full max-w-sm">
                <div className="flex items-center justify-center mb-4 gap-3">
                  <label htmlFor="cycles" className="text-lg text-gray-700 font-bold">
                    Number of cycles
                  </label>
                  <span className="text-sm text-gray-500 font-medium">
                    {`${Math.floor(cycles * 16 / 60)}:${(cycles * 16 % 60).toString().padStart(2, '0')} total`}
                  </span>
                </div>
                <CycleDropdown value={cycles} onChange={setCycles} />
              </div>

              <button
                onClick={startExercise}
                disabled={isLoadingPrompts}
                className="w-full max-w-sm rounded-full bg-cyan-500 px-8 py-4 text-xl font-semibold text-white shadow-lg shadow-cyan-500/25 transition-all hover:scale-[1.02] hover:shadow-xl hover:shadow-cyan-500/30 active:scale-[0.98] focus:outline-none focus:ring-2 focus:ring-cyan-400 focus:ring-offset-2 disabled:opacity-70"
              >
                {isLoadingPrompts ? 'Preparing...' : 'Begin Session'}
              </button>
              <p className="mt-6 text-sm text-gray-500 text-center font-medium">
                Box breathing: Inhale • Hold • Exhale • Hold
              </p>
            </motion.div>
          ) : breathingState === 'completed' ? (
            <motion.div
              key="completed"
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className="flex flex-col items-center"
            >
              <div className="mt-8">
                <Balloon breathingState={breathingState} countdown={0} prompt={getPrompt(breathingState)} />
              </div>
              <button
                onClick={() => setBreathingState('idle')}
                className="mt-8 w-full max-w-xs rounded-xl bg-cyan-500 px-6 py-3 text-xl font-semibold text-white shadow-lg shadow-cyan-500/30 transition-transform hover:scale-[1.02] focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:ring-offset-2"
              >
                Back to Start
              </button>
            </motion.div>
          ) : (
            <motion.div
              key="active"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="w-full flex flex-col items-center"
            >
              <div className="absolute top-4 right-4 flex flex-col items-end gap-2 z-20">
                <div className="flex items-center bg-white/80 backdrop-blur-sm rounded-full px-4 py-2 shadow-md">
                  <button
                    onClick={stopExercise}
                    className="mr-3 text-gray-600 hover:text-gray-900"
                    aria-label="Stop breathing exercise"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 sm:h-6 sm:w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                  <span className="text-lg sm:text-xl font-semibold text-gray-800">
                    {`${minutesRemaining.toString().padStart(2, '0')}:${secondsRemaining.toString().padStart(2, '0')}`}
                  </span>
                </div>
                <AudioControls
                  volume={volume}
                  isMuted={isMuted}
                  onToggleMute={toggleMute}
                  onVolumeChange={updateVolume}
                />
              </div>
              <div className="mt-8">
                <Balloon breathingState={breathingState} countdown={countdown} prompt={getPrompt(breathingState)} />
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </main>
    </div>
  );
}
