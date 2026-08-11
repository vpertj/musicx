import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: MusicxApp()));
}

class MusicxApp extends StatelessWidget {
  const MusicxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicX',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const HomeShell(),
    );
  }
}
