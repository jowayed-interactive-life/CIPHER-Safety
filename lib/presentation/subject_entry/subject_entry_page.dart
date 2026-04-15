import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cipher_safety/core/formatters/device_id_text_input_formatter.dart';
import 'package:cipher_safety/data/models/listener_config.dart';
import 'package:cipher_safety/data/repositories/listener_repository.dart';
import 'package:cipher_safety/presentation/listener/listener_page.dart';
import 'package:cipher_safety/presentation/subject_entry/subject_entry_view_model.dart';

class SubjectEntryPage extends StatefulWidget {
  const SubjectEntryPage({
    super.key,
    required this.listenerRepository,
    this.autoConnect = true,
    this.enableForegroundService = true,
  });

  final ListenerRepository listenerRepository;
  final bool autoConnect;
  final bool enableForegroundService;

  @override
  State<SubjectEntryPage> createState() => _SubjectEntryPageState();
}

class _SubjectEntryPageState extends State<SubjectEntryPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _buildingIdController = TextEditingController();
  final TextEditingController _cameraIdController = TextEditingController();
  late final SubjectEntryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SubjectEntryViewModel(widget.listenerRepository);
    unawaited(_loadSavedConfig());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _buildingIdController.dispose();
    _cameraIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedConfig() async {
    final ListenerConfig? savedConfig = await _viewModel.loadSavedConfig();
    if (!mounted || savedConfig == null || _viewModel.didOpenSavedListener) {
      return;
    }

    _buildingIdController.text = savedConfig.buildingName;
    _cameraIdController.text = DeviceIdTextInputFormatter.format(
      savedConfig.displayDeviceId,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewModel.didOpenSavedListener) return;
      _viewModel.markSavedListenerOpened();
      _openListener(savedConfig);
    });
  }

  Future<void> _continueToListener() async {
    if (!_formKey.currentState!.validate()) return;
    if (_viewModel.isSearchingRoom) return;

    final String buildingName = _buildingIdController.text.trim();
    final String tabletId = _cameraIdController.text.trim().toUpperCase();

    try {
      final ListenerConfig config = await _viewModel.continueToListener(
        buildingName: buildingName,
        tabletId: tabletId,
      );
      if (!mounted) return;
      _openListener(config);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Building name or device ID is incorrect. Please try again.',
          ),
        ),
      );
    }
  }

  void _openListener(ListenerConfig config) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ListenerPage(
          config: config,
          listenerRepository: widget.listenerRepository,
          autoConnect: widget.autoConnect,
          enableForegroundService: widget.enableForegroundService,
          startupPendingAlert: _viewModel.startupPendingAlert,
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (BuildContext context, Widget? child) {
        if (_viewModel.isLoadingSavedConfig) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
                          decoration: _inputDecoration('Building Name'),
                          validator: _validateRequired,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _cameraIdController,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: const <TextInputFormatter>[
                            DeviceIdTextInputFormatter(),
                          ],
                          onFieldSubmitted: (_) => _continueToListener(),
                          decoration: _inputDecoration('Device ID'),
                          validator: _validateRequired,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _viewModel.isSearchingRoom
                                ? null
                                : _continueToListener,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: Text(
                              _viewModel.isSearchingRoom
                                  ? 'Searching...'
                                  : 'Continue',
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
      },
    );
  }

  InputDecoration _inputDecoration(String labelText) {
    return InputDecoration(
      labelText: labelText,
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
    );
  }
}
