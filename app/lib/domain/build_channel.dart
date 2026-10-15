import 'package:flutter/services.dart';

abstract final class BuildChannel {
  static const name = appFlavor ?? 'stable';
  static const isTesting = name == 'alpha' || name == 'beta';
  static const projectUrl = 'https://github.com/skyboooox/SkyInfo';
}
