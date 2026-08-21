import { useEffect, useMemo, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Animated,
  Easing,
  StyleSheet,
  View,
  useWindowDimensions,
} from 'react-native';
import Svg, { Defs, RadialGradient, Stop, Circle } from 'react-native-svg';

/**
 * Procedural cloud layer.
 *
 * Each cloud is a cluster of soft radial-gradient puffs rather than a sprite,
 * so nothing is pre-rendered. Motion is layered from slow loops of different,
 * deliberately incommensurate periods — drift, whole-cloud bob, and per-group
 * puff sway — which never realign, giving continuous undulation instead of a
 * visible repeat. Every animation is transform-only and runs on the native
 * driver, so the JS thread stays free for the breathing timer.
 */

// Deterministic RNG so the sky is identical on every launch.
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
  cx: number; // fraction of cloud width
  cy: number; // fraction of cloud height
  r: number; // fraction of cloud width
  opacity: number;
  group: 0 | 1 | 2; // which sway group this puff belongs to
}

interface CloudSpec {
  id: number;
  yFrac: number;
  depth: number; // 0 = far/small/slow, 1 = near/large/fast
  driftSeconds: number;
  startOffset: number; // 0..1 through its own crossing
  opacity: number;
  bobSeconds: number;
  bobAmount: number;
  puffs: Puff[];
}

const CLOUD_COUNT = 7;
const GROUP_PERIODS = [9200, 12700, 16300]; // ms — mutually non-repeating

function buildClouds(): CloudSpec[] {
  const rand = mulberry32(20240607);
  const clouds: CloudSpec[] = [];

  for (let i = 0; i < CLOUD_COUNT; i++) {
    const depth = rand();
    const puffCount = 5 + Math.floor(rand() * 3);
    const puffs: Puff[] = [];

    for (let p = 0; p < puffCount; p++) {
      puffs.push({
        cx: 0.22 + rand() * 0.56,
        cy: 0.4 + (rand() * 2 - 1) * 0.16,
        r: 0.17 + rand() * 0.13,
        opacity: 0.7 + rand() * 0.3,
        group: Math.floor(rand() * 3) as 0 | 1 | 2,
      });
    }
    // A flatter, wider puff along the base gives clouds their level underside.
    puffs.push({ cx: 0.5, cy: 0.56, r: 0.26, opacity: 0.9, group: 0 });

    clouds.push({
      id: i,
      yFrac: 0.05 + rand() * 0.72,
      depth,
      // Nearer clouds cross faster: roughly 55s (far) to 30s (near).
      driftSeconds: 55 - depth * 25,
      startOffset: (i + rand() * 0.7) / CLOUD_COUNT,
      opacity: 0.5 + depth * 0.42,
      bobSeconds: 14 + rand() * 11,
      bobAmount: 6 + rand() * 10,
      puffs,
    });
  }

  return clouds.sort((a, b) => a.depth - b.depth); // far clouds drawn first
}

/** A looping 0->1 driver used to build every motion in this file. */
function useLoop(durationMs: number, enabled: boolean, startAt = 0) {
  const value = useRef(new Animated.Value(startAt)).current;

  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;

    const runFrom = (from: number) => {
      if (cancelled) return;
      value.setValue(from);
      Animated.timing(value, {
        toValue: 1,
        // Shorten only the first pass so the phase offset is honoured without
        // ever re-introducing a pause between passes.
        duration: durationMs * (1 - from),
        easing: Easing.linear,
        useNativeDriver: true,
      }).start(({ finished }) => {
        if (finished && !cancelled) runFrom(0);
      });
    };

    runFrom(startAt);
    return () => {
      cancelled = true;
      value.stopAnimation();
    };
  }, [durationMs, enabled, startAt, value]);

  return value;
}

function PuffGroup({
  cloud,
  group,
  width,
  height,
  animate,
}: {
  cloud: CloudSpec;
  group: 0 | 1 | 2;
  width: number;
  height: number;
  animate: boolean;
}) {
  const puffs = cloud.puffs.filter((p) => p.group === group);
  const phase = ((cloud.id + group) % 3) / 3;
  const t = useLoop(GROUP_PERIODS[group], animate, phase);

  // Each group slides and breathes on its own period, so the cluster's outline
  // keeps changing shape as the groups pass through each other.
  const translateX = t.interpolate({
    inputRange: [0, 0.25, 0.5, 0.75, 1],
    outputRange: [0, width * 0.03, 0, -width * 0.03, 0],
  });
  const translateY = t.interpolate({
    inputRange: [0, 0.33, 0.66, 1],
    outputRange: [0, height * 0.05, -height * 0.04, 0],
  });
  const scale = t.interpolate({
    inputRange: [0, 0.5, 1],
    outputRange: [1, 1.07, 1],
  });

  if (puffs.length === 0) return null;

  return (
    <Animated.View
      style={[
        StyleSheet.absoluteFill,
        { transform: [{ translateX }, { translateY }, { scale }] },
      ]}
      pointerEvents="none"
    >
      <Svg width={width} height={height}>
        <Defs>
          <RadialGradient id={`puff-${cloud.id}-${group}`} cx="50%" cy="50%" r="50%">
            <Stop offset="0%" stopColor="#ffffff" stopOpacity={1} />
            <Stop offset="32%" stopColor="#ffffff" stopOpacity={0.94} />
            <Stop offset="58%" stopColor="#ffffff" stopOpacity={0.62} />
            <Stop offset="80%" stopColor="#ffffff" stopOpacity={0.24} />
            <Stop offset="100%" stopColor="#ffffff" stopOpacity={0} />
          </RadialGradient>
        </Defs>
        {puffs.map((p, i) => (
          <Circle
            key={i}
            cx={p.cx * width}
            cy={p.cy * height}
            r={p.r * width}
            fill={`url(#puff-${cloud.id}-${group})`}
            opacity={p.opacity}
          />
        ))}
      </Svg>
    </Animated.View>
  );
}

function Cloud({
  cloud,
  screenWidth,
  screenHeight,
  animate,
}: {
  cloud: CloudSpec;
  screenWidth: number;
  screenHeight: number;
  animate: boolean;
}) {
  const width = Math.min(Math.max(screenWidth, 320), 900) * (0.55 + cloud.depth * 0.5);
  const height = width * 0.55;

  const drift = useLoop(cloud.driftSeconds * 1000, animate, cloud.startOffset);
  const bob = useLoop(cloud.bobSeconds * 1000, animate, cloud.startOffset);

  const translateX = drift.interpolate({
    inputRange: [0, 1],
    outputRange: [-width, screenWidth + width * 0.2],
  });
  const translateY = bob.interpolate({
    inputRange: [0, 0.5, 1],
    outputRange: [0, cloud.bobAmount, 0],
  });

  return (
    <Animated.View
      style={{
        position: 'absolute',
        top: cloud.yFrac * screenHeight,
        left: 0,
        width,
        height,
        opacity: cloud.opacity,
        transform: [{ translateX }, { translateY }],
      }}
      pointerEvents="none"
    >
      {([0, 1, 2] as const).map((g) => (
        <PuffGroup
          key={g}
          cloud={cloud}
          group={g}
          width={width}
          height={height}
          animate={animate}
        />
      ))}
    </Animated.View>
  );
}

export default function CloudBackground() {
  const { width, height } = useWindowDimensions();
  const clouds = useMemo(buildClouds, []);
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceMotionEnabled()
      .then((enabled) => {
        if (mounted) setReduceMotion(enabled);
      })
      .catch(() => {
        // Default to animating if the preference can't be read.
      });

    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', (enabled) =>
      setReduceMotion(enabled)
    );
    return () => {
      mounted = false;
      sub.remove();
    };
  }, []);

  return (
    <View style={styles.container} pointerEvents="none">
      {clouds.map((cloud) => (
        <Cloud
          key={cloud.id}
          cloud={cloud}
          screenWidth={width}
          screenHeight={height}
          animate={!reduceMotion}
        />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    overflow: 'hidden',
  },
});
