import 'dart:convert';
import 'package:flutter/services.dart';
import 'defaults.g.dart';

abstract final class Strings {
  static Map<String, String> _values = defaultStrings;
  static String locale = 'zh_CN';
  static Future<void> load([String language = 'zh_CN']) async {
    try {
      final data = jsonDecode(
        await rootBundle.loadString('assets/i18n/$language.json'),
      );
      _values = {...defaultStrings, ...Map<String, String>.from(data)};
      locale = language;
    } catch (_) {
      _values = defaultStrings;
      locale = 'zh_CN';
    }
  }

  static String text(String key, [Map<String, Object?> arguments = const {}]) {
    final template = _values[key] ?? defaultStrings[key] ?? key;
    return template.replaceAllMapped(
      RegExp(r'\{([a-zA-Z0-9_]+)\}'),
      (match) => arguments[match[1]]?.toString() ?? match[0]!,
    );
  }

  static String display(String source) {
    for (final entry in defaultStrings.entries) {
      if (entry.value == source) return _values[entry.key] ?? source;
    }
    return source;
  }
}
