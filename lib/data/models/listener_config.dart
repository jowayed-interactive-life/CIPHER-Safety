import 'package:cipher_safety/core/config/nats_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ListenerConfig {
  const ListenerConfig({
    required this.buildingId,
    required this.floorId,
    required this.buildingName,
    required this.displayDeviceId,
    required this.resolvedBuildingName,
    required this.roomName,
    required this.cameraId,
    required this.streamUrl,
  });

  final String buildingId;
  final String floorId;
  final String buildingName;
  final String displayDeviceId;
  final String resolvedBuildingName;
  final String roomName;
  final String cameraId;
  final String streamUrl;

  String get sanitizedSubjectTarget =>
      roomName.trim().replaceAll(' ', '_');

  String get subject =>
      '${NatsConfig.env}.${NatsConfig.organizationId}.indoor-alerts-$buildingId-$floorId-$sanitizedSubjectTarget';

  String get mobileSubject => '$subject.mobile';

  String get buildingSubject =>
      '${NatsConfig.env}.${NatsConfig.organizationId}.indoor-alerts-$buildingId';

  static const String _buildingIdKey = 'listener_building_id';
  static const String _floorIdKey = 'listener_floor_id';
  static const String _buildingNameKey = 'listener_building_name';
  static const String _displayDeviceIdKey = 'listener_display_device_id';
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
    await prefs.remove(_resolvedBuildingNameKey);
    await prefs.remove(_roomNameKey);
    await prefs.remove(_cameraIdKey);
    await prefs.remove(_streamUrlKey);
  }
}
