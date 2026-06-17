import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'gaon_card.dart';
import 'gaon_theme.dart';

class SeniorCategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;
  final int animationIndex;

  const SeniorCategoryCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
    this.animationIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child:
          GaonCard(
                onTap: onTap,
                backgroundColor: backgroundColor,
                borderColor: color.withAlpha(55),
                minHeight: 76,
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(210),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(icon, color: color, size: 36),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              maxLines: 1,
                              style: GaonTextStyles.title,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle!,
                              style: GaonTextStyles.body.copyWith(
                                fontSize: 18,
                                color: Colors.black.withAlpha(165),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: color.withAlpha(170),
                      size: 22,
                    ),
                  ],
                ),
              )
              .animate(delay: Duration(milliseconds: 55 * animationIndex))
              .fadeIn(duration: 260.ms)
              .slideY(begin: 0.08, end: 0, duration: 260.ms),
    );
  }
}
