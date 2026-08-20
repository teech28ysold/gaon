import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaon_frontend/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('LocationService', () {
    test('returns a current position when permission is granted', () async {
      final gateway = FakeLocationGateway(
        currentPosition: const LocationCoordinates(
          latitude: 37.5665,
          longitude: 126.9780,
        ),
      );
      final service = LocationService(gateway: gateway);

      final result = await service.getCurrentLocation();

      expect(result.isSuccess, isTrue);
      expect(result.coordinates?.latitude, 37.5665);
      expect(result.usedCachedPosition, isFalse);
      expect(gateway.requestPermissionCallCount, 0);
    });

    test('requests permission once when it was denied', () async {
      final gateway = FakeLocationGateway(
        permission: LocationPermission.denied,
        requestedPermission: LocationPermission.whileInUse,
        currentPosition: const LocationCoordinates(
          latitude: 35.1796,
          longitude: 129.0756,
        ),
      );

      final result = await LocationService(
        gateway: gateway,
      ).getCurrentLocation();

      expect(result.isSuccess, isTrue);
      expect(gateway.requestPermissionCallCount, 1);
    });

    test('distinguishes disabled services from permission failures', () async {
      final result = await LocationService(
        gateway: FakeLocationGateway(serviceEnabled: false),
      ).getCurrentLocation();

      expect(result.failure, LocationFailure.serviceDisabled);
      expect(result.shouldOpenLocationSettings, isTrue);
      expect(result.userMessage, contains('위치 서비스가 꺼져'));
    });

    test('returns a recent cached position after a timeout', () async {
      final gateway = FakeLocationGateway(
        currentError: TimeoutException('gps timeout'),
        lastKnownPosition: LocationCoordinates(
          latitude: 37.5,
          longitude: 127.0,
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      );

      final result = await LocationService(
        gateway: gateway,
      ).getCurrentLocation();

      expect(result.isSuccess, isTrue);
      expect(result.usedCachedPosition, isTrue);
    });

    test('does not use a stale cached position', () async {
      final gateway = FakeLocationGateway(
        currentError: TimeoutException('gps timeout'),
        lastKnownPosition: LocationCoordinates(
          latitude: 37.5,
          longitude: 127.0,
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );

      final result = await LocationService(
        gateway: gateway,
      ).getCurrentLocation();

      expect(result.isSuccess, isFalse);
      expect(result.failure, LocationFailure.timedOut);
    });
  });
}

class FakeLocationGateway implements LocationGateway {
  FakeLocationGateway({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.requestedPermission = LocationPermission.whileInUse,
    this.currentPosition,
    this.lastKnownPosition,
    this.currentError,
  });

  final bool serviceEnabled;
  final LocationPermission permission;
  final LocationPermission requestedPermission;
  final LocationCoordinates? currentPosition;
  final LocationCoordinates? lastKnownPosition;
  final Object? currentError;
  int requestPermissionCallCount = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationCoordinates> getCurrentPosition(Duration timeout) async {
    if (currentError case final error?) throw error;
    return currentPosition ??
        const LocationCoordinates(latitude: 37.0, longitude: 127.0);
  }

  @override
  Future<LocationCoordinates?> getLastKnownPosition() async =>
      lastKnownPosition;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCallCount += 1;
    return requestedPermission;
  }
}
