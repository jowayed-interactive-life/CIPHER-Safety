import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nats/nats.dart';

import 'package:cipher_safety/core/config/nats_config.dart';
import 'package:cipher_safety/data/models/listener_config.dart';
import 'package:cipher_safety/data/models/pending_emergency_alert.dart';
import 'package:cipher_safety/data/repositories/listener_repository.dart';
import 'package:cipher_safety/domain/models/parsed_alert_payload.dart';
import 'package:cipher_safety/domain/models/received_alert.dart';

enum AlertResponseStatus {
  confirmed('Confirmed'),
  cannotComply('Can not comply');

  const AlertResponseStatus(this.label);

  final String label;
}

class ListenerViewModel extends ChangeNotifier {
  ListenerViewModel({
    required this.config,
    required this.listenerRepository,
    required this.autoConnect,
    required this.enableForegroundService,
  });

  final ListenerConfig config;
  final ListenerRepository listenerRepository;
  final bool autoConnect;
  final bool enableForegroundService;

  NatsClient? _client;
  StreamSubscription<NatsMessage>? _primaryMessageSubscription;
  StreamSubscription<NatsMessage>? _mobileMessageSubscription;
  StreamSubscription<NatsMessage>? _buildingMessageSubscription;
  Timer? _alertEffectsAutoStopTimer;

  bool isConnecting = false;
  bool isConnected = false;
  bool isStartingManualStream = false;
  bool isPanicActive = false;
  String status = 'Disconnected';
  final List<ReceivedAlert> messages = <ReceivedAlert>[];
  final Map<String, AlertResponseStatus> alertResponses =
      <String, AlertResponseStatus>{};
  ReceivedAlert? activeDialogAlert;
  bool isAlertDialogVisible = false;
  PendingEmergencyAlert? startupPendingAlert;

  String get primarySubscriberId => '${NatsConfig.subscriberId}-primary';
  String get mobileSubscriberId => '${NatsConfig.subscriberId}-mobile';
  String get buildingSubscriberId => '${NatsConfig.subscriberId}-building';

  Future<void> initialize({PendingEmergencyAlert? initialPendingAlert}) async {
    startupPendingAlert = initialPendingAlert;

    if (enableForegroundService) {
      await listenerRepository.setAppInForeground(true);
      await listenerRepository.startForegroundSync(config);
    }

    await listenerRepository.syncStreamingConfig(config);

    if (autoConnect) {
      await connectAndSubscribe();
    }
  }

  Future<void> onLifecycleChanged(AppLifecycleState state) async {
    if (!enableForegroundService) return;
    final bool isForeground = state == AppLifecycleState.resumed;
    await listenerRepository.setAppInForeground(isForeground);
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      await listenerRepository.startForegroundSync(config);
    }
  }

  Future<ReceivedAlert?> recoverPendingEmergencyAlert() async {
    try {
      final PendingEmergencyAlert? pendingAlert =
          startupPendingAlert ??
          await listenerRepository.consumePendingAlert();
      startupPendingAlert = null;
      if (pendingAlert == null) return null;

      final ParsedAlertPayload parsed = await compute(
        ParsedAlertPayload.fromRaw,
        pendingAlert.payload,
      );
      final ReceivedAlert alert = ReceivedAlert(
        message: NatsMessage(
          subject: pendingAlert.subject,
          payload: pendingAlert.payload,
          sid: 'pending-${pendingAlert.receivedAt.microsecondsSinceEpoch}',
          length: pendingAlert.payload.length,
        ),
        parsed: parsed,
        receivedAt: pendingAlert.receivedAt,
      );
      addIncomingAlert(alert);
      return alert;
    } catch (_) {
      return null;
    }
  }

  Future<void> connectAndSubscribe() async {
    if (isConnecting) return;

    isConnecting = true;
    status = 'Connecting...';
    notifyListeners();

    final NatsClient client = NatsClient(NatsConfig.host, NatsConfig.port);

    try {
      await client.connect();

      final Stream<NatsMessage> primaryStream = client.subscribe(
        primarySubscriberId,
        config.subject,
      );
      final Stream<NatsMessage> mobileStream = client.subscribe(
        mobileSubscriberId,
        config.mobileSubject,
      );
      final Stream<NatsMessage> buildingStream = client.subscribe(
        buildingSubscriberId,
        config.buildingSubject,
      );

      await _primaryMessageSubscription?.cancel();
      await _mobileMessageSubscription?.cancel();
      await _buildingMessageSubscription?.cancel();
      _primaryMessageSubscription = primaryStream.listen(handleMessage);
      _mobileMessageSubscription = mobileStream.listen(handleMessage);
      _buildingMessageSubscription = buildingStream.listen(handleMessage);

      _client = client;
      isConnected = true;
      status = 'Connected';
    } catch (error) {
      isConnected = false;
      status = 'Connection failed: $error';
    } finally {
      isConnecting = false;
      notifyListeners();
    }
  }

  Future<ReceivedAlert?> handleMessage(NatsMessage message) async {
    final ParsedAlertPayload parsed = await compute(
      ParsedAlertPayload.fromRaw,
      message.payload,
    );

    if (parsed.isCameraControlSignal) {
      if (parsed.isEnabled != null) {
        isPanicActive = parsed.isEnabled == true;
        notifyListeners();
      }
      return null;
    }

    if (parsed.isResolved == true) {
      handleResolvedAlert(parsed);
      return null;
    }

    if (!parsed.hasDisplayableAlertMode) {
      return null;
    }

    final ReceivedAlert alert = ReceivedAlert(
      message: message,
      parsed: parsed,
      receivedAt: DateTime.now(),
    );
    addIncomingAlert(alert);
    return alert;
  }

  void addIncomingAlert(ReceivedAlert alert) {
    final bool alreadyPresent = messages.any(
      (ReceivedAlert existing) =>
          existing.message.subject == alert.message.subject &&
          existing.message.payload == alert.message.payload &&
          existing.receivedAt == alert.receivedAt,
    );

    if (!alreadyPresent) {
      messages.insert(0, alert);
    }

    activeDialogAlert = alert;
    _scheduleAlertEffectsAutoStop();
    notifyListeners();
  }

  void handleResolvedAlert(ParsedAlertPayload resolvedAlert) {
    final String? resolvedBuildingId = resolvedAlert.buildingId?.trim();
    if (resolvedBuildingId == null || resolvedBuildingId.isEmpty) {
      return;
    }

    final List<String> removedAlertKeys = messages
        .where(
          (ReceivedAlert alert) =>
              alert.parsed.buildingId?.trim() == resolvedBuildingId,
        )
        .map((ReceivedAlert alert) => alert.uniqueKey)
        .toList();

    messages.removeWhere(
      (ReceivedAlert alert) =>
          alert.parsed.buildingId?.trim() == resolvedBuildingId,
    );
    for (final String alertKey in removedAlertKeys) {
      alertResponses.remove(alertKey);
    }

    if (activeDialogAlert?.parsed.buildingId?.trim() == resolvedBuildingId) {
      _alertEffectsAutoStopTimer?.cancel();
      activeDialogAlert = null;
      isAlertDialogVisible = false;
    }

    notifyListeners();
  }

  Future<void> handleAlertResponse({
    required ReceivedAlert alert,
    required AlertResponseStatus responseStatus,
  }) async {
    await listenerRepository.sendAlertResponse(
      config: config,
      isComply: responseStatus == AlertResponseStatus.confirmed,
    );
    _alertEffectsAutoStopTimer?.cancel();
    alertResponses[alert.uniqueKey] = responseStatus;
    notifyListeners();
  }

  Future<void> startManualStreaming() async {
    if (isStartingManualStream) return;

    isStartingManualStream = true;
    notifyListeners();
    try {
      await listenerRepository.startManualStreaming();
      isPanicActive = true;
    } finally {
      isStartingManualStream = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await listenerRepository.clearSavedConfig();
    await listenerRepository.clearStreamingConfig();
    await listenerRepository.stopForegroundService();
  }

  void setDialogVisibility(bool isVisible) {
    isAlertDialogVisible = isVisible;
    if (!isVisible) {
      activeDialogAlert = null;
    }
    notifyListeners();
  }

  void _scheduleAlertEffectsAutoStop() {
    final ReceivedAlert? alert = activeDialogAlert;
    if (alert?.parsed.isSilent == true) {
      _alertEffectsAutoStopTimer?.cancel();
      return;
    }
    _alertEffectsAutoStopTimer?.cancel();
    _alertEffectsAutoStopTimer = Timer(const Duration(seconds: 20), () async {
      try {
        await listenerRepository.silenceEmergencyAlert();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (enableForegroundService) {
      unawaited(listenerRepository.setAppInForeground(false));
    }
    _primaryMessageSubscription?.cancel();
    _mobileMessageSubscription?.cancel();
    _buildingMessageSubscription?.cancel();
    _client?.unsubscribe(primarySubscriberId);
    _client?.unsubscribe(mobileSubscriberId);
    _client?.unsubscribe(buildingSubscriberId);
    _alertEffectsAutoStopTimer?.cancel();
    super.dispose();
  }
}
