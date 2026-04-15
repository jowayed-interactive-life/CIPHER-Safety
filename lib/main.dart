import 'package:flutter/widgets.dart';

import 'package:cipher_safety/app/app.dart';
import 'package:cipher_safety/data/repositories/listener_repository.dart';
import 'package:cipher_safety/data/services/nats_platform_service.dart';

void main() {
  final ListenerRepository listenerRepository = ListenerRepository(
    NatsPlatformService(),
  );

  runApp(CipherSafetyApp(listenerRepository: listenerRepository));
}
