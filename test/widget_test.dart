// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:cipher_safety/app/app.dart';
import 'package:cipher_safety/data/models/listener_config.dart';
import 'package:cipher_safety/data/models/pending_emergency_alert.dart';
import 'package:cipher_safety/data/repositories/listener_repository.dart';
import 'package:cipher_safety/data/services/nats_platform_service.dart';

void main() {
  testWidgets('renders subject entry screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      CipherSafetyApp(
        listenerRepository: _TestListenerRepository(),
        autoConnect: false,
        enableForegroundService: false,
      ),
    );
    await tester.pump();

    expect(find.text('Building Name'), findsOneWidget);
    expect(find.text('Device ID'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}

class _TestListenerRepository extends ListenerRepository {
  _TestListenerRepository() : super(NatsPlatformService());

  @override
  Future<PendingEmergencyAlert?> consumePendingAlert() async => null;

  @override
  Future<ListenerConfig?> loadSavedConfig() async => null;
}
