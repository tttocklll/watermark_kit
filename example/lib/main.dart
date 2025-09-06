import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:watermark_kit/watermark_kit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  Uint8List? _resultImage;
  final _watermarkKitPlugin = WatermarkKit();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _watermarkKitPlugin.getPlatformVersion() ?? 'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Running on: $_platformVersion'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _runCompose,
                child: const Text('Compose Sample Image'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: _resultImage == null
                      ? const Text('Tap the button to generate an image')
                      : Image.memory(_resultImage!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runCompose() async {
    // Generate a base image (600x400, gradient) and a watermark (logo-like) in memory.
    final basePng = await _generateSampleBasePng(600, 400);
    final wmPng = await _generateSampleWatermarkPng(256, 128);

    try {
      final composed = await _watermarkKitPlugin.composeImage(
        inputImage: basePng,
        watermarkImage: wmPng,
        anchor: 'bottomRight',
        margin: 24,
        widthPercent: 0.35,
        opacity: 0.85,
        format: 'png',
      );
      setState(() => _resultImage = composed);

      // Optionally write to temp dir for manual inspection
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/composed.png');
      await out.writeAsBytes(composed);
      // ignore: avoid_print
      print('Wrote: ${out.path}');
    } catch (e) {
      // ignore: avoid_print
      print('Compose failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compose failed: $e')));
    }
  }

  Future<Uint8List> _generateSampleBasePng(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(width.toDouble(), height.toDouble()),
        [const Color(0xFF3A7BD5), const Color(0xFF00D2FF)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint);
    final tp = _textPainter('Watermark Kit', 36);
    tp.layout();
    tp.paint(canvas, const Offset(24, 24));
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<Uint8List> _generateSampleWatermarkPng(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    canvas.drawColor(const Color(0x00000000), BlendMode.src); // transparent bg
    final r = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final paint = Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.95);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(24)))
      ..close();
    canvas.drawPath(path, paint);
    final tp = _textPainter('WM', 64, color: const Color(0xFF000000));
    tp.layout();
    tp.paint(canvas, Offset(width / 2 - tp.width / 2, height / 2 - tp.height / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  TextPainter _textPainter(String text, double size, {Color color = const Color(0xFFFFFFFF)}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    );
    return tp;
  }
}
