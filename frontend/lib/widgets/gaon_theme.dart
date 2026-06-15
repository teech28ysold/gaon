import 'package:flutter/material.dart';

class GaonColors {
  static const deepTeal = Color(0xFF0F5F5C);
  static const brightTeal = Color(0xFF2BB8A8);
  static const warmIvory = Color(0xFFFFFAF0);
  static const ink = Color(0xFF1E272E);
  static const softLine = Color(0xFFE5E0D3);
}

class GaonRadius {
  static const card = 22.0;
  static const button = 22.0;
}

class GaonTextStyles {
  static const title = TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w800,
    color: GaonColors.ink,
    height: 1.25,
  );

  static const body = TextStyle(
    fontSize: 19,
    color: GaonColors.ink,
    height: 1.45,
  );

  static const major = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    color: GaonColors.ink,
    height: 1.4,
  );
}
