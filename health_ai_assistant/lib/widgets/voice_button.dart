import 'package:flutter/material.dart';

/// Round mic button; turns red while listening.
class VoiceButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onPressed;

  const VoiceButton({super.key, required this.listening, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'voice',
      onPressed: onPressed,
      backgroundColor: listening ? Colors.red : Colors.teal,
      foregroundColor: Colors.white,
      child: Icon(listening ? Icons.stop : Icons.mic),
    );
  }
}
