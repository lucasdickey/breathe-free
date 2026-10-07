"use client";

import { motion, MotionValue, useTransform } from 'framer-motion';

type BalloonProps = {
  breathingState: 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';
  countdown: number;
  prompt: string;
  /** The words before, fading out as `prompt` fades in. */
  previousPrompt: string;
  /** How full the lungs are, 0..1, straight from the session clock. */
  level: MotionValue<number>;
  /** How far the words have crossed from `previousPrompt` to `prompt`, 0..1, from the session clock. */
  fade: MotionValue<number>;
};

const Balloon = ({ breathingState, countdown, prompt, previousPrompt, level, fade }: BalloonProps) => {
  const balloonVariants = {
    idle: { backgroundColor: '#ffffff' },
    'pre-start': { backgroundColor: '#06b6d4' },
    in: { backgroundColor: '#06b6d4' },
    'hold-in': { backgroundColor: '#06b6d4' },
    out: { backgroundColor: '#06b6d4' },
    'hold-out': { backgroundColor: '#06b6d4' },
    completed: { backgroundColor: '#06b6d4' },
  };

  // The size is the breath itself, read every frame from the same curve the sound
  // swells with, rather than a tween started when the phase changes.
  const scale = useTransform(level, (l) => 1 + l);
  const fadingOut = useTransform(fade, (f) => 1 - f);
  const textColour = ['idle', 'completed'].includes(breathingState) ? 'text-gray-800' : 'text-white';

  return (
    <motion.div
      variants={balloonVariants}
      animate={breathingState}
      transition={{ backgroundColor: { duration: 0.5 } }}
      style={{ scale }}
      className="relative flex h-64 w-64 items-center justify-center rounded-full shadow-2xl sm:h-64 sm:w-64"
    >
      <div className="absolute flex flex-col items-center justify-center text-center px-4">
        {/* The words before fade out as the new ones fade in, both in the same place and both
            following the session clock, so nothing moves between them. */}
        <div className="grid place-items-center">
          <motion.span
            aria-hidden
            style={{ opacity: fadingOut, gridArea: '1 / 1' }}
            className={`text-2xl font-bold ${textColour} text-center`}
          >
            {previousPrompt}
          </motion.span>
          <motion.span
            aria-live="polite"
            style={{ opacity: fade, gridArea: '1 / 1' }}
            className={`text-2xl font-bold ${textColour} text-center`}
          >
            {prompt}
          </motion.span>
        </div>

        {breathingState !== 'completed' && breathingState !== 'idle' && (
          <motion.span
            key={countdown}
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            className={`text-5xl font-bold ${['idle', 'completed'].includes(breathingState) ? 'text-gray-800' : 'text-white'}`}
          >
            {countdown}
          </motion.span>
        )}
      </div>

      {/* Decorative pulse effect when holding */}
      {(breathingState === 'hold-in' || breathingState === 'hold-out') && (
        <motion.div
          className="absolute inset-0 rounded-full border-4 border-white/30"
          initial={{ scale: 1, opacity: 0.5 }}
          animate={{ scale: 1.1, opacity: 0 }}
          transition={{ duration: 1, repeat: Infinity, ease: "easeOut" }}
        />
      )}
    </motion.div>
  );
};

export default Balloon;
