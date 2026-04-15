import 'dart:convert';
import 'dart:typed_data';

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

  String get displayBody =>
      instructions?.trim().isNotEmpty == true ? instructions! : rawPayload;

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
