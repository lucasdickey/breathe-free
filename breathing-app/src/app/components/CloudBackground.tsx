import Image from 'next/image';

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
  { id: 1, left: '-15%', top: '20%', size: 350, duration: 25, delay: 0, rotation: 0, opacity: 0.45 },
  { id: 2, left: '110%', top: '15%', size: 180, duration: 30, delay: 5, rotation: 15, opacity: 0.3 },
  { id: 3, left: '-20%', top: '50%', size: 280, duration: 28, delay: 10, rotation: -10, opacity: 0.5 },
  { id: 4, left: '115%', top: '30%', size: 420, duration: 35, delay: 3, rotation: 8, opacity: 0.55 },
  { id: 5, left: '-10%', top: '65%', size: 240, duration: 26, delay: 15, rotation: -20, opacity: 0.35 },
  { id: 6, left: '105%', top: '75%', size: 160, duration: 22, delay: 8, rotation: 12, opacity: 0.25 },
  { id: 7, left: '-18%', top: '45%', size: 380, duration: 32, delay: 12, rotation: 5, opacity: 0.6 },
  { id: 8, left: '112%', top: '10%', size: 200, duration: 24, delay: 18, rotation: -15, opacity: 0.4 },
  { id: 9, left: '-12%', top: '80%', size: 320, duration: 29, delay: 6, rotation: 18, opacity: 0.48 },
  { id: 10, left: '108%', top: '55%', size: 150, duration: 20, delay: 14, rotation: -8, opacity: 0.28 },
  { id: 11, left: '-16%', top: '35%', size: 290, duration: 27, delay: 4, rotation: -12, opacity: 0.42 },
  { id: 12, left: '113%', top: '60%', size: 220, duration: 31, delay: 11, rotation: 10, opacity: 0.38 },
  { id: 13, left: '-14%', top: '8%', size: 360, duration: 33, delay: 7, rotation: 6, opacity: 0.52 },
  { id: 14, left: '107%', top: '42%', size: 190, duration: 23, delay: 16, rotation: -18, opacity: 0.32 },
  { id: 15, left: '-22%', top: '70%', size: 400, duration: 36, delay: 2, rotation: 14, opacity: 0.58 },
  { id: 16, left: '111%', top: '25%', size: 170, duration: 21, delay: 13, rotation: -5, opacity: 0.27 },
  { id: 17, left: '-11%', top: '90%', size: 260, duration: 25, delay: 9, rotation: 20, opacity: 0.46 },
  { id: 18, left: '109%', top: '5%', size: 340, duration: 34, delay: 17, rotation: -7, opacity: 0.54 },
  { id: 19, left: '-19%', top: '58%', size: 210, duration: 28, delay: 1, rotation: 16, opacity: 0.36 },
  { id: 20, left: '114%', top: '82%', size: 300, duration: 30, delay: 19, rotation: -14, opacity: 0.5 },
];

export default function CloudBackground() {
  return (
    <div className="fixed inset-0 overflow-hidden pointer-events-none" style={{ zIndex: 0 }}>
      {clouds.map((cloud) => (
        <div
          key={cloud.id}
          className="absolute"
          style={{
            left: cloud.left,
            top: cloud.top,
            width: `${cloud.size}px`,
            height: `${cloud.size / 2}px`,
            animation: `floatCloud${cloud.id} ${cloud.duration}s linear ${cloud.delay}s infinite`,
            transform: `rotate(${cloud.rotation}deg)`,
            opacity: cloud.opacity,
          }}
        >
          <Image
            src="/cloud.svg"
            alt=""
            width={cloud.size}
            height={cloud.size / 2}
            priority={cloud.id <= 3}
            loading={cloud.id <= 3 ? "eager" : "lazy"}
          />
        </div>
      ))}
    </div>
  );
}
