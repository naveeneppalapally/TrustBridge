import 'package:flutter/material.dart';

import '../models/child_profile.dart';

class ChildRequestScreen extends StatelessWidget {
  const ChildRequestScreen({
    super.key,
    required this.child,
  });

  final ChildProfile child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask for Access')),
      body: const Center(
        child: Text('Coming in Day 45!'),
      ),
    );
  }
}
