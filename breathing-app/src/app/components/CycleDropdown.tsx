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
        className="w-full rounded-xl border-2 border-gray-200 bg-white p-3 text-lg text-gray-800 hover:border-gray-300 focus:outline-none focus:ring-2 focus:ring-cyan-500 flex items-center justify-between transition-colors"
      >
        <span>{value}</span>
        <svg
          className={`w-5 h-5 text-gray-600 transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute z-50 w-full mt-2 bg-white rounded-xl border-2 border-gray-200 shadow-xl overflow-hidden">
          {cycleOptions.map((option) => (
            <button
              key={option}
              type="button"
              onClick={() => handleSelect(option)}
              className={`w-full p-3 text-lg text-left hover:bg-cyan-50 transition-colors ${
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
