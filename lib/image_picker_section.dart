import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImagePickerSection extends StatefulWidget {
  final Function(Uint8List?) onImageSelected;

  const ImagePickerSection({super.key, required this.onImageSelected});

  @override
  State<ImagePickerSection> createState() => _ImagePickerSectionState();
}

class _ImagePickerSectionState extends State<ImagePickerSection> {
  Uint8List? _selectedImage;

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image == null) return;

      Uint8List imageBytes = await image.readAsBytes();
      setState(() {
        _selectedImage = imageBytes;
      });

      widget.onImageSelected(imageBytes);
    } catch (e) {
      debugPrint("Image pick error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 240,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: _selectedImage == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo,
                      size: 48, color: Colors.grey.shade600),
                  SizedBox(height: 8),
                  Text(
                    "點擊以上傳食物照片",
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _selectedImage!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
      ),
    );
  }
}
