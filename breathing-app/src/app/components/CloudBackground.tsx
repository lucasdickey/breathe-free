"use client";

import { useEffect, useRef } from 'react';

/**
 * Procedural cloud layer.
 *
 * Instead of pre-rendered assets, each cloud is a cluster of soft "puffs"
 * (a single shared radial-gradient sprite, drawn many times). Puff offsets
 * and radii are modulated by sums of incommensurate sine waves — a cheap,
 * smooth stand-in for noise — so the clouds slowly undulate and morph while
 * drifting across the sky with depth-based parallax.
 */

// Deterministic RNG so the sky looks the same on every visit.
function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Puff {
  dx: number; // offset from cloud center, in units of cloud size
  dy: number;
  r: number; // base radius, in units of cloud size
  alpha: number;
  // undulation: x/y sway and radius "breathing", two sine terms each
  ax1: number; wx1: number; px1: number;
  ax2: number; wx2: number; px2: number;
  ay1: number; wy1: number; py1: number;
  ar1: number; wr1: number; pr1: number;
  ar2: number; wr2: number; pr2: number;
}

interface Cloud {
  xFrac: number; // horizontal position as fraction of viewport width
  yFrac: number; // vertical position as fraction of viewport height
  depth: number; // 0 = far/small/slow, 1 = near/large/fast
  speed: number; // fraction of viewport width per second
  opacity: number;
  bobAmp: number; // whole-cloud vertical bob, in units of cloud size
  bobFreq: number;
  bobPhase: number;
  puffs: Puff[];
}

const CLOUD_COUNT = 9;
const MARGIN_FRAC = 0.22; // off-screen margin so clouds enter/exit fully formed

function makePuff(rand: () => number, spreadX: number): Puff {
  return {
    dx: (rand() * 2 - 1) * spreadX,
    dy: (rand() * 2 - 1) * 0.16,
    r: 0.22 + rand() * 0.2,
    alpha: 0.55 + rand() * 0.45,
    ax1: 0.015 + rand() * 0.03, wx1: 0.15 + rand() * 0.25, px1: rand() * Math.PI * 2,
    ax2: 0.008 + rand() * 0.015, wx2: 0.4 + rand() * 0.35, px2: rand() * Math.PI * 2,
    ay1: 0.012 + rand() * 0.025, wy1: 0.12 + rand() * 0.22, py1: rand() * Math.PI * 2,
    ar1: 0.04 + rand() * 0.05, wr1: 0.1 + rand() * 0.18, pr1: rand() * Math.PI * 2,
    ar2: 0.02 + rand() * 0.03, wr2: 0.3 + rand() * 0.3, pr2: rand() * Math.PI * 2,
  };
}

function makeCloud(rand: () => number, xFrac: number): Cloud {
  const depth = rand();
  const puffCount = 6 + Math.floor(rand() * 4);
  const puffs: Puff[] = [];
  for (let i = 0; i < puffCount; i++) {
    puffs.push(makePuff(rand, 0.55));
  }
  // A flatter puff along the bottom gives clouds their level base.
  puffs.push({ ...makePuff(rand, 0.35), dy: 0.16, r: 0.34, alpha: 0.8 });
  return {
    xFrac,
    yFrac: 0.06 + rand() * 0.74,
    depth,
    // Nearer clouds drift faster (parallax): ~45–110s to cross the screen.
    speed: (0.009 + depth * 0.013) * (rand() < 0.5 ? 1 : 1.15),
    opacity: 0.3 + depth * 0.45,
    bobAmp: 0.02 + rand() * 0.03,
    bobFreq: 0.03 + rand() * 0.05,
    bobPhase: rand() * Math.PI * 2,
    puffs,
  };
}

function makePuffSprite(): HTMLCanvasElement {
  const size = 256;
  const sprite = document.createElement('canvas');
  sprite.width = size;
  sprite.height = size;
  const sctx = sprite.getContext('2d')!;
  const g = sctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  // Roughly Gaussian falloff for a soft, cottony edge.
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.3, 'rgba(255,255,255,0.9)');
  g.addColorStop(0.55, 'rgba(255,255,255,0.55)');
  g.addColorStop(0.78, 'rgba(255,255,255,0.2)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  sctx.fillStyle = g;
  sctx.fillRect(0, 0, size, size);
  return sprite;
}

export default function CloudBackground() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const rand = mulberry32(20240607);
    const clouds: Cloud[] = [];
    for (let i = 0; i < CLOUD_COUNT; i++) {
      // Spread starting positions across the sky (including the wrap margin)
      // so it never starts empty and never bunches up.
      const xFrac = -MARGIN_FRAC + ((i + rand() * 0.8) / CLOUD_COUNT) * (1 + 2 * MARGIN_FRAC);
      clouds.push(makeCloud(rand, xFrac));
    }
    // Far clouds first so near ones layer on top.
    clouds.sort((a, b) => a.depth - b.depth);

    const sprite = makePuffSprite();

    let width = 0;
    let height = 0;
    const resize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    window.addEventListener('resize', resize);

    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const draw = (t: number) => {
      ctx.clearRect(0, 0, width, height);
      const sizeBase = Math.min(Math.max(width, 480), 1600);
      for (const cloud of clouds) {
        const size = sizeBase * (0.09 + cloud.depth * 0.13);
        const cx = cloud.xFrac * width;
        const cy =
          cloud.yFrac * height +
          Math.sin(t * cloud.bobFreq * 2 * Math.PI + cloud.bobPhase) * cloud.bobAmp * size;
        for (const p of cloud.puffs) {
          const px =
            cx +
            (p.dx + p.ax1 * Math.sin(t * p.wx1 + p.px1) + p.ax2 * Math.sin(t * p.wx2 + p.px2)) *
              size;
          const py = cy + (p.dy + p.ay1 * Math.sin(t * p.wy1 + p.py1)) * size;
          const pr =
            (p.r * (1 + p.ar1 * Math.sin(t * p.wr1 + p.pr1) + p.ar2 * Math.sin(t * p.wr2 + p.pr2))) *
            size;
          ctx.globalAlpha = cloud.opacity * p.alpha;
          ctx.drawImage(sprite, px - pr, py - pr, pr * 2, pr * 2);
        }
      }
      ctx.globalAlpha = 1;
    };

    let raf = 0;
    let lastTs = performance.now();
    let t = rand() * 100; // start mid-flow, not at everyone's sine zero-crossing

    if (reducedMotion) {
      draw(t);
    } else {
      const frame = (ts: number) => {
        // Clamp dt so a backgrounded tab doesn't teleport the sky on return.
        const dt = Math.min((ts - lastTs) / 1000, 0.1);
        lastTs = ts;
        t += dt;
        for (const cloud of clouds) {
          cloud.xFrac += cloud.speed * dt;
          if (cloud.xFrac > 1 + MARGIN_FRAC) {
            cloud.xFrac = -MARGIN_FRAC;
            cloud.yFrac = 0.06 + rand() * 0.74; // re-enter at a fresh altitude
          }
        }
        draw(t);
        raf = requestAnimationFrame(frame);
      };
      raf = requestAnimationFrame(frame);
    }

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', resize);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className="fixed inset-0 pointer-events-none"
      style={{ zIndex: 0 }}
      aria-hidden="true"
    />
  );
}
