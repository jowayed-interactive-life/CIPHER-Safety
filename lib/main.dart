import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nats/nats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nats_service_controller.dart';

void main() {
  runApp(const CipherSafetyApp());
}

class CipherSafetyApp extends StatelessWidget {
  const CipherSafetyApp({
    super.key,
    this.autoConnect = true,
    this.enableForegroundService = true,
  });

  final bool autoConnect;
  final bool enableForegroundService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CIPHER Safety',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1F1F1F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5A5A5A),
          secondary: Color(0xFF7A7A7A),
          surface: Color(0xFF2A2A2A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF151515),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        final double baseFontSize = mediaQuery.size.width * 0.03;
        final double textScaleFactor = baseFontSize / 14;
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: SubjectEntryPage(
        autoConnect: autoConnect,
        enableForegroundService: enableForegroundService,
      ),
    );
  }
}

class NatsConfig {
  static const String host = 'nats.interactivelife.me';
  static const int port = 4222;
  static const String serverUrl = 'nats://$host:$port';
  static const String env = 'staging';
  static const String subscriberId = 'cipher-safety-mobile';
  static const String organizationId = '698af675991550fcad337a3f';
}

class ListenerConfig {
  const ListenerConfig({
    required this.buildingId,
    required this.floorId,
    required this.buildingName,
    required this.displayDeviceId,
    required this.floorName,
    required this.resolvedName,
    required this.resolvedBuildingName,
    required this.roomName,
    required this.cameraId,
    required this.streamUrl,
  });

  final String buildingId;
  final String floorId;
  final String buildingName;
  final String displayDeviceId;
  final String floorName;
  final String resolvedName;
  final String resolvedBuildingName;
  final String roomName;
  final String cameraId;
  final String streamUrl;

  String get sanitizedSubjectTarget =>
      roomName.trim().replaceAll(RegExp(r'\s+'), '_');

  String get subject =>
      '${NatsConfig.env}.${NatsConfig.organizationId}.indoor-alerts-$buildingId-$floorId-$sanitizedSubjectTarget';

  String get mobileSubject => '$subject.mobile';

  String get buildingSubject =>
      '${NatsConfig.env}.${NatsConfig.organizationId}.indoor-alerts-$buildingId';

  static const String _buildingIdKey = 'listener_building_id';
  static const String _floorIdKey = 'listener_floor_id';
  static const String _buildingNameKey = 'listener_building_name';
  static const String _displayDeviceIdKey = 'listener_display_device_id';
  static const String _floorNameKey = 'listener_floor_name';
  static const String _resolvedNameKey = 'listener_resolved_name';
  static const String _resolvedBuildingNameKey =
      'listener_resolved_building_name';
  static const String _roomNameKey = 'listener_room_name';
  static const String _cameraIdKey = 'listener_camera_id';
  static const String _streamUrlKey = 'listener_stream_url';

  static Future<ListenerConfig?> loadSaved() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? buildingId = prefs.getString(_buildingIdKey);
    final String? floorId = prefs.getString(_floorIdKey);
    final String? buildingName = prefs.getString(_buildingNameKey);
    final String? displayDeviceId = prefs.getString(_displayDeviceIdKey);
    final String? floorName = prefs.getString(_floorNameKey);
    final String? resolvedName = prefs.getString(_resolvedNameKey);
    final String? resolvedBuildingName = prefs.getString(
      _resolvedBuildingNameKey,
    );
    final String? roomName = prefs.getString(_roomNameKey);
    final String? cameraId = prefs.getString(_cameraIdKey);
    final String? streamUrl = prefs.getString(_streamUrlKey);

    if (buildingId == null ||
        buildingId.isEmpty ||
        floorId == null ||
        floorId.isEmpty ||
        roomName == null ||
        roomName.isEmpty ||
        cameraId == null ||
        cameraId.isEmpty ||
        streamUrl == null ||
        streamUrl.isEmpty) {
      return null;
    }

    return ListenerConfig(
      buildingId: buildingId,
      floorId: floorId,
      buildingName: buildingName ?? buildingId,
      displayDeviceId: displayDeviceId ?? cameraId,
      floorName: floorName ?? floorId,
      resolvedName: resolvedName ?? floorId,
      resolvedBuildingName: resolvedBuildingName ?? buildingName ?? buildingId,
      roomName: roomName,
      cameraId: cameraId,
      streamUrl: streamUrl,
    );
  }

  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_buildingIdKey, buildingId);
    await prefs.setString(_floorIdKey, floorId);
    await prefs.setString(_buildingNameKey, buildingName);
    await prefs.setString(_displayDeviceIdKey, displayDeviceId);
    await prefs.setString(_floorNameKey, floorName);
    await prefs.setString(_resolvedNameKey, resolvedName);
    await prefs.setString(_resolvedBuildingNameKey, resolvedBuildingName);
    await prefs.setString(_roomNameKey, roomName);
    await prefs.setString(_cameraIdKey, cameraId);
    await prefs.setString(_streamUrlKey, streamUrl);
  }

  static Future<void> clearSaved() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_buildingIdKey);
    await prefs.remove(_floorIdKey);
    await prefs.remove(_buildingNameKey);
    await prefs.remove(_displayDeviceIdKey);
    await prefs.remove(_floorNameKey);
    await prefs.remove(_resolvedNameKey);
    await prefs.remove(_resolvedBuildingNameKey);
    await prefs.remove(_roomNameKey);
    await prefs.remove(_cameraIdKey);
    await prefs.remove(_streamUrlKey);
  }
}

class SubjectEntryPage extends StatefulWidget {
  const SubjectEntryPage({
    super.key,
    this.autoConnect = true,
    this.enableForegroundService = true,
  });

  final bool autoConnect;
  final bool enableForegroundService;

  @override
  State<SubjectEntryPage> createState() => _SubjectEntryPageState();
}

class _SubjectEntryPageState extends State<SubjectEntryPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _buildingIdController = TextEditingController();
  final TextEditingController _cameraIdController = TextEditingController();
  bool _isLoadingSavedConfig = true;
  bool _isSearchingRoom = false;
  bool _didOpenSavedListener = false;
  PendingEmergencyAlert? _startupPendingAlert;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedConfig());
  }

  @override
  void dispose() {
    _buildingIdController.dispose();
    _cameraIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedConfig() async {
    _startupPendingAlert ??=
        await NatsServiceController.consumePendingEmergencyAlert();
    if (kDebugMode) {
      debugPrint(
        'SubjectEntryPage loadSavedConfig | startupPendingAlert=${_startupPendingAlert != null}',
      );
    }
    final ListenerConfig? savedConfig = await ListenerConfig.loadSaved();
    if (!mounted) return;

    if (savedConfig == null) {
      setState(() {
        _isLoadingSavedConfig = false;
      });
      return;
    }

    _buildingIdController.text = savedConfig.buildingName;
    _cameraIdController.text = savedConfig.cameraId;

    setState(() {
      _isLoadingSavedConfig = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didOpenSavedListener) return;
      _didOpenSavedListener = true;
      if (kDebugMode) {
        debugPrint(
          'SubjectEntryPage opening saved listener | subject=${savedConfig.subject} | hasStartupPendingAlert=${_startupPendingAlert != null}',
        );
      }
      _openListener(savedConfig, startupPendingAlert: _startupPendingAlert);
    });
  }

  Future<void> _continueToListener() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSearchingRoom) return;

    setState(() {
      _isSearchingRoom = true;
    });

    final String buildingName = _buildingIdController.text.trim();
    final String tabletId = _cameraIdController.text.trim();

    if (kDebugMode) {
      debugPrint(
        'continueToListener start | buildingName=$buildingName | tabletId=$tabletId',
      );
    }

    try {
      final TabletCameraLookupResult lookupResult = await NatsServiceController
          .getTabletCameraConfig(
            tabletId: tabletId,
            buildingName: buildingName,
          );

      if (kDebugMode) {
        debugPrint(
          'continueToListener resolved | resolvedRoom=${lookupResult.roomName} | buildingId=${lookupResult.buildingId} | floorId=${lookupResult.floorId} | streamUrl=${lookupResult.streamUrl}',
        );
      }

      final ListenerConfig config = ListenerConfig(
        buildingId: lookupResult.buildingId,
        floorId: lookupResult.floorId,
        buildingName: buildingName,
        displayDeviceId: tabletId,
        floorName: lookupResult.floorName,
        resolvedName: lookupResult.roomName,
        resolvedBuildingName: lookupResult.buildingName,
        roomName: lookupResult.roomName,
        cameraId: lookupResult.cameraId,
        streamUrl: lookupResult.streamUrl,
      );

      await config.save();
      await NatsServiceController.syncStreamingConfig(
        cameraId: config.cameraId,
        streamUrl: config.streamUrl,
        tabletId: config.displayDeviceId,
        buildingName: config.buildingName,
      );
      if (kDebugMode) {
        debugPrint(
          'continueToListener saved | cameraId=${config.cameraId} | streamUrl=${config.streamUrl}',
        );
      }
      if (!mounted) return;
      _openListener(config);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('continueToListener failed | error=$error');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not find device details. ${error is Exception ? error.toString() : 'Please try again.'}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingRoom = false;
        });
      }
    }
  }

  void _openListener(
    ListenerConfig config, {
    PendingEmergencyAlert? startupPendingAlert,
  }) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => NatsListenerPage(
          config: config,
          autoConnect: widget.autoConnect,
          enableForegroundService: widget.enableForegroundService,
          startupPendingAlert: startupPendingAlert,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSavedConfig) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final bool isMobile = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: isMobile ? 24 : 32,
          child: Image.asset(
            'assets/images/cipher-safety-logotxt.png',
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextFormField(
                      controller: _buildingIdController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Building Name',
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Colors.white70,
                            width: 1.2,
                          ),
                        ),
                      ),
                      validator: _validateRequired,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cameraIdController,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _continueToListener(),
                      decoration: InputDecoration(
                        labelText: 'Device ID',
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Colors.white70,
                            width: 1.2,
                          ),
                        ),
                      ),
                      validator: _validateRequired,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSearchingRoom
                            ? null
                            : _continueToListener,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: Text(
                          _isSearchingRoom ? 'Searching...' : 'Continue',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }
}

class NatsListenerPage extends StatefulWidget {
  const NatsListenerPage({
    super.key,
    required this.config,
    this.autoConnect = true,
    this.enableForegroundService = true,
    this.startupPendingAlert,
  });

  final ListenerConfig config;
  final bool autoConnect;
  final bool enableForegroundService;
  final PendingEmergencyAlert? startupPendingAlert;

  @override
  State<NatsListenerPage> createState() => _NatsListenerPageState();
}

class _NatsListenerPageState extends State<NatsListenerPage>
    with WidgetsBindingObserver {
  NatsClient? _client;
  StreamSubscription<NatsMessage>? _primaryMessageSubscription;
  StreamSubscription<NatsMessage>? _mobileMessageSubscription;
  StreamSubscription<NatsMessage>? _buildingMessageSubscription;

  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isStartingManualStream = false;
  String _status = 'Disconnected';
  final List<ReceivedAlert> _messages = <ReceivedAlert>[];
  final Map<String, AlertResponseStatus> _alertResponses =
      <String, AlertResponseStatus>{};
  ReceivedAlert? _activeDialogAlert;
  bool _isAlertDialogVisible = false;
  StateSetter? _alertDialogSetState;
  Timer? _alertEffectsAutoStopTimer;

  @override
  void initState() {
    super.initState();

    if (widget.enableForegroundService) {
      WidgetsBinding.instance.addObserver(this);
      unawaited(NatsServiceController.setAppInForeground(true));
      NatsServiceController.syncWithSessionOrFallback(
        fallbackServerUrl: NatsConfig.serverUrl,
        fallbackEnv: NatsConfig.env,
        fallbackPrimarySubject: widget.config.subject,
        fallbackMobileSubject: widget.config.mobileSubject,
        fallbackBuildingSubject: widget.config.buildingSubject,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (kDebugMode) {
          debugPrint(
            'NatsListenerPage first frame | startupPendingAlert=${widget.startupPendingAlert != null}',
          );
        }
        unawaited(
          _recoverPendingEmergencyAlert(seedAlert: widget.startupPendingAlert),
        );
      });
    }

    if (widget.autoConnect) {
      _connectAndSubscribe();
    }

    unawaited(
      NatsServiceController.syncStreamingConfig(
        cameraId: widget.config.cameraId,
        streamUrl: widget.config.streamUrl,
        tabletId: widget.config.displayDeviceId,
        buildingName: widget.config.buildingName,
      ),
    );
    if (kDebugMode) {
      debugPrint(
        'NatsListenerPage syncStreamingConfig | cameraId=${widget.config.cameraId} | streamUrl=${widget.config.streamUrl}',
      );
    }
  }

  @override
  void dispose() {
    if (widget.enableForegroundService) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(NatsServiceController.setAppInForeground(false));
    }
    _primaryMessageSubscription?.cancel();
    _mobileMessageSubscription?.cancel();
    _buildingMessageSubscription?.cancel();
    _client?.unsubscribe(_primarySubscriberId);
    _client?.unsubscribe(_mobileSubscriberId);
    _client?.unsubscribe(_buildingSubscriberId);
    _alertEffectsAutoStopTimer?.cancel();
    super.dispose();
  }

  String get _primarySubscriberId => '${NatsConfig.subscriberId}-primary';

  String get _mobileSubscriberId => '${NatsConfig.subscriberId}-mobile';

  String get _buildingSubscriberId => '${NatsConfig.subscriberId}-building';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enableForegroundService) return;
    final bool isForeground = state == AppLifecycleState.resumed;
    unawaited(NatsServiceController.setAppInForeground(isForeground));
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      NatsServiceController.syncWithSessionOrFallback(
        fallbackServerUrl: NatsConfig.serverUrl,
        fallbackEnv: NatsConfig.env,
        fallbackPrimarySubject: widget.config.subject,
        fallbackMobileSubject: widget.config.mobileSubject,
        fallbackBuildingSubject: widget.config.buildingSubject,
      );
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverPendingEmergencyAlert());
    }
  }

  Future<void> _connectAndSubscribe() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _status = 'Connecting...';
    });

    final client = NatsClient(NatsConfig.host, NatsConfig.port);

    try {
      await client.connect();

      if (kDebugMode) {
        debugPrint(
          'NatsListenerPage subscribing | primary=${widget.config.subject} | mobile=${widget.config.mobileSubject} | building=${widget.config.buildingSubject}',
        );
      }

      final Stream<NatsMessage> primaryStream = client.subscribe(
        _primarySubscriberId,
        widget.config.subject,
      );
      final Stream<NatsMessage> mobileStream = client.subscribe(
        _mobileSubscriberId,
        widget.config.mobileSubject,
      );
      final Stream<NatsMessage> buildingStream = client.subscribe(
        _buildingSubscriberId,
        widget.config.buildingSubject,
      );

      await _primaryMessageSubscription?.cancel();
      await _mobileMessageSubscription?.cancel();
      await _buildingMessageSubscription?.cancel();
      _primaryMessageSubscription = primaryStream.listen(_onMessageReceived);
      _mobileMessageSubscription = mobileStream.listen(_onMessageReceived);
      _buildingMessageSubscription = buildingStream.listen(_onMessageReceived);

      if (!mounted) return;
      setState(() {
        _client = client;
        _isConnected = true;
        _status = 'Connected';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _status = 'Connection failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _onMessageReceived(NatsMessage message) async {
    if (!mounted) return;

    final ParsedAlertPayload parsed = await compute(
      ParsedAlertPayload.fromRaw,
      message.payload,
    );
    if (!mounted) return;

    if (kDebugMode) {
      final Uint8List? imageBytes = parsed.imageBytes;
      debugPrint(
        'NATS message received | subject=${message.subject} | payloadLength=${message.payload.length} | '
        'threat=${parsed.threatType} | mode=${parsed.alertMode} | '
        'instructionsPresent=${parsed.instructions != null} | '
        'imagePresent=${parsed.image != null} | imageLength=${parsed.image?.length ?? 0} | '
        'imageBytesLength=${imageBytes?.length ?? 0}',
      );
    }

    if (parsed.isCameraControlSignal) {
      if (kDebugMode) {
        debugPrint(
          'camera control signal ignored in Flutter UI | enabled=${parsed.isEnabled} | cameraId=${parsed.cameraControlId}',
        );
      }
      return;
    }

    if (parsed.isResolved == true) {
      _handleResolvedAlert(parsed);
      return;
    }

    if (!parsed.hasDisplayableAlertMode) {
      if (kDebugMode) {
        debugPrint(
          'non-alert payload ignored in Flutter UI | alertMode=${parsed.alertMode} | isResolved=${parsed.isResolved}',
        );
      }
      return;
    }

    final ReceivedAlert alert = ReceivedAlert(
      message: message,
      parsed: parsed,
      receivedAt: DateTime.now(),
    );
    await _presentIncomingAlert(alert);
  }

  Future<void> _recoverPendingEmergencyAlert({
    PendingEmergencyAlert? seedAlert,
  }) async {
    try {
      final PendingEmergencyAlert? pendingAlert =
          seedAlert ??
          await NatsServiceController.consumePendingEmergencyAlert();
      if (!mounted || pendingAlert == null) return;

      final ParsedAlertPayload parsed = await compute(
        ParsedAlertPayload.fromRaw,
        pendingAlert.payload,
      );
      if (!mounted) return;

      if (kDebugMode) {
        debugPrint(
          'recover pending alert | subject=${pendingAlert.subject} | payloadLength=${pendingAlert.payload.length}',
        );
      }

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
      await _presentIncomingAlert(alert);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('recover pending alert failed | error=$error');
      }
    }
  }

  Future<void> _presentIncomingAlert(ReceivedAlert alert) async {
    if (!mounted) return;
    final bool alreadyPresent = _messages.any(
      (ReceivedAlert existing) =>
          existing.message.subject == alert.message.subject &&
          existing.message.payload == alert.message.payload &&
          existing.receivedAt == alert.receivedAt,
    );

    if (!alreadyPresent) {
      setState(() {
        _messages.insert(0, alert);
      });
    }

    await _showDangerDialog(alert);
  }

  void _handleResolvedAlert(ParsedAlertPayload resolvedAlert) {
    if (kDebugMode) {
      debugPrint(
        'resolved alert received | alertMode=${resolvedAlert.alertMode} | roomName=${resolvedAlert.roomName} | floorId=${resolvedAlert.floorId} | buildingId=${resolvedAlert.buildingId}',
      );
    }

    final String? resolvedBuildingId = resolvedAlert.buildingId?.trim();
    if (resolvedBuildingId == null || resolvedBuildingId.isEmpty) {
      if (kDebugMode) {
        debugPrint('resolved alert ignored | buildingId missing');
      }
      return;
    }

    setState(() {
      final List<String> removedAlertKeys = _messages
          .where(
            (ReceivedAlert alert) =>
                alert.parsed.buildingId?.trim() == resolvedBuildingId,
          )
          .map((ReceivedAlert alert) => alert.uniqueKey)
          .toList();
      _messages.removeWhere(
        (ReceivedAlert alert) => alert.parsed.buildingId?.trim() == resolvedBuildingId,
      );
      for (final String alertKey in removedAlertKeys) {
        _alertResponses.remove(alertKey);
      }
    });

    final ReceivedAlert? activeAlert = _activeDialogAlert;
    if (activeAlert != null &&
        activeAlert.parsed.buildingId?.trim() == resolvedBuildingId &&
        _isAlertDialogVisible) {
      _alertEffectsAutoStopTimer?.cancel();
      _activeDialogAlert = null;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  void _scheduleAlertEffectsAutoStop() {
    final ReceivedAlert? alert = _activeDialogAlert;
    if (alert?.parsed.isSilent == true) {
      _alertEffectsAutoStopTimer?.cancel();
      return;
    }
    _alertEffectsAutoStopTimer?.cancel();
    _alertEffectsAutoStopTimer = Timer(const Duration(seconds: 20), () async {
      try {
        await NatsServiceController.silenceEmergencyAlert();
      } catch (error) {
        if (kDebugMode) {
          debugPrint('auto silence emergency alert failed | error=$error');
        }
      }
    });
  }

  Future<void> _showDangerDialog(ReceivedAlert alert) async {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(
        'showDangerDialog start | mounted=$mounted | currentRoute=${ModalRoute.of(context)?.settings.name ?? "unnamed"}',
      );
    }

    _activeDialogAlert = alert;
    _scheduleAlertEffectsAutoStop();
    if (_isAlertDialogVisible) {
      _alertDialogSetState?.call(() {});
      return;
    }

    final BuildContext dialogContext = context;
    _isAlertDialogVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ParsedAlertPayload parsed =
          _activeDialogAlert?.parsed ?? alert.parsed;
      if (kDebugMode) {
        debugPrint(
          'showDangerDialog presenting | imageBytesLength=${parsed.imageBytes?.length ?? 0} | title=${parsed.displayTitle}',
        );
      }
      showGeneralDialog<void>(
        context: dialogContext,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierLabel: 'Security Alert',
        barrierColor: Colors.black54,
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
            ) {
              if (kDebugMode) {
                debugPrint('showDangerDialog builder invoked');
              }
              return StatefulBuilder(
                builder: (BuildContext context, StateSetter dialogSetState) {
                  _alertDialogSetState = dialogSetState;
                  final ReceivedAlert currentAlert =
                      _activeDialogAlert ?? alert;
                  final ParsedAlertPayload parsed = currentAlert.parsed;
                  final String alertKey = currentAlert.uniqueKey;
                  final AlertResponseStatus? responseStatus =
                      _alertResponses[alertKey];
                  final bool isConfirmed =
                      responseStatus == AlertResponseStatus.confirmed;
                  final bool isCannotComply =
                      responseStatus == AlertResponseStatus.cannotComply;
                  final Size screenSize = MediaQuery.sizeOf(context);
                  final bool isTablet = screenSize.width >= 600;
                  final double emphasisFontSize =
                      screenSize.width * (isTablet ? 0.025 : 0.05);
                  final double titleFontSize = emphasisFontSize;
                  final double threatFontSize = emphasisFontSize;
                  final double bodyFontSize = isTablet ? 20 : 16;
                  final double buttonHeight = isTablet ? 68 : 48;
                  final double warningIconSize = isTablet ? 34 : 28;
                  final double imageMaxHeight = isTablet ? 320 : 220;
                  final double dialogMaxHeight = screenSize.height * 0.7;
                  final String dialogTitle =
                      parsed.alertMode?.trim().isNotEmpty == true
                      ? parsed.alertMode!
                      : 'Security Alert';

                  return SafeArea(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 32 : 20,
                          vertical: 24,
                        ),
                        child: Material(
                          color: const Color(0xFF8B0000),
                          elevation: 24,
                          borderRadius: BorderRadius.circular(28),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: isTablet ? 720 : 420,
                              maxHeight: dialogMaxHeight,
                              minWidth: 280,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                16,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.white,
                                        size: warningIconSize,
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          dialogTitle,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          if (parsed.imageBytes != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: ColoredBox(
                                                  color: Colors.black26,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    child: LayoutBuilder(
                                                      builder:
                                                          (
                                                            BuildContext
                                                            context,
                                                            BoxConstraints
                                                            constraints,
                                                          ) {
                                                            return Center(
                                                              child: ConstrainedBox(
                                                                constraints: BoxConstraints(
                                                                  maxWidth:
                                                                      constraints
                                                                          .maxWidth,
                                                                  maxHeight:
                                                                      imageMaxHeight,
                                                                ),
                                                                child: Image.memory(
                                                                  parsed
                                                                      .imageBytes!,
                                                                  fit: BoxFit
                                                                      .contain,
                                                                  errorBuilder:
                                                                      (
                                                                        BuildContext
                                                                        context,
                                                                        Object
                                                                        error,
                                                                        StackTrace?
                                                                        stackTrace,
                                                                      ) {
                                                                        if (kDebugMode) {
                                                                          debugPrint(
                                                                            'showDangerDialog image errorBuilder hit',
                                                                          );
                                                                        }
                                                                        return const SizedBox.shrink();
                                                                      },
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (parsed.threatType
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  parsed.threatType!,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: threatFontSize,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          Text(
                                            parsed.displayBody,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: bodyFontSize,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isConfirmed
                                                ? const Color(0xFF0E7A0D)
                                                : const Color(0xFF2E2E2E),
                                            foregroundColor: Colors.white,
                                            minimumSize: Size.fromHeight(
                                              buttonHeight,
                                            ),
                                          ),
                                          onPressed: () async {
                                            await _handleAlertResponse(
                                              alert: currentAlert,
                                              responseStatus:
                                                  AlertResponseStatus.confirmed,
                                              context: context,
                                            );
                                            _alertDialogSetState?.call(() {});
                                          },
                                          child: Text(
                                            isConfirmed
                                                ? 'Confirmed'
                                                : 'Confirm',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isCannotComply
                                                ? const Color(0xFF0E7A0D)
                                                : const Color(0xFF2E2E2E),
                                            foregroundColor: Colors.white,
                                            minimumSize: Size.fromHeight(
                                              buttonHeight,
                                            ),
                                          ),
                                          onPressed: () async {
                                            await _handleAlertResponse(
                                              alert: currentAlert,
                                              responseStatus:
                                                  AlertResponseStatus
                                                      .cannotComply,
                                              context: context,
                                            );
                                            _alertDialogSetState?.call(() {});
                                          },
                                          child: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'Cannot comply',
                                              maxLines: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
        transitionBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
              Widget child,
            ) {
              final CurvedAnimation curvedAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curvedAnimation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.96,
                    end: 1,
                  ).animate(curvedAnimation),
                  child: child,
                ),
              );
            },
      ).whenComplete(() {
        _isAlertDialogVisible = false;
        _activeDialogAlert = null;
        _alertDialogSetState = null;
      });
    });
  }

  Future<void> _handleAlertResponse({
    required ReceivedAlert alert,
    required AlertResponseStatus responseStatus,
    required BuildContext context,
  }) async {
    try {
      await NatsServiceController.postFloorplanComply(
        buildingId: widget.config.buildingId,
        floorId: widget.config.floorId,
        roomName: widget.config.roomName,
        isComply: responseStatus == AlertResponseStatus.confirmed,
      );

      if (responseStatus == AlertResponseStatus.confirmed) {
        await NatsServiceController.confirmEmergencyAlert();
      } else {
        await NatsServiceController.cannotComplyEmergencyAlert();
      }

      _alertEffectsAutoStopTimer?.cancel();

      if (!mounted) return;
      setState(() {
        _alertResponses[alert.uniqueKey] = responseStatus;
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('floorplan comply failed | error=$error');
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send ${responseStatus == AlertResponseStatus.confirmed ? 'confirm' : 'cannot comply'} response yet.',
          ),
        ),
      );
    }
  }

  Future<void> _startManualStreaming() async {
    if (_isStartingManualStream) return;

    setState(() {
      _isStartingManualStream = true;
    });

    try {
      await NatsServiceController.startManualStreaming();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Panic streaming started.')),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('manual streaming start failed | error=$error');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start panic streaming right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isStartingManualStream = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: isMobile ? 24 : 32,
          child: Image.asset(
            'assets/images/cipher-safety-logotxt.png',
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ResolvedLocationCard(config: widget.config),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Icon(
                  _isConnected ? Icons.check_circle : Icons.error,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_status)),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isConnecting ? null : _connectAndSubscribe,
                  child: const Text('Reconnect'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Spacer(),
            Center(
              child: _PanicButton(
                isLoading: _isStartingManualStream,
                onPressed: _startManualStreaming,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await ListenerConfig.clearSaved();
    await NatsServiceController.clearStreamingConfig();
    await NatsServiceController.stop();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SubjectEntryPage(
          autoConnect: widget.autoConnect,
          enableForegroundService: widget.enableForegroundService,
        ),
      ),
    );
  }
}

class ReceivedAlert {
  const ReceivedAlert({
    required this.message,
    required this.parsed,
    required this.receivedAt,
  });

  final NatsMessage message;
  final ParsedAlertPayload parsed;
  final DateTime receivedAt;

  String get uniqueKey =>
      '${message.subject}|${receivedAt.microsecondsSinceEpoch}';
}

class _ResolvedLocationCard extends StatelessWidget {
  const _ResolvedLocationCard({required this.config});

  final ListenerConfig config;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(config.resolvedBuildingName, style: textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(config.displayDeviceId),
        ],
      ),
    );
  }
}

class _PanicButton extends StatelessWidget {
  const _PanicButton({
    required this.onPressed,
    required this.isLoading,
  });

  final Future<void> Function() onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Panic button',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: <Color>[
                  Color(0xFFFF8A80),
                  Color(0xFFD32F2F),
                  Color(0xFF7F1010),
                ],
                stops: <double>[0.0, 0.55, 1.0],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66FF5252),
                  blurRadius: 40,
                  spreadRadius: 6,
                ),
                BoxShadow(
                  color: Color(0xAA5C0C0C),
                  blurRadius: 18,
                  offset: Offset(0, 14),
                ),
              ],
              border: Border.all(
                color: const Color(0xFFFFCDD2).withValues(alpha: 0.65),
                width: 6,
              ),
            ),
            child: Center(
              child: Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLoading
                      ? const Color(0xFF8E1A1A)
                      : const Color(0xFFB71C1C),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 2,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.warning_rounded,
                              size: 34,
                              color: Colors.white,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'PANIC',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.6,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Emergency',
                              style: TextStyle(
                                color: Color(0xFFFFD7D7),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum AlertResponseStatus {
  confirmed('Confirmed'),
  cannotComply('Can not comply');

  const AlertResponseStatus(this.label);

  final String label;
}

class ParsedAlertPayload {
  const ParsedAlertPayload({
    required this.rawPayload,
    this.image,
    this.isSilent,
    this.isResolved,
    this.isEnabled,
    this.cameraControlId,
    this.alertType,
    this.threatType,
    this.instructions,
    this.alertMode,
    this.roomName,
    this.floorId,
    this.buildingId,
  });

  final String rawPayload;
  final String? image;
  final bool? isSilent;
  final bool? isResolved;
  final bool? isEnabled;
  final String? cameraControlId;
  final String? alertType;
  final String? threatType;
  final String? instructions;
  final String? alertMode;
  final String? roomName;
  final String? floorId;
  final String? buildingId;

  bool get hasDisplayableAlertMode => alertMode?.trim().isNotEmpty == true;
  bool get isCameraControlSignal =>
      cameraControlId?.trim().isNotEmpty == true && isEnabled != null;

  String get displayTitle => alertType ?? alertMode ?? 'Security Alert';
  String get displayBody =>
      instructions?.trim().isNotEmpty == true ? instructions! : rawPayload;

  bool matchesAlertTarget(ParsedAlertPayload other) {
    final bool sameRoom =
        roomName?.trim().isNotEmpty == true &&
        other.roomName?.trim().isNotEmpty == true &&
        roomName == other.roomName;
    final bool sameFloor =
        floorId?.trim().isNotEmpty == true &&
        other.floorId?.trim().isNotEmpty == true &&
        floorId == other.floorId;
    final bool sameBuilding =
        buildingId?.trim().isNotEmpty == true &&
        other.buildingId?.trim().isNotEmpty == true &&
        buildingId == other.buildingId;
    final bool sameMode =
        alertMode?.trim().isNotEmpty == true &&
        other.alertMode?.trim().isNotEmpty == true &&
        alertMode == other.alertMode;
    return sameRoom ||
        (sameFloor && sameBuilding) ||
        (sameMode && sameBuilding);
  }

  Uint8List? get imageBytes {
    if (image == null || image!.trim().isEmpty) return null;
    final String value = image!.trim().replaceAll(RegExp(r'\s+'), '');
    try {
      if (value.startsWith('data:image')) {
        final List<String> parts = value.split(',');
        if (parts.length > 1) {
          return base64Decode(parts.last);
        }
      }
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  static ParsedAlertPayload fromRaw(String rawPayload) {
    final Map<String, dynamic>? parsedMap = _extractAlertMap(
      _tryParseObject(rawPayload),
    );
    final _FallbackFields fallbackFields = _extractFallbackFields(rawPayload);

    if (parsedMap == null && fallbackFields.isEmpty) {
      return ParsedAlertPayload(rawPayload: rawPayload);
    }

    return ParsedAlertPayload(
      rawPayload: rawPayload,
      image: _readField(parsedMap, <String>['image']) ?? fallbackFields.image,
      isSilent:
          _readBoolField(parsedMap, <String>['isSilent', 'is_silent']) ??
          fallbackFields.isSilent,
      isResolved:
          _readBoolField(parsedMap, <String>['isResolved', 'is_resolved']) ??
          fallbackFields.isResolved,
      isEnabled:
          _readBoolField(parsedMap, <String>['isEnabled', 'is_enabled']) ??
          fallbackFields.isEnabled,
      cameraControlId:
          _readField(parsedMap, <String>['id', 'cameraId', 'camera_id']) ??
          fallbackFields.cameraControlId,
      alertType:
          _readField(parsedMap, <String>[
            'alertType',
            'alert_type',
            'alert type',
            'allertType',
            'allert_type',
            'allert type',
          ]) ??
          fallbackFields.alertType,
      threatType:
          _readField(parsedMap, <String>['threatType', 'threat_type']) ??
          fallbackFields.threatType,
      instructions:
          _readField(parsedMap, <String>['instructions', 'instruction']) ??
          fallbackFields.instructions,
      alertMode:
          _readField(parsedMap, <String>['alertMode', 'alert_mode']) ??
          fallbackFields.alertMode,
      roomName:
          _readField(parsedMap, <String>['roomName', 'room_name']) ??
          fallbackFields.roomName,
      floorId:
          _readField(parsedMap, <String>['floorId', 'floor_id']) ??
          fallbackFields.floorId,
      buildingId:
          _readField(parsedMap, <String>['buildingId', 'building_id']) ??
          fallbackFields.buildingId,
    );
  }

  static Map<String, dynamic>? _tryParseObject(String raw) {
    final String trimmed = raw.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;

    try {
      final dynamic direct = jsonDecode(trimmed);
      if (direct is Map<String, dynamic>) return direct;
    } catch (_) {}

    try {
      final String normalizedKeys = trimmed.replaceAllMapped(
        RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'),
        (Match m) => '${m.group(1)}"${m.group(2)}":',
      );
      final String normalizedQuotes = normalizedKeys.replaceAll("'", '"');
      final dynamic parsed = jsonDecode(normalizedQuotes);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}

    return null;
  }

  static Map<String, dynamic>? _extractAlertMap(Map<String, dynamic>? source) {
    if (source == null) return null;
    final dynamic nestedData = source['data'];
    if (nestedData is Map<String, dynamic>) {
      return nestedData;
    }
    if (nestedData is Map) {
      return Map<String, dynamic>.from(nestedData);
    }
    if (nestedData is String) {
      final Map<String, dynamic>? nestedParsed = _tryParseObject(nestedData);
      if (nestedParsed != null) {
        return nestedParsed;
      }
    }
    return source;
  }

  static _FallbackFields _extractFallbackFields(String raw) {
    return _FallbackFields(
      image: _matchField(raw, 'image'),
      isSilent:
          _matchBoolField(raw, 'isSilent') ?? _matchBoolField(raw, 'is_silent'),
      isResolved:
          _matchBoolField(raw, 'isResolved') ??
          _matchBoolField(raw, 'is_resolved'),
      isEnabled:
          _matchBoolField(raw, 'isEnabled') ??
          _matchBoolField(raw, 'is_enabled'),
      cameraControlId:
          _matchField(raw, 'id') ??
          _matchField(raw, 'cameraId') ??
          _matchField(raw, 'camera_id'),
      alertType:
          _matchField(raw, 'alertType') ?? _matchField(raw, 'allertType'),
      threatType: _matchField(raw, 'threatType'),
      instructions: _matchField(raw, 'instructions'),
      alertMode: _matchField(raw, 'alertMode'),
      roomName: _matchField(raw, 'roomName'),
      floorId: _matchField(raw, 'floorId'),
      buildingId: _matchField(raw, 'buildingId'),
    );
  }

  static String? _matchField(String raw, String fieldName) {
    final RegExp pattern = RegExp(
      '[\'"]?$fieldName[\'"]?\\s*[:=]\\s*[\'"]((?:\\\\.|[^\'"\\\\])*)[\'"]',
      dotAll: true,
    );
    final Match? match = pattern.firstMatch(raw);
    if (match == null) return null;
    final String value = _unescapeString(match.group(1)?.trim() ?? '');
    return value.isEmpty ? null : value;
  }

  static String _unescapeString(String value) {
    if (value.isEmpty) return value;
    return value
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\/', '/')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');
  }

  static String? _asString(dynamic value) {
    if (value == null) return null;
    final String converted = value.toString().trim();
    return converted.isEmpty ? null : converted;
  }

  static bool? _asBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final String normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return null;
  }

  static String? _readField(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final String key in keys) {
      final String? value = _asString(map[key]);
      if (value != null) return value;
    }
    return null;
  }

  static bool? _readBoolField(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    for (final String key in keys) {
      final bool? value = _asBool(map[key]);
      if (value != null) return value;
    }
    return null;
  }

  static bool? _matchBoolField(String raw, String fieldName) {
    final RegExp pattern = RegExp(
      '[\'"]?$fieldName[\'"]?\\s*[:=]\\s*(true|false)',
      caseSensitive: false,
    );
    final Match? match = pattern.firstMatch(raw);
    if (match == null) return null;
    return match.group(1)?.toLowerCase() == 'true';
  }
}

class _FallbackFields {
  const _FallbackFields({
    this.image,
    this.isSilent,
    this.isResolved,
    this.isEnabled,
    this.cameraControlId,
    this.alertType,
    this.threatType,
    this.instructions,
    this.alertMode,
    this.roomName,
    this.floorId,
    this.buildingId,
  });

  final String? image;
  final bool? isSilent;
  final bool? isResolved;
  final bool? isEnabled;
  final String? cameraControlId;
  final String? alertType;
  final String? threatType;
  final String? instructions;
  final String? alertMode;
  final String? roomName;
  final String? floorId;
  final String? buildingId;

  bool get isEmpty =>
      image == null &&
      isSilent == null &&
      isResolved == null &&
      isEnabled == null &&
      cameraControlId == null &&
      alertType == null &&
      threatType == null &&
      instructions == null &&
      alertMode == null &&
      roomName == null &&
      floorId == null &&
      buildingId == null;
}
