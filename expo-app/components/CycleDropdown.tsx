import { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Modal, Pressable } from 'react-native';
import Svg, { Path } from 'react-native-svg';

interface CycleDropdownProps {
  value: number;
  onChange: (value: number) => void;
}

const cycleOptions = [2, 6, 10, 20, 36, 50];

const ChevronIcon = ({ isOpen }: { isOpen: boolean }) => (
  <Svg
    width="20"
    height="20"
    viewBox="0 0 24 24"
    fill="none"
    stroke="#6b7280"
    strokeWidth={2}
    style={{
      transform: [{ rotate: isOpen ? '180deg' : '0deg' }],
    }}
  >
    <Path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
  </Svg>
);

export default function CycleDropdown({ value, onChange }: CycleDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);

  const handleSelect = (option: number) => {
    onChange(option);
    setIsOpen(false);
  };

  return (
    <View style={styles.container}>
      <TouchableOpacity
        onPress={() => setIsOpen(!isOpen)}
        style={styles.button}
      >
        <Text style={styles.buttonText}>{value}</Text>
        <ChevronIcon isOpen={isOpen} />
      </TouchableOpacity>

      <Modal
        visible={isOpen}
        transparent={true}
        animationType="fade"
        onRequestClose={() => setIsOpen(false)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setIsOpen(false)}
        >
          <View style={styles.dropdown}>
            {cycleOptions.map((option) => {
              const minutes = Math.floor(option * 16 / 60);
              const seconds = (option * 16 % 60).toString().padStart(2, '0');
              return (
                <TouchableOpacity
                  key={option}
                  onPress={() => handleSelect(option)}
                  style={[
                    styles.option,
                    value === option && styles.selectedOption,
                  ]}
                >
                  <Text
                    style={[
                      styles.optionText,
                      value === option && styles.selectedOptionText,
                    ]}
                  >
                    {`${option} (${minutes}:${seconds})`}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>
        </Pressable>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#e5e7eb',
    backgroundColor: 'rgba(255, 255, 255, 0.8)',
    paddingHorizontal: 24,
    paddingVertical: 16,
    minHeight: 56,
  },
  buttonText: {
    fontSize: 20,
    color: '#1f2937',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.3)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  dropdown: {
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#e5e7eb',
    overflow: 'hidden',
    minWidth: 200,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 8,
  },
  option: {
    paddingHorizontal: 24,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
  },
  selectedOption: {
    backgroundColor: '#cffafe',
  },
  optionText: {
    fontSize: 20,
    color: '#1f2937',
  },
  selectedOptionText: {
    color: '#0e7490',
    fontWeight: '600',
  },
});
