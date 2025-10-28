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

  const handleVolumeClick = () => {
    setShowVolumeSlider(true);
  };

  const handleCloseSlider = () => {
    setShowVolumeSlider(false);
  };

  const handleVolumeChange = (newVolume: number) => {
    onVolumeChange(newVolume);
  };

  return (
    <div className="relative flex items-center justify-center gap-4 mt-4">
      {/* Mute/Unmute Toggle */}
      <button
        onClick={onToggleMute}
        className="p-2 rounded-lg bg-white/20 hover:bg-white/30 transition-colors"
        aria-label={isMuted ? 'Unmute' : 'Mute'}
      >
        {isMuted ? (
          // Muted icon
          <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 text-gray-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2" />
          </svg>
        ) : (
          // Unmuted icon
          <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 text-gray-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
          </svg>
        )}
      </button>

      {/* Volume Control */}
      <button
        onClick={handleVolumeClick}
        className="p-2 rounded-lg bg-white/20 hover:bg-white/30 transition-colors"
        aria-label="Volume control"
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 text-gray-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
        </svg>
      </button>

      {/* Volume Slider Overlay */}
      {showVolumeSlider && (
        <div
          className="fixed inset-0 flex items-center justify-center bg-black/30 z-50"
          onClick={handleCloseSlider}
        >
          <div
            className="bg-white rounded-2xl p-6 shadow-2xl flex flex-col items-center gap-4"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="text-lg font-semibold text-gray-800">Volume</div>

            {/* Vertical Slider */}
            <div className="relative h-48 w-12 flex items-center justify-center">
              <input
                type="range"
                min="0"
                max="100"
                value={volume * 100}
                onChange={(e) => handleVolumeChange(Number(e.target.value) / 100)}
                className="w-48 h-2 appearance-none bg-gray-200 rounded-lg cursor-pointer"
                style={{
                  transform: 'rotate(-90deg)',
                }}
                aria-label="Volume slider"
              />
            </div>

            <div className="text-sm text-gray-600">{Math.round(volume * 100)}%</div>
          </div>
        </div>
      )}
    </div>
  );
}
