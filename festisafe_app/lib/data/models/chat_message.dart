/// Mensaje de chat del grupo (no persistido entre sesiones).
class ChatMessage {
  final String userId;
  final String name;
  final String text;
  final DateTime timestamp;

  const ChatMessage({
    required this.userId,
    required this.name,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromWsMessage(Map<String, dynamic> payload) {
    final userId = payload['user_id'] as String?;
    final name = payload['name'] as String?;
    final text = payload['text'] as String?;
    if (userId == null || userId.isEmpty) {
      throw ArgumentError('Campo user_id faltante en payload WS chat');
    }
    return ChatMessage(
      userId: userId,
      name: name ?? 'Desconocido',
      text: text ?? '',
      timestamp: DateTime.now(),
    );
  }
}
