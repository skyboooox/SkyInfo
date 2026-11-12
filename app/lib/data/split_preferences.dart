part of 'app_controller.dart';

extension SplitPreferences on AppController {
  Future<bool> saveSplitPreferences({
    String? page,
    List<SplitCombo>? combos,
  }) async {
    if (_disposed || splitSaving) return false;
    splitSaving = true;
    _notify();
    try {
      final result = await bridge.call('saveSplitPreferences', {
        'startupPage': ?page,
        if (combos != null)
          'splitCombos': combos.map((e) => e.toJson()).toList(),
      });
      if (_disposed) return false;
      if (result['config'] is! Map) throw StateError('split_save_result');
      final saved = result['config'] as Map;
      startupPage = startupPages.contains(saved['startupPage'])
          ? saved['startupPage'] as String
          : 'information';
      splitCombos = (saved['splitCombos'] as List? ?? [])
          .map((e) => SplitCombo.fromJson(e as Map))
          .toList();
      return true;
    } catch (_) {
      return false;
    } finally {
      splitSaving = false;
      _notify();
    }
  }

  Future<Map<String, dynamic>> launchSplit(SplitDraft draft) async {
    if (splitLaunching) return {'status': 'busy'};
    if (!draft.complete) {
      return {'status': 'failed', 'reason': 'invalid_target'};
    }
    splitLaunching = true;
    _notify();
    try {
      return await bridge.call('launchSplit', {
        'left': draft.left!.toJson(),
        'right': draft.right!.toJson(),
        'ratio': draft.ratio,
      });
    } catch (_) {
      return {'status': 'failed', 'reason': 'launch_failed'};
    } finally {
      splitLaunching = false;
      _notify();
    }
  }
}
