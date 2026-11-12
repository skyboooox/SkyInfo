import '../l10n/strings.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../domain/models.dart';
import '../domain/control_entity.dart';
import '../domain/ha_entity.dart';
import '../domain/dashboard_layout.dart';
import '../domain/split_screen.dart';
import 'vehicle_bridge.dart';
import 'runtime_performance.dart';

part 'ha_controller.dart';
part 'permissions_controller.dart';
part 'overlay_appearance.dart';
part 'overlay_preferences.dart';
part 'split_preferences.dart';

class AppController extends ChangeNotifier {
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  final VehicleBridge bridge;
  final RuntimePerformance? _performanceOverride;
  late final runtimePerformance =
      _performanceOverride ??
      RuntimePerformance(
        report: (session, report) {
          unawaited(
            bridge
                .call('performanceReport', {
                  'session': session,
                  'report': report,
                })
                .catchError((Object _) => <String, dynamic>{}),
          );
        },
      );
  late final overlayAppearance = OverlayAppearance(this);
  bool overlayPositionPending = false;
  AppController({VehicleBridge? bridge, RuntimePerformance? performance})
    : bridge = bridge ?? VehicleBridge(),
      _performanceOverride = performance;
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
  Set<String> _previewDemand = {};
  Set<String> _previewSent = {};
  bool _previewSending = false;
  bool _previewUnknown = false;
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
  String startupPage = 'information';
  List<SplitCombo> splitCombos = [];
  final SplitDraft splitQuickDraft = SplitDraft();
  bool splitSaving = false,
      splitLaunching = false,
      splitCompatibilityAcknowledged = false;
  DashboardSize dashboardSize = DashboardSize.standard;
  bool adbEnabled = false;
  bool autoSystemAdb = false;
  bool overlayPermissionPending = false, autoSystemAdbPending = false;
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
  final Map<String, Future<List<HistoryPoint>>> _historyInFlight = {};
  int _historyEpoch = 0;
  double overlayFont = 18, overlayOpacity = 0.8;
  double? overlayX, overlayY;
  StreamSubscription<Map<String, dynamic>>? _events;
  String? error;
  String appVersion = '—', appBuildNumber = '';
  String get versionLabel =>
      appBuildNumber.isEmpty ? appVersion : '$appVersion ($appBuildNumber)';
  String get effectiveTheme {
    if (theme != 'system') return theme;
    final appearance = status['appearance'];
    final brightness = appearance is Map ? appearance['brightness'] : null;
    return brightness == 'light' || brightness == 'dark'
        ? brightness as String
        : 'system';
  }

  Map<String, dynamic> get config => {
    'schema': 2,
    'startupPage': startupPage,
    'splitCombos': splitCombos.map((e) => e.toJson()).toList(),
    'adbEnabled': adbEnabled,
    'autoSystemAdb': autoSystemAdb,
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
    'overlayX': overlayX,
    'overlayY': overlayY,
  };
  Future<void> initialize() async {
    await Strings.load();
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      appBuildNumber = info.buildNumber;
    } catch (_) {
      appVersion = '—';
      appBuildNumber = '';
    }
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
          if (e['performanceControl'] is Map) {
            runtimePerformance.control(e['performanceControl'] as Map);
          }
          runtimePerformance.add('events');
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
            if (!_sameJson(status, next)) {
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
    startupPage = startupPages.contains(c['startupPage'])
        ? c['startupPage'] as String
        : 'information';
    splitCombos = (c['splitCombos'] as List? ?? [])
        .map((e) => SplitCombo.fromJson(e as Map))
        .toList();
    adbEnabled = c['adbEnabled'] ?? false;
    autoSystemAdb = c['autoSystemAdb'] ?? false;
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
  void _assignSample(ValueNotifier<Sample> target, Sample next) {
    final old = target.value;
    if (_sameSampleData(old.value, next.value) &&
        _sameSampleData(old.raw, next.raw) &&
        old.quality == next.quality &&
        old.source == next.source &&
        old.unit == next.unit &&
        old.stateLabel == next.stateLabel &&
        old.updatedAt == next.updatedAt &&
        old.changedAt == next.changedAt) {
      return;
    }
    target.value = next;
    runtimePerformance.add('sampleNotifications');
  }

  void applySamples(Map<String, dynamic> batch) {
    if (_disposed) return;
    final measured = runtimePerformance.begin();
    for (final entry in batch.entries) {
      if (entry.key.startsWith('ha|')) reading(entry.key);
      final target = readings[entry.key];
      if (target != null) {
        _assignSample(
          target,
          Sample.fromJson(Map<String, dynamic>.from(entry.value)),
        );
      }
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
      _assignSample(
        reading(entity.id),
        Sample(
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
        ),
      );
    }
    runtimePerformance.applied(measured, batch.length);
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
    if (_disposed) return;
    if (fields == null) {
      _previewLeases.remove(owner);
    } else {
      _previewLeases[owner] = fields.toSet();
    }
    final demand = _previewLeases.values.expand((e) => e).toSet();
    if (setEquals(_previewDemand, demand) && !_previewUnknown) return;
    _previewDemand = demand;
    _sendPreview();
  }

  Future<void> _sendPreview() async {
    if (_previewSending) return;
    _previewSending = true;
    try {
      while (_previewUnknown || !setEquals(_previewSent, _previewDemand)) {
        final fields = Set<String>.from(_previewDemand);
        try {
          final r = await bridge.call('previewFields', {
            'fields': fields.toList(),
          });
          if (!_disposed) {
            applySamples(Map<String, dynamic>.from(r['samples'] ?? {}));
          }
          _previewSent = fields;
          _previewUnknown = false;
        } catch (_) {
          _previewUnknown = true;
          if (setEquals(fields, _previewDemand)) break;
        }
      }
    } finally {
      _previewSending = false;
    }
  }

  void _clearHistoryRequests() {
    _historyEpoch++;
    _historyRequests.clear();
    _historyInFlight.clear();
  }

  Future<bool> save({String? haToken, String? mqttPassword}) async {
    error = null;
    _clearHistoryRequests();
    try {
      final r = await bridge.call('save', {
        'config': config,
        if (haToken != null && haToken.isNotEmpty) 'haToken': haToken,
        if (mqttPassword != null && mqttPassword.isNotEmpty)
          'mqttPassword': mqttPassword,
      });
      if (_disposed) return false;
      if (r['status'] is Map) status = Map<String, dynamic>.from(r['status']);
      if (r['config'] is Map) restore(Map<String, dynamic>.from(r['config']));
      if (r['haDirectory'] is Map) {
        applyHaDirectory(
          Map<String, dynamic>.from(r['haDirectory']),
          notify: false,
        );
      }
      _notify();
      return true;
    } catch (e) {
      error = Strings.text('text_40525a7328');
      _notify();
      return false;
    }
  }

  Future<bool> importConfig(String text) async {
    try {
      final config = jsonDecode(text);
      if (config is! Map<String, dynamic>) throw FormatException();
      final result = await bridge.call('importConfig', {'config': config});
      restore(Map<String, dynamic>.from(result['config']));
      _clearHistoryRequests();
      notifyListeners();
      return true;
    } catch (_) {
      error = Strings.text('text_24dffa6f22');
      notifyListeners();
      return false;
    }
  }

  void releaseHistoryViews() => _clearHistoryRequests();
  String exportConfig() => JsonEncoder.withIndent('  ').convert(config);
  Future<void> action(String name) async {
    if (name == 'clearHistory') _clearHistoryRequests();
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
    final running = _historyInFlight[key];
    if (running != null) return running;
    final old = _historyRequests[key];
    if (!refresh &&
        old != null &&
        DateTime.now().difference(old.$1).inSeconds < 30) {
      return old.$2;
    }
    final epoch = _historyEpoch;
    late final Future<List<HistoryPoint>> future;
    future = _fetchHistory(field, minutes).then(
      (points) {
        if (!_disposed &&
            epoch == _historyEpoch &&
            identical(_historyInFlight[key], future)) {
          _historyInFlight.remove(key);
          _historyRequests[key] = (DateTime.now(), future);
          if (_historyRequests.length > 32) {
            _historyRequests.remove(_historyRequests.keys.first);
          }
        }
        return points;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_historyInFlight[key], future)) {
          _historyInFlight.remove(key);
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _historyInFlight[key] = future;
    return future;
  }

  Future<List<HistoryPoint>> _fetchHistory(String field, int minutes) async {
    final r = await bridge.call('history', {
      'field': field,
      'minutes': minutes,
      'includeSample': false,
    });
    if (r['error'] != null) throw StateError(r['error']);
    final snapshotAt = r['queriedAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch((r['queriedAt'] as num).toInt())
        : null;
    return List<HistoryPoint>.unmodifiable(
      (r['points'] as List? ?? []).map(
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
          snapshotAt: snapshotAt,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    runtimePerformance.dispose();
    _previewLeases.clear();
    _previewDemand = {};
    _sendPreview();
    _clearHistoryRequests();
    overlayAppearance.dispose();
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

bool _sameSampleData(Object? a, Object? b) {
  if (a is double && b is double && a == 0 && b == 0) {
    return a.isNegative == b.isNegative;
  }
  if (identical(a, b)) return true;
  if (a is num || b is num) {
    return a.runtimeType == b.runtimeType && a == b;
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _sameSampleData(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => _sameSampleData(a[i], b[i]));
  }
  return a == b;
}

bool _sameJson(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _sameJson(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _sameJson(a[i], b[i]));
  }
  return a == b;
}
