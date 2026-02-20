import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Child-facing mode display card with live countdown support.
class ModeDisplayCard extends StatefulWidget {
  const ModeDisplayCard({
    super.key,
    required this.modeName,
    required this.modeEmoji,
    required this.cardColor,
    this.activeUntil,
    this.progress = 0,
    this.subtitle,
  });

  /// Friendly mode label such as "Study Mode".
  final String modeName;

  /// Emoji shown next to mode name.
  final String modeEmoji;

  /// Optional mode end timestamp.
  final DateTime? activeUntil;

  /// Accent color for the card.
  final Color cardColor;

  /// Optional progress value between 0 and 1.
  final double progress;

  /// Optional helper subtitle shown under mode.
  final String? subtitle;

  @override
  State<ModeDisplayCard> createState() => _ModeDisplayCardState();
}

class _ModeDisplayCardState extends State<ModeDisplayCard> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _activeUntilLabel() {
    final activeUntil = widget.activeUntil;
    if (activeUntil == null) {
      return 'No end time set';
    }
    final formatter = DateFormat('h:mm a');
    if (!activeUntil.isAfter(_now)) {
      return 'Ending now';
    }
    return 'Active until ${formatter.format(activeUntil)}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.cardColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.cardColor.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.modeEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.modeName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _activeUntilLabel(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (progress > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: progress,
                backgroundColor: widget.cardColor.withValues(alpha: 0.20),
                valueColor: AlwaysStoppedAnimation<Color>(widget.cardColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
