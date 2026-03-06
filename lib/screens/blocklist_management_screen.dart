import 'package:flutter/material.dart';

class BlocklistManagementScreen extends StatelessWidget {
  const BlocklistManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocklist Management')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Blocklist management is not available in this baseline.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
