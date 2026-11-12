import 'dart:typed_data';

String splitActivityName(String package, String activity) =>
    activity.startsWith('.')
    ? '$package$activity'
    : activity.contains('.')
    ? activity
    : '$package.$activity';

const startupPages = [
  'information',
  'overlay',
  'split',
  'connection',
  'settings',
];
const startupPageIndices = {
  'information': 0,
  'overlay': 1,
  'split': 4,
  'connection': 2,
  'settings': 3,
};

class SplitApp {
  final String packageName, label, defaultActivity;
  final Uint8List? iconBytes;
  const SplitApp({
    required this.packageName,
    required this.label,
    required this.defaultActivity,
    this.iconBytes,
  });
  factory SplitApp.fromJson(Map value) => SplitApp(
    packageName: value['packageName'] as String,
    label: value['label'] as String? ?? value['packageName'] as String,
    defaultActivity: value['defaultActivity'] as String? ?? '',
    iconBytes: value['iconBytes'] is List
        ? Uint8List.fromList(List<int>.from(value['iconBytes']))
        : null,
  );
  SplitTarget get target => SplitTarget(packageName: packageName, label: label);
}

class SplitActivity {
  final String packageName, activityName, label;
  final bool isDefault, available;
  final String? reason;
  const SplitActivity({
    required this.packageName,
    required this.activityName,
    required this.label,
    required this.isDefault,
    required this.available,
    this.reason,
  });
  factory SplitActivity.fromJson(Map value) => SplitActivity(
    packageName: value['packageName'] as String,
    activityName: value['activityName'] as String,
    label: value['label'] as String? ?? value['activityName'] as String,
    isDefault: value['isDefault'] == true,
    available:
        value['available'] == true &&
        value['enabled'] != false &&
        value['exported'] != false,
    reason: value['reason'] as String?,
  );
}

class SplitTarget {
  final String packageName, label;
  final String? activityName;
  const SplitTarget({
    required this.packageName,
    required this.label,
    this.activityName,
  });
  factory SplitTarget.fromJson(Map value) => SplitTarget(
    packageName: value['packageName'] as String,
    label: value['label'] as String? ?? value['packageName'] as String,
    activityName: value['activityName'] as String?,
  );
  SplitTarget get defaultEntry =>
      SplitTarget(packageName: packageName, label: label);
  SplitTarget withActivity(String name) =>
      SplitTarget(packageName: packageName, label: label, activityName: name);
  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'label': label,
    if (activityName != null) 'activityName': activityName,
  };
}

class SplitCombo {
  final String id, name, ratio;
  final SplitTarget left, right;
  final bool advanced;
  const SplitCombo({
    required this.id,
    required this.name,
    required this.ratio,
    required this.left,
    required this.right,
    this.advanced = false,
  });
  factory SplitCombo.fromJson(Map value) => SplitCombo(
    id: value['id'] as String,
    name: value['name'] as String,
    ratio: value['ratio'] == '3/7' ? '3/7' : '7/3',
    left: SplitTarget.fromJson(value['left'] as Map),
    right: SplitTarget.fromJson(value['right'] as Map),
    advanced: value['advanced'] == true,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ratio': ratio,
    'left': left.toJson(),
    'right': right.toJson(),
    'advanced': advanced,
  };
}

/// A process-local draft. Selection and cancellation never persist or launch.
class SplitDraft {
  final String? id;
  String name, ratio;
  SplitTarget? left, right;
  bool advanced;
  SplitDraft({
    this.id,
    this.name = '',
    this.ratio = '7/3',
    this.left,
    this.right,
    this.advanced = false,
  });
  factory SplitDraft.fromCombo(SplitCombo combo) => SplitDraft(
    id: combo.id,
    name: combo.name,
    ratio: combo.ratio,
    left: combo.left,
    right: combo.right,
    advanced: combo.advanced,
  );
  void select(bool isLeft, SplitTarget target) {
    if (isLeft) {
      left = target.defaultEntry;
    } else {
      right = target.defaultEntry;
    }
  }

  void setAdvanced(bool value) {
    advanced = value;
    if (!value) {
      left = left?.defaultEntry;
      right = right?.defaultEntry;
    }
  }

  void swap() {
    final previous = left;
    left = right;
    right = previous;
  }

  bool get complete => left != null && right != null;
  SplitCombo snapshot(String newId) => SplitCombo(
    id: id ?? newId,
    name: name.trim().isEmpty
        ? '${left!.label} + ${right!.label}'
        : name.trim(),
    ratio: ratio,
    left: left!,
    right: right!,
    advanced: advanced,
  );
}
