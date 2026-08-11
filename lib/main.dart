import 'package:flutter/material.dart';

void main() {
  runApp(const MusicxApp());
}

class MusicxApp extends StatelessWidget {
  const MusicxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicX',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      home: const Scaffold(
        body: Center(child: Text('MusicX')),
      ),
    );
  }
}
