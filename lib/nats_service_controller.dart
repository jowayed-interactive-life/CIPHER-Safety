import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NatsServiceController {
  static const MethodChannel _channel = MethodChannel('nats_service_channel');
  static const String _batteryPromptedKey = 'nats_battery_opt_prompted';
  static const String _apiBaseUrl =
      'https://staging.api.cipher.interactivelife.me/api';
  static const String _projectHeaderValue = 'cipher';
  static const String _organizationIdHeaderValue = '698af675991550fcad337a3f';
  static const String _productIdHeaderValue =
      '40095093-5ee8-44eb-b92a-68cb5ae9d04c';

  static Future<void> start({
    String? accessToken,
    String? userId,
    String? organizationId,
    String? chatBusAuthUrl,
    String? serverUrl,
    String? env,
    String? primarySubject,
    String? mobileSubject,
  }) async {
    await _ensureNotificationPermission();
    await _ensureCameraPermission();
    await _ensureMicrophonePermission();
    await _ensureBatteryOptimizationExemption();

    final Map<String, String> args = <String, String>{};
    if (accessToken != null && accessToken.isNotEmpty) {
      args['accessToken'] = accessToken;
    }
    if (userId != null && userId.isNotEmpty) {
      args['userId'] = userId;
    }
    if (organizationId != null && organizationId.isNotEmpty) {
      args['organizationId'] = organizationId;
    }
    if (chatBusAuthUrl != null && chatBusAuthUrl.isNotEmpty) {
      args['chatBusAuthUrl'] = chatBusAuthUrl;
    }
    if (serverUrl != null && serverUrl.isNotEmpty) {
      args['serverUrl'] = serverUrl;
    }
    if (env != null && env.isNotEmpty) {
      args['env'] = env;
    }
    if (primarySubject != null && primarySubject.isNotEmpty) {
      args['primarySubject'] = primarySubject;
    }
    if (mobileSubject != null && mobileSubject.isNotEmpty) {
      args['mobileSubject'] = mobileSubject;
    }

    await _channel.invokeMethod<void>('startNatsService', args);
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stopNatsService');
  }

  static Future<void> debugShowEmergencyNotification({
    String subject = 'debug.subject',
    String payload = 'Debug emergency payload',
  }) async {
    await _channel.invokeMethod<void>(
      'debugShowEmergencyNotification',
      <String, String>{'subject': subject, 'payload': payload},
    );
  }

  static Future<void> confirmEmergencyAlert() async {
    await _channel.invokeMethod<void>('confirmEmergencyAlert');
  }

  static Future<void> cannotComplyEmergencyAlert() async {
    await _channel.invokeMethod<void>('cannotComplyEmergencyAlert');
  }

  static Future<void> silenceEmergencyAlert() async {
    await _channel.invokeMethod<void>('silenceEmergencyAlert');
  }

  static Future<void> syncStreamingConfig({
    required String cameraId,
    required String streamUrl,
  }) async {
    await _channel.invokeMethod<void>('syncStreamingConfig', <String, String>{
      'cameraId': cameraId,
      'streamUrl': streamUrl,
    });
  }

  static Future<void> clearStreamingConfig() async {
    await _channel.invokeMethod<void>('clearStreamingConfig');
  }

  static Future<void> postFloorplanComply({
    required String buildingId,
    required String floorId,
    required String roomName,
    required bool isComply,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? accessToken = _readAny(prefs, <String>[
      'accessToken',
      'access_token',
    ]);
    final Uri endpoint = Uri.parse('$_apiBaseUrl/floorplan/comply');
    final Map<String, dynamic> payload = <String, dynamic>{
      'buildingId': buildingId,
      'floorId': floorId,
      'roomName': roomName,
      'isComply': isComply,
    };

    if (kDebugMode) {
      debugPrint(
        'floorplan comply resolve | source=static | endpoint=$endpoint',
      );
      debugPrint('floorplan comply payload | payload=${jsonEncode(payload)}');
    }

    final HttpClient httpClient = HttpClient();
    try {
      final HttpClientRequest request = await httpClient.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('project', _projectHeaderValue);
      request.headers.set('organizationid', _organizationIdHeaderValue);
      request.headers.set('productid', _productIdHeaderValue);
      if (accessToken != null && accessToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      request.write(jsonEncode(payload));

      final HttpClientResponse response = await request.close();
      final String responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
            'floorplan comply error | endpoint=$endpoint | status=${response.statusCode} | response=${responseBody.isEmpty ? '<empty>' : responseBody}',
          );
        }
        throw HttpException(
          'POST /floorplan/comply failed (${response.statusCode}): ${responseBody.isEmpty ? 'empty body' : responseBody}',
          uri: endpoint,
        );
      }

      if (kDebugMode) {
        debugPrint(
          'floorplan comply sent | endpoint=$endpoint | isComply=$isComply | status=${response.statusCode}',
        );
        debugPrint(
          'floorplan comply response | endpoint=$endpoint | response=${responseBody.isEmpty ? '<empty>' : responseBody}',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'floorplan comply exception | endpoint=$endpoint | error=$error',
        );
      }
      rethrow;
    } finally {
      httpClient.close(force: true);
    }
  }

  static Future<FloorplanSearchResult> searchFloorplanRoomName({
    required String buildingName,
    required String floorName,
    required String roomName,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? accessToken = _readAny(prefs, <String>[
      'accessToken',
      'access_token',
    ]);
    final Uri endpoint = Uri.parse('$_apiBaseUrl/floorplan/search/roomname');
    final Map<String, dynamic> payload = <String, dynamic>{
      'buildingName': buildingName,
      'floorName': floorName,
      'roomName': roomName,
    };

    if (kDebugMode) {
      debugPrint(
        'floorplan search resolve | source=static | endpoint=$endpoint',
      );
      debugPrint('floorplan search payload | payload=${jsonEncode(payload)}');
    }

    final HttpClient httpClient = HttpClient();
    try {
      final HttpClientRequest request = await httpClient.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('project', _projectHeaderValue);
      request.headers.set('organizationid', _organizationIdHeaderValue);
      request.headers.set('productid', _productIdHeaderValue);
      if (accessToken != null && accessToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      request.write(jsonEncode(payload));

      final HttpClientResponse response = await request.close();
      final String responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
            'floorplan search error | endpoint=$endpoint | status=${response.statusCode} | response=${responseBody.isEmpty ? '<empty>' : responseBody}',
          );
        }
        throw HttpException(
          'POST /floorplan/search/roomname failed (${response.statusCode}): ${responseBody.isEmpty ? 'empty body' : responseBody}',
          uri: endpoint,
        );
      }

      if (kDebugMode) {
        debugPrint(
          'floorplan search response | endpoint=$endpoint | response=${responseBody.isEmpty ? '<empty>' : responseBody}',
        );
      }

      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid search response shape');
      }
      final Map<String, dynamic> decodedMap = decoded;
      final dynamic statusValue = decodedMap['status'];
      if (statusValue == false) {
        throw HttpException(
          'POST /floorplan/search/roomname reported failure: ${responseBody.isEmpty ? 'empty body' : responseBody}',
          uri: endpoint,
        );
      }
      final dynamic results = decodedMap['results'];
      final Map<String, dynamic> responsePayload =
          results is Map<String, dynamic>
          ? results
          : results is Map
          ? Map<String, dynamic>.from(results)
          : decodedMap;
      final String resolvedRoomName =
          (responsePayload['roomName'] as String?)?.trim() ??
          (responsePayload['name'] as String?)?.trim() ??
          '';
      final String resolvedBuildingId = _extractId(
        responsePayload['buildingId'],
      );
      final String resolvedFloorId = _extractId(responsePayload['floorId']);
      final String? resolvedBuildingName = _extractOptionalName(
        responsePayload['buildingId'],
      );

      if (resolvedRoomName.isEmpty ||
          resolvedBuildingId.isEmpty ||
          resolvedFloorId.isEmpty) {
        throw const FormatException('Incomplete search response');
      }

      return FloorplanSearchResult(
        roomName: resolvedRoomName,
        buildingId: resolvedBuildingId,
        floorId: resolvedFloorId,
        buildingName: resolvedBuildingName,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'floorplan search exception | endpoint=$endpoint | error=$error',
        );
      }
      rethrow;
    } finally {
      httpClient.close(force: true);
    }
  }

  static Future<String> getCameraStreamUrl({required String cameraId}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? accessToken = _readAny(prefs, <String>[
      'accessToken',
      'access_token',
    ]);
    final Uri endpoint = Uri.parse('$_apiBaseUrl/camera/get/stream');
    final Map<String, dynamic> payload = <String, dynamic>{'id': cameraId};

    if (kDebugMode) {
      debugPrint('camera stream resolve | source=static | endpoint=$endpoint');
      debugPrint('camera stream payload | payload=${jsonEncode(payload)}');
    }

    final HttpClient httpClient = HttpClient();
    try {
      final HttpClientRequest request = await httpClient.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('project', _projectHeaderValue);
      request.headers.set('organizationid', _organizationIdHeaderValue);
      request.headers.set('productid', _productIdHeaderValue);
      if (accessToken != null && accessToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      request.write(jsonEncode(payload));

      final HttpClientResponse response = await request.close();
      final String responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'POST /camera/get/stream failed (${response.statusCode}): ${responseBody.isEmpty ? 'empty body' : responseBody}',
          uri: endpoint,
        );
      }

      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid camera stream response shape');
      }
      final dynamic statusValue = decoded['status'];
      if (statusValue == false) {
        throw HttpException(
          'POST /camera/get/stream reported failure: ${responseBody.isEmpty ? 'empty body' : responseBody}',
          uri: endpoint,
        );
      }

      final dynamic results = decoded['results'];
      final Map<String, dynamic> responsePayload =
          results is Map<String, dynamic>
          ? results
          : results is Map
          ? Map<String, dynamic>.from(results)
          : decoded;
      final String streamUrl =
          (responsePayload['stream_url'] as String?)?.trim() ?? '';
      if (streamUrl.isEmpty) {
        throw const FormatException('Camera stream URL is missing');
      }

      if (kDebugMode) {
        debugPrint('camera stream response | streamUrl=$streamUrl');
      }
      return streamUrl;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'camera stream exception | endpoint=$endpoint | error=$error',
        );
      }
      rethrow;
    } finally {
      httpClient.close(force: true);
    }
  }

  static Future<void> setAppInForeground(bool isForeground) async {
    await _channel.invokeMethod<void>('setAppInForeground', <String, bool>{
      'isForeground': isForeground,
    });
  }

  static Future<PendingEmergencyAlert?> consumePendingEmergencyAlert() async {
    final dynamic result = await _channel.invokeMethod<dynamic>(
      'consumePendingEmergencyAlert',
    );
    if (result is! Map) return null;

    final String? subject = result['subject']?.toString();
    final String? payload = result['payload']?.toString();
    if (subject == null ||
        subject.isEmpty ||
        payload == null ||
        payload.isEmpty) {
      return null;
    }

    final int receivedAtMillis = switch (result['receivedAt']) {
      final int value => value,
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    };

    return PendingEmergencyAlert(
      subject: subject,
      payload: payload,
      receivedAt: receivedAtMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(receivedAtMillis)
          : DateTime.now(),
    );
  }

  static Future<void> syncWithSession() async {
    await syncWithSessionOrFallback();
  }

  static Future<void> syncWithSessionOrFallback({
    String? fallbackServerUrl,
    String? fallbackEnv,
    String? fallbackPrimarySubject,
    String? fallbackMobileSubject,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final String? accessToken = _readAny(prefs, <String>[
        'accessToken',
        'access_token',
      ]);
      final String? userId = _readAny(prefs, <String>['userId', 'user_id']);
      final String? organizationId = _readAny(prefs, <String>[
        'organizationId',
        'organization_id',
      ]);
      final String? chatBusAuthUrl = _readAny(prefs, <String>[
        'chatBusAuthUrl',
        'chat_bus_auth_url',
      ]);

      final bool hasValidSession =
          accessToken != null &&
          accessToken.isNotEmpty &&
          userId != null &&
          userId.isNotEmpty &&
          organizationId != null &&
          organizationId.isNotEmpty;

      if (!hasValidSession) {
        if (fallbackServerUrl != null &&
            fallbackServerUrl.isNotEmpty &&
            fallbackPrimarySubject != null &&
            fallbackPrimarySubject.isNotEmpty) {
          await start(
            serverUrl: fallbackServerUrl,
            env: fallbackEnv,
            primarySubject: fallbackPrimarySubject,
            mobileSubject: fallbackMobileSubject,
          );
          return;
        }

        await stop();
        return;
      }

      await start(
        accessToken: accessToken,
        userId: userId,
        organizationId: organizationId,
        chatBusAuthUrl: chatBusAuthUrl,
        serverUrl: fallbackServerUrl,
        env: fallbackEnv,
        primarySubject: fallbackPrimarySubject,
        mobileSubject: fallbackMobileSubject,
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('NatsServiceController sync failed');
      }
    }
  }

  static Future<void> _ensureNotificationPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final PermissionStatus status = await Permission.notification.status;
    if (status.isGranted) return;
    await Permission.notification.request();
  }

  static Future<void> _ensureCameraPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final PermissionStatus status = await Permission.camera.status;
    if (status.isGranted) return;
    await Permission.camera.request();
  }

  static Future<void> _ensureMicrophonePermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final PermissionStatus status = await Permission.microphone.status;
    if (status.isGranted) return;
    await Permission.microphone.request();
  }

  static Future<void> _ensureBatteryOptimizationExemption() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool promptedBefore = prefs.getBool(_batteryPromptedKey) ?? false;

      final bool ignoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
      if (!ignoring && !promptedBefore) {
        await prefs.setBool(_batteryPromptedKey, true);
        await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('NatsServiceController battery optimization request failed');
      }
    }
  }

  static String? _readAny(SharedPreferences prefs, List<String> keys) {
    for (final String key in keys) {
      final String? value = prefs.getString(key);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String _extractId(dynamic value) {
    if (value is String) return value.trim();
    if (value is Map<String, dynamic>) {
      return (value['_id'] as String?)?.trim() ?? '';
    }
    if (value is Map) {
      return (value['_id'] as String?)?.trim() ?? '';
    }
    return '';
  }

  static String? _extractOptionalName(dynamic value) {
    if (value is Map<String, dynamic>) {
      final String? name = value['name'] as String?;
      return name?.trim().isEmpty == true ? null : name?.trim();
    }
    if (value is Map) {
      final String? name = value['name'] as String?;
      return name?.trim().isEmpty == true ? null : name?.trim();
    }
    return null;
  }
}

class FloorplanSearchResult {
  const FloorplanSearchResult({
    required this.roomName,
    required this.buildingId,
    required this.floorId,
    this.buildingName,
  });

  final String roomName;
  final String buildingId;
  final String floorId;
  final String? buildingName;
}

class PendingEmergencyAlert {
  const PendingEmergencyAlert({
    required this.subject,
    required this.payload,
    required this.receivedAt,
  });

  final String subject;
  final String payload;
  final DateTime receivedAt;
}
