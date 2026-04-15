import 'package:flutter/foundation.dart';

import 'package:cipher_safety/data/models/listener_config.dart';
import 'package:cipher_safety/data/models/pending_emergency_alert.dart';
import 'package:cipher_safety/data/repositories/listener_repository.dart';

class SubjectEntryViewModel extends ChangeNotifier {
  SubjectEntryViewModel(this._listenerRepository);

  final ListenerRepository _listenerRepository;

  bool isLoadingSavedConfig = true;
  bool isSearchingRoom = false;
  bool didOpenSavedListener = false;
  PendingEmergencyAlert? startupPendingAlert;

  Future<ListenerConfig?> loadSavedConfig() async {
    startupPendingAlert ??= await _listenerRepository.consumePendingAlert();
    final ListenerConfig? savedConfig =
        await _listenerRepository.loadSavedConfig();
    isLoadingSavedConfig = false;
    notifyListeners();
    return savedConfig;
  }

  Future<ListenerConfig> continueToListener({
    required String buildingName,
    required String tabletId,
  }) async {
    isSearchingRoom = true;
    notifyListeners();
    try {
      return await _listenerRepository.resolveListenerConfig(
        buildingName: buildingName,
        tabletId: tabletId,
      );
    } finally {
      isSearchingRoom = false;
      notifyListeners();
    }
  }

  void markSavedListenerOpened() {
    didOpenSavedListener = true;
    notifyListeners();
  }
}
