import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

import '../../common.dart';

class ScanPage extends StatefulWidget {
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');

  @override
  void reassemble() {
    super.reassemble();
    if (isAndroid && controller != null) {
      controller!.pauseCamera();
    } else if (controller != null) {
      controller!.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('摄像头'),
        actions: [
          _buildFlashToggleButton(),
        ],
      ),
      body: _buildCameraView(context),
    );
  }

  Widget _buildCameraView(BuildContext context) {
    return QRView(
      key: qrKey,
      onQRViewCreated: _onViewCreated,
      onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
    );
  }

  void _onViewCreated(QRViewController controller) {
    setState(() {
      this.controller = controller;
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      showToast('没有相机权限');
    }
  }

  Widget _buildFlashToggleButton() {
    return IconButton(
      color: Colors.yellow,
      icon: Icon(Icons.flash_on),
      iconSize: 32.0,
      onPressed: () async {
        await controller?.toggleFlash();
      },
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
