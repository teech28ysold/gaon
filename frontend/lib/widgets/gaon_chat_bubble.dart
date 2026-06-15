import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'gaon_theme.dart';

class GaonChatBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final String formattedTime;
  final Widget? footer;

  const GaonChatBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.formattedTime,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFFFFF3D6) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isUser ? 24 : 6),
          topRight: Radius.circular(isUser ? 6 : 24),
          bottomLeft: const Radius.circular(24),
          bottomRight: const Radius.circular(24),
        ),
        border: Border.all(
          color: isUser
              ? const Color(0xFFECDDAF)
              : GaonColors.brightTeal.withAlpha(45),
        ),
        boxShadow: [
          BoxShadow(
            color: GaonColors.deepTeal.withAlpha(13),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SelectableText(
        message,
        style: GaonTextStyles.major.copyWith(
          color: isUser ? const Color(0xFF2A2418) : const Color(0xFF111827),
        ),
      ),
    );

    if (isUser) {
      return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formattedTime,
                  style: const TextStyle(fontSize: 18, color: Colors.black45),
                ),
                const SizedBox(width: 8),
                Flexible(child: bubble),
              ],
            ),
          )
          .animate()
          .fadeIn(duration: 260.ms)
          .slideY(begin: 0.06, end: 0, duration: 260.ms);
    }

    return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                backgroundColor: GaonColors.deepTeal,
                radius: 25,
                child: Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '가온 비서',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    bubble,
                    if (footer != null) ...[const SizedBox(height: 8), footer!],
                  ],
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 260.ms)
        .slideY(begin: 0.06, end: 0, duration: 260.ms);
  }
}
