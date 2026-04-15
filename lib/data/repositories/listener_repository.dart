import 'package:cipher_safety/data/models/listener_config.dart';
import 'package:cipher_safety/data/models/pending_emergency_alert.dart';
import 'package:cipher_safety/data/models/tablet_camera_lookup_result.dart';
import 'package:cipher_safety/data/services/nats_platform_service.dart';

class ListenerRepository {
  ListenerRepository(this._platformService);

  final NatsPlatformService _platformService;

  Future<ListenerConfig?> loadSavedConfig() => ListenerConfig.loadSaved();

  Future<void> clearSavedConfig() => ListenerConfig.clearSaved();

  Future<PendingEmergencyAlert?> consumePendingAlert() =>
      _platformService.consumePendingEmergencyAlert();

  Future<ListenerConfig> resolveListenerConfig({
    required String buildingName,
    required String tabletId,
  }) async {
    final TabletCameraLookupResult lookupResult =
        await _platformService.getTabletCameraConfig(
          tabletId: tabletId,
          buildingName: buildingName,
        );

    final ListenerConfig config = ListenerConfig(
      buildingId: lookupResult.buildingId,
      floorId: lookupResult.floorId,
      buildingName: buildingName,
      displayDeviceId: tabletId,
      resolvedBuildingName: lookupResult.buildingName,
      roomName: lookupResult.roomName,
      cameraId: lookupResult.cameraId,
      streamUrl: lookupResult.streamUrl,
    );

    await config.save();
    await syncStreamingConfig(config);
    return config;
  }

  Future<void> syncStreamingConfig(ListenerConfig config) {
    return _platformService.syncStreamingConfig(
      cameraId: config.cameraId,
      streamUrl: config.streamUrl,
      tabletId: config.displayDeviceId,
      buildingName: config.buildingName,
    );
  }

  Future<void> clearStreamingConfig() => _platformService.clearStreamingConfig();

  Future<void> startForegroundSync(ListenerConfig config) {
    return _platformService.syncWithSessionOrFallback(
      fallbackServerUrl: 'nats://nats.interactivelife.me:4222',
      fallbackEnv: 'staging',
      fallbackPrimarySubject: config.subject,
      fallbackMobileSubject: config.mobileSubject,
      fallbackBuildingSubject: config.buildingSubject,
    );
  }

  Future<void> setAppInForeground(bool isForeground) {
    return _platformService.setAppInForeground(isForeground);
  }

  Future<void> stopForegroundService() => _platformService.stop();

  Future<void> startManualStreaming() => _platformService.startManualStreaming();

  Future<void> sendAlertResponse({
    required ListenerConfig config,
    required bool isComply,
  }) async {
    await _platformService.postFloorplanComply(
      buildingId: config.buildingId,
      floorId: config.floorId,
      roomName: config.roomName,
      isComply: isComply,
    );
    if (isComply) {
      await _platformService.confirmEmergencyAlert();
    } else {
      await _platformService.cannotComplyEmergencyAlert();
    }
  }

  Future<void> silenceEmergencyAlert() =>
      _platformService.silenceEmergencyAlert();
}
