import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/rollout_flags.dart';
import '../models/installed_app_info.dart';
import 'app_usage_service.dart';
import 'pairing_service.dart';

class ChildAppInventorySyncService {
  ChildAppInventorySyncService({
    FirebaseFirestore? firestore,
    AppUsageService? appUsageService,
    PairingService? pairingService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _appUsageService = appUsageService ?? AppUsageService(),
        _pairingService = pairingService ?? PairingService();

  final FirebaseFirestore _firestore;
  final AppUsageService _appUsageService;
  final PairingService _pairingService;

  static const Duration _freshUploadInterval = Duration(hours: 24);
  DateTime? _lastUploadedAt;
  String? _lastUploadedHash;

  Future<bool> syncIfNeeded({
    required String childId,
    bool force = false,
  }) async {
    if (!RolloutFlags.appInventory) {
      return false;
    }
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      return false;
    }

    try {
      final apps = await _appUsageService.getInstalledLaunchableApps();
      final normalizedApps = apps
          .where((app) => app.isValid)
          .map(
            (app) => app.copyWith(
              packageName: app.packageName.trim().toLowerCase(),
              appName: app.appName.trim(),
            ),
          )
          .toList(growable: false)
        ..sort(
          (a, b) => a.packageName.compareTo(b.packageName),
        );
      final hash = _computeInventoryHash(normalizedApps);
      final now = DateTime.now();
      final needsFreshUpload = _lastUploadedAt == null ||
          now.difference(_lastUploadedAt!) >= _freshUploadInterval;
      final hasChanged = _lastUploadedHash == null || _lastUploadedHash != hash;
      if (!force && !hasChanged && !needsFreshUpload) {
        return false;
      }

      final deviceId = await _pairingService.getOrCreateDeviceId();
      final payload = <String, dynamic>{
        'version': now.millisecondsSinceEpoch,
        'hash': hash,
        'capturedAt': FieldValue.serverTimestamp(),
        'deviceId': deviceId.trim(),
        'apps': normalizedApps
            .map(
              (app) => <String, dynamic>{
                'packageName': app.packageName,
                'appName': app.appName,
                'isSystemApp': app.isSystemApp,
                'isLaunchable': app.isLaunchable,
                'firstSeenAtEpochMs': app.firstSeenAt?.millisecondsSinceEpoch ??
                    now.millisecondsSinceEpoch,
                'lastSeenAtEpochMs': app.lastSeenAt?.millisecondsSinceEpoch ??
                    now.millisecondsSinceEpoch,
                if (app.appIconBase64 != null &&
                    app.appIconBase64!.trim().isNotEmpty)
                  'appIconBase64': app.appIconBase64!.trim(),
              },
            )
            .toList(growable: false),
        'inventoryStatus': <String, dynamic>{
          'source': 'launchable_apps',
          'appCount': normalizedApps.length,
          'updatedAtLocal': now.toIso8601String(),
        },
      };

      await _firestore
          .collection('children')
          .doc(normalizedChildId)
          .collection('app_inventory')
          .doc('current')
          .set(payload, SetOptions(merge: false));

      _lastUploadedHash = hash;
      _lastUploadedAt = now;
      return true;
    } catch (error) {
      debugPrint('[ChildAppInventorySync] failed: $error');
      return false;
    }
  }

  String _computeInventoryHash(List<InstalledAppInfo> apps) {
    final normalized = apps
        .map(
          (app) => '${app.packageName}|${app.appName.toLowerCase()}|'
              '${app.isSystemApp ? 1 : 0}',
        )
        .toList(growable: false)
      ..sort();
    return base64Url.encode(utf8.encode(normalized.join('\n')));
  }
}
