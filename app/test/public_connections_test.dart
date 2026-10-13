import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skyinfo/data/app_controller.dart';
import 'package:skyinfo/domain/connection_options.dart';
import 'package:skyinfo/ui/connection_confirmation.dart';
import 'package:skyinfo/ui/industrial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'HA accepts HTTP and HTTPS domains, IP and IPv6, rejects malformed addresses',
    () {
      for (final value in [
        'http://home.example.com:8123/',
        'https://ha.example.com/',
        'http://192.168.10.40:8123/',
        'http://[::1]:8123/',
      'HTTP://home.example.com:8123/',
      'HTTPS://HA.example.com/',
      ]) {
        expect(validHaEndpoint(value), isNotNull);
      }
      for (final value in [
        '',
        'ftp://example.com',
        'http://user:password@example.com/',
        'http://example.com:0',
        'https://example.com:65536',
        'https://example.com/?x=1',
        'https://example.com/#secret',
      ]) {
        expect(validHaEndpoint(value), isNull);
      }
      expect(
        haEndpointIdentity('https://HA.example.com/'),
        haEndpointIdentity('https://ha.example.com:443'),
      );
    },
  );
  testWidgets(
    'HTTP confirmation can cancel without mutation and is remembered only on save',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController();
      Set<String>? result;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: industrialTheme(Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  returned = false;
                  result = await confirmConnectionConfiguration(context, c, {
                    'connection': 'ha',
                    'haUrl': 'http://home.example.com:8123/',
                  });
                  returned = true;
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('使用未加密连接？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
      expect(c.insecureAcknowledgements, isEmpty);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续保存'));
      await tester.pumpAndSettle();
      expect(result, hasLength(1));
      expect(c.insecureAcknowledgements, isEmpty);
      c.insecureAcknowledgements = result!;
      final saved = c.config;
      c.restore(saved);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(find.text('使用未加密连接？'), findsNothing);
      expect(result, c.insecureAcknowledgements);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test('TLS and TCP keep distinct acknowledgement keys per endpoint', () {
    expect(
      insecureConnectionKey(
        mode: 'mqtt',
        haUrl: '',
        transport: 'tls',
        mqttHost: 'broker.example.com',
        mqttPort: 8883,
      ),
      isNull,
    );
    final key = insecureConnectionKey(
      mode: 'mqtt',
      haUrl: '',
      transport: 'tcp',
      mqttHost: 'broker.example.com',
      mqttPort: 1883,
    );
    expect(key, 'mqtt|tcp|broker.example.com|1883');
    expect(
      key,
      isNot(
        insecureConnectionKey(
          mode: 'mqtt',
          haUrl: '',
          transport: 'tcp',
          mqttHost: 'other.example.com',
          mqttPort: 1883,
        ),
      ),
    );
  });
}
