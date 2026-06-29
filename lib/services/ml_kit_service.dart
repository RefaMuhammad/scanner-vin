import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class MLKitService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<String?> scanTextFromImage(XFile imageFile) async {
    final InputImage inputImage = InputImage.fromFilePath(imageFile.path);
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      print("Error saat OCR scan teks: $e");
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}