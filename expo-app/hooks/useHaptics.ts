import { useEffect } from 'react';
import * as Haptics from 'expo-haptics';

type BreathingState = 'idle' | 'pre-start' | 'in' | 'hold-in' | 'out' | 'hold-out' | 'completed';

export function useHaptics(breathingState: BreathingState) {
  useEffect(() => {
    const triggerHaptic = async () => {
      try {
        switch (breathingState) {
          case 'pre-start':
            // Light notification for starting
            await Haptics.notificationAsync(
              Haptics.NotificationFeedbackType.Success
            );
            break;

          case 'in':
            // Medium impact for breathing in
            await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
            break;

          case 'hold-in':
            // Light impact for holding
            await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
            break;

          case 'out':
            // Medium impact for breathing out
            await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
            break;

          case 'hold-out':
            // Light impact for holding
            await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
            break;

          case 'completed':
            // Success notification for completion
            await Haptics.notificationAsync(
              Haptics.NotificationFeedbackType.Success
            );
            break;

          case 'idle':
            // No haptic feedback for idle state
            break;
        }
      } catch (error) {
        console.error('Error triggering haptic feedback:', error);
      }
    };

    if (breathingState !== 'idle') {
      triggerHaptic();
    }
  }, [breathingState]);
}
