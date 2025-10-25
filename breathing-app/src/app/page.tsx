"use client";

import { useState, useEffect } from 'react';
import Balloon from './components/Balloon';

type BreathingState = 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';

const promptMap: { [key in BreathingState]: string } = {
  'idle': '',
  'pre-start': 'Settle your mind',
  'in': 'Breathe in',
  'hold-in': 'Hold',
  'out': 'Breathe out',
  'hold-out': 'Hold',
  'completed': 'Be easy, breathe deeply',
};

export default function Home() {
  const [cycles, setCycles] = useState(6);
  const [breathingState, setBreathingState] = useState<BreathingState>('idle');
  const [countdown, setCountdown] = useState(0);
  const [currentCycle, setCurrentCycle] = useState(0);
  const [totalDuration, setTotalDuration] = useState(0);

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


  const startExercise = () => {
    setCurrentCycle(0);
    setBreathingState('pre-start');
    setCountdown(8);
    setTotalDuration(0);
  };

  const stopExercise = () => {
    setBreathingState('idle');
    setCurrentCycle(0);
    setTotalDuration(0);
  };

  const mainContainerClasses =
    breathingState === 'idle' || breathingState === 'completed'
      ? 'flex w-full max-w-md flex-col items-center justify-center rounded-2xl bg-white p-6 shadow-xl sm:p-8'
      : 'flex w-full flex-col items-center justify-center min-h-screen';

  const topContainerClasses =
    'flex min-h-screen flex-col items-center justify-center p-4 bg-gradient-to-br from-[#f0f9ff] via-[#e6f2ff] to-[#cce6ff]';

  // Calculate total session duration and remaining time
  const totalSessionDuration = cycles * 16; // 4 seconds * 4 phases * number of cycles
  const remainingTime = totalSessionDuration - totalDuration;
  const minutesRemaining = Math.floor(remainingTime / 60);
  const secondsRemaining = remainingTime % 60;

  return (
    <div className={topContainerClasses}>
      <main className={mainContainerClasses}>
        {breathingState === 'idle' ? (
          <>
            <div className="absolute top-6 left-6 bg-cyan-100/50 p-2 rounded-xl">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-6 h-6 text-cyan-600">
                <path fillRule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25zm.53 5.47a.75.75 0 00-1.06 0l-3 3a.75.75 0 101.06 1.06l1.72-1.72v5.69a.75.75 0 001.5 0v-5.69l1.72 1.72a.75.75 0 101.06-1.06l-3-3z" clipRule="evenodd" />
              </svg>
            </div>
            <h1 className="mb-2 text-4xl font-bold text-gray-800 text-center">
              Breathe Free
            </h1>
            <p className="mb-6 text-lg text-gray-600 text-center">
              Find your calm through guided breathing
            </p>
            <div className="mb-6 w-full max-w-xs">
              <div className="flex items-center justify-between mb-2">
                <label htmlFor="cycles" className="text-lg text-gray-700">
                  Number of cycles
                </label>
                <span className="text-gray-600">
                  {`${Math.floor(cycles * 16 / 60)}:${(cycles * 16 % 60).toString().padStart(2, '0')} total`}
                </span>
              </div>
              <select
                id="cycles"
                value={cycles}
                onChange={(e) => setCycles(Number(e.target.value))}
                className="w-full rounded-xl border-2 border-gray-200 p-2 text-lg text-gray-800 focus:ring-2 focus:ring-cyan-500"
              >
                {[...Array(10).keys()].map((i) => (
                  <option key={i + 1} value={i + 1}>
                    {i + 1}
                  </option>
                ))}
              </select>
            </div>
            <button
              onClick={startExercise}
              className="w-full max-w-xs rounded-xl bg-cyan-500 px-6 py-3 text-xl font-semibold text-white shadow-lg shadow-cyan-500/30 transition-transform hover:scale-[1.02] focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:ring-offset-2"
            >
              Begin Session
            </button>
            <p className="mt-4 text-sm text-gray-500 text-center">
              Box breathing: Inhale • Hold • Exhale • Hold
            </p>
          </>
        ) : breathingState === 'completed' ? (
          <>
            <div className="mt-8">
              <Balloon breathingState={breathingState} countdown={0} prompt={promptMap[breathingState]} />
            </div>
            <button
              onClick={() => setBreathingState('idle')}
              className="mt-4 flex items-center text-lg text-gray-600 hover:text-gray-900"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
              Back to Start
            </button>
          </>
        ) : (
          <>
            <div className="absolute top-4 right-4 flex items-center">
              <button 
                onClick={stopExercise}
                className="mr-4 text-gray-600 hover:text-gray-900"
                aria-label="Stop breathing exercise"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
              <span className="text-xl font-semibold">
                {`${minutesRemaining.toString().padStart(2, '0')}:${secondsRemaining.toString().padStart(2, '0')}`}
              </span>
            </div>
            <div className="mt-8">
              <Balloon breathingState={breathingState} countdown={countdown} prompt={promptMap[breathingState]} />
            </div>
          </>
        )}
      </main>
    </div>
  );
}
