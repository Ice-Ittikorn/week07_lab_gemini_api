import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/listing_draft.dart';
import '../services/gemini_vision_service.dart';

class SellItemPage extends StatefulWidget {
  const SellItemPage({super.key});

  @override
  State<SellItemPage> createState() => _SellItemPageState();
}

class _SellItemPageState extends State<SellItemPage> {
  File? _selectedImage;
  bool _isAnalyzing = false;
  String? _errorMessage;
  ListingDraft? _draft;

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) return;

    setState(() {
      _selectedImage = File(pickedFile.path);
      _draft = null;
      _errorMessage = null;
    });
  }

  Future<void> _analyzeImage() async {
    final image = _selectedImage;
    if (image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรูปภาพสินค้าก่อน')),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _draft = null;
    });

    _showAnalyzingDialog();

    try {
      final draft = await GeminiVisionService().analyzeProductImage(image);
      if (!mounted) return;
      setState(() => _draft = draft);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // ปิด popup
        setState(() => _isAnalyzing = false);
      }
    }
  }

  void _showAnalyzingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(strokeWidth: 6),
                ),
                SizedBox(height: 28),
                Text(
                  'AI กำลังวิเคราะห์ภาพสินค้า...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('กรุณารอสักครู่'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    if (_errorMessage != null) {
      return Text(
        _errorMessage!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
        textAlign: TextAlign.center,
      );
    }
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ชื่อประกาศ', style: Theme.of(context).textTheme.labelMedium),
            Text(draft.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('หมวดหมู่', style: Theme.of(context).textTheme.labelMedium),
            Text(draft.category),
            const SizedBox(height: 12),
            Text('คำบรรยาย', style: Theme.of(context).textTheme.labelMedium),
            Text(draft.description),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลงประกาศขายสินค้า')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_selectedImage != null)
              Image.file(_selectedImage!, height: 300, fit: BoxFit.cover)
            else
              Container(
                height: 300,
                color: Colors.grey[300],
                child: const Icon(Icons.image, size: 80),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('เลือกรูปภาพ'),
                    onPressed: _pickImage,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.smart_toy),
                    label: const Text('ให้ AI ช่วยแนะนำ'),
                    onPressed: _isAnalyzing ? null : _analyzeImage,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildResult(),
          ],
        ),
      ),
    );
  }
}
