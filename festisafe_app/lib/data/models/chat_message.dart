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
    return ChatMessage(
      userId: payload['user_id'] as String,
      name: payload['name'] as String,
      text: payload['text'] as String,
      timestamp: DateTime.now(),
    );
  }
}
