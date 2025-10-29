'use client';

import { useState, useRef, useEffect } from 'react';

interface CycleDropdownProps {
  value: number;
  onChange: (value: number) => void;
}

const cycleOptions = [2, 6, 10, 20, 36, 50];

export default function CycleDropdown({ value, onChange }: CycleDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = (option: number) => {
    onChange(option);
    setIsOpen(false);
  };

  return (
    <div ref={dropdownRef} className="relative w-full">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="w-full rounded-2xl border border-gray-200 bg-white/80 backdrop-blur-sm px-6 py-4 text-xl text-gray-800 hover:border-gray-300 hover:bg-white/90 focus:outline-none focus:ring-2 focus:ring-cyan-400 focus:ring-offset-2 flex items-center justify-between transition-all min-h-[56px]"
      >
        <span>{value}</span>
        <svg
          className={`w-5 h-5 text-gray-500 transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute z-50 w-full mt-2 bg-white/95 backdrop-blur-xl rounded-2xl border border-gray-200 shadow-2xl overflow-hidden">
          {cycleOptions.map((option) => (
            <button
              key={option}
              type="button"
              onClick={() => handleSelect(option)}
              className={`w-full px-6 py-4 text-xl text-left hover:bg-cyan-50 transition-all ${
                value === option ? 'bg-cyan-100 text-cyan-700 font-semibold' : 'text-gray-800'
              }`}
            >
              {option}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
