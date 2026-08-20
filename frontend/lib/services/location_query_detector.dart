class LocationQueryDetector {
  const LocationQueryDetector._();

  static const _keywords = <String>[
    '주변',
    '근처',
    '가까운',
    '병원',
    '약국',
    '날씨',
    '등산',
    '맛집',
    '길찾기',
    '위치',
  ];

  static const _phrases = <String>['여기가 어디', '내가 어디', '현재 장소'];

  static bool isLocationRelated(String text) {
    final normalized = text.trim().toLowerCase();
    return _keywords.any(normalized.contains) ||
        _phrases.any(normalized.contains);
  }
}
