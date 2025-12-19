import 'dart:io';
import 'dart:ui'; // Needed for ImageFilter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home Appliances Classifier',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          secondary: Colors.cyanAccent,
        ),
        scaffoldBackgroundColor: Colors.transparent, // Important for gradient
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 8,
            shadowColor: Colors.deepPurple.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
          ),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  File? _image;
  final picker = ImagePicker();
  
  // Analytics Data
  List<Map<String, dynamic>>? _recognitions;
  String? _topLabel;
  double? _topConfidence;
  
  // TFLite
  bool _modelLoaded = false;
  Interpreter? _interpreter;
  List<String> _labels = [];

  @override
  void initState() {
    super.initState();
    loadModel();
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('converted_tflite/model_unquant.tflite');
      final labelsData = await rootBundle.loadString('converted_tflite/labels.txt');
      _labels = labelsData.split('\n').where((s) => s.isNotEmpty).toList();
      
      setState(() {
        _modelLoaded = true;
      });
      print('TFLite model loaded');
    } catch (e, st) {
      print('Failed to load TFLite model: $e\n$st');
      setState(() => _modelLoaded = false);
    }
  }

  Future<void> pickImage() async {
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => _image = File(pickedFile.path));
        runModelOnImage(_image!);
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> captureImage() async {
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() => _image = File(pickedFile.path));
        runModelOnImage(_image!);
      }
    } catch (e) {
      print('Error capturing image: $e');
    }
  }

  Future<void> runModelOnImage(File image) async {
    if (!_modelLoaded || _interpreter == null) {
      print('Model not loaded yet');
      return;
    }

    try {
      final imageBytes = await image.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) return;

      final inputTensor = _interpreter!.getInputTensor(0);
      final inputShape = inputTensor.shape; 
      final height = inputShape[1];
      final width = inputShape[2];

      img.Image resizedImage;
      if (decodedImage.width < decodedImage.height) {
         resizedImage = img.copyResize(decodedImage, width: width);
      } else {
         resizedImage = img.copyResize(decodedImage, height: height);
      }
      
      final cropX = (resizedImage.width - width) ~/ 2;
      final cropY = (resizedImage.height - height) ~/ 2;
      
      final img.Image croppedImage = img.copyCrop(resizedImage, x: cropX, y: cropY, width: width, height: height);

      final input = [imageToByteListFloat32(croppedImage, width, height, 127.5, 127.5)];
      
      final outputTensor = _interpreter!.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      final outputBuffer = List.generate(outputShape[0], (_) => List.filled(outputShape[1], 0.0));

      _interpreter!.run(input, outputBuffer);

      final result = outputBuffer[0];
      final recognitions = <Map<String, dynamic>>[];
      
      for (var i = 0; i < result.length; i++) {
        if (i < _labels.length) {
          recognitions.add({
            'label': _labels[i],
            'confidence': result[i],
          });
        }
      }

      recognitions.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
      final topRecognitions = recognitions.take(5).toList();

      setState(() {
        _recognitions = topRecognitions;
        if (topRecognitions.isNotEmpty) {
          _topLabel = topRecognitions[0]['label'];
          _topConfidence = topRecognitions[0]['confidence'];
        } else {
          _topLabel = "Unknown";
          _topConfidence = 0.0;
        }
      });

    } catch (e, st) {
      print('Inference failed: $e\n$st');
    }
  }

  List<List<List<double>>> imageToByteListFloat32(
      img.Image image, int width, int height, double mean, double std) {
    var buffer = List.generate(
      height,
      (y) => List.generate(
        width,
        (x) {
          final pixel = image.getPixel(x, y);
          return [
            ((pixel.r) - mean) / std,
            ((pixel.g) - mean) / std,
            ((pixel.b) - mean) / std
          ];
        },
      ),
    );
    return buffer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A2E), // Dark Navy
            Color(0xFF16213E), // Slightly lighter navy
            Color(0xFF0F3460), // Deep blue
          ],
        ),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Home Appliances Classifier')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              // Image Preview Card
              Container(
                height: 380,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: _image == null
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    theme.colorScheme.primary.withOpacity(0.2),
                                    Colors.transparent,
                                  ],
                                  radius: 0.8,
                                ),
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo_outlined, 
                                  size: 60, 
                                  color: theme.colorScheme.primary.withOpacity(0.8)
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Tap below to start',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Image.file(_image!, fit: BoxFit.cover),
                ),
              ),
              
              const SizedBox(height: 30),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      onPressed: pickImage,
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      isPrimary: false,
                      theme: theme,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildActionButton(
                      onPressed: captureImage,
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      isPrimary: true,
                      theme: theme,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Analytics Section
              if (_recognitions != null) ...[
                Text(
                  "Results",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        children: _recognitions!.map((res) {
                          final label = res['label'];
                          final double confidence = res['confidence'];
                          final isTop = label == _topLabel;
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontWeight: isTop ? FontWeight.bold : FontWeight.w500,
                                        fontSize: isTop ? 18 : 16,
                                        color: isTop ? theme.colorScheme.secondary : Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      "${(confidence * 100).toStringAsFixed(1)}%",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: isTop ? 18 : 16,
                                        color: isTop ? theme.colorScheme.secondary : Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: confidence,
                                    minHeight: 10,
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                    color: isTop ? theme.colorScheme.secondary : theme.colorScheme.primary.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ] else if (_image != null && _recognitions == null) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required bool isPrimary,
    required ThemeData theme,
  }) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isPrimary ? theme.colorScheme.primary.withOpacity(0.4) : Colors.transparent,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: isPrimary ? theme.colorScheme.primary : Colors.white.withOpacity(0.1),
          foregroundColor: isPrimary ? Colors.white : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }
}
