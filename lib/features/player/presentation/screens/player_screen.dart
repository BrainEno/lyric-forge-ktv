import 'package:flutter/material.dart';

class PlayerScreen extends StatelessWidget {
  final String projectId;

  const PlayerScreen({
    super.key,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player'),
      ),
      body: Center(
        child: Text('Player: $projectId'),
      ),
    );
  }
}
