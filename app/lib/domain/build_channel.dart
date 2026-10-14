import 'package:flutter/services.dart';

abstract final class BuildChannel {
  static const name = appFlavor ?? 'stable';
  static const isBeta = name == 'beta';
  static const projectUrl = 'https://github.com/skyboooox/SkyInfo';
}
