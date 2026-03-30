import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/ws_provider.dart';

/// Reacciones rápidas predefinidas.
const _reactions = [
  ('✓', 'Estoy bien'),
  ('🎵', 'Voy al escenario'),
  ('⏳', 'Espérenme'),
  ('📍', 'Estoy en la entrada'),
  ('💧', 'Necesito agua'),
];

/// Panel de reacciones rápidas del grupo.
class ReactionPanel extends ConsumerWidget {
  const ReactionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _reactions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (emoji, label) = _reactions[i];
          return ActionChip(
            avatar: Text(emoji, style: const TextStyle(fontSize: 16)),
            label: Text(label, style: const TextStyle(fontSize: 12)),
            onPressed: () {
              ref.read(wsProvider.notifier).sendReaction('$emoji $label');
            },
          );
        },
      ),
    );
  }
}

/// Banner temporal que muestra la reacción recibida de un compañero.
class ReactionBanner extends StatefulWidget {
  final String senderName;
  final String reaction;
  final VoidCallback onDismiss;

  const ReactionBanner({
    super.key,
    required this.senderName,
    required this.reaction,
    required this.onDismiss,
  });

  @override
  State<ReactionBanner> createState() => _ReactionBannerState();
}

class _ReactionBannerState extends State<ReactionBanner> {
  @override
  void initState() {
    super.initState();
    // Auto-dismiss después de 3 segundos
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.reaction,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${widget.senderName}: ${widget.reaction}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
