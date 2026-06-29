import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_scankit/flutter_scankit.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ml_kit_service.dart';
import '../services/tflite_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final MLKitService _mlKitService = MLKitService();
  final TfliteService _tfliteService = TfliteService();

  String _ocrRawText = "Belum ada teks dipindai";
  String _preprocessedText = "-";
  String _modelPrediction = "-";
  bool _isLoading = false;

  // Metrics
  int? _ocrDurationMs;
  int? _modelDurationMs;
  String? _modelSizeStr;

  @override
  void initState() {
    super.initState();
    _tfliteService.init();
    _loadModelSize();
  }

  Future<void> _loadModelSize() async {
    try {
      final data = await rootBundle.load('assets/model_bigru_crf.tflite');
      final bytes = data.lengthInBytes;
      setState(() {
        if (bytes >= 1024 * 1024) {
          _modelSizeStr = "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
        } else {
          _modelSizeStr = "${(bytes / 1024).toStringAsFixed(1)} KB";
        }
      });
    } catch (e) {
      setState(() => _modelSizeStr = "N/A");
    }
  }

  // --- LOGIKA SCAN BARCODE DENGAN TIMEOUT ---
  Future<void> _startBarcodeScan() async {
    PermissionStatus status = await Permission.camera.request();

    if (status.isGranted) {
      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );

      if (result == "TIMEOUT" || result == "CANCEL" || result == null) {
        _showOcrFallbackDialog();
      } else {
        _processExtractedText(result.toString(), isOcr: false, ocrDurationMs: null);
      }
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Izin kamera dibutuhkan untuk scan barcode')),
      );
    }
  }

  // --- POP UP DIALOG (FALLBACK KALO BARCODE GAGAL) ---
  void _showOcrFallbackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Gagal Scan Barcode"),
        content: const Text("Tidak bisa scan barcode, Ganti ke OCR?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("Tidak"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processImage(ImageSource.camera); // Langsung ke OCR Kamera
            },
            child: const Text("Ganti"),
          ),
        ],
      ),
    );
  }

  // --- LOGIKA OCR IMAGE PICKER (KAMERA ATAU GALERI) ---
  Future<void> _processImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    setState(() {
      _isLoading = true;
      _ocrDurationMs = null;
      _modelDurationMs = null;
    });

    final ocrStart = DateTime.now();
    final ocrResult = await _mlKitService.scanTextFromImage(image);
    final ocrEnd = DateTime.now();
    final ocrMs = ocrEnd.difference(ocrStart).inMilliseconds;

    if (ocrResult != null && ocrResult.isNotEmpty) {
      await _processExtractedText(ocrResult, isOcr: true, ocrDurationMs: ocrMs);
    } else {
      setState(() {
        _ocrRawText = "Teks tidak ditemukan pada gambar.";
        _preprocessedText = "-";
        _modelPrediction = "-";
        _ocrDurationMs = ocrMs;
        _modelDurationMs = null;
        _isLoading = false;
      });
    }
  }

  // --- LOGIKA PEMROSESAN TEKS & INFERENSI ---
  Future<void> _processExtractedText(String text, {required bool isOcr, int? ocrDurationMs}) async {
    setState(() => _isLoading = true);

    final preprocessed = _tfliteService.preprocessText(text);

    final modelStart = DateTime.now();
    final prediction = _tfliteService.runInference(text);
    final modelEnd = DateTime.now();
    final modelMs = modelEnd.difference(modelStart).inMilliseconds;

    setState(() {
      _ocrRawText = text;
      _preprocessedText = preprocessed;
      _modelPrediction = prediction ?? "Gagal memprediksi";
      _ocrDurationMs = ocrDurationMs;
      _modelDurationMs = modelMs;
      _isLoading = false;
    });
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$label disalin ke clipboard"),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _mlKitService.dispose();
    _tfliteService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("VIN Scanner")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Tombol Utama Scan Barcode
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text("Mulai Scan Barcode"),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
              ),
              onPressed: _startBarcodeScan,
            ),
            const SizedBox(height: 10),

            // 2. Tombol Baru: Langsung Scan OCR via Kamera
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text("Mulai Scan OCR"),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
              ),
              onPressed: () => _processImage(ImageSource.camera),
            ),
            const SizedBox(height: 10),

            // 3. Tombol Galeri
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text("OCR dari Galeri"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _processImage(ImageSource.gallery),
            ),
            const SizedBox(height: 24),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              _buildMetricRow(),
              const SizedBox(height: 16),

              _buildResultCard(
                "Hasil Raw (Barcode / OCR)",
                _ocrRawText,
                copyable: _ocrRawText != "Belum ada teks dipindai" && _ocrRawText != "Teks tidak ditemukan pada gambar.",
                copyLabel: "Teks Raw",
              ),
              const SizedBox(height: 12),
              _buildResultCard(
                "Teks Setelah Preprocessing",
                _preprocessedText,
                copyable: _preprocessedText != "-",
                copyLabel: "Teks Preprocessing",
              ),
              const SizedBox(height: 12),
              _buildResultCard(
                "VIN Hasil Ekstraksi Model",
                _modelPrediction,
                isHighlighted: true,
                copyable: _modelPrediction != "-" && _modelPrediction != "Gagal memprediksi",
                copyLabel: "VIN",
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.document_scanner_outlined,
            label: "Waktu Ekstraksi",
            value: _ocrDurationMs != null ? "${_ocrDurationMs} ms" : "N/A",
            color: Colors.teal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.memory,
            label: "Waktu Inferensi",
            value: _modelDurationMs != null ? "${_modelDurationMs} ms" : "-",
            color: Colors.indigo,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.storage_outlined,
            label: "Ukuran Model",
            value: _modelSizeStr ?? "...",
            color: Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(
      String title,
      String content, {
        bool isHighlighted = false,
        bool copyable = false,
        String copyLabel = "Teks",
      }) {
    return Card(
      color: isHighlighted ? Colors.blue.shade50 : Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (copyable)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: "Salin $copyLabel",
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _copyToClipboard(content, copyLabel),
                  ),
              ],
            ),
            const Divider(),
            Text(
              content,
              style: TextStyle(
                fontSize: isHighlighted ? 18 : 14,
                fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// CUSTOM VIEW SCREEN UNTUK BARCODE SCANNER (DENGAN TIMEOUT 10 DETIK)
// =========================================================================
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late ScanKitController _controller;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _controller = ScanKitController();

    _controller.onResult.listen((ScanResult result) {
      if (result.originalValue != null && result.originalValue!.isNotEmpty) {
        if (mounted) {
          _timeoutTimer?.cancel();
          Navigator.pop(context, result.originalValue);
        }
      }
    });

    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        Navigator.pop(context, "TIMEOUT");
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ScanKitWidget(
            controller: _controller,
            continuouslyScan: false,
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () {
                  Navigator.pop(context, "CANCEL");
                },
              ),
            ),
          ),
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 40.0),
                child: Text(
                  "Arahkan kamera ke Barcode\n(Otomatis beralih ke OCR dalam 10 detik)",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}