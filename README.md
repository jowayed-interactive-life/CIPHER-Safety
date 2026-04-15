# CIPHER Safety

`CIPHER Safety` is a Flutter app with an Android native foreground-service layer for realtime alert handling, panic streaming, and background resilience.

This README explains:

- what runs in Flutter
- what runs in Android native code
- why both layers exist
- how NATS is used
- how Flutter and Android communicate

## High-Level Architecture

The app is intentionally split across two runtime layers:

- Flutter:
  Owns the app UI, app-level state, alert parsing, listener setup flow, and some API calls used while the app is in the foreground.
- Android native:
  Owns the foreground service, persistent background realtime handling, notification delivery, RTMP camera streaming, and the camera on/off update API tied to actual native streaming state.

This is not accidental duplication. Each layer is responsible for the things it can do most reliably.

## Current Flutter Structure

The Dart code is organized in a high-level layered architecture:

- `lib/app`
  App shell and root widget.
- `lib/core`
  Shared configuration and formatting utilities.
- `lib/data`
  Models, services, and repositories.
- `lib/domain`
  Alert parsing and domain models.
- `lib/presentation`
  Pages and view models.

Important files:

- [lib/main.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/main.dart)
  App bootstrap.
- [lib/app/app.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/app/app.dart)
  Root `MaterialApp`.
- [lib/presentation/subject_entry/subject_entry_page.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/presentation/subject_entry/subject_entry_page.dart)
  Entry screen for building/device lookup.
- [lib/presentation/listener/listener_page.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/presentation/listener/listener_page.dart)
  Main realtime listener screen.
- [lib/presentation/listener/listener_view_model.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/presentation/listener/listener_view_model.dart)
  Foreground NATS subscription logic and UI-facing state.
- [lib/data/services/nats_platform_service.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/data/services/nats_platform_service.dart)
  Flutter-to-Android method-channel bridge plus Dart-side API calls.
- [lib/data/repositories/listener_repository.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/data/repositories/listener_repository.dart)
  App-facing orchestration layer between UI and platform/data code.

## What Flutter Owns

Flutter is responsible for:

- rendering the UI
- handling the subject entry / device selection flow
- loading and saving listener config
- resolving camera/tablet configuration from the backend
- opening a foreground Dart NATS connection for the active listener screen
- parsing incoming alert payloads for display
- sending high-level commands to Android through the method channel

### Flutter NATS Usage

Flutter directly uses a Dart NATS client package here:

- [lib/presentation/listener/listener_view_model.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/presentation/listener/listener_view_model.dart:112)
  Creates the Dart NATS client, connects, and subscribes.
- [lib/domain/models/received_alert.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/domain/models/received_alert.dart:1)
  Stores normalized subject/payload alert data for the app.

The foreground screen subscribes to:

- the room/primary subject
- the mobile subject
- the building subject

This Flutter connection is useful while the app screen is open and active.

## What Android Native Owns

Android native code is responsible for:

- starting and keeping a foreground service alive
- listening in the background even when Flutter is paused or not visible
- showing realtime emergency notifications
- saving pending emergency alerts for the Flutter UI to recover later
- starting and stopping RTMP camera streaming
- handling panic/confirm/cannot-comply/silence intents
- updating backend camera state based on actual native stream state
- surviving task removal and service restarts more reliably than Flutter alone

Important Android files:

- [android/app/src/main/kotlin/com/example/cipher_safety/MainActivity.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/MainActivity.kt)
  Flutter method-channel entry point.
- [android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsForegroundService.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsForegroundService.kt)
  Native foreground service for alerts, streaming, and state updates.
- [android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsNotificationsManager.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsNotificationsManager.kt)
  Native NATS-driven alert/notification manager.

### Why Android Native Was Added

Android native code was added because Flutter alone is not a reliable owner for these behaviors on Android:

- persistent foreground service lifecycle
- background realtime listening
- native notification channels and urgent notification handling
- RTMP camera streaming tied to native camera APIs
- stream start/stop behavior when the Flutter UI is not running
- camera state updates that must reflect the actual native streaming state

In short:

- Flutter knows what the user configured.
- Android knows what the device is actually doing.

That distinction matters for background alerts and streaming.

## Why We Use Both Flutter and Android

We use both because they solve different problems well.

### Flutter is good for

- screen UI
- app navigation
- alert rendering
- view models and app state
- user-driven API lookups
- fast iteration on app behavior

### Android native is good for

- foreground services
- background execution
- device-level notification behavior
- camera and RTMP lifecycle
- accurate stream-state ownership
- resilience when the app is backgrounded, closed, or restarted

If this app were Flutter-only, we would likely lose reliability for:

- background NATS listening
- panic streaming outside the active Flutter screen
- true source-of-truth camera on/off reporting
- service restart behavior after task removal or process death

## How Flutter and Android Are Linked

Flutter and Android communicate through a `MethodChannel`.

Channel definition:

- [lib/data/services/nats_platform_service.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/data/services/nats_platform_service.dart:13)
  `MethodChannel('nats_service_channel')`

Android method handler:

- [MainActivity.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/MainActivity.kt:48)

### Methods Flutter Calls Into Android

Flutter uses the method channel to call Android methods such as:

- `startNatsService`
- `stopNatsService`
- `syncStreamingConfig`
- `clearStreamingConfig`
- `startManualStreaming`
- `confirmEmergencyAlert`
- `cannotComplyEmergencyAlert`
- `silenceEmergencyAlert`
- `setAppInForeground`
- `consumePendingEmergencyAlert`

These are defined on the Flutter side in:

- [lib/data/services/nats_platform_service.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/data/services/nats_platform_service.dart)

And received on Android in:

- [MainActivity.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/MainActivity.kt:52)

## NATS Responsibilities by Layer

There are two NATS-related paths in the app.

### 1. Flutter foreground listener

Used when the app screen is active.

- Connects with the Dart NATS client
- Subscribes to subjects
- Parses payloads
- Updates the UI immediately

Main file:

- [listener_view_model.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/presentation/listener/listener_view_model.dart)

### 2. Android background listener/service path

Used for persistent background behavior.

- Starts the native foreground service
- Handles incoming alert behavior while the app is backgrounded
- Triggers notifications and streaming actions
- Saves pending alerts for Flutter to recover later

Main file:

- [NatsForegroundService.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsForegroundService.kt:150)

## Camera / Streaming Flow

### Config lookup

Flutter calls the backend to resolve a tablet/camera configuration:

- [lib/data/services/nats_platform_service.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/data/services/nats_platform_service.dart:156)
  `POST /floorplan/tablet/camera/get`

That returns values like:

- `buildingId`
- `floorId`
- `cameraId`
- `streamUrl`

### Config handoff to Android

Flutter then sends the selected config to Android:

- [lib/data/services/nats_platform_service.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/data/services/nats_platform_service.dart:90)
  `syncStreamingConfig(...)`

Android saves that config here:

- [MainActivity.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/MainActivity.kt:130)
- [MainActivity.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/MainActivity.kt:191)

### Actual stream start/stop

Android starts and stops RTMP streaming here:

- [NatsForegroundService.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsForegroundService.kt:426)
  `startConfiguredRtmpStream(...)`
- [NatsForegroundService.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsForegroundService.kt:482)
  `stopConfiguredRtmpStream(...)`

This is native because the real stream lifecycle is owned by Android.

### Camera state update API

The backend camera on/off update happens in Android native code:

- [NatsForegroundService.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsForegroundService.kt:527)
  `postCameraStreamingStateUpdate(isCameraOn, reason)`

Endpoint:

- `POST /floorplan/tablet/camera/update`

This stays native on purpose because:

- Android knows when the stream really started
- Android knows when the stream really stopped
- Flutter may be paused, backgrounded, or killed when native streaming still runs

If this API lived only in Flutter, it would be based on intent rather than actual stream state.

## Alert Action Flow

When a user responds to an alert in Flutter:

- Flutter calls `confirmEmergencyAlert` or `cannotComplyEmergencyAlert` over the method channel
- Android receives the action in `MainActivity`
- Android forwards the action to the foreground service
- The foreground service stops/starts effects and streaming as needed

Relevant files:

- [lib/data/services/nats_platform_service.dart](/Users/johnnyowayed/Documents/cipher_safety/lib/data/services/nats_platform_service.dart:74)
- [MainActivity.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/MainActivity.kt:98)
- [NatsForegroundService.kt](/Users/johnnyowayed/Documents/cipher_safety/android/app/src/main/kotlin/com/example/cipher_safety/nats/NatsForegroundService.kt:100)

## Dart NATS Package

The Flutter app uses the hosted `dart_nats` package:

- [pubspec.yaml](/Users/johnnyowayed/Documents/cipher_safety/pubspec.yaml:37)
  `dart_nats: ^0.6.5`

This is only the Dart-side client. It does not replace the Android foreground-service code.

## Summary

The app uses both Flutter and Android native code because the problem space is split:

- Flutter owns UI, config flow, alert presentation, and foreground app logic.
- Android owns the durable background service, native notifications, RTMP streaming, and true device-state updates.

That split is what makes the app practical and reliable on Android.
