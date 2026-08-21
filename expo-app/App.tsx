import { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  SafeAreaView,
  StatusBar,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Balloon from './components/Balloon';
import AudioControls from './components/AudioControls';
import CloudBackground from './components/CloudBackground';
import CycleDropdown from './components/CycleDropdown';
import { useBreathingSession, BreathingPhase, CYCLE_SECONDS } from './hooks/useBreathingSession';
import { useHaptics } from './hooks/useHaptics';
import Svg, { Circle, Path } from 'react-native-svg';

const promptMap: { [key in BreathingPhase]: string } = {
  'idle': '',
  'pre-start': 'Settle your mind',
  'in': 'Breathe in',
  'hold-in': 'Hold',
  'out': 'Breathe out',
  'hold-out': 'Hold',
  'completed': 'Be easy\nBreathe deeply',
};

const BreathIcon = () => (
  <Svg width="64" height="64" viewBox="0 0 64 64" fill="none">
    <Circle cx="32" cy="32" r="8" stroke="#8B9DC3" strokeWidth="1.5" opacity="0.9" />
    <Circle cx="32" cy="32" r="16" stroke="#8B9DC3" strokeWidth="1.2" opacity="0.6" />
    <Circle cx="32" cy="32" r="24" stroke="#8B9DC3" strokeWidth="1" opacity="0.4" />
    <Circle cx="32" cy="32" r="30" stroke="#8B9DC3" strokeWidth="0.8" opacity="0.2" />
  </Svg>
);

const CloseIcon = () => (
  <Svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#4b5563" strokeWidth={2}>
    <Path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
  </Svg>
);

export default function App() {
  const [cycles, setCycles] = useState(6);

  const {
    phase,
    countdown,
    remainingSeconds,
    start,
    stop,
    volume,
    isMuted,
    toggleMute,
    updateVolume,
  } = useBreathingSession();

  // Haptics follow the phase the engine reports, so they land on the same
  // boundaries as the visuals and the audio loop.
  useHaptics(phase);

  const startExercise = () => start(cycles);
  const stopExercise = () => stop();

  const minutesRemaining = Math.floor(remainingSeconds / 60);
  const secondsRemaining = remainingSeconds % 60;

  const isActiveState = phase !== 'idle' && phase !== 'completed';

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar barStyle="dark-content" />
      <LinearGradient
        colors={['#f0f9ff', '#e6f2ff', '#cce6ff']}
        style={styles.gradient}
      >
        <CloudBackground />

        {isActiveState ? (
          <View style={styles.activeContainer}>
            <View style={styles.topBar}>
              <View style={styles.timerContainer}>
                <TouchableOpacity
                  onPress={stopExercise}
                  style={styles.closeButton}
                  accessibilityLabel="Stop breathing exercise"
                >
                  <CloseIcon />
                </TouchableOpacity>
                <Text style={styles.timerText}>
                  {`${minutesRemaining.toString().padStart(2, '0')}:${secondsRemaining.toString().padStart(2, '0')}`}
                </Text>
              </View>
              <AudioControls
                volume={volume}
                isMuted={isMuted}
                onToggleMute={toggleMute}
                onVolumeChange={updateVolume}
              />
            </View>
            <View style={styles.balloonWrapper}>
              <Balloon
                breathingState={phase}
                countdown={countdown}
                prompt={promptMap[phase]}
              />
            </View>
          </View>
        ) : (
          <ScrollView
            contentContainerStyle={styles.scrollContent}
            showsVerticalScrollIndicator={false}
          >
            <View style={styles.idleContainer}>
              {phase === 'idle' ? (
                <>
                  <View style={styles.iconContainer}>
                    <BreathIcon />
                  </View>
                  <Text style={styles.title}>Breathe</Text>
                  <Text style={styles.subtitle}>Find your calm through guided breathing</Text>

                  <View style={styles.cycleSection}>
                    <Text style={styles.cycleLabel}>
                      Number of cycles
                      <Text style={styles.cycleTotal}>
                        {`   ${Math.floor((cycles * CYCLE_SECONDS) / 60)}:${((cycles * CYCLE_SECONDS) % 60).toString().padStart(2, '0')} total`}
                      </Text>
                    </Text>
                    <CycleDropdown value={cycles} onChange={setCycles} />
                  </View>

                  <TouchableOpacity
                    onPress={startExercise}
                    style={styles.startButton}
                  >
                    <Text style={styles.startButtonText}>Begin Session</Text>
                  </TouchableOpacity>

                  <Text style={styles.instructionText}>
                    Inhale • Hold • Exhale • Hold
                  </Text>
                </>
              ) : (
                <>
                  <View style={styles.balloonWrapper}>
                    <Balloon
                      breathingState={phase}
                      countdown={0}
                      prompt={promptMap[phase]}
                    />
                  </View>
                  <TouchableOpacity
                    onPress={stopExercise}
                    style={styles.backButton}
                  >
                    <Text style={styles.backButtonText}>Back to Start</Text>
                  </TouchableOpacity>
                </>
              )}
            </View>
          </ScrollView>
        )}
      </LinearGradient>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#f0f9ff',
  },
  gradient: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 16,
  },
  idleContainer: {
    width: '100%',
    maxWidth: 512,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 24,
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    padding: 40,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.2,
    shadowRadius: 12,
    elevation: 8,
  },
  activeContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  topBar: {
    position: 'absolute',
    top: 50,
    right: 16,
    flexDirection: 'column',
    alignItems: 'flex-end',
    gap: 8,
    zIndex: 20,
  },
  timerContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  closeButton: {
    marginRight: 12,
  },
  timerText: {
    fontSize: 20,
    fontWeight: '600',
    color: '#1f2937',
  },
  balloonWrapper: {
    marginTop: 32,
  },
  iconContainer: {
    marginBottom: 32,
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 36,
    fontWeight: '500',
    color: '#1f2937',
    textAlign: 'center',
    marginBottom: 12,
    letterSpacing: 0.5,
  },
  subtitle: {
    fontSize: 18,
    color: '#6b7280',
    textAlign: 'center',
    marginBottom: 40,
  },
  cycleSection: {
    width: '100%',
    marginBottom: 32,
  },
  cycleLabel: {
    fontSize: 16,
    color: '#374151',
    fontWeight: '600',
    marginBottom: 12,
    textAlign: 'center',
  },
  cycleTotal: {
    fontSize: 14,
    fontWeight: 'normal',
    color: '#6b7280',
  },
  startButton: {
    width: '100%',
    borderRadius: 28,
    backgroundColor: '#06b6d4',
    paddingHorizontal: 32,
    paddingVertical: 16,
    shadowColor: '#06b6d4',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 4,
  },
  startButtonText: {
    fontSize: 20,
    fontWeight: '600',
    color: '#ffffff',
    textAlign: 'center',
  },
  instructionText: {
    marginTop: 24,
    fontSize: 14,
    color: '#6b7280',
    textAlign: 'center',
    fontWeight: '500',
  },
  backButton: {
    marginTop: 32,
    width: '100%',
    maxWidth: 300,
    borderRadius: 12,
    backgroundColor: '#06b6d4',
    paddingHorizontal: 24,
    paddingVertical: 12,
    shadowColor: '#06b6d4',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
  },
  backButtonText: {
    fontSize: 20,
    fontWeight: '600',
    color: '#ffffff',
    textAlign: 'center',
  },
});
