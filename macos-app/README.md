# Breathe Free - Native macOS App

A native macOS breathing exercise application built with SwiftUI, featuring box breathing techniques with synchronized audio and haptic feedback.

## Features

This native macOS app provides complete feature parity with the Expo mobile app:

### Core Features
- **Box Breathing Pattern**: 4-4-4-4 second breathing cycles (Inhale • Hold • Exhale • Hold)
- **Customizable Sessions**: Choose from 2, 6, 10, 20, 36, or 50 breathing cycles
- **Animated Balloon**: Visual breathing indicator that scales with your breath
- **Audio Accompaniment**: Synchronized ambient audio track with volume controls
- **Haptic Feedback**: Trackpad haptics for each breathing phase transition
- **Cloud Animation**: Relaxing animated cloud background
- **Session Timer**: Track your breathing session duration
- **Cycle Counter**: Monitor your progress through the session

### User Interface
- **Apple-Inspired Design**: Clean, modern interface with frosted glass effects
- **Smooth Animations**: Fluid transitions between breathing states
- **Gradient Background**: Calming blue gradient with animated clouds
- **Responsive Controls**: Audio mute button and volume slider modal
- **Dropdown Selector**: Easy cycle selection with duration preview

### Breathing States
1. **Idle**: Home screen with session configuration
2. **Pre-Start**: 8-second settling period before breathing begins
3. **Breathe In**: 4-second inhalation phase (balloon expands)
4. **Hold In**: 4-second hold after inhalation
5. **Breathe Out**: 4-second exhalation phase (balloon contracts)
6. **Hold Out**: 4-second hold after exhalation
7. **Completed**: Session complete screen with option to restart

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Project Structure

```
macos-app/
├── BreatheFree.xcodeproj/     # Xcode project file
└── BreatheFree/
    ├── BreatheFreeApp.swift   # App entry point
    ├── ContentView.swift      # Main UI and breathing logic
    ├── Models/
    │   ├── BreathingState.swift    # State machine for breathing cycles
    │   ├── AudioManager.swift      # Audio playback management
    │   └── HapticManager.swift     # Trackpad haptics
    ├── Views/
    │   ├── BalloonView.swift       # Animated breathing indicator
    │   ├── CloudBackgroundView.swift # Animated cloud decoration
    │   ├── CycleDropdownView.swift   # Cycle selection dropdown
    │   └── AudioControlsView.swift   # Audio controls with volume modal
    ├── Audio/
    │   └── breath-chord-loop-icetinespad.mp3  # Breathing audio track
    ├── Assets.xcassets/        # App icons and color assets
    ├── Info.plist             # App configuration
    └── BreatheFree.entitlements # Sandboxing configuration
```

## Building the App

### Option 1: Using Xcode (Recommended)

1. **Open the project:**
   ```bash
   cd macos-app
   open BreatheFree.xcodeproj
   ```

2. **Select your development team:**
   - In Xcode, select the project in the navigator
   - Go to "Signing & Capabilities"
   - Select your Apple Developer Team or use "Sign to Run Locally"

3. **Build and run:**
   - Press `Cmd+R` or click the Run button
   - The app will launch in a new window

### Option 2: Command Line Build

1. **Build the app:**
   ```bash
   cd macos-app
   xcodebuild -project BreatheFree.xcodeproj \
              -scheme BreatheFree \
              -configuration Release \
              build
   ```

2. **Locate the built app:**
   ```bash
   # The app will be in the build directory:
   # build/Release/BreatheFree.app
   ```

3. **Run the app:**
   ```bash
   open build/Release/BreatheFree.app
   ```

## Development

### Code Signing

For local development, you can use automatic code signing:

1. Open `BreatheFree.xcodeproj` in Xcode
2. Select the project in the navigator
3. Go to "Signing & Capabilities"
4. Check "Automatically manage signing"
5. Select your team or use "Sign to Run Locally"

### Debugging

- **Console Logs**: View in Xcode's debug console (Cmd+Shift+Y)
- **SwiftUI Previews**: Available in most view files (press Option+Cmd+Return)
- **Breakpoints**: Set in Xcode by clicking line numbers

### Audio Issues

If audio doesn't play:
1. Check that `breath-chord-loop-icetinespad.mp3` is in the `Audio` folder
2. Verify the audio file is included in the Xcode project (shown in navigator)
3. Check system audio settings and volume
4. Try toggling mute in the app

### Haptic Issues

Haptic feedback requires:
- A Mac with Force Touch trackpad (MacBook Pro 2015+, MacBook 2015+, Magic Trackpad 2)
- macOS haptic settings enabled in System Settings > Trackpad > Force Click and haptic feedback

## Feature Parity with Expo/Android App

This native macOS app replicates all features from the React Native Expo app:

| Feature | Expo App | macOS App | Notes |
|---------|----------|-----------|-------|
| Box breathing pattern | ✅ | ✅ | 4-4-4-4 seconds |
| Cycle selection (2-50) | ✅ | ✅ | Same options |
| Animated balloon | ✅ | ✅ | Scale animations |
| Audio playback | ✅ | ✅ | Same audio file |
| Volume controls | ✅ | ✅ | Slider + mute |
| Haptic feedback | ✅ | ✅ | Platform-specific APIs |
| Cloud animation | ✅ | ✅ | 6 animated clouds |
| Session timer | ✅ | ✅ | MM:SS format |
| Cycle counter | ✅ | ✅ | Current/total display |
| Pre-start settling | ✅ | ✅ | 8-second period |
| Completion screen | ✅ | ✅ | With restart option |
| Gradient background | ✅ | ✅ | Blue gradient |
| Frosted glass UI | ✅ | ✅ | Semi-transparent cards |

### Platform Differences

- **Haptics**:
  - Expo: Uses `expo-haptics` API for iOS/Android devices
  - macOS: Uses `NSHapticFeedbackManager` for trackpad feedback

- **Audio**:
  - Expo: Uses `expo-av` library
  - macOS: Uses native `AVFoundation` framework

- **Window Management**:
  - Expo: Full-screen mobile app
  - macOS: Fixed-size window (800x600 minimum)

## Architecture

### State Management

The app uses SwiftUI's `@State` and `@StateObject` for reactive state management:

- **BreathingState**: Enum-based state machine for breathing phases
- **AudioManager**: ObservableObject for audio playback control
- **Timer**: Foundation Timer for 1-second interval ticks

### Animation System

- **Balloon Scaling**: SwiftUI's `scaleEffect` with `easeInOut` animation (4 seconds)
- **Cloud Movement**: Continuous linear animation with `repeatForever`
- **Opacity Fades**: Quick transitions (0.2 seconds) for text changes
- **Rotation**: Chevron rotation for dropdown open/close

### Audio Synchronization

The audio track is synchronized to match the 16-second breathing cycle:
1. Calculate audio duration using AVAudioPlayer
2. Compute playback rate: `rate = audioDuration / 16.0`
3. Restart audio from position 0 on each "Breathe In" phase
4. Apply rate adjustment for perfect synchronization

## Troubleshooting

### App Won't Launch

- Check macOS version (requires 13.0+)
- Verify code signing in Xcode
- Try cleaning build folder: `Cmd+Shift+K` in Xcode

### Build Errors

- Ensure all files are included in Xcode project
- Check that audio file exists in `Audio/` folder
- Verify Swift version (5.9+)
- Clean and rebuild: `Cmd+Shift+K` then `Cmd+B`

### Audio Issues

- Check system audio volume and output device
- Verify audio file is MP3 format
- Test audio file in macOS Music app
- Check app audio controls (unmute, increase volume)

### Haptic Issues

- Verify device has Force Touch trackpad
- Check System Settings > Trackpad > Force Click enabled
- Test haptics in other apps (QuickLook preview, Mail)
- Some Macs don't support haptic feedback

## License

Copyright © 2025 Breathe Free. All rights reserved.

## Acknowledgments

- Audio track: "breath-chord-loop-icetinespad.mp3"
- Design inspired by Apple Human Interface Guidelines
- Based on the Breathe Free Expo mobile app

## Support

For issues or questions:
1. Check this README's troubleshooting section
2. Review Xcode console logs for error messages
3. Verify system requirements are met
4. Test with a clean build

---

**Note**: This is a native macOS implementation with full feature parity to the Expo/Android mobile app. The breathing algorithm, UI/UX, and audio synchronization match the mobile experience while using platform-native APIs for optimal performance on macOS.
