import 'package:flutter/material.dart';

/// PIN lock has been removed from parent flows.
/// Keep this helper for backward compatibility and always allow.
Future<bool> requireParentPin(BuildContext context) async {
  return true;
}
