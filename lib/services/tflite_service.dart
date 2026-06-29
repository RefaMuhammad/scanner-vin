import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteService {
  Interpreter? _interpreter;
  Map<String, int>? _char2idx;
  List<List<double>>? _transitionMatrix;
  final int maxLength = 120;

  Future<void> init() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model_bigru_crf.tflite');

      String vocabString = await rootBundle.loadString('assets/vocab_config_vin.json');
      final vocabJson = json.decode(vocabString);
      _char2idx = Map<String, int>.from(vocabJson['char2idx']);

      String transString = await rootBundle.loadString('assets/transition_matrix.json');
      List<dynamic> transJson = json.decode(transString);
      _transitionMatrix = transJson.map((e) => List<double>.from(e)).toList();

      print("[INIT] ✅ TFLite & Config loaded successfully");
      print("[INIT] Vocab size: ${_char2idx?.length}");
      print("[INIT] Transition matrix size: ${_transitionMatrix?.length}x${_transitionMatrix?[0].length}");

      // DEBUG: Cek apakah transition matrix dalam log-space atau linear
      double sample = _transitionMatrix![1][2]; // O -> B-VIN
      print("[INIT] Sample transition[O->B]: $sample (negatif = log-space, 0-1 = linear)");
    } catch (e) {
      print("[INIT] ❌ Error loading TFLite Config: $e");
    }
  }

  String preprocessText(String text) {
    String upper = text.toUpperCase();
    print("\n[PREPROCESS] === INPUT TEXT ===");
    print("[PREPROCESS] Raw input (${text.length} chars): '$text'");
    print("[PREPROCESS] After toUpperCase: '$upper'");

    upper = upper.replaceAll('I', '1').replaceAll('O', '0').replaceAll('Q', '0');
    print("[PREPROCESS] After I->1, O->0, Q->0: '$upper'");

    upper = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    print("[PREPROCESS] After strip non-alphanumeric (${upper.length} chars): '$upper'");
    return upper;
  }

  List<int> _tokenizeAndPad(String text) {
    List<int> tokens = [];
    for (int i = 0; i < text.length; i++) {
      String char = text[i];
      int idx = _char2idx?[char] ?? _char2idx?['UNK'] ?? 1;
      tokens.add(idx);
    }

    int originalLength = tokens.length;

    if (tokens.length > maxLength) {
      tokens = tokens.sublist(0, maxLength);
      print("[TOKENIZE] ⚠️  Text truncated from $originalLength to $maxLength chars");
    }

    int paddingAdded = 0;
    while (tokens.length < maxLength) {
      tokens.add(_char2idx?['PAD'] ?? 0);
      paddingAdded++;
    }

    print("\n[TOKENIZE] === TOKENIZATION RESULT ===");
    print("[TOKENIZE] Original text length: $originalLength chars");
    print("[TOKENIZE] Padding added: $paddingAdded tokens");
    print("[TOKENIZE] Total tokens: ${tokens.length}");
    print("[TOKENIZE] First 20 tokens: ${tokens.sublist(0, 20)}");
    if (originalLength < maxLength) {
      print("[TOKENIZE] Last 5 before PAD region: ${tokens.sublist(originalLength - 5, originalLength)}");
      print("[TOKENIZE] First 3 PAD tokens: ${tokens.sublist(originalLength, originalLength + 3)}");
    }

    return tokens;
  }

  // ============================================================
  // FIX: Viterbi dalam LOG-SPACE untuk menghindari numeric underflow
  // Sebelumnya pakai perkalian (*) yang menyebabkan probabilitas
  // mengecil drastis dan path tidak optimal.
  //
  // Jika transition matrix dari Python sudah log-space (nilai negatif):
  //   logTrans[i][j] = transitions[i][j]  (langsung pakai)
  // Jika transition matrix masih linear (nilai 0.0 - 1.0):
  //   logTrans[i][j] = log(transitions[i][j])
  //
  // Deteksi otomatis: cek apakah ada nilai negatif di matrix.
  // ============================================================
  List<int> _viterbiDecode(
      List<List<double>> emissions,
      List<List<double>> transitions,
      int actualSeqLen,
      ) {
    print("\n[VITERBI] === VITERBI DECODE (LOG-SPACE) ===");
    print("[VITERBI] Total emission length: ${emissions.length}");
    print("[VITERBI] Actual seq len (non-PAD): $actualSeqLen");
    print("[VITERBI] Num tags: ${transitions.length}");

    int seqLen = actualSeqLen;
    int numTags = transitions.length;

    // Deteksi apakah transition matrix sudah log-space
    bool isLogSpace = transitions.any((row) => row.any((v) => v < 0));
    print("[VITERBI] Transition matrix mode: ${isLogSpace ? 'LOG-SPACE (nilai negatif)' : 'LINEAR (0-1)'}");

    // Konversi emission ke log-space
    // emission dari model sudah softmax (sum=1), jadi log(p) valid
    List<List<double>> logEmissions = emissions.map((row) =>
        row.map((v) => v > 0 ? log(v) : -1e9).toList()
    ).toList();

    // Konversi transition ke log-space jika belum
    List<List<double>> logTransitions = isLogSpace
        ? transitions
        : transitions.map((row) =>
        row.map((v) => v > 0 ? log(v) : -1e9).toList()
    ).toList();

    // DEBUG: Tampilkan emission log pertama 5 posisi
    print("[VITERBI] Log-emission (first 5 positions):");
    for (int t = 0; t < 5 && t < actualSeqLen; t++) {
      print("[VITERBI]   pos[$t]: O=${logEmissions[t][1].toStringAsFixed(4)}, "
          "B=${logEmissions[t][2].toStringAsFixed(4)}, "
          "I=${logEmissions[t][3].toStringAsFixed(4)}, "
          "E=${logEmissions[t][4].toStringAsFixed(4)}");
    }

    // Inisialisasi viterbi score dengan -infinity
    List<List<double>> viterbi = List.generate(seqLen, (_) => List.filled(numTags, -1e9));
    List<List<int>> backpointers = List.generate(seqLen, (_) => List.filled(numTags, 0));

    // Step 1: Inisialisasi posisi pertama (hanya emission, tanpa transisi)
    for (int j = 0; j < numTags; j++) {
      viterbi[0][j] = logEmissions[0][j];
    }

    // Step 2: Forward pass dengan log-space (penjumlahan, bukan perkalian)
    for (int t = 1; t < seqLen; t++) {
      for (int j = 0; j < numTags; j++) {
        double maxScore = -1e9;
        int bestPrevTag = 0;

        for (int i = 0; i < numTags; i++) {
          // LOG-SPACE: tambah, bukan kali
          double score = viterbi[t - 1][i] + logTransitions[i][j] + logEmissions[t][j];
          if (score > maxScore) {
            maxScore = score;
            bestPrevTag = i;
          }
        }
        viterbi[t][j] = maxScore;
        backpointers[t][j] = bestPrevTag;
      }
    }

    // Step 3: Backtracking dari posisi terakhir
    int bestLastTag = 0;
    double maxScore = -1e9;
    for (int j = 0; j < numTags; j++) {
      if (viterbi[seqLen - 1][j] > maxScore) {
        maxScore = viterbi[seqLen - 1][j];
        bestLastTag = j;
      }
    }

    List<int> bestPath = List.filled(seqLen, 0);
    bestPath[seqLen - 1] = bestLastTag;
    for (int t = seqLen - 1; t > 0; t--) {
      bestPath[t - 1] = backpointers[t][bestPath[t]];
    }

    // DEBUG: Tampilkan hasil path
    print("\n[VITERBI] === PATH RESULT ===");
    List<int> vinPositions = [];
    for (int i = 0; i < bestPath.length; i++) {
      if (bestPath[i] >= 2 && bestPath[i] <= 4) {
        vinPositions.add(i);
      }
    }
    print("[VITERBI] VIN tag positions: $vinPositions");
    print("[VITERBI] Full path (${bestPath.length} steps): $bestPath");

    return bestPath;
  }

  String _extractVin(String cleanText, List<int> path) {
    print("\n[EXTRACT] === VIN EXTRACTION ===");
    print("[EXTRACT] cleanText length: ${cleanText.length}");
    print("[EXTRACT] path length: ${path.length}");
    print("[EXTRACT] cleanText: '$cleanText'");

    String vin = "";
    List<String> debugExtraction = [];

    for (int i = 0; i < path.length; i++) {
      if (i >= cleanText.length) {
        print("[EXTRACT] ⚠️  Path index $i melebihi panjang cleanText (${cleanText.length}). BERHENTI.");
        break;
      }
      int tag = path[i];
      String char = cleanText[i];
      String tagName = {0: "PAD", 1: "O", 2: "B", 3: "I", 4: "E"}[tag] ?? "?";

      if (tag == 2 || tag == 3 || tag == 4) {
        vin += char;
        debugExtraction.add("[$i]$char($tagName)");
      }
    }

    print("[EXTRACT] Karakter VIN yang dipilih: $debugExtraction");
    print("[EXTRACT] VIN Extracted: '$vin' (${vin.length} chars)");

    if (vin.length != 17) {
      print("[EXTRACT] ⚠️  PANJANG VIN TIDAK 17! (${vin.length} chars)");
    } else {
      print("[EXTRACT] ✅ Panjang VIN valid (17 karakter).");
    }

    return vin;
  }

  String? runInference(String text) {
    if (_interpreter == null || _char2idx == null || _transitionMatrix == null) {
      print("[INFERENCE] ❌ Model belum diinisialisasi!");
      return null;
    }

    print("\n" + "="*60);
    print("[INFERENCE] ===== MULAI INFERENSI =====");
    print("="*60);

    String cleanText = preprocessText(text);
    if (cleanText.isEmpty) {
      print("[INFERENCE] ❌ cleanText kosong setelah preprocessing!");
      return null;
    }

    int actualLen = cleanText.length.clamp(0, maxLength);
    print("\n[INFERENCE] actualLen (non-PAD): $actualLen");

    List<int> tokens = _tokenizeAndPad(cleanText);

    var inputTensor = [tokens];
    var outputTensor = List.generate(1, (_) => List.generate(maxLength, (_) => List.filled(5, 0.0)));

    try {
      _interpreter!.run(inputTensor, outputTensor);
      print("\n[INFERENCE] ✅ Model berhasil dijalankan.");
    } catch (e) {
      print("[INFERENCE] ❌ Kesalahan run TFLite: $e");
      return null;
    }

    var emissions = outputTensor[0];
    print("\n[INFERENCE] === RAW OUTPUT TENSOR ===");
    print("[INFERENCE] Emission shape: ${emissions.length} x ${emissions[0].length}");

    double sumPos0 = emissions[0].reduce((a, b) => a + b);
    double sumPos10 = emissions[10].reduce((a, b) => a + b);
    print("[INFERENCE] Sum probabilitas posisi[0]: ${sumPos0.toStringAsFixed(4)}");
    print("[INFERENCE] Sum probabilitas posisi[10]: ${sumPos10.toStringAsFixed(4)}");

    // Argmax tanpa Viterbi (sebagai pembanding)
    print("\n[INFERENCE] === ARGMAX BIASA (Tanpa Viterbi) ===");
    String argmaxVin = "";
    for (int i = 0; i < actualLen; i++) {
      int argmax = 0;
      double maxVal = emissions[i][0];
      for (int j = 1; j < 5; j++) {
        if (emissions[i][j] > maxVal) {
          maxVal = emissions[i][j];
          argmax = j;
        }
      }
      if (argmax >= 2 && argmax <= 4) {
        argmaxVin += cleanText[i];
      }
    }
    print("[INFERENCE] Argmax VIN: '$argmaxVin' (${argmaxVin.length} chars)");

    // Viterbi log-space
    List<int> bestPath = _viterbiDecode(emissions, _transitionMatrix!, actualLen);
    String finalVin = _extractVin(cleanText, bestPath);

    print("\n[INFERENCE] ===== HASIL AKHIR =====");
    print("[INFERENCE] Argmax VIN  : '$argmaxVin'");
    print("[INFERENCE] Viterbi VIN : '$finalVin'");
    print("="*60 + "\n");

    return finalVin.isNotEmpty ? finalVin : "Gagal memprediksi";
  }

  void dispose() {
    _interpreter?.close();
  }
}