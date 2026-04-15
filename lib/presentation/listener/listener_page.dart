import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cipher_safety/data/models/listener_config.dart';
import 'package:cipher_safety/data/models/pending_emergency_alert.dart';
import 'package:cipher_safety/data/repositories/listener_repository.dart';
import 'package:cipher_safety/domain/models/received_alert.dart';
import 'package:cipher_safety/presentation/listener/listener_view_model.dart';
import 'package:cipher_safety/presentation/subject_entry/subject_entry_page.dart';

class ListenerPage extends StatefulWidget {
  const ListenerPage({
    super.key,
    required this.config,
    required this.listenerRepository,
    this.autoConnect = true,
    this.enableForegroundService = true,
    this.startupPendingAlert,
  });

  final ListenerConfig config;
  final ListenerRepository listenerRepository;
  final bool autoConnect;
  final bool enableForegroundService;
  final PendingEmergencyAlert? startupPendingAlert;

  @override
  State<ListenerPage> createState() => _ListenerPageState();
}

class _ListenerPageState extends State<ListenerPage>
    with WidgetsBindingObserver {
  late final ListenerViewModel _viewModel;
  StateSetter? _alertDialogSetState;

  @override
  void initState() {
    super.initState();
    _viewModel = ListenerViewModel(
      config: widget.config,
      listenerRepository: widget.listenerRepository,
      autoConnect: widget.autoConnect,
      enableForegroundService: widget.enableForegroundService,
    );
    _viewModel.addListener(_maybeShowAlertDialog);
    if (widget.enableForegroundService) {
      WidgetsBinding.instance.addObserver(this);
    }
    unawaited(_initialize());
  }

  @override
  void dispose() {
    if (widget.enableForegroundService) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _viewModel.removeListener(_maybeShowAlertDialog);
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _viewModel.initialize(initialPendingAlert: widget.startupPendingAlert);
    if (!mounted) return;
    await _viewModel.recoverPendingEmergencyAlert();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_viewModel.onLifecycleChanged(state));
    if (state == AppLifecycleState.resumed) {
      unawaited(_viewModel.recoverPendingEmergencyAlert());
    }
  }

  void _maybeShowAlertDialog() {
    final ReceivedAlert? alert = _viewModel.activeDialogAlert;
    if (!mounted) return;

    if (alert == null) {
      if (_viewModel.isAlertDialogVisible &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }

    if (_viewModel.isAlertDialogVisible) {
      _alertDialogSetState?.call(() {});
      return;
    }

    _viewModel.setDialogVisibility(true);

    showGeneralDialog<void>(
      context: context,
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
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter dialogSetState) {
                _alertDialogSetState = dialogSetState;
                final ReceivedAlert currentAlert =
                    _viewModel.activeDialogAlert ?? alert;
                final String alertKey = currentAlert.uniqueKey;
                final AlertResponseStatus? responseStatus =
                    _viewModel.alertResponses[alertKey];
                return _SecurityAlertDialog(
                  alert: currentAlert,
                  responseStatus: responseStatus,
                  onRespond: (AlertResponseStatus nextStatus) async {
                    try {
                      await _viewModel.handleAlertResponse(
                        alert: currentAlert,
                        responseStatus: nextStatus,
                      );
                      _alertDialogSetState?.call(() {});
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not send ${nextStatus == AlertResponseStatus.confirmed ? 'confirm' : 'cannot comply'} response yet.',
                          ),
                        ),
                      );
                    }
                  },
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
                scale: Tween<double>(begin: 0.96, end: 1).animate(
                  curvedAnimation,
                ),
                child: child,
              ),
            );
          },
    ).whenComplete(() {
      _alertDialogSetState = null;
      _viewModel.setDialogVisibility(false);
    });
  }

  Future<void> _logout() async {
    await _viewModel.logout();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SubjectEntryPage(
          listenerRepository: widget.listenerRepository,
          autoConnect: widget.autoConnect,
          enableForegroundService: widget.enableForegroundService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (BuildContext context, Widget? child) {
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
                      _viewModel.isConnected
                          ? Icons.check_circle
                          : Icons.error,
                      color: _viewModel.isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_viewModel.status)),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _viewModel.isConnecting
                          ? null
                          : _viewModel.connectAndSubscribe,
                      child: const Text('Reconnect'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Spacer(),
                Center(
                  child: _PanicButton(
                    isActive: _viewModel.isPanicActive,
                    isLoading: _viewModel.isStartingManualStream,
                    onPressed: () async {
                      final ScaffoldMessengerState messenger =
                          ScaffoldMessenger.of(context);
                      try {
                        await _viewModel.startManualStreaming();
                      } catch (_) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not start panic streaming right now.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }
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
          Text(config.roomName),
        ],
      ),
    );
  }
}

class _PanicButton extends StatelessWidget {
  const _PanicButton({
    required this.onPressed,
    required this.isLoading,
    required this.isActive,
  });

  final Future<void> Function() onPressed;
  final bool isLoading;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Panic logo button',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onLongPress: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: isLoading ? 0.55 : 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 220,
                        child: Image.asset(
                          isActive
                              ? 'assets/images/cipher-safety-logo-red.png'
                              : 'assets/images/cipher-safety-logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 42,
                          height: 42,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isActive) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    'Long press the logo to activate panic.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.25,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityAlertDialog extends StatelessWidget {
  const _SecurityAlertDialog({
    required this.alert,
    required this.responseStatus,
    required this.onRespond,
  });

  final ReceivedAlert alert;
  final AlertResponseStatus? responseStatus;
  final Future<void> Function(AlertResponseStatus status) onRespond;

  @override
  Widget build(BuildContext context) {
    final parsed = alert.parsed;
    final bool isConfirmed = responseStatus == AlertResponseStatus.confirmed;
    final bool isCannotComply =
        responseStatus == AlertResponseStatus.cannotComply;
    final Size screenSize = MediaQuery.sizeOf(context);
    final bool isTablet = screenSize.width >= 600;
    final double emphasisFontSize = screenSize.width * (isTablet ? 0.025 : 0.05);
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
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
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
                              fontSize: emphasisFontSize,
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (parsed.imageBytes != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: ColoredBox(
                                    color: Colors.black26,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: imageMaxHeight,
                                          ),
                                          child: Image.memory(
                                            parsed.imageBytes!,
                                            fit: BoxFit.contain,
                                            errorBuilder:
                                                (
                                                  BuildContext context,
                                                  Object error,
                                                  StackTrace? stackTrace,
                                                ) => const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (parsed.threatType?.trim().isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Center(
                                  child: Text(
                                    parsed.threatType!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: emphasisFontSize,
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
                              minimumSize: Size.fromHeight(buttonHeight),
                            ),
                            onPressed: () => onRespond(
                              AlertResponseStatus.confirmed,
                            ),
                            child: Text(isConfirmed ? 'Confirmed' : 'Confirm'),
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
                              minimumSize: Size.fromHeight(buttonHeight),
                            ),
                            onPressed: () => onRespond(
                              AlertResponseStatus.cannotComply,
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Cannot comply', maxLines: 1),
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
  }
}
