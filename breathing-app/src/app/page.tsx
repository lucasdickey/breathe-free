"use client";

import { useState, useEffect } from 'react';
import Balloon from './components/Balloon';

type BreathingState = 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out';

const promptMap: { [key in BreathingState]: string } = {
  'idle': '',
  'pre-start': 'Get ready...',
  'in': 'Breathe in',
  'hold-in': 'Hold',
  'out': 'Breathe out',
  'hold-out': 'Hold',
};

export default function Home() {
  const [cycles, setCycles] = useState(1);
  const [breathingState, setBreathingState] = useState<BreathingState>('idle');
  const [countdown, setCountdown] = useState(0);
  const [currentCycle, setCurrentCycle] = useState(0);

  useEffect(() => {
    if (breathingState === 'idle') {
      return;
    }

    if (currentCycle >= cycles && breathingState !== 'pre-start') {
      setBreathingState('idle');
      setCurrentCycle(0);
      return;
    }

    const interval = setInterval(() => {
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
            setCurrentCycle(currentCycle + 1);
            if (currentCycle + 1 < cycles) {
              setBreathingState('in');
            } else {
              setBreathingState('idle');
            }
            return 4;
        }
        return 0;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [breathingState, cycles, currentCycle]);


  const startExercise = () => {
    setCurrentCycle(0);
    setBreathingState('pre-start');
    setCountdown(8);
  };

  const mainContainerClasses =
    breathingState === 'idle'
      ? 'flex w-full max-w-md flex-col items-center justify-center rounded-lg bg-white p-6 shadow-lg sm:p-8'
      : 'flex w-full flex-col items-center justify-start pt-20 sm:max-w-md sm:justify-center sm:rounded-lg sm:bg-white sm:pt-0 sm:p-8 sm:shadow-lg';

  const topContainerClasses =
    breathingState === 'idle'
      ? 'flex min-h-screen flex-col items-center justify-center bg-gray-50 p-4'
      : 'flex min-h-screen flex-col items-center bg-gray-50 p-4';

  return (
    <div className={topContainerClasses}>
      <main className={mainContainerClasses}>
        <h1
          className={`mb-4 text-3xl font-bold sm:text-4xl ${
            breathingState !== 'idle' ? 'sm:block' : ''
          }`}
        >
          Box Breathing
        </h1>
        {breathingState === 'idle' ? (
          <>
            <div className="mb-6">
              <label htmlFor="cycles" className="mr-2 text-lg">
                Number of cycles:
              </label>
              <select
                id="cycles"
                value={cycles}
                onChange={(e) => setCycles(Number(e.target.value))}
                className="rounded-md border-2 border-gray-300 p-2 text-lg"
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
              className="rounded-full bg-blue-500 px-6 py-3 text-xl font-semibold text-white shadow-md transition-transform hover:scale-105"
            >
              Start
            </button>
          </>
        ) : (
          <div className="mt-8">
            <Balloon breathingState={breathingState} countdown={countdown} prompt={promptMap[breathingState]} />
          </div>
        )}
      </main>
    </div>
  );
}
