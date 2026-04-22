import 'package:flutter/material.dart';

class LyricEditorScreen extends StatelessWidget {
  final String projectId;

  const LyricEditorScreen({
    super.key,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyric Editor'),
      ),
      body: Center(
        child: Text('Lyric Editor: $projectId'),
      ),
    );
  }
}
