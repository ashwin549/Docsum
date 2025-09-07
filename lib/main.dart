import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart'; // ✅ NEW

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();

  // Look for the back camera
  final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first, // fallback if none found
  );

  runApp(OCRApp(camera: backCamera));
}

class OCRApp extends StatelessWidget {
  final CameraDescription camera;
  const OCRApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCR Camera App',
      theme: ThemeData.dark(),
      home: CameraScreen(camera: camera),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OCRResultScreen(imageFile: File(image.path)),
        ),
      );
    } catch (e) {
      print("Error taking picture: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return CameraPreview(_controller);
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        child: const Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class OCRResultScreen extends StatefulWidget {
  final File imageFile;
  const OCRResultScreen({super.key, required this.imageFile});

  @override
  State<OCRResultScreen> createState() => _OCRResultScreenState();
}

class _OCRResultScreenState extends State<OCRResultScreen> {
  String _extractedText = "Extracting text...";
  String _summarizedText = "";
  bool _isLoading = true;
  bool _isSummarizing = false;
  bool _showSummary = false;

  @override
  void initState() {
    super.initState();
    _performOCR();
  }

  Future<void> _performOCR() async {
    try {
      final textRecognizer = TextRecognizer();
      final inputImage = InputImage.fromFile(widget.imageFile);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      setState(() {
        _extractedText = recognizedText.text.isEmpty
            ? "No text detected in the image."
            : recognizedText.text;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _extractedText = "Error extracting text: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _summarizeText() async {
    if (_extractedText.isEmpty || _extractedText == "No text detected in the image.") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No text to summarize!"),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSummarizing = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://fastapi-example-68a1.onrender.com/summarize'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'text': _extractedText,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        String summaryText = "";
        try {
          if (responseData['candidates'] != null &&
              responseData['candidates'].isNotEmpty &&
              responseData['candidates'][0]['content'] != null &&
              responseData['candidates'][0]['content']['parts'] != null &&
              responseData['candidates'][0]['content']['parts'].isNotEmpty) {
            summaryText = responseData['candidates'][0]['content']['parts'][0]['text'] ?? "";
          } else {
            summaryText = responseData['summary'] ?? responseData.toString();
          }
        } catch (e) {
          summaryText = responseData.toString();
        }

        setState(() {
          _summarizedText = summaryText.isEmpty ? "No summary generated" : summaryText;
          _showSummary = true;
          _isSummarizing = false;
        });
      } else {
        throw Exception('Failed to summarize: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isSummarizing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error summarizing text: $e"),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyToClipboard() async {
    String textToCopy = _showSummary ? _summarizedText : _extractedText;
    await Clipboard.setData(ClipboardData(text: textToCopy));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_showSummary ? "Summary copied to clipboard!" : "Text copied to clipboard!"),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showSummary ? "Summary" : "Extracted Text"),
        actions: [
          if (_showSummary)
            IconButton(
              onPressed: () {
                setState(() {
                  _showSummary = false;
                });
              },
              icon: const Icon(Icons.text_fields),
              tooltip: "Show original text",
            ),
          IconButton(
            onPressed: _isLoading ? null : _copyToClipboard,
            icon: const Icon(Icons.copy),
            tooltip: "Copy to clipboard",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show the captured image
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  widget.imageFile,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Text extraction result with summarize button
            Row(
              children: [
                Text(
                  _showSummary ? "Summary:" : "Extracted Text:",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                if (!_isLoading && _extractedText.isNotEmpty && _extractedText != "No text detected in the image.")
                  ElevatedButton.icon(
                    onPressed: _isSummarizing ? null : (_showSummary ? null : _summarizeText),
                    icon: _isSummarizing
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.summarize, size: 18),
                    label: Text(_isSummarizing ? "Summarizing..." : "Summarize"),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[900],
                ),
                child: _isLoading
                    ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Processing image..."),
                    ],
                  ),
                )
                    : SingleChildScrollView(
                  child: _showSummary
                      ? MarkdownBody(   // ✅ render markdown
                    data: _summarizedText,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: const TextStyle(fontSize: 16, color: Colors.lightBlueAccent),
                    ),
                  )
                      : SelectableText(
                    _extractedText,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isLoading
          ? null
          : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showSummary)
            FloatingActionButton(
              onPressed: () {
                setState(() {
                  _showSummary = false;
                });
              },
              heroTag: "show_original",
              child: const Icon(Icons.text_fields),
              tooltip: "Show original text",
            ),
          if (_showSummary) const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: _copyToClipboard,
            label: Text(_showSummary ? "Copy Summary" : "Copy Text"),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}
