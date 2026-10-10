"use client";

import { useEffect, useState } from 'react';

// How long "End session" stays open for its second click, and how soon after opening it listens.
const OPEN_MS = 4000;
const READY_MS = 300;

/**
 * The ✕ that ends a session, in two steps so a stray click can't: clicked, it opens into
 * "End session", and a click on that ends it. Left alone it closes again, and a second click
 * too quick to be meant (a double click on the ✕) does nothing.
 */
export default function EndSessionButton({ onEnd }: { onEnd: () => void }) {
  // When it opened (performance.now()), or null while it is just the ✕.
  const [openedAt, setOpenedAt] = useState<number | null>(null);
  const open = openedAt !== null;

  useEffect(() => {
    if (openedAt === null) return;
    const close = setTimeout(() => setOpenedAt(null), OPEN_MS);
    return () => clearTimeout(close);
  }, [openedAt]);

  const click = () => {
    const now = performance.now();
    if (openedAt === null) setOpenedAt(now);
    else if (now - openedAt >= READY_MS) onEnd();
  };

  return (
    <button
      type="button"
      onClick={click}
      aria-label={open ? 'Click again to end the session' : 'End session'}
      title={open ? 'Click again to end the session' : 'End session'}
      className="flex h-11 items-center rounded-full bg-white/80 px-3 text-gray-700 shadow-md backdrop-blur-sm transition-colors hover:bg-white hover:text-gray-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
    >
      {/* The words slide open beside the ✕, so the button grows rather than jumps. */}
      <span
        aria-hidden
        className={`overflow-hidden whitespace-nowrap text-sm font-semibold transition-all duration-200 ease-out sm:text-base ${
          open ? 'mr-1.5 max-w-[8rem] opacity-100' : 'max-w-0 opacity-0'
        }`}
      >
        End session
      </span>
      <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeWidth={2} d="M6 6l12 12M18 6 6 18" />
      </svg>
    </button>
  );
}
