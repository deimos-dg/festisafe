import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/chat_message.dart';

/// Mensajes de chat del grupo en memoria (no persistidos entre sesiones).
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier() : super([]);

  void addMessage(ChatMessage msg) {
    // Mantener orden de recepción (Propiedad 18)
    // Limitar a 500 mensajes para evitar consumo ilimitado de memoria
    final updated = [...state, msg];
    state = updated.length > 500 ? updated.sublist(updated.length - 500) : updated;
  }

  void clear() => state = [];
}

final chatProvider = StateNotifierProvider<ChatNotifier, List<ChatMessage>>(
  (ref) => ChatNotifier(),
);
