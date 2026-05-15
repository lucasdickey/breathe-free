"use client";

import { motion, AnimatePresence } from 'framer-motion';
import { useState } from 'react';

interface AudioControlsProps {
  volume: number;
  isMuted: boolean;
  onToggleMute: () => void;
  onVolumeChange: (volume: number) => void;
}

export default function AudioControls({
  volume,
  isMuted,
  onToggleMute,
  onVolumeChange,
}: AudioControlsProps) {
  const [showVolumeSlider, setShowVolumeSlider] = useState(false);

  return (
    <div className="relative flex items-center gap-2">
      {/* Mute/Unmute Toggle */}
      <motion.button
        whileHover={{ scale: 1.1 }}
        whileTap={{ scale: 0.9 }}
        onClick={onToggleMute}
        className="p-3 rounded-full bg-white/40 backdrop-blur-md hover:bg-white/60 transition-colors shadow-sm"
        aria-label={isMuted ? 'Unmute' : 'Mute'}
      >
        {isMuted ? (
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-gray-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2" />
          </svg>
        ) : (
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-gray-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
          </svg>
        )}
      </motion.button>

      {/* Volume Control Toggle */}
      <motion.button
        whileHover={{ scale: 1.1 }}
        whileTap={{ scale: 0.9 }}
        onClick={() => setShowVolumeSlider(!showVolumeSlider)}
        className="p-3 rounded-full bg-white/40 backdrop-blur-md hover:bg-white/60 transition-colors shadow-sm"
        aria-label="Volume control"
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-gray-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
        </svg>
      </motion.button>

      {/* Volume Slider Overlay */}
      <AnimatePresence>
        {showVolumeSlider && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 z-40 bg-black/5"
              onClick={() => setShowVolumeSlider(false)}
            />
            <motion.div
              initial={{ opacity: 0, scale: 0.9, y: 10 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.9, y: 10 }}
              className="absolute right-0 top-16 bg-white/90 backdrop-blur-xl rounded-2xl p-4 shadow-2xl z-50 flex flex-col items-center gap-4 min-w-[60px]"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="relative h-32 w-2 flex items-center justify-center">
                <input
                  type="range"
                  min="0"
                  max="100"
                  value={volume * 100}
                  onChange={(e) => onVolumeChange(Number(e.target.value) / 100)}
                  className="w-32 h-1 appearance-none bg-gray-200 rounded-full cursor-pointer accent-cyan-500"
                  style={{ transform: 'rotate(-90deg)' }}
                  aria-label="Volume slider"
                />
              </div>
              <div className="text-xs font-bold text-gray-500">{Math.round(volume * 100)}%</div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}
