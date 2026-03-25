import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ScanPage extends StatefulWidget {
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  File? _capturedImage;
  final ImagePicker _picker = ImagePicker();
  bool _useRearCamera = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照'),
        actions: [
          IconButton(
            icon: Icon(Icons.switch_camera),
            iconSize: 32.0,
            color: Colors.white,
            onPressed: () {
              setState(() {
                _useRearCamera = !_useRearCamera;
              });
            },
          ),
        ],
      ),
      body: _capturedImage != null ? _buildPreview() : _buildPlaceholder(),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePhoto,
        child: Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 80, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            '点击下方按钮拍照',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          SizedBox(height: 8),
          Text(
            _useRearCamera ? '当前: 后置摄像头' : '当前: 前置摄像头',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          _capturedImage!,
          fit: BoxFit.contain,
        ),
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'close',
            onPressed: () {
              setState(() {
                _capturedImage = null;
              });
            },
            child: Icon(Icons.close),
          ),
        ),
      ],
    );
  }

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice:
          _useRearCamera ? CameraDevice.rear : CameraDevice.front,
    );
    if (photo != null) {
      setState(() {
        _capturedImage = File(photo.path);
      });
    }
  }
}
