import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
  final _watermarkKitPlugin = WatermarkKit();
  final _picker = ImagePicker();

  Uint8List? _baseImage;
  Uint8List? _watermarkImage;
  Uint8List? _resultImage;

  String _anchor = 'bottomRight';
  double _margin = 16.0;
  double _widthPercent = 0.18;
  double _opacity = 0.6;
  String _format = 'png';
  double _quality = 0.9;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  bool _isComposing = false;

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
          title: const Text('Watermark Kit Example'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Running on: $_platformVersion'),
                const SizedBox(height: 12),
                _rowSelectImages(),
                const SizedBox(height: 12),
                _controls(),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: (_baseImage != null && _watermarkImage != null && !_isComposing)
                      ? _compose
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_isComposing ? 'Composing...' : 'Compose'),
                ),
                const SizedBox(height: 12),
                _previewResult(),
                const SizedBox(height: 24),
                const Divider(),
                const Text('Quick Demo (optional)'),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _loadSampleBase,
                      child: const Text('Use Sample Base'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loadSampleWatermark,
                      child: const Text('Use Sample Watermark'),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowSelectImages() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _imageCard('Base Image', _baseImage, () => _pickImage(isBase: true))),
        const SizedBox(width: 12),
        Expanded(child: _imageCard('Watermark Image', _watermarkImage, () => _pickImage(isBase: false))),
      ],
    );
  }

  Widget _imageCard(String title, Uint8List? bytes, VoidCallback onPick) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 3 / 2,
              child: Container(
                color: Colors.grey.shade200,
                child: bytes == null
                    ? const Center(child: Text('No image selected'))
                    : Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library),
              label: const Text('Select from Library'),
            )
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Anchor: '),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _anchor,
              items: const [
                DropdownMenuItem(value: 'topLeft', child: Text('topLeft')),
                DropdownMenuItem(value: 'topRight', child: Text('topRight')),
                DropdownMenuItem(value: 'bottomLeft', child: Text('bottomLeft')),
                DropdownMenuItem(value: 'bottomRight', child: Text('bottomRight')),
                DropdownMenuItem(value: 'center', child: Text('center')),
              ],
              onChanged: (v) => setState(() => _anchor = v ?? _anchor),
            ),
            const SizedBox(width: 24),
            const Text('Format: '),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _format,
              items: const [
                DropdownMenuItem(value: 'png', child: Text('png')),
                DropdownMenuItem(value: 'jpeg', child: Text('jpeg')),
              ],
              onChanged: (v) => setState(() => _format = v ?? _format),
            ),
          ],
        ),
        _slider('Margin', _margin, 0, 64, (v) => setState(() => _margin = v), suffix: 'px'),
        _slider('Width % of base', _widthPercent, 0.05, 0.8, (v) => setState(() => _widthPercent = v),
            formatter: (v) => '${(v * 100).toStringAsFixed(0)}%'),
        _slider('Opacity', _opacity, 0.0, 1.0, (v) => setState(() => _opacity = v), formatter: (v) => v.toStringAsFixed(2)),
        _slider('Offset X', _offsetX, -200, 200, (v) => setState(() => _offsetX = v), formatter: (v) => v.toStringAsFixed(0), suffix: 'px'),
        _slider('Offset Y', _offsetY, -200, 200, (v) => setState(() => _offsetY = v), formatter: (v) => v.toStringAsFixed(0), suffix: 'px'),
        if (_format == 'jpeg')
          _slider('JPEG Quality', _quality, 0.2, 1.0, (v) => setState(() => _quality = v), formatter: (v) => v.toStringAsFixed(2)),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String Function(double)? formatter, String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const SizedBox(width: 8),
            Text(formatter != null ? formatter(value) : '${value.toStringAsFixed(1)}$suffix'),
          ],
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  Widget _previewResult() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Result', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 3 / 2,
              child: Container(
                color: Colors.grey.shade100,
                child: _resultImage == null ? const Center(child: Text('No result')) : Image.memory(_resultImage!, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage({required bool isBase}) async {
    try {
      final xfile = await _picker.pickImage(source: ImageSource.gallery);
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      setState(() {
        if (isBase) {
          _baseImage = bytes;
        } else {
          _watermarkImage = bytes;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pick failed: $e')));
    }
  }

  Future<void> _compose() async {
    if (_baseImage == null || _watermarkImage == null) return;
    setState(() => _isComposing = true);
    try {
      final bytes = await _watermarkKitPlugin.composeImage(
        inputImage: _baseImage!,
        watermarkImage: _watermarkImage!,
        anchor: _anchor,
        margin: _margin,
        widthPercent: _widthPercent,
        opacity: _opacity,
        format: _format,
        quality: _quality,
        offsetX: _offsetX,
        offsetY: _offsetY,
      );
      setState(() => _resultImage = bytes);

      final dir = await getTemporaryDirectory();
      final ext = _format == 'png' ? 'png' : 'jpg';
      final out = File('${dir.path}/composed.$ext');
      await out.writeAsBytes(bytes);
      // ignore: avoid_print
      print('Wrote: ${out.path}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compose failed: $e')));
    } finally {
      if (mounted) setState(() => _isComposing = false);
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

  Future<void> _loadSampleBase() async {
    final basePng = await _generateSampleBasePng(800, 500);
    setState(() => _baseImage = basePng);
  }

  Future<void> _loadSampleWatermark() async {
    final wmPng = await _generateSampleWatermarkPng(300, 140);
    setState(() => _watermarkImage = wmPng);
  }
}
