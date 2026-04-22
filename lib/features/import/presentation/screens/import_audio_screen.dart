import 'package:flutter/material.dart';

class ImportAudioScreen extends StatelessWidget {
  const ImportAudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Audio'),
      ),
      body: const Center(
        child: Text('Import Audio Screen'),
      ),
    );
  }
}
