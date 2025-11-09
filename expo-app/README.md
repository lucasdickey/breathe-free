# Breathe Free - Expo Mobile App

A guided breathing exercise app built with React Native and Expo, featuring haptic feedback for an enhanced mindfulness experience.

## Features

- **Box Breathing Exercise**: 4-4-4-4 breathing pattern (Inhale, Hold, Exhale, Hold)
- **Haptic Feedback**: Gentle vibrations guide you through each breathing phase
- **Audio Accompaniment**: Soothing background music synchronized with breathing cycles
- **Customizable Sessions**: Choose from 2 to 50 breathing cycles
- **Beautiful UI**: Apple-inspired design with smooth animations

## Prerequisites

- Node.js (v14 or later)
- Expo CLI: `npm install -g expo-cli`
- For Android development:
  - Android Studio (for emulator) or
  - Physical Android device with Expo Go app installed

## Installation

1. Navigate to the expo-app directory:
   ```bash
   cd expo-app
   ```

2. Install dependencies (already done):
   ```bash
   npm install
   ```

## Running the App

### Development Mode (Expo Go)

1. Start the Expo development server:
   ```bash
   npm start
   ```

2. Scan the QR code with:
   - **Android**: Use the Expo Go app from Google Play Store
   - **iOS**: Use the Camera app (will open in Expo Go)

### Android Development Build

For full native features including haptic feedback on Android:

1. Install EAS CLI:
   ```bash
   npm install -g eas-cli
   ```

2. Login to Expo:
   ```bash
   eas login
   ```

3. Configure your project:
   ```bash
   eas build:configure
   ```

4. Build for Android (development build):
   ```bash
   eas build --platform android --profile development
   ```

5. Install the built APK on your Android device

### Local Android Build

To build locally without EAS:

1. Install dependencies:
   ```bash
   npx expo install expo-dev-client
   ```

2. Prebuild the native Android project:
   ```bash
   npx expo prebuild --platform android
   ```

3. Run on Android:
   ```bash
   npx expo run:android
   ```

## Side-loading on Android (Dev Mode)

1. Enable Developer Options on your Android device:
   - Go to Settings > About Phone
   - Tap "Build Number" 7 times

2. Enable USB Debugging:
   - Settings > Developer Options > USB Debugging

3. Connect your device via USB

4. Run the app:
   ```bash
   npx expo run:android
   ```

   Or use:
   ```bash
   npm run android
   ```

## Building for Production

### Create Production APK

```bash
eas build --platform android --profile production
```

### Create Production AAB (for Google Play Store)

```bash
eas build --platform android --profile production
```

The build will be available for download from your Expo dashboard.

## App Structure

```
expo-app/
├── App.tsx                 # Main app component
├── components/
│   ├── AudioControls.tsx   # Audio volume and mute controls
│   ├── Balloon.tsx         # Animated breathing indicator
│   ├── CloudBackground.tsx # Animated cloud background
│   └── CycleDropdown.tsx   # Cycle selection dropdown
├── hooks/
│   ├── useAudio.ts         # Audio playback management
│   └── useHaptics.ts       # Haptic feedback management
├── assets/
│   └── audio/              # Audio files for breathing exercises
├── app.json                # Expo configuration
└── package.json            # Dependencies
```

## Haptic Feedback

The app uses Expo's Haptics API to provide tactile feedback during breathing exercises:

- **Pre-start**: Success notification (getting ready)
- **Breathe In**: Medium impact vibration
- **Hold In**: Light impact vibration
- **Breathe Out**: Medium impact vibration
- **Hold Out**: Light impact vibration
- **Completed**: Success notification

## Troubleshooting

### Audio not playing
- Ensure your device is not in silent mode
- Check volume settings in the app
- Verify audio permissions are granted

### Haptic feedback not working
- Haptic feedback requires a physical device (won't work in emulator)
- Some devices may have haptic feedback disabled in settings
- Ensure the app has necessary permissions

### Build errors
- Clear cache: `npx expo start -c`
- Reinstall dependencies: `rm -rf node_modules && npm install`
- Check that all required packages are installed

## Development

To make changes to the app:

1. Edit source files in the project directory
2. The app will automatically reload with your changes
3. Press 'r' in the terminal to manually reload
4. Press 'm' to toggle the developer menu

## License

This project is part of the Breathe Free application.
