import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:trustbridge_app/core/utils/app_logger.dart';

import '../config/blocklist_sources.dart';
import '../firebase_options.dart';
import '../models/blocklist_source.dart';
import 'blocklist_sync_service.dart';
import 'heartbeat_service.dart';
import 'remote_command_service.dart';

const String _categoriesInputKey = 'categories_csv';

/// Background callback used by WorkManager to run periodic blocklist sync.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      if (taskName == HeartbeatService.taskName) {
        await HeartbeatService.sendHeartbeat();
        await RemoteCommandService().processPendingCommands();
        return true;
      }

      if (taskName == RemoteCommandService.taskName) {
        await RemoteCommandService().processPendingCommands();
        return true;
      }

      final categories = _decodeCategories(inputData);
      await BlocklistSyncService().syncAll(categories);
      return true;
    } catch (error) {
      AppLogger.debug('[BlocklistWork] Background sync failed: $error');
      return false;
    }
  });
}

/// Schedules and manages periodic blocklist sync tasks.
class BlocklistWorkmanagerService {
  BlocklistWorkmanagerService._();

  /// Periodic task identifier.
  static const String taskName = 'trustbridge_blocklist_sync';
  static const String _uniqueTaskName = 'trustbridge_blocklist_sync_unique';

  static bool _initialized = false;

  /// Initializes WorkManager and callback dispatcher.
  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await Workmanager().initialize(
      callbackDispatcher,
    );
    _initialized = true;
  }

  /// Registers daily periodic blocklist sync for enabled categories.
  static Future<void> registerDailySync(
    List<BlocklistCategory> enabledCategories,
  ) async {
    await initialize();

    if (enabledCategories.isEmpty) {
      await cancelDailySync();
      return;
    }

    await Workmanager().registerPeriodicTask(
      _uniqueTaskName,
      taskName,
      frequency: const Duration(days: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      inputData: <String, dynamic>{
        _categoriesInputKey: _encodeCategories(enabledCategories),
      },
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// Cancels scheduled daily blocklist sync.
  static Future<void> cancelDailySync() async {
    await Workmanager().cancelByUniqueName(_uniqueTaskName);
  }
}

String _encodeCategories(List<BlocklistCategory> categories) {
  final unique = <String>{};
  for (final category in categories) {
    unique.add(category.name);
  }
  return unique.join(',');
}

List<BlocklistCategory> _decodeCategories(Map<String, dynamic>? inputData) {
  final raw = inputData?[_categoriesInputKey];
  if (raw is! String || raw.trim().isEmpty) {
    return BlocklistSources.all
        .map((source) => source.category)
        .toList(growable: false);
  }

  final decoded = <BlocklistCategory>[];
  for (final token in raw.split(',')) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    for (final category in BlocklistCategory.values) {
      if (category.name == trimmed) {
        decoded.add(category);
      }
    }
  }

  if (decoded.isEmpty) {
    return BlocklistSources.all
        .map((source) => source.category)
        .toList(growable: false);
  }
  return decoded;
}
