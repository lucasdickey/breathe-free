import { useEffect, useRef } from 'react';
import { View, StyleSheet, Animated, Dimensions } from 'react-native';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');

interface Cloud {
  id: number;
  left: number;
  topPercent: number;
  size: number;
  duration: number;
  delay: number;
  opacity: number;
}

const clouds: Cloud[] = [
  { id: 1, left: -150, topPercent: 20, size: 350, duration: 25000, delay: 0, opacity: 0.65 },
  { id: 2, left: -100, topPercent: 15, size: 180, duration: 30000, delay: 5000, opacity: 0.5 },
  { id: 3, left: -200, topPercent: 50, size: 280, duration: 28000, delay: 10000, opacity: 0.7 },
  { id: 4, left: -250, topPercent: 30, size: 420, duration: 35000, delay: 3000, opacity: 0.75 },
  { id: 5, left: -100, topPercent: 65, size: 240, duration: 26000, delay: 15000, opacity: 0.55 },
  { id: 6, left: -80, topPercent: 75, size: 160, duration: 22000, delay: 8000, opacity: 0.45 },
];

const CloudItem = ({ cloud }: { cloud: Cloud }) => {
  const position = useRef(new Animated.Value(cloud.left)).current;

  useEffect(() => {
    const animate = () => {
      position.setValue(cloud.left);
      Animated.sequence([
        Animated.delay(cloud.delay),
        Animated.timing(position, {
          toValue: SCREEN_WIDTH + 200,
          duration: cloud.duration,
          useNativeDriver: true,
        }),
      ]).start(() => animate());
    };

    animate();
  }, []);

  return (
    <Animated.View
      style={[
        styles.cloud,
        {
          top: (SCREEN_HEIGHT * cloud.topPercent) / 100,
          width: cloud.size,
          height: cloud.size / 2,
          opacity: cloud.opacity,
          transform: [{ translateX: position }],
        },
      ]}
    >
      <View style={[styles.cloudShape, { width: cloud.size, height: cloud.size / 2 }]} />
    </Animated.View>
  );
};

export default function CloudBackground() {
  return (
    <View style={styles.container} pointerEvents="none">
      {clouds.map((cloud) => (
        <CloudItem key={cloud.id} cloud={cloud} />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    overflow: 'hidden',
  },
  cloud: {
    position: 'absolute',
  },
  cloudShape: {
    backgroundColor: '#ffffff',
    borderRadius: 100,
    opacity: 0.7,
  },
});
