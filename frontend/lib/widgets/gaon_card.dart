import 'package:flutter/material.dart';

import 'gaon_theme.dart';

class GaonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double minHeight;

  const GaonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.backgroundColor = Colors.white,
    this.borderColor,
    this.onTap,
    this.minHeight = 60,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(GaonRadius.card);
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Ink(
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: radius,
          border: Border.all(color: borderColor ?? GaonColors.softLine),
          boxShadow: [
            BoxShadow(
              color: GaonColors.deepTeal.withAlpha(14),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }
}
