import 'dart:async';

import 'package:dart_nats/dart_nats.dart' as nats;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

  nats.Client? _client;
  nats.Subscription<dynamic>? _primarySubscription;
  nats.Subscription<dynamic>? _mobileSubscription;
  nats.Subscription<dynamic>? _buildingSubscription;
  StreamSubscription<nats.Message<dynamic>>? _primaryMessageSubscription;
  StreamSubscription<nats.Message<dynamic>>? _mobileMessageSubscription;
  StreamSubscription<nats.Message<dynamic>>? _buildingMessageSubscription;
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
        subject: pendingAlert.subject,
        payload: pendingAlert.payload,
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

    final nats.Client client = nats.Client();

    try {
      await client.connect(Uri.parse(NatsConfig.serverUrl), retry: false);

      final nats.Subscription<dynamic> primarySubscription = client.sub(
        config.subject,
      );
      final nats.Subscription<dynamic> mobileSubscription = client.sub(
        config.mobileSubject,
      );
      final nats.Subscription<dynamic> buildingSubscription = client.sub(
        config.buildingSubject,
      );

      await _primaryMessageSubscription?.cancel();
      await _mobileMessageSubscription?.cancel();
      await _buildingMessageSubscription?.cancel();
      _primarySubscription = primarySubscription;
      _mobileSubscription = mobileSubscription;
      _buildingSubscription = buildingSubscription;
      _primaryMessageSubscription = primarySubscription.stream.listen(
        (nats.Message<dynamic> message) =>
            handleMessage(config.subject, message.string),
      );
      _mobileMessageSubscription = mobileSubscription.stream.listen(
        (nats.Message<dynamic> message) =>
            handleMessage(config.mobileSubject, message.string),
      );
      _buildingMessageSubscription = buildingSubscription.stream.listen(
        (nats.Message<dynamic> message) =>
            handleMessage(config.buildingSubject, message.string),
      );

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

  Future<ReceivedAlert?> handleMessage(String subject, String payload) async {
    final ParsedAlertPayload parsed = await compute(
      ParsedAlertPayload.fromRaw,
      payload,
    );

    if (parsed.isCameraControlSignal) {
      if (parsed.isEnabled == false) {
        isPanicActive = false;
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
      subject: subject,
      payload: payload,
      parsed: parsed,
      receivedAt: DateTime.now(),
    );
    addIncomingAlert(alert);
    return alert;
  }

  void addIncomingAlert(ReceivedAlert alert) {
    final bool alreadyPresent = messages.any(
      (ReceivedAlert existing) =>
          existing.subject == alert.subject &&
          existing.payload == alert.payload &&
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
    if (_client != null) {
      if (_primarySubscription != null) {
        _client!.unSub(_primarySubscription!);
      }
      if (_mobileSubscription != null) {
        _client!.unSub(_mobileSubscription!);
      }
      if (_buildingSubscription != null) {
        _client!.unSub(_buildingSubscription!);
      }
      _client!.close();
    }
    _alertEffectsAutoStopTimer?.cancel();
    super.dispose();
  }
}
