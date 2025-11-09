import { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Pressable,
} from 'react-native';
import Slider from '@react-native-community/slider';
import Svg, { Path } from 'react-native-svg';

interface AudioControlsProps {
  volume: number;
  isMuted: boolean;
  onToggleMute: () => void;
  onVolumeChange: (volume: number) => void;
}

const MutedIcon = () => (
  <Svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#374151" strokeWidth={2}>
    <Path strokeLinecap="round" strokeLinejoin="round" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
    <Path strokeLinecap="round" strokeLinejoin="round" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2" />
  </Svg>
);

const UnmutedIcon = () => (
  <Svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#374151" strokeWidth={2}>
    <Path strokeLinecap="round" strokeLinejoin="round" d="M15.536 8.464a5 5 0 010 7.072m2.828-9.9a9 9 0 010 12.728M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
  </Svg>
);

const VolumeIcon = () => (
  <Svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#374151" strokeWidth={2}>
    <Path strokeLinecap="round" strokeLinejoin="round" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
  </Svg>
);

export default function AudioControls({
  volume,
  isMuted,
  onToggleMute,
  onVolumeChange,
}: AudioControlsProps) {
  const [showVolumeSlider, setShowVolumeSlider] = useState(false);

  const handleVolumeClick = () => {
    setShowVolumeSlider(true);
  };

  const handleCloseSlider = () => {
    setShowVolumeSlider(false);
  };

  const handleVolumeChange = (newVolume: number) => {
    onVolumeChange(newVolume);
  };

  return (
    <View style={styles.container}>
      {/* Mute/Unmute Toggle */}
      <TouchableOpacity
        onPress={onToggleMute}
        style={styles.button}
        accessibilityLabel={isMuted ? 'Unmute' : 'Mute'}
      >
        {isMuted ? <MutedIcon /> : <UnmutedIcon />}
      </TouchableOpacity>

      {/* Volume Control */}
      <TouchableOpacity
        onPress={handleVolumeClick}
        style={styles.button}
        accessibilityLabel="Volume control"
      >
        <VolumeIcon />
      </TouchableOpacity>

      {/* Volume Slider Modal */}
      <Modal
        visible={showVolumeSlider}
        transparent={true}
        animationType="fade"
        onRequestClose={handleCloseSlider}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={handleCloseSlider}
        >
          <Pressable
            style={styles.modalContent}
            onPress={(e) => e.stopPropagation()}
          >
            <Text style={styles.modalTitle}>Volume</Text>

            <View style={styles.sliderContainer}>
              <Slider
                style={styles.slider}
                minimumValue={0}
                maximumValue={1}
                value={volume}
                onValueChange={handleVolumeChange}
                minimumTrackTintColor="#06b6d4"
                maximumTrackTintColor="#e5e7eb"
                thumbTintColor="#06b6d4"
              />
            </View>

            <Text style={styles.volumeText}>{Math.round(volume * 100)}%</Text>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  button: {
    padding: 8,
    borderRadius: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.3)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    backgroundColor: '#ffffff',
    borderRadius: 16,
    padding: 24,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
    width: 200,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#1f2937',
    marginBottom: 16,
  },
  sliderContainer: {
    width: '100%',
    height: 40,
    justifyContent: 'center',
    marginBottom: 16,
  },
  slider: {
    width: '100%',
    height: 40,
  },
  volumeText: {
    fontSize: 14,
    color: '#6b7280',
  },
});
