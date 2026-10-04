import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:health_core/health_core.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiStatus {
  /// 32-bit phone / platform without llama.cpp runtime: keywords only.
  unsupported,
  notDownloaded,
  downloading,
  importing,
  downloaded,
  loading,
  ready,
  failed,
}

/// Owns the optional on-device model: download or import, load, extract.
///
/// The model is Gemma 3 270M fine-tuned on this exact task
/// (tools/finetune). Off-the-shelf 0.5–1B models were benchmarked
/// (tools/llm_eval) and added more wrong findings than right ones.
///
/// The model only pre-fills the form: output is grammar-constrained to the
/// allowed keys, re-validated by [LlmExtraction.parse], and confirmed by the
/// worker. Any failure silently falls back to keyword matching.
class AiModelService extends ChangeNotifier implements AnswerExtractor {
  AiModelService._();
  static final AiModelService instance = AiModelService._();

  static const modelName = 'Health Extractor (Gemma 3 270M, fine-tuned)';
  static const approxSizeMb = 280;

  /// Where to download the GGUF from. Set at build time once you've hosted
  /// the file (e.g. on Hugging Face):
  ///   flutter build apk --dart-define=AI_MODEL_URL=https://huggingface.co/<you>/<repo>/resolve/main/health-extractor-270m-q8_0.gguf
  /// Empty -> the screen offers "Import model file" only.
  static const modelUrl = String.fromEnvironment('AI_MODEL_URL');

  static const _prefEnabled = 'ai_enabled';
  static const _importedName = 'health-extractor-imported.gguf';
  static const extractionTimeout = Duration(seconds: 20);

  AiStatus status = AiStatus.notDownloaded;
  bool enabled = true;
  double? downloadFraction;
  int downloadedBytes = 0;
  String? error;
  int? phoneRamMb;

  ModelDownloadManager? _manager;
  ModelDownloadController? _controller;
  LlamaEngine? _engine;
  String? _modelPath;
  String? _modelsDir;
  Future<bool>? _loading;
  bool _busy = false;

  static bool get platformSupported => const [
        Abi.androidArm64,
        Abi.androidX64,
        Abi.linuxX64,
        Abi.macosArm64,
      ].contains(Abi.current());

  bool get canDownload => modelUrl.isNotEmpty;
  bool get isDownloaded => _modelPath != null;

  /// True when extraction will actually use the model.
  bool get usable => enabled && isDownloaded && status != AiStatus.unsupported;

  Future<void> init() async {
    phoneRamMb = await _readRamMb();
    if (!platformSupported) {
      status = AiStatus.unsupported;
      notifyListeners();
      return;
    }
    enabled = (await SharedPreferences.getInstance()).getBool(_prefEnabled) ?? true;
    // App-support (not cache) dir: Android may wipe the cache dir when
    // storage is low, and this is a large download we want to keep.
    _modelsDir = '${(await getApplicationSupportDirectory()).path}/models';
    _manager = DefaultModelDownloadManager.auto(appPrivateCacheDirectory: _modelsDir);
    await _refreshState();
  }

  Future<void> _refreshState() async {
    String? path;
    final imported = File('$_modelsDir/$_importedName');
    if (imported.existsSync()) {
      path = imported.path;
    } else if (canDownload) {
      final entry = await _manager!.get(ModelSource.parse(modelUrl).cacheKey);
      if (entry != null && File(entry.filePath).existsSync()) path = entry.filePath;
    }
    _modelPath = path;
    status = path != null ? AiStatus.downloaded : AiStatus.notDownloaded;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    (await SharedPreferences.getInstance()).setBool(_prefEnabled, value);
    if (!value) await _unload();
    notifyListeners();
  }

  Future<void> download() async {
    if (!canDownload || _manager == null || status == AiStatus.downloading) return;
    final controller = _controller = ModelDownloadController(manager: _manager);
    status = AiStatus.downloading;
    error = null;
    downloadFraction = null;
    downloadedBytes = 0;
    notifyListeners();

    // Snapshots arrive per network chunk; repaint at most ~4x per second.
    final throttle = Stopwatch()..start();
    final sub = controller.snapshots.listen((s) {
      downloadFraction = s.progress?.fraction;
      downloadedBytes = s.progress?.receivedBytes ?? downloadedBytes;
      if (throttle.elapsedMilliseconds >= 250) {
        throttle.reset();
        notifyListeners();
      }
    });
    try {
      final entry = await controller.start(ModelSource.parse(modelUrl));
      _modelPath = entry.filePath;
      status = AiStatus.downloaded;
    } on Object catch (e) {
      if (controller.snapshot.stage == ModelDownloadTaskStage.cancelled) {
        status = AiStatus.notDownloaded;
      } else {
        status = AiStatus.failed;
        error = controller.snapshot.errorMessage ?? e.toString();
      }
    } finally {
      await sub.cancel();
      await controller.dispose();
      _controller = null;
      notifyListeners();
    }
  }

  void cancelDownload() => _controller?.cancel();

  /// Copies a .gguf picked from phone storage (USB, Bluetooth, SD card) into
  /// app storage — lets one laptop/phone seed many devices with no internet.
  Future<void> importFromFile() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    status = AiStatus.importing;
    error = null;
    notifyListeners();

    final target = File('$_modelsDir/$_importedName');
    final temp = File('${target.path}.part');
    try {
      await _unload();
      await Directory(_modelsDir!).create(recursive: true);
      final sink = temp.openWrite();
      await sink.addStream(picked.readAsByteStream());
      await sink.close();
      if (!await _isGguf(temp)) {
        throw const FormatException('Not a GGUF model file');
      }
      await temp.rename(target.path);
      await _refreshState();
    } on Object catch (e) {
      if (temp.existsSync()) await temp.delete();
      status = isDownloaded ? AiStatus.downloaded : AiStatus.failed;
      error = e.toString();
      notifyListeners();
    }
  }

  static Future<bool> _isGguf(File f) async {
    final raf = await f.open();
    try {
      return utf8.decode(await raf.read(4), allowMalformed: true) == 'GGUF';
    } finally {
      await raf.close();
    }
  }

  Future<void> delete() async {
    await _unload();
    final imported = File('$_modelsDir/$_importedName');
    if (imported.existsSync()) await imported.delete();
    if (canDownload) await _manager?.remove(ModelSource.parse(modelUrl).cacheKey);
    await _refreshState();
  }

  /// Loads the model into RAM (a second or two for 270M). Safe to call
  /// repeatedly; call early (e.g. when a consultation opens) to hide it.
  Future<bool> ensureLoaded() {
    if (status == AiStatus.ready) return Future.value(true);
    if (!enabled || _modelPath == null) return Future.value(false);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<bool> _load() async {
    status = AiStatus.loading;
    notifyListeners();
    final engine = LlamaEngine(LlamaBackend());
    try {
      // CPU only: predictable on low-end GPUs; prompts are short, so a small
      // context keeps RAM use low.
      await engine.loadModel(
        _modelPath!,
        modelParams: const ModelParams(contextSize: 512, gpuLayers: 0),
      );
      _engine = engine;
      status = AiStatus.ready;
      return true;
    } on Object catch (e) {
      await engine.dispose();
      status = AiStatus.failed;
      error = e.toString();
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _unload() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) await engine.dispose();
    if (status == AiStatus.ready) status = AiStatus.downloaded;
  }

  static final Map<String, dynamic> _schema = LlmExtraction.compactSchema();

  /// Returns {} (never throws) if the model is unavailable, busy or slow.
  @override
  Future<Map<String, String>> extract(String text) async {
    if (text.trim().isEmpty || _busy || !await ensureLoaded()) return {};
    _busy = true;
    try {
      final raw = await _engine!
          .createStructuredJson(
            [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: LlmExtraction.finetunedPrompt(text.trim()),
              ),
            ],
            output: LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
              schema: _schema,
              decoder: (j) => j,
            ),
            params: const GenerationParams(maxTokens: 64, temp: 0),
          )
          .timeout(extractionTimeout, onTimeout: () {
        _engine?.cancelGeneration();
        return const {};
      });
      return LlmExtraction.parse(jsonEncode(raw));
    } on Object catch (e) {
      debugPrint('AI extraction failed: $e');
      return {};
    } finally {
      _busy = false;
    }
  }

  /// Total RAM from /proc/meminfo (Android/Linux); null elsewhere.
  static Future<int?> _readRamMb() async {
    try {
      final line = (await File('/proc/meminfo').readAsLines())
          .firstWhere((l) => l.startsWith('MemTotal:'));
      return int.parse(RegExp(r'\d+').firstMatch(line)!.group(0)!) ~/ 1024;
    } on Object {
      return null;
    }
  }
}
