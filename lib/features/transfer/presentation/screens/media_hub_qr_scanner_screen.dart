import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

class MediaHubQrScannerScreen extends StatefulWidget {
  const MediaHubQrScannerScreen({super.key});

  @override
  State<MediaHubQrScannerScreen> createState() =>
      _MediaHubQrScannerScreenState();
}

class _MediaHubQrScannerScreenState extends State<MediaHubQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;

    final value = capture.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;

    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'lyricforge' ||
        uri.host != 'media-hub') {
      return;
    }

    _handled = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pureBlack,
      appBar: AppBar(
        title: const Text('扫描桌面配对码'),
        backgroundColor: AppColors.pureBlack,
        actions: [
          IconButton(
            tooltip: '切换闪光灯',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.accent,
                    width: 3,
                  ),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusLarge),
                ),
              ),
            ),
          ),
          const Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.xxl,
            child: Text(
              '将桌面端“远程音乐库”中的二维码放入框内',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.pureWhite),
            ),
          ),
        ],
      ),
    );
  }
}
