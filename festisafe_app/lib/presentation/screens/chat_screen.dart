import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ws_provider.dart';
import '../../core/constants.dart';
import '../widgets/reaction_panel.dart';
import '../../data/models/chat_message.dart';

/// Chat del grupo reutilizable como pantalla completa o widget embebido.
///
/// - [embedded] = false → pantalla completa con AppBar (desde el mapa)
/// - [embedded] = true  → widget sin Scaffold (desde GroupScreen)
class ChatScreen extends ConsumerStatefulWidget {
  final String eventId;
  final bool embedded;

  const ChatScreen({
    super.key,
    required this.eventId,
    this.embedded = false,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || text.length > AppConstants.chatMaxLength) return;
    ref.read(wsProvider.notifier).sendMessage(text);
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _ChatBody(
      controller: _controller,
      scrollController: _scrollController,
      onSend: _sendMessage,
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat del grupo')),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Cuerpo compartido — usado tanto en pantalla completa como embebido
// ---------------------------------------------------------------------------
class _ChatBody extends ConsumerWidget {
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;

  const _ChatBody({
    required this.controller,
    required this.scrollController,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatProvider);
    final authState = ref.watch(authProvider);
    final myId = authState is AuthAuthenticated
        ? authState.user.id
        : (authState is AuthGuest ? authState.user.id : null);

    return Column(
      children: [
        const ReactionPanel(),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text('Sin mensajes aún',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => ChatBubble(
                    msg: messages[i],
                    isMe: messages[i].userId == myId,
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
              top: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: AppConstants.chatMaxLength,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      counterText: '',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Burbuja de chat — exportada para uso en GroupScreen
// ---------------------------------------------------------------------------
class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;

  const ChatBubble({super.key, required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                msg.name,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              msg.text,
              style: TextStyle(
                color: isMe
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
