import 'dart:io' show Platform;

import 'package:flutter/material.dart';

void main() {
  runApp(const PhotoSwipeApp());
}

class PhotoSwipeApp extends StatelessWidget {
  const PhotoSwipeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwipeSort',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const SetupCheckScreen(),
    );
  }
}

/// Temporary Phase 0 screen. It proves the app builds and runs on each
/// platform. Phase 1 replaces it with the album picker.
class SetupCheckScreen extends StatelessWidget {
  const SetupCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Phase 1 uses this same check to choose a PhotoRepository:
    // the Android gallery on a phone, or a test folder on Windows.
    final platform = Platform.isAndroid
        ? 'Android'
        : Platform.isWindows
        ? 'Windows'
        : Platform.operatingSystem;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swipe, size: 64),
            const SizedBox(height: 16),
            Text(
              'SwipeSort',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text('Running on $platform'),
          ],
        ),
      ),
    );
  }
}
