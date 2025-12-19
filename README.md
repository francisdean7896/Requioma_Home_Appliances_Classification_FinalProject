# Home Appliances Classifier

A Flutter mobile app that classifies photos of home appliances using a TensorFlow Lite model. The app lets you pick an image from the gallery or capture a photo, runs inference locally with tflite_flutter, and displays the top predictions.

## Features:
- On-device image classification with TensorFlow Lite.
- Pick image from gallery or capture with camera.
- Top-5 prediction list with confidence bars.
- Minimal, dark Material 3 UI.

## Requirements:
- Flutter SDK (stable channel recommended)
- Android Studio / Xcode for device/emulator
- Device/emulator with camera support (if using camera)
- Pub packages used: tflite_flutter, image, image_picker, flutter SDK (see pubspec.yaml)
