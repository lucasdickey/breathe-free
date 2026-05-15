"use client";

import Image from 'next/image';
import { motion } from 'framer-motion';

interface Cloud {
  id: number;
  left: string;
  top: string;
  size: number;
  duration: number;
  delay: number;
  rotation: number;
  opacity: number;
}

const clouds: Cloud[] = [
  { id: 1, left: '-15%', top: '20%', size: 350, duration: 25, delay: 0, rotation: 0, opacity: 0.65 },
  { id: 2, left: '110%', top: '15%', size: 180, duration: 30, delay: 5, rotation: 15, opacity: 0.5 },
  { id: 3, left: '-20%', top: '50%', size: 280, duration: 28, delay: 10, rotation: -10, opacity: 0.7 },
  { id: 4, left: '115%', top: '30%', size: 420, duration: 35, delay: 3, rotation: 8, opacity: 0.75 },
  { id: 5, left: '-10%', top: '65%', size: 240, duration: 26, delay: 15, rotation: -20, opacity: 0.55 },
  { id: 6, left: '105%', top: '75%', size: 160, duration: 22, delay: 8, rotation: 12, opacity: 0.45 },
  { id: 7, left: '-18%', top: '45%', size: 380, duration: 32, delay: 12, rotation: 5, opacity: 0.8 },
  { id: 8, left: '112%', top: '10%', size: 200, duration: 24, delay: 18, rotation: -15, opacity: 0.6 },
  { id: 9, left: '-12%', top: '80%', size: 320, duration: 29, delay: 6, rotation: 18, opacity: 0.68 },
  { id: 10, left: '108%', top: '55%', size: 150, duration: 20, delay: 14, rotation: -8, opacity: 0.48 },
];

export default function CloudBackground() {
  return (
    <div className="fixed inset-0 overflow-hidden pointer-events-none" style={{ zIndex: 0 }}>
      {clouds.map((cloud) => (
        <motion.div
          key={cloud.id}
          className="absolute"
          initial={{
            x: cloud.left.startsWith('-') ? '-20%' : '120%',
            y: cloud.top,
            rotate: cloud.rotation,
            opacity: 0
          }}
          animate={{
            x: cloud.left.startsWith('-') ? '120vw' : '-20vw',
            opacity: cloud.opacity
          }}
          transition={{
            duration: cloud.duration,
            repeat: Infinity,
            delay: cloud.delay,
            ease: "linear"
          }}
          style={{
            width: `${cloud.size}px`,
            height: `${cloud.size / 2}px`,
          }}
        >
          <Image
            src="/cloud.svg"
            alt=""
            width={cloud.size}
            height={cloud.size / 2}
            priority={cloud.id <= 3}
          />
        </motion.div>
      ))}
    </div>
  );
}
