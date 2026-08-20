import 'package:flutter_test/flutter_test.dart';
import 'package:gaon_frontend/services/location_query_detector.dart';

void main() {
  test('detects queries that need the current location', () {
    expect(LocationQueryDetector.isLocationRelated('가까운 약국 알려줘'), isTrue);
    expect(LocationQueryDetector.isLocationRelated('오늘 날씨 어때?'), isTrue);
    expect(LocationQueryDetector.isLocationRelated('여기가 어디야?'), isTrue);
  });

  test('ignores questions unrelated to location', () {
    expect(LocationQueryDetector.isLocationRelated('물 마실 시간 알려줘'), isFalse);
    expect(LocationQueryDetector.isLocationRelated('어디가 아픈지 설명할게'), isFalse);
  });
}
