"use client";

import { useEffect, useState } from 'react';

type BalloonProps = {
  breathingState: 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';
  countdown: number;
  prompt: string;
};

const Balloon = ({ breathingState, countdown, prompt }: BalloonProps) => {
  const [displayText, setDisplayText] = useState(prompt);
  const [displayCountdown, setDisplayCountdown] = useState(countdown);
  const [textOpacity, setTextOpacity] = useState(1);
  const [previousBreathingState, setPreviousBreathingState] = useState(breathingState);
  const [, setScale] = useState(1);

  // Update countdown and text on any change
  useEffect(() => {
    let timeoutId: NodeJS.Timeout | null = null;
    let isCancelled = false;

    const updateText = () => {
      if (!isCancelled) {
        // Update scale state
        setScale((prevScale) => {
          switch (breathingState) {
            case 'in':
            case 'hold-in':
              return 2;
            case 'out':
            case 'hold-out':
              return 1;
            default:
              return prevScale;
          }
        });
        
        // Update text
        setDisplayText(prompt);
        
        // Update countdown only if necessary
        Promise.resolve().then(() => {
          if (!isCancelled && countdown !== displayCountdown) {
            setDisplayCountdown(countdown);
          }
        });
        
        // Fade in text
        setTextOpacity(1);

        // Update previous state
        setPreviousBreathingState(breathingState);
      }
    };

    // Update text only when breathing state changes
    if (breathingState !== previousBreathingState) {
      // Fade out text using microtask to prevent synchronous state update
      Promise.resolve().then(() => {
        if (!isCancelled) {
          setTextOpacity(0);

          // After fade out, update text and fade in
          timeoutId = setTimeout(updateText, 200);
        }
      });
    } else if (countdown !== displayCountdown) {
      // Update countdown if changed and no state transition
      Promise.resolve().then(() => {
        if (!isCancelled) {
          setDisplayCountdown(countdown);
        }
      });
    }

    return () => {
      isCancelled = true;
      if (timeoutId) clearTimeout(timeoutId);
    };
  }, [breathingState, prompt, countdown, displayCountdown, previousBreathingState]);

  const balloonClasses = {
    'idle': 'bg-white',
    'pre-start': 'bg-cyan-500',
    'in': 'bg-cyan-500',
    'hold-in': 'bg-cyan-500',
    'out': 'bg-cyan-500',
    'hold-out': 'bg-cyan-500',
    'completed': 'bg-cyan-500',
  }[breathingState];

  return (
    <div
      className={`relative flex h-64 w-64 items-center justify-center rounded-full transition-transform duration-[4000ms] ease-in-out sm:h-64 sm:w-64 ${balloonClasses}`}
      style={{ 
        transform: ['in', 'hold-in'].includes(breathingState) ? `scale(2)` : 
                   ['out', 'hold-out'].includes(breathingState) ? `scale(1)` : 
                   breathingState === 'completed' ? `scale(1)` : 
                   `scale(1)` 
      }}
    >
      <div className="absolute flex flex-col items-center justify-center">
        <span 
          className={`text-2xl font-bold transition-opacity duration-300 ease-in-out ${['idle', 'completed'].includes(breathingState) ? 'text-gray-800' : 'text-white'} sm:text-2xl`}
          style={{ opacity: textOpacity }}
        >
          {displayText}
        </span>
        {breathingState !== 'completed' && (
          <span 
            className={`text-5xl font-bold transition-opacity duration-300 ease-in-out ${['idle', 'completed'].includes(breathingState) ? 'text-gray-800' : 'text-white'} sm:text-5xl`}
            style={{ opacity: textOpacity }}
          >
            {displayCountdown}
          </span>
        )}
      </div>
    </div>
  );
};

export default Balloon;
