# Flutter Native Waveform

A Flutter application that visualizes audio files' waveform. This app uses platform channels to extract PCM data from audio files on the native side and transforms it into a visual waveform on the Flutter side.

## Features

- 🔊 Native audio processing using platform channels
- 📊 Customizable waveform visualization
- ▶️ Audio play/pause controls
- 📱 Cross-platform functionality (Android/iOS)
- 🎛️ Waveform customization options (bar width, spacing, count, etc.)

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/flutter_native_waveform.git

# Navigate to project directory
cd flutter_native_waveform

# Install dependencies
flutter pub get

# Run the application
flutter run
```

## How It Works

The application accesses native code through platform channels:

1. PCM data is extracted from audio files on Android or iOS side
2. This data is transferred to the Flutter side
3. A custom CustomPainter is used to visualize the waveform in Flutter
4. Parameters can be adjusted through the user interface

## Contributing

If you'd like to contribute:

1. Fork this repository
2. Create your feature branch (`git checkout -b new-feature`)
3. Commit your changes (`git commit -m 'Added new feature'`)
4. Push to the branch (`git push origin new-feature`)
5. Create a Pull Request
