"use client";

import { motion, AnimatePresence } from 'framer-motion';

type BalloonProps = {
  breathingState: 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';
  countdown: number;
  prompt: string;
};

const Balloon = ({ breathingState, countdown, prompt }: BalloonProps) => {
  const balloonVariants = {
    idle: { scale: 1, backgroundColor: '#ffffff' },
    'pre-start': { scale: 1, backgroundColor: '#06b6d4' },
    in: { scale: 2, backgroundColor: '#06b6d4' },
    'hold-in': { scale: 2, backgroundColor: '#06b6d4' },
    out: { scale: 1, backgroundColor: '#06b6d4' },
    'hold-out': { scale: 1, backgroundColor: '#06b6d4' },
    completed: { scale: 1, backgroundColor: '#06b6d4' },
  };

  return (
    <motion.div
      variants={balloonVariants}
      animate={breathingState}
      transition={{
        duration: 4,
        ease: "easeInOut",
        backgroundColor: { duration: 0.5 }
      }}
      className="relative flex h-64 w-64 items-center justify-center rounded-full shadow-2xl sm:h-64 sm:w-64"
    >
      <div className="absolute flex flex-col items-center justify-center text-center px-4">
        <AnimatePresence mode="wait">
          <motion.span
            key={prompt}
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -5 }}
            transition={{ duration: 0.3 }}
            className={`text-2xl font-bold ${['idle', 'completed'].includes(breathingState) ? 'text-gray-800' : 'text-white'} text-center`}
          >
            {prompt}
          </motion.span>
        </AnimatePresence>

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
