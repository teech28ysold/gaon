import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timedOut,
  unavailable,
}

class LocationCoordinates {
  const LocationCoordinates({
    required this.latitude,
    required this.longitude,
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final DateTime? timestamp;
}

class LocationResult {
  const LocationResult.success(
    LocationCoordinates coordinates, {
    bool usedCachedPosition = false,
  }) : this._(coordinates: coordinates, usedCachedPosition: usedCachedPosition);

  const LocationResult.failure(LocationFailure failure)
    : this._(failure: failure);

  const LocationResult._({
    this.coordinates,
    this.failure,
    this.usedCachedPosition = false,
  });

  final LocationCoordinates? coordinates;
  final LocationFailure? failure;
  final bool usedCachedPosition;

  bool get isSuccess => coordinates != null;

  String get userMessage {
    if (usedCachedPosition) {
      return 'GPS 연결이 늦어 최근 확인된 위치를 사용합니다.';
    }

    return switch (failure) {
      LocationFailure.serviceDisabled =>
        '휴대전화의 위치 서비스가 꺼져 있습니다. 위치를 켠 뒤 다시 시도해 주세요.',
      LocationFailure.permissionDenied => '가온이 현재 위치를 확인하려면 위치 권한이 필요합니다.',
      LocationFailure.permissionDeniedForever =>
        '위치 권한이 차단되어 있습니다. 앱 설정에서 위치 권한을 허용해 주세요.',
      LocationFailure.timedOut =>
        '현재 위치 확인이 지연되고 있습니다. 잠시 후 창가나 실외에서 다시 시도해 주세요.',
      LocationFailure.unavailable ||
      null => '현재 위치를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.',
    };
  }

  bool get shouldOpenLocationSettings =>
      failure == LocationFailure.serviceDisabled;

  bool get shouldOpenAppSettings =>
      failure == LocationFailure.permissionDenied ||
      failure == LocationFailure.permissionDeniedForever;
}

abstract interface class LocationGateway {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<LocationCoordinates> getCurrentPosition(Duration timeout);

  Future<LocationCoordinates?> getLastKnownPosition();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorLocationGateway implements LocationGateway {
  const GeolocatorLocationGateway();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<LocationCoordinates> getCurrentPosition(Duration timeout) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return _toCoordinates(position);
  }

  @override
  Future<LocationCoordinates?> getLastKnownPosition() async {
    final position = await Geolocator.getLastKnownPosition();
    return position == null ? null : _toCoordinates(position);
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  LocationCoordinates _toCoordinates(Position position) {
    return LocationCoordinates(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
    );
  }
}

class LocationService {
  LocationService({
    LocationGateway? gateway,
    this.currentPositionTimeout = const Duration(seconds: 12),
    this.maximumCachedPositionAge = const Duration(minutes: 15),
  }) : _gateway = gateway ?? const GeolocatorLocationGateway();

  final LocationGateway _gateway;
  final Duration currentPositionTimeout;
  final Duration maximumCachedPositionAge;

  Future<LocationResult> getCurrentLocation() async {
    try {
      if (!await _gateway.isLocationServiceEnabled()) {
        return const LocationResult.failure(LocationFailure.serviceDisabled);
      }

      var permission = await _gateway.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _gateway.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return const LocationResult.failure(LocationFailure.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failure(
          LocationFailure.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.unableToDetermine) {
        return const LocationResult.failure(LocationFailure.unavailable);
      }

      try {
        final coordinates = await _gateway.getCurrentPosition(
          currentPositionTimeout,
        );
        return LocationResult.success(coordinates);
      } on TimeoutException {
        return _cachedPositionOrFailure(LocationFailure.timedOut);
      } catch (_) {
        return _cachedPositionOrFailure(LocationFailure.unavailable);
      }
    } catch (_) {
      return const LocationResult.failure(LocationFailure.unavailable);
    }
  }

  Future<LocationResult> _cachedPositionOrFailure(
    LocationFailure failure,
  ) async {
    try {
      final cached = await _gateway.getLastKnownPosition();
      final timestamp = cached?.timestamp;
      final isRecent =
          timestamp != null &&
          DateTime.now().difference(timestamp).abs() <=
              maximumCachedPositionAge;

      if (cached != null && isRecent) {
        return LocationResult.success(cached, usedCachedPosition: true);
      }
    } catch (_) {
      // The original failure is more useful than a cache lookup error.
    }
    return LocationResult.failure(failure);
  }

  Future<bool> openSettings(LocationResult result) {
    if (result.shouldOpenLocationSettings) {
      return _gateway.openLocationSettings();
    }
    return _gateway.openAppSettings();
  }
}
