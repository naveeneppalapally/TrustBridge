import 'package:flutter/material.dart';

Future<void> guardedNavigate(
  BuildContext context,
  Future<void> Function() navigate,
) async {
  if (context.mounted) {
    await navigate();
  }
}
