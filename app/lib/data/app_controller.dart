import '../l10n/strings.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../domain/control_entity.dart';
import '../domain/ha_entity.dart';
import '../domain/dashboard_layout.dart';
import 'vehicle_bridge.dart';

part 'ha_controller.dart';

class AppController extends ChangeNotifier {
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  final VehicleBridge bridge;
  AppController({VehicleBridge? bridge}) : bridge = bridge ?? VehicleBridge();
  List<Metric> metrics = [];
  List<HaEntity> haEntities = [];
  final Map<String, int> _haEntityIndices = {};
  Map<String, Metric> haFields = {};
  String haConnectionId = '', haImportState = 'disabled';
  bool haImportEnabled = false;
  List<ControlEntity> controlEntities = [];
  final Map<String, ValueNotifier<String?>> commandResults = {};
  final Set<String> pendingCommands = {};
  final Map<Object, Set<String>> _previewLeases = {};
  Future<void>? _previewQueue;
  bool _disposed = false;
  List<Map<String, dynamic>> iconCatalog = [];
  List<TileSpec> tiles = [];
  List<OverlaySpec> overlays = [];
  Set<String> uploaded = {};
  final Map<String, ValueNotifier<Sample>> readings = {};
  Map<String, dynamic> status = {};
  String theme = 'system',
      connection = 'ha',
      haUrl = '',
      prefix = 'skyinfo',
      mqttHost = '';
  DashboardSize dashboardSize = DashboardSize.standard;
  bool adbEnabled = false;
  String adbHost = '127.0.0.1', adbMode = 'tcp';
  int adbPort = 5555;
  int mqttPort = 8883;
  String mqttTopic = '', mqttUser = '';
  String mqttTransport = 'tls',
      haBirthTopic = 'homeassistant/status',
      haBirthPayload = 'online';
  Set<String> insecureAcknowledgements = {};
  bool reduceMotion = false,
      autoStart = true,
      haControlEnabled = false,
      mqttControlEnabled = false,
      collect = true,
      overlayEnabled = false,
      publishEnabled = false,
      fallbackPolling = false,
      localHistory = true,
      retainHistory = false,
      mqttState = false;
  int localHistoryMinutes = 30;
  String mqttProtocol = "5";
  Map<String, String> entityMappings = {};
  final Map<String, (DateTime, Future<List<HistoryPoint>>)> _historyRequests =
      {};
  double overlayFont = 18,
      overlayOpacity = 0.8,
      overlayOffset = 0,
      overlayLeft = 128,
      overlayRight = 320;
  double? overlayX, overlayY;
  StreamSubscription<Map<String, dynamic>>? _events;
  String? error;
  Map<String, dynamic> get config => {
    'schema': 2,
    'adbEnabled': adbEnabled,
    'adbHost': adbHost,
    'adbPort': adbPort,
    'adbMode': adbMode,
    'haConnectionId': haConnectionId,
    'haImportEnabled': haImportEnabled,
    'haFields': {
      for (final id in {
        ...tiles.expand((t) => t.fields),
        ...overlays.map((o) => o.field),
      }.where((id) => id.startsWith('ha|')))
        id: {
          'id': id,
          'name': metric(id).name,
          'category': 'Home Assistant',
          'icon': '',
          'unit': metric(id).unit,
          'encoding': metric(id).encoding == 'number' ? '数值' : '文本',
          'entityKey': id.split('|')[2],
          'displayAllowed': true,
        },
    },
    'localHistoryPolicyVersion': 1,
    'haControlEnabled': haControlEnabled,
    'mqttControlEnabled': mqttControlEnabled,
    'localHistory': localHistory,
    'retainHistory': retainHistory,
    'localHistoryMinutes': localHistoryMinutes,
    'mqttProtocol': mqttProtocol,
    'mqttTransport': mqttTransport,
    'haBirthTopic': haBirthTopic,
    'haBirthPayload': haBirthPayload,
    'insecureAcknowledgements': insecureAcknowledgements.toList(),
    'mqttState': mqttState,
    'entityMappings': entityMappings,
    'tiles': tiles.map((t) => t.toJson()).toList(),
    'overlays': overlays.map((o) => o.toJson()).toList(),
    'uploaded': uploaded.toList(),
    'theme': theme,
    'dashboardSize': dashboardSize.name,
    'connection': connection,
    'haUrl': haUrl,
    'prefix': prefix,
    'mqttHost': mqttHost,
    'mqttPort': mqttPort,
    'mqttTopic': mqttTopic,
    'mqttUser': mqttUser,
    'reduceMotion': reduceMotion,
    'autoStart': autoStart,
    'collect': collect,
    'overlayEnabled': overlayEnabled,
    'publishEnabled': publishEnabled,
    'fallbackPolling': fallbackPolling,
    'overlayFont': overlayFont,
    'overlayOpacity': overlayOpacity,
    'overlayOffset': overlayOffset,
    'overlayLeft': overlayLeft,
    'overlayRight': overlayRight,
    'overlayX': overlayX,
    'overlayY': overlayY,
  };
  Future<void> initialize() async {
    await Strings.load();
    final catalog =
        jsonDecode(await rootBundle.loadString('assets/catalog.json')) as List;
    metrics = catalog
        .map((j) => Metric.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    final icons = jsonDecode(
      await rootBundle.loadString('assets/icon-manifest.json'),
    );
    iconCatalog = List<Map<String, dynamic>>.from(icons['icons'])
        .map(
          (i) => {
            ...i,
            'name': Strings.text(i['nameKey']),
            'category': Strings.text(i['categoryKey']),
          },
        )
        .toList();
    controlEntities =
        (jsonDecode(await rootBundle.loadString('assets/entities.json'))
                as List)
            .map((j) => ControlEntity.fromJson(Map<String, dynamic>.from(j)))
            .toList();
    for (final m in metrics) {
      readings[m.id] = ValueNotifier(Sample());
    }
    for (final entity in controlEntities) {
      readings[entity.id] = ValueNotifier(Sample());
      commandResults[entity.id] = ValueNotifier(null);
      for (final field in entity.feedbackFields) {
        readings.putIfAbsent(field, () => ValueNotifier(Sample()));
      }
    }
    try {
      final loaded = await bridge.call('load');
      restore(Map<String, dynamic>.from(loaded['config'] ?? {}));
      status = Map<String, dynamic>.from(loaded['status'] ?? {});
      if (loaded['haDirectory'] is Map) {
        applyHaDirectory(
          Map<String, dynamic>.from(loaded['haDirectory']),
          notify: false,
        );
      }
      applySamples(Map<String, dynamic>.from(loaded['samples'] ?? {}));
      _events = bridge.events.listen(
        (e) {
          if (e['overlayPosition'] is Map) {
            final position = e['overlayPosition'] as Map;
            final x = (position['x'] as num?)?.toDouble();
            final y = (position['y'] as num?)?.toDouble();
            if (overlayX != x || overlayY != y) {
              overlayX = x;
              overlayY = y;
              notifyListeners();
            }
          }
          if (e['config'] is Map) {
            restore(Map<String, dynamic>.from(e['config']));
          }
          if (e['haDirectory'] is Map) {
            applyHaDirectory(Map<String, dynamic>.from(e['haDirectory']));
          }
          if (e['haEntityUpdates'] is List) {
            applyHaEntityUpdates(
              List<Map<String, dynamic>>.from(
                (e['haEntityUpdates'] as List).map(
                  (v) => Map<String, dynamic>.from(v),
                ),
              ),
            );
          }
          if (e['samples'] is Map) {
            applySamples(Map<String, dynamic>.from(e['samples']));
          }
          if (e['status'] is Map) {
            final next = Map<String, dynamic>.from(e['status']);
            if (!mapEquals(status, next)) {
              status = next;
              notifyListeners();
            }
          }
        },
        onError: (Object e) {
          status = {'vehicle': Strings.text('text_c5bf1313e8')};
          notifyListeners();
        },
      );
    } catch (e) {
      error = Strings.text('text_6cfbed4855');
    }
    notifyListeners();
  }

  void restore(Map<String, dynamic> c) {
    if (c.isEmpty) return;
    adbEnabled = c['adbEnabled'] ?? false;
    adbHost = c['adbHost'] ?? '127.0.0.1';
    adbPort = c['adbPort'] ?? 5555;
    adbMode = c['adbMode'] ?? 'tcp';
    haConnectionId = c['haConnectionId'] ?? haConnectionId;
    haImportEnabled = c['haImportEnabled'] ?? false;
    for (final entry in Map<String, dynamic>.from(
      c['haFields'] ?? {},
    ).entries) {
      haFields[entry.key] = Metric.fromJson(
        Map<String, dynamic>.from(entry.value),
      );
      reading(entry.key);
    }
    tiles = (c['tiles'] as List? ?? [])
        .map((t) => TileSpec.fromJson(Map<String, dynamic>.from(t)))
        .toList();
    overlays = (c['overlays'] as List? ?? [])
        .map((o) => OverlaySpec.fromJson(Map<String, dynamic>.from(o)))
        .toList();
    uploaded = Set<String>.from(c['uploaded'] ?? []);
    theme = c['theme'] ?? 'system';
    dashboardSize = DashboardSize.values.firstWhere(
      (size) => size.name == c['dashboardSize'],
      orElse: () => DashboardSize.standard,
    );
    connection = c['connection'] ?? 'ha';
    haUrl = c['haUrl'] ?? '';
    prefix = c['prefix'] ?? prefix;
    mqttHost = c['mqttHost'] ?? '';
    mqttPort = c['mqttPort'] ?? 8883;
    mqttTopic = c['mqttTopic'] ?? mqttTopic;
    mqttTransport = c['mqttTransport'] ?? 'tls';
    haBirthTopic = c['haBirthTopic'] ?? 'homeassistant/status';
    haBirthPayload = c['haBirthPayload'] ?? 'online';
    insecureAcknowledgements = Set<String>.from(
      c['insecureAcknowledgements'] ?? [],
    );
    mqttUser = c['mqttUser'] ?? '';
    reduceMotion = c['reduceMotion'] ?? false;
    autoStart = c['autoStart'] ?? true;
    haControlEnabled = c['haControlEnabled'] ?? false;
    mqttControlEnabled = c['mqttControlEnabled'] ?? false;
    collect = c['collect'] ?? true;
    overlayEnabled = c['overlayEnabled'] ?? false;
    publishEnabled = c['publishEnabled'] ?? false;
    fallbackPolling = c['fallbackPolling'] ?? false;
    localHistory = (c['localHistoryPolicyVersion'] ?? 0) < 1
        ? (c['connection'] == 'mqtt' ? c['localHistory'] ?? true : true)
        : c['localHistory'] ?? true;
    retainHistory = c['retainHistory'] ?? false;
    localHistoryMinutes = c['localHistoryMinutes'] ?? 30;
    mqttProtocol = c['mqttProtocol'] ?? '5';
    mqttState = c['mqttState'] ?? false;
    entityMappings = Map<String, String>.from(c['entityMappings'] ?? {});
    overlayFont = (c['overlayFont'] as num? ?? 18).toDouble();
    overlayOpacity = (c['overlayOpacity'] as num? ?? 0.8).toDouble();
    overlayOffset = (c['overlayOffset'] as num? ?? 0).toDouble();
    overlayLeft = (c['overlayLeft'] as num? ?? 128).toDouble();
    overlayRight = (c['overlayRight'] as num? ?? 320).toDouble();
    overlayX = (c['overlayX'] as num?)?.toDouble();
    overlayY = (c['overlayY'] as num?)?.toDouble();
  }

  Metric metric(String id) => id.startsWith('ha|')
      ? haFields[id] ??
            Metric(
              id: id,
              name: id.split('|').skip(2).join(' · '),
              category: 'Home Assistant',
              icon: '',
              unit: '',
              encoding: 'text',
              entityKey: '',
              displayAllowed: true,
            )
      : id.startsWith('control.')
      ? controlEntity(id).metric
      : metrics.firstWhere((m) => m.id == id);
  ControlEntity controlEntity(String id) =>
      controlEntities.firstWhere((e) => e.id == id);
  ValueNotifier<Sample> reading(String id) =>
      readings.putIfAbsent(id, () => ValueNotifier(Sample()));
  void applySamples(Map<String, dynamic> batch) {
    if (_disposed) return;
    for (final entry in batch.entries) {
      if (entry.key.startsWith('ha|')) reading(entry.key);
      readings[entry.key]?.value = Sample.fromJson(
        Map<String, dynamic>.from(entry.value),
      );
    }
    for (final entity in controlEntities) {
      if (entity.readField == null ||
          !entity.feedbackFields.any(batch.containsKey)) {
        continue;
      }
      final source = reading(entity.readField!).value;
      final known =
          source.value != null &&
          source.raw is num &&
          source.raw != 65535 &&
          (entity.unit != '°C' || source.unit == entity.unit) &&
          (entity.capability == EntityCapability.button ||
              entity.options.any((o) => o.expected == source.raw)) &&
          ['available', 'unverified'].contains(source.quality);
      final coherent =
          entity.action != 'ac_temperature' ||
          entity.feedbackFields.every(
            (id) =>
                reading(id).value.value == source.value &&
                ['available', 'unverified'].contains(reading(id).value.quality),
          );
      reading(entity.id).value = Sample(
        value: known && coherent ? source.value : null,
        raw: source.raw,
        unit: entity.unit,
        source: source.source,
        stateLabel:
            entity.unit.isEmpty &&
                entity.capability != EntityCapability.number &&
                known &&
                coherent
            ? entity.states[source.raw.toString()]
            : null,
        quality: known && coherent ? source.quality : 'invalid',
        updatedAt: source.updatedAt,
        changedAt: source.changedAt,
      );
    }
  }

  Future<Map<String, dynamic>> command(String id, int value) async {
    final entity = controlEntity(id);
    if (_disposed || status['stopped'] == true) return {'status': 'stopped'};
    if (pendingCommands.contains(id)) return {'status': 'busy'};
    if (!tiles.any((t) => t.kind.controls && t.fields.contains(id))) {
      return {'status': 'not_added'};
    }
    if (!entity.options.any((o) => o.value == value)) {
      return {'status': 'invalid_value'};
    }
    pendingCommands.add(id);
    commandResults[id]!.value = 'pending';
    try {
      final result = await bridge.call('control', {
        'action': entity.action,
        'value': value,
      });
      if (!_disposed) commandResults[id]!.value = result['status'] ?? 'error';
      // State changes arrive through the shared feedback subscription, never from requested values.
      return result;
    } catch (_) {
      if (!_disposed) commandResults[id]!.value = 'error';
      return {'status': 'error'};
    } finally {
      pendingCommands.remove(id);
    }
  }

  PreviewLease acquirePreview(Iterable<String> fields) {
    final lease = PreviewLease._(this);
    lease.update(fields);
    return lease;
  }

  void _updatePreview(Object owner, Iterable<String>? fields) {
    if (fields == null) {
      _previewLeases.remove(owner);
    } else {
      _previewLeases[owner] = fields.toSet();
    }
    final demand = _previewLeases.values.expand((e) => e).toSet().toList();
    _previewQueue = _previewQueue == null
        ? _sendPreview(demand)
        : _previewQueue!.then((_) => _sendPreview(demand));
  }

  Future<void> _sendPreview(List<String> fields) async {
    if (_disposed) return;
    try {
      final r = await bridge.call('previewFields', {'fields': fields});
      applySamples(Map<String, dynamic>.from(r['samples'] ?? {}));
    } catch (_) {}
  }

  Future<bool> save({String? haToken, String? mqttPassword}) async {
    error = null;
    _historyRequests.clear();
    try {
      final r = await bridge.call('save', {
        'config': config,
        if (haToken != null && haToken.isNotEmpty) 'haToken': haToken,
        if (mqttPassword != null && mqttPassword.isNotEmpty)
          'mqttPassword': mqttPassword,
      });
      if (r['status'] is Map) status = Map<String, dynamic>.from(r['status']);
      if (r['config'] is Map) restore(Map<String, dynamic>.from(r['config']));
      if (r['haDirectory'] is Map) {
        applyHaDirectory(
          Map<String, dynamic>.from(r['haDirectory']),
          notify: false,
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      error = Strings.text('text_40525a7328');
      notifyListeners();
      return false;
    }
  }

  Future<bool> importConfig(String text) async {
    try {
      final config = jsonDecode(text);
      if (config is! Map<String, dynamic>) throw FormatException();
      final result = await bridge.call('importConfig', {'config': config});
      restore(Map<String, dynamic>.from(result['config']));
      _historyRequests.clear();
      notifyListeners();
      return true;
    } catch (_) {
      error = Strings.text('text_24dffa6f22');
      notifyListeners();
      return false;
    }
  }

  void releaseHistoryViews() => _historyRequests.clear();
  String exportConfig() => JsonEncoder.withIndent('  ').convert(config);
  Future<void> action(String name) async {
    if (name == 'clearHistory') _historyRequests.clear();
    try {
      final r = await bridge.call(name);
      if (r['config'] is Map) restore(Map<String, dynamic>.from(r['config']));
      if (r['status'] is Map) status = Map<String, dynamic>.from(r['status']);
      applySamples(Map<String, dynamic>.from(r['samples'] ?? {}));
      error = null;
    } catch (e) {
      error = Strings.text('text_267521170d');
    }
    notifyListeners();
  }

  Future<List<HistoryPoint>> history(
    String field,
    int minutes, {
    bool refresh = false,
  }) {
    final key = 'local|$field|$minutes';
    final old = _historyRequests[key];
    if (!refresh &&
        old != null &&
        DateTime.now().difference(old.$1).inSeconds < 30) {
      return old.$2;
    }
    final future = _fetchHistory(field, minutes);
    _historyRequests[key] = (DateTime.now(), future);
    if (_historyRequests.length > 32) {
      _historyRequests.remove(_historyRequests.keys.first);
    }
    return future;
  }

  Future<List<HistoryPoint>> _fetchHistory(String field, int minutes) async {
    final r = await bridge.call('history', {
      'field': field,
      'minutes': minutes,
    });
    if (r['error'] != null) throw StateError(r['error']);
    return (r['points'] as List? ?? [])
        .map(
          (j) => HistoryPoint(
            DateTime.parse(j['at']),
            (j['value'] as num?)?.toDouble(),
            segment: j['segment'] ?? '',
            state: j['state'],
            observedUntil: j['observedUntil'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (j['observedUntil'] as num).toInt(),
                  )
                : null,
            snapshotAt: r['queriedAt'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (r['queriedAt'] as num).toInt(),
                  )
                : null,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    for (final s in readings.values) {
      s.dispose();
    }
    for (final s in commandResults.values) {
      s.dispose();
    }
    super.dispose();
  }
}

class PreviewLease {
  final AppController _controller;
  bool _closed = false;
  PreviewLease._(this._controller);
  void update(Iterable<String> fields) {
    if (!_closed) _controller._updatePreview(this, fields);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _controller._updatePreview(this, null);
  }
}
