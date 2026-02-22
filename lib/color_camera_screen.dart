import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ColorCameraScreen extends StatefulWidget {
  const ColorCameraScreen({super.key});

  @override
  State<ColorCameraScreen> createState() => _ColorCameraScreenState();
}

class _ColorCameraScreenState extends State<ColorCameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isCameraReady = false;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    final cameras = await availableCameras();
    final rearCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      rearCamera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    await _controller.initialize();
    await _controller.setFlashMode(FlashMode.off);

    setState(() {
      _isCameraReady = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _returnRealColor() async {
    try {
      final XFile file = await _controller.takePicture();
      final bytes = await File(file.path).readAsBytes();
      final img.Image? capturedImage = img.decodeImage(bytes);

      if (capturedImage != null) {
        final centerX = capturedImage.width ~/ 2;
        final centerY = capturedImage.height ~/ 2;

        int rTotal = 0, gTotal = 0, bTotal = 0;
        int count = 0;

        for (int dx = -2; dx <= 2; dx++) {
          for (int dy = -2; dy <= 2; dy++) {
            final pixel = capturedImage.getPixel(centerX + dx, centerY + dy);
            rTotal += pixel.r.toInt();
            gTotal += pixel.g.toInt();
            bTotal += pixel.b.toInt();
            count++;
          }
        }

        final r = (rTotal ~/ count).clamp(0, 255);
        final g = (gTotal ~/ count).clamp(0, 255);
        final b = (bTotal ~/ count).clamp(0, 255);

        final selectedColor = Color.fromARGB(255, r, g, b);
        Navigator.pop(context, selectedColor);
      } else {
        Navigator.pop(context, Colors.grey);
      }
    } catch (e) {
      print('Error picking color: $e');
      Navigator.pop(context, Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          _isCameraReady
              ? Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_controller),
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(Icons.add, color: Colors.white, size: 40),
                  ),
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton(
                        onPressed: _returnRealColor,
                        child: const Text('Pick Color'),
                      ),
                    ),
                  ),
                ],
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }
}
