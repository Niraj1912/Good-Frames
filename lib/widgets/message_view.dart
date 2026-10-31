import 'package:flutter/material.dart';

/// A centered message for empty and error states.
class MessageView extends StatelessWidget {
  const MessageView(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
