import { useEffect, useState, useRef } from 'react';
import { View, Text, StyleSheet, Animated } from 'react-native';

type BalloonProps = {
  breathingState: 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';
  countdown: number;
  prompt: string;
};

const Balloon = ({ breathingState, countdown, prompt }: BalloonProps) => {
  const [displayText, setDisplayText] = useState(prompt);
  const [displayCountdown, setDisplayCountdown] = useState(countdown);
  const [previousBreathingState, setPreviousBreathingState] = useState(breathingState);

  const textOpacity = useRef(new Animated.Value(1)).current;
  const scale = useRef(new Animated.Value(1)).current;

  // Update countdown and text on any change
  useEffect(() => {
    let timeoutId: NodeJS.Timeout | null = null;
    let isCancelled = false;

    const updateText = () => {
      if (!isCancelled) {
        setDisplayText(prompt);

        if (countdown !== displayCountdown) {
          setDisplayCountdown(countdown);
        }

        // Fade in text
        Animated.timing(textOpacity, {
          toValue: 1,
          duration: 300,
          useNativeDriver: true,
        }).start();

        setPreviousBreathingState(breathingState);
      }
    };

    // Update text only when breathing state changes
    if (breathingState !== previousBreathingState) {
      // Fade out text
      Animated.timing(textOpacity, {
        toValue: 0,
        duration: 200,
        useNativeDriver: true,
      }).start(() => {
        if (!isCancelled) {
          timeoutId = setTimeout(updateText, 200);
        }
      });
    } else if (countdown !== displayCountdown) {
      setDisplayCountdown(countdown);
    }

    return () => {
      isCancelled = true;
      if (timeoutId) clearTimeout(timeoutId);
    };
  }, [breathingState, prompt, countdown, displayCountdown, previousBreathingState]);

  // Animate scale based on breathing state
  useEffect(() => {
    const targetScale = ['in', 'hold-in'].includes(breathingState) ? 2 : 1;

    Animated.timing(scale, {
      toValue: targetScale,
      duration: 4000,
      useNativeDriver: true,
    }).start();
  }, [breathingState]);

  const backgroundColor = ['idle'].includes(breathingState) ? '#ffffff' : '#06b6d4';
  const textColor = ['idle', 'completed'].includes(breathingState) ? '#1f2937' : '#ffffff';

  return (
    <Animated.View
      style={[
        styles.balloon,
        {
          backgroundColor,
          transform: [{ scale }],
        },
      ]}
    >
      <View style={styles.content}>
        <Animated.Text
          style={[
            styles.promptText,
            {
              color: textColor,
              opacity: textOpacity,
            },
          ]}
        >
          {displayText}
        </Animated.Text>
        {breathingState !== 'completed' && (
          <Animated.Text
            style={[
              styles.countdownText,
              {
                color: textColor,
                opacity: textOpacity,
              },
            ]}
          >
            {displayCountdown}
          </Animated.Text>
        )}
      </View>
    </Animated.View>
  );
};

const styles = StyleSheet.create({
  balloon: {
    width: 256,
    height: 256,
    borderRadius: 128,
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  promptText: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  countdownText: {
    fontSize: 48,
    fontWeight: 'bold',
    textAlign: 'center',
  },
});

export default Balloon;
