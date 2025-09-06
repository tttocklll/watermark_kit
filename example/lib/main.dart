import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
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
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _platformVersion = 'Unknown';
  final _watermarkKitPlugin = WatermarkKit();
  final _picker = ImagePicker();

  Uint8List? _baseImage;
  Uint8List? _watermarkImage;
  Uint8List? _resultImage;
  String _text = '© Watermark Kit';
  String? _videoPath;
  double _videoProgress = 0.0;
  VideoTask? _videoTask;

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
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Watermark Kit Example'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Image'),
              Tab(text: 'Video'),
            ]),
          ),
          body: const TabBarView(children: [
            _ImageTab(),
            _VideoTab(),
          ]),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
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

  Widget _textControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Text Watermark', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(labelText: 'Text'),
          controller: TextEditingController(text: _text),
          onChanged: (v) => _text = v,
        ),
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
      _showSnack('Pick failed: $e');
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
      _showSnack('Compose failed: $e');
    } finally {
      if (mounted) setState(() => _isComposing = false);
    }
  }

  Future<void> _composeText() async {
    if (_baseImage == null) return;
    setState(() => _isComposing = true);
    try {
      final bytes = await _watermarkKitPlugin.composeTextImage(
        inputImage: _baseImage!,
        text: _text,
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
      final out = File('${dir.path}/composed_text.$ext');
      await out.writeAsBytes(bytes);
      // ignore: avoid_print
      print('Wrote: ${out.path}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Compose text failed: $e');
    } finally {
      if (mounted) setState(() => _isComposing = false);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final xfile = await _picker.pickVideo(source: ImageSource.gallery);
      if (xfile == null) return;
      setState(() => _videoPath = xfile.path);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Pick video failed: $e');
    }
  }

  Future<void> _startVideo() async {
    if (_videoPath == null) return;
    setState(() {
      _videoProgress = 0.0;
    });
    try {
      final task = await _watermarkKitPlugin.composeVideo(
        inputVideoPath: _videoPath!,
        text: _text,
        anchor: _anchor,
        margin: _margin,
        marginUnit: 'px',
        offsetX: _offsetX,
        offsetY: _offsetY,
        offsetUnit: 'px',
        widthPercent: _widthPercent,
        opacity: _opacity,
        codec: 'h264',
      );
      setState(() => _videoTask = task);
      task.progress.listen((p) {
        setState(() => _videoProgress = p);
      });
      final res = await task.done;
      if (!mounted) return;
      _showSnack('Video done: ${res.path}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Video failed: $e');
    } finally {
      if (mounted) setState(() => _videoTask = null);
    }
  }

  Future<void> _cancelVideo() async {
    final t = _videoTask;
    if (t == null) return;
    await t.cancel();
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

class _ImageTab extends StatefulWidget {
  const _ImageTab();
  @override
  State<_ImageTab> createState() => _ImageTabState();
}

class _ImageTabState extends State<_ImageTab> {
  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<_MyAppState>()!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Running on: ${parent._platformVersion}'),
            const SizedBox(height: 12),
            parent._rowSelectImages(),
            const SizedBox(height: 12),
            parent._controls(),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (parent._baseImage != null && parent._watermarkImage != null && !parent._isComposing)
                  ? parent._compose
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(parent._isComposing ? 'Composing...' : 'Compose'),
            ),
            const SizedBox(height: 8),
            parent._textControls(),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: (parent._baseImage != null && !parent._isComposing)
                  ? parent._composeText
                  : null,
              icon: const Icon(Icons.text_fields),
              label: Text(parent._isComposing ? 'Composing...' : 'Compose Text'),
            ),
            const SizedBox(height: 12),
            parent._previewResult(),
            const SizedBox(height: 24),
            const Divider(),
            const Text('Quick Demo (optional)'),
            Row(
              children: [
                ElevatedButton(
                  onPressed: parent._loadSampleBase,
                  child: const Text('Use Sample Base'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: parent._loadSampleWatermark,
                  child: const Text('Use Sample Watermark'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoTab extends StatefulWidget {
  const _VideoTab();
  @override
  State<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<_VideoTab> {
  final _wm = WatermarkKit();
  final _picker = ImagePicker();

  String? _videoPath;
  Uint8List? _wmImage;
  String _wmText = '© Watermark Kit';
  bool _useImageWatermark = false;

  String _anchor = 'bottomRight';
  double _margin = 16.0;
  double _widthPercent = 0.18;
  double _opacity = 0.6;
  double _offsetX = 0.0;
  double _offsetY = 0.0;

  double _progress = 0.0;
  VideoTask? _task;

  VideoPlayerController? _outController;

  @override
  void dispose() {
    _outController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<_MyAppState>()!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Video (iOS only)'),
            const SizedBox(height: 8),
            Row(children: [
              ElevatedButton(onPressed: _pickVideo, child: const Text('Pick Video')),
              const SizedBox(width: 8),
              if (_videoPath != null) Expanded(child: Text(_videoPath!, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Watermark:'),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Text'),
                selected: !_useImageWatermark,
                onSelected: (v) => setState(() => _useImageWatermark = !v),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Image'),
                selected: _useImageWatermark,
                onSelected: (v) => setState(() => _useImageWatermark = v),
              ),
            ]),
            const SizedBox(height: 8),
            if (!_useImageWatermark)
              TextField(
                decoration: const InputDecoration(labelText: 'Watermark Text'),
                controller: TextEditingController(text: _wmText),
                onChanged: (v) => _wmText = v,
              )
            else
              Row(children: [
                ElevatedButton.icon(
                  onPressed: _pickWmImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Pick Watermark Image'),
                ),
                const SizedBox(width: 8),
                if (_wmImage != null)
                  SizedBox(width: 64, height: 64, child: Image.memory(_wmImage!, fit: BoxFit.contain)),
              ]),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Anchor:'),
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
              ],
            ),
            _slider('Margin', _margin, 0, 64, (v) => setState(() => _margin = v), suffix: 'px'),
            _slider('Width % of base', _widthPercent, 0.05, 0.8, (v) => setState(() => _widthPercent = v), formatter: (v) => '${(v * 100).toStringAsFixed(0)}%'),
            _slider('Opacity', _opacity, 0.0, 1.0, (v) => setState(() => _opacity = v), formatter: (v) => v.toStringAsFixed(2)),
            _slider('Offset X', _offsetX, -200, 200, (v) => setState(() => _offsetX = v), formatter: (v) => v.toStringAsFixed(0), suffix: 'px'),
            _slider('Offset Y', _offsetY, -200, 200, (v) => setState(() => _offsetY = v), formatter: (v) => v.toStringAsFixed(0), suffix: 'px'),
            const SizedBox(height: 8),
            Row(children: [
              ElevatedButton.icon(
                onPressed: (_videoPath != null && _task == null && (_useImageWatermark ? _wmImage != null : _wmText.trim().isNotEmpty))
                    ? _startCompose
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(_task == null ? 'Compose Video' : 'Composing...'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: (_task != null) ? _cancel : null,
                icon: const Icon(Icons.stop),
                label: const Text('Cancel'),
              ),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (_task != null) ? _progress : null),
            const SizedBox(height: 12),
            if (_outController != null) _videoPlayer(_outController!),
          ],
        ),
      ),
    );
  }

  Widget _videoPlayer(VideoPlayerController c) {
    // Controller is initialized before setting state.
    return AspectRatio(
      aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
      child: Stack(children: [
        VideoPlayer(c),
        Positioned(
          bottom: 8,
          right: 8,
          child: Row(children: [
            IconButton(
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
              onPressed: () {
                setState(() {
                  c.value.isPlaying ? c.pause() : c.play();
                });
              },
            )
          ]),
        )
      ]),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String Function(double)? formatter, String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Text(label), const SizedBox(width: 8), Text(formatter != null ? formatter(value) : '${value.toStringAsFixed(1)}$suffix')]),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  Future<void> _pickVideo() async {
    try {
      final x = await _picker.pickVideo(source: ImageSource.gallery);
      if (x == null) return;
      setState(() {
        _videoPath = x.path;
        _outController?.dispose();
        _outController = null;
      });
    } catch (e) {
      _snack('Pick video failed: $e');
    }
  }

  Future<void> _pickWmImage() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _wmImage = bytes;
      });
    } catch (e) {
      _snack('Pick watermark failed: $e');
    }
  }

  Future<void> _startCompose() async {
    if (_videoPath == null) return;
    setState(() {
      _progress = 0.0;
    });
    try {
      final task = await _wm.composeVideo(
        inputVideoPath: _videoPath!,
        outputVideoPath: null,
        watermarkImage: _useImageWatermark ? _wmImage : null,
        text: _useImageWatermark ? null : _wmText,
        anchor: _anchor,
        margin: _margin,
        marginUnit: 'px',
        offsetX: _offsetX,
        offsetY: _offsetY,
        offsetUnit: 'px',
        widthPercent: _widthPercent,
        opacity: _opacity,
        codec: 'h264',
      );
      setState(() => _task = task);
      task.progress.listen((p) => setState(() => _progress = p));
      final res = await task.done;
      _snack('Video done: ${res.path}');
      final c = VideoPlayerController.file(File(res.path));
      await c.initialize();
      await c.setLooping(true);
      setState(() => _outController = c);
    } catch (e) {
      _snack('Video failed: $e');
    } finally {
      if (mounted) setState(() => _task = null);
    }
  }

  Future<void> _cancel() async {
    final t = _task;
    if (t == null) return;
    await t.cancel();
  }

  void _snack(String m) {
    final parent = context.findAncestorStateOfType<_MyAppState>()!;
    parent._messengerKey.currentState?.showSnackBar(SnackBar(content: Text(m)));
  }
}
