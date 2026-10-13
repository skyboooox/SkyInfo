part of 'app_controller.dart';

extension HaController on AppController {
  bool canOperateHa(String id) {
    final quality = reading(id).value.quality;
    if (quality == 'available') return true;
    final entity = haEntity(id);
    return quality == 'unknown' &&
        id.split('|').length == 3 &&
        entity != null &&
        {'button', 'input_button', 'scene', 'script'}.contains(entity.domain) &&
        entity.functions.isNotEmpty &&
        entity.functions.every((function) => function.kind == 'button');
  }

  List<Metric> get allMetrics => [
    ...metrics,
    ...controlEntities.map((e) => e.metric),
    ...haFields.values,
  ];
  HaEntity? haEntity(String id) {
    final key = id.split('|').take(3).join('|');
    final index = _haEntityIndices[key];
    return index == null ? null : haEntities[index];
  }

  bool isControl(String id) =>
      id.startsWith('control.') ||
      id.startsWith('ha|') &&
          id.split('|').length == 3 &&
          (haEntity(id)?.functions.isNotEmpty ?? false);
  void applyHaDirectory(Map<String, dynamic> directory, {bool notify = true}) {
    haImportState = directory['state'] ?? 'disabled';
    haEntities = (directory['entities'] as List? ?? [])
        .map((j) => HaEntity.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    _haEntityIndices.clear();
    for (var i = 0; i < haEntities.length; i++) {
      _haEntityIndices[haEntities[i].id] = i;
    }
    final fields = Map<String, dynamic>.from(directory['fields'] ?? {});
    final retained = {
      ...tiles.expand((tile) => tile.fields),
      ...overlays.map((m) => m.field),
    };
    haFields.removeWhere(
      (id, _) => !fields.containsKey(id) && !retained.contains(id),
    );
    for (final entry in fields.entries) {
      haFields[entry.key] = Metric.fromJson(
        Map<String, dynamic>.from(entry.value),
      );
      reading(entry.key);
      commandResults.putIfAbsent(entry.key, () => ValueNotifier(null));
    }
    if (notify && !_disposed) _notify();
  }

  void applyHaEntityUpdates(List<Map<String, dynamic>> updates) {
    if (_disposed) return;
    var changed = false;
    final next = List<HaEntity>.of(haEntities);
    for (final update in updates) {
      final id = update['id'] as String?;
      final index = _haEntityIndices[id];
      if (index == null || id?.split('|')[1] != haConnectionId) continue;
      next[index] = HaEntity.fromJson(update);
      changed = true;
    }
    if (changed) {
      haEntities = next;
      _notify();
    }
  }

  Future<void> refreshHaDirectory() async {
    try {
      final r = await bridge.call('haDirectory');
      if (!_disposed) applyHaDirectory(r);
    } catch (_) {
      if (!_disposed) {
        haImportState = 'error';
        _notify();
      }
    }
  }

  Future<Map<String, dynamic>> haCommand(
    String id,
    String function,
    Object? value, {
    bool confirmed = false,
  }) async {
    final key = id.split('|').take(3).join('|');
    if (!id.startsWith('ha|') ||
        id.split('|').length != 3 ||
        id.split('|')[1] != haConnectionId) {
      return {'status': 'not_added'};
    }
    if (haImportState != 'connected' || !canOperateHa(key)) {
      return {'status': 'disconnected'};
    }
    if (_disposed || status['stopped'] == true) return {'status': 'stopped'};
    if (!tiles.any((t) => t.kind.controls && t.fields.contains(key))) {
      return {'status': 'not_added'};
    }
    if (pendingCommands.contains(key)) return {'status': 'busy'};
    final resultNotifier = commandResults.putIfAbsent(
      key,
      () => ValueNotifier(null),
    );
    pendingCommands.add(key);
    resultNotifier.value = 'pending';
    try {
      final r = await bridge.call('haControl', {
        'field': key,
        'function': function,
        'value': value,
        'confirmed': confirmed,
      });
      if (!_disposed) resultNotifier.value = r['status'] ?? 'error';
      return r;
    } catch (_) {
      if (!_disposed) resultNotifier.value = 'error';
      return {'status': 'error'};
    } finally {
      pendingCommands.remove(key);
    }
  }
}
