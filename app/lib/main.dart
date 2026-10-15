import 'ui/shell/home.dart';
import 'package:flutter/material.dart';
import 'data/app_controller.dart';
import 'ui/industrial.dart';
import 'ui/attention.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.initialize();
  runApp(SkyInfo(controller: controller));
}

class SkyInfo extends StatelessWidget {
  final AppController controller;
  const SkyInfo({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'SkyInfo',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              controller.reduceMotion ||
              MediaQuery.disableAnimationsOf(context),
        ),
        child: LifecycleMotion(child: DesignViewport(child: child!)),
      ),
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: controller.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      themeAnimationCurve: Curves.easeOutCubic,
      theme: industrialTheme(Brightness.light),
      darkTheme: industrialTheme(Brightness.dark),
      themeMode: switch (controller.effectiveTheme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: Home(controller: controller),
    ),
  );
}
