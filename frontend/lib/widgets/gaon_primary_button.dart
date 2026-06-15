import 'package:flutter/material.dart';

import 'gaon_theme.dart';

class GaonPrimaryButton extends StatelessWidget {
  final Widget label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  const GaonPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.backgroundColor = GaonColors.deepTeal,
    this.foregroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: GaonColors.softLine,
      disabledForegroundColor: Colors.black45,
      elevation: 0,
      minimumSize: const Size.fromHeight(60),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GaonRadius.button),
      ),
      textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
    );

    if (icon == null) {
      return ElevatedButton(style: style, onPressed: onPressed, child: label);
    }

    return ElevatedButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      label: label,
    );
  }
}
