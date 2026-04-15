class TabletCameraLookupResult {
  const TabletCameraLookupResult({
    required this.buildingId,
    required this.floorId,
    required this.buildingName,
    required this.roomName,
    required this.cameraId,
    required this.streamUrl,
  });

  final String buildingId;
  final String floorId;
  final String buildingName;
  final String roomName;
  final String cameraId;
  final String streamUrl;
}
