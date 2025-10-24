"use client";

import { useEffect, useState } from 'react';

type BalloonProps = {
  breathingState: 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out';
  countdown: number;
};

const Balloon = ({ breathingState, countdown }: BalloonProps) => {
  const [scale, setScale] = useState(1);

  useEffect(() => {
    if (breathingState === 'in') {
      setScale(1.5);
    } else if (breathingState === 'out') {
      setScale(1);
    }
  }, [breathingState]);

  return (
    <div
      className="relative flex h-48 w-48 items-center justify-center rounded-full bg-blue-500 transition-transform duration-[4000ms] ease-in-out sm:h-64 sm:w-64"
      style={{ transform: `scale(${scale})` }}
    >
      <span className="text-4xl font-bold text-white sm:text-5xl">{countdown}</span>
    </div>
  );
};

export default Balloon;
