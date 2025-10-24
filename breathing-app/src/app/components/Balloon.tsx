"use client";

import { useEffect, useState } from 'react';

type BalloonProps = {
  breathingState: 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out';
  countdown: number;
  prompt: string;
};

const Balloon = ({ breathingState, countdown, prompt }: BalloonProps) => {
  const [scale, setScale] = useState(1);

  useEffect(() => {
    if (breathingState === 'in') {
      setScale(2);
    } else if (breathingState === 'out') {
      setScale(1);
    }
  }, [breathingState]);

  return (
    <div
      className="relative flex h-64 w-64 items-center justify-center rounded-full bg-blue-500 transition-transform duration-[4000ms] ease-in-out sm:h-64 sm:w-64"
      style={{ transform: `scale(${scale})` }}
    >
      <div className="absolute flex flex-col items-center justify-center">
        <span className="text-2xl font-bold text-white sm:text-2xl">{prompt}</span>
        <span className="text-5xl font-bold text-white sm:text-5xl">{countdown}</span>
      </div>
    </div>
  );
};

export default Balloon;
