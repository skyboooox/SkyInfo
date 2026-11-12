import 'package:flutter/foundation.dart';
import '../domain/split_screen.dart';
import 'vehicle_bridge.dart';

class SplitCatalog extends ChangeNotifier {
  final VehicleBridge bridge;
  SplitCatalog(this.bridge);
  List<SplitApp> apps = [];
  final Map<String, List<SplitActivity>> activities = {};
  final Map<String, String> activityErrors = {};
  bool loading = true, supported = true, disposed = false;
  String? error;
  int _epoch = 0;
  final Map<String, int> _activityEpochs = {};
  Future<void> refresh(Iterable<SplitTarget?> targets) async {
    if (disposed) return;
    final epoch = ++_epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await bridge.call('splitApps');
      if (disposed || epoch != _epoch) return;
      if (result['reason'] != null || result['apps'] is! List) {
        throw StateError('query_failed');
      }
      apps = (result['apps'] as List)
          .map((e) => SplitApp.fromJson(e as Map))
          .toList();
      supported = result['supported'] != false;
      activities.clear();
      activityErrors.clear();
      for (final package
          in targets
              .whereType<SplitTarget>()
              .where((e) => e.activityName != null)
              .map((e) => e.packageName)
              .toSet()) {
        if (disposed || epoch != _epoch) return;
        try {
          await loadActivities(package, refreshEpoch: epoch);
        } catch (_) {
          /* A failed side remains repairable without hiding other applications. */
        }
      }
    } catch (_) {
      if (!disposed && epoch == _epoch) error = 'query_failed';
    } finally {
      if (!disposed && epoch == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<List<SplitActivity>> loadActivities(
    String package, {
    int? refreshEpoch,
  }) async {
    final catalogEpoch = refreshEpoch ?? _epoch;
    final activityEpoch = (_activityEpochs[package] ?? 0) + 1;
    _activityEpochs[package] = activityEpoch;
    bool current() =>
        !disposed &&
        _activityEpochs[package] == activityEpoch &&
        catalogEpoch == _epoch;
    try {
      final result = await bridge.call('splitActivities', {
        'packageName': package,
      });
      if (!current()) return [];
      if (result['reason'] != null || result['activities'] is! List) {
        throw StateError('query_failed');
      }
      final list = (result['activities'] as List)
          .map((e) => SplitActivity.fromJson(e as Map))
          .toList();
      activities[package] = list;
      activityErrors.remove(package);
      return list;
    } catch (_) {
      if (current()) {
        activityErrors[package] = 'query_failed';
        activities.remove(package);
      }
      rethrow;
    }
  }

  SplitApp? app(SplitTarget? target) {
    if (target == null) return null;
    for (final app in apps) {
      if (app.packageName == target.packageName) return app;
    }
    return null;
  }

  String? invalid(SplitTarget? target) {
    if (target == null) return 'invalid_target';
    if (error != null) return error;
    final installed = app(target);
    if (installed == null) return 'package_unavailable';
    if (activityErrors[target.packageName] != null) return 'query_failed';
    final entries = activities[target.packageName];
    if (target.activityName == null) {
      if (installed.defaultActivity.isEmpty) return 'activity_unavailable';
      if (entries == null) return null;
      for (final entry in entries) {
        if (entry.isDefault ||
            splitActivityName(target.packageName, entry.activityName) ==
                splitActivityName(
                  target.packageName,
                  installed.defaultActivity,
                )) {
          return entry.available
              ? null
              : entry.reason ?? 'activity_unavailable';
        }
      }
      return 'activity_unavailable';
    }
    if (entries == null) return 'query_failed';
    for (final entry in entries) {
      if (splitActivityName(target.packageName, entry.activityName) ==
          splitActivityName(target.packageName, target.activityName!)) {
        return entry.available ? null : entry.reason ?? 'activity_unavailable';
      }
    }
    return 'activity_unavailable';
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
