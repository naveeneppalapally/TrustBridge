import 'package:shared_preferences/shared_preferences.dart';

class OnboardingStateService {
  static const String _localCompletionPrefix = 'onboarding_complete_local_';

  String _keyFor(String parentId) {
    return '$_localCompletionPrefix${parentId.trim()}';
  }

  Future<bool> isCompleteLocally(String parentId) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFor(normalizedParentId)) == true;
  }

  Future<void> markCompleteLocally(String parentId) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFor(normalizedParentId), true);
  }

  Future<void> clearLocalCompletion(String parentId) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(normalizedParentId));
  }
}
