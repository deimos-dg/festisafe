/// Tipos de mensaje WebSocket soportados.
enum WsMessageType {
  connected,
  location,
  sos,
  sosCancelled,
  sosEscalated,
  ping,
  reaction,
  message,
  error,
  groupJoinRequest,
  groupJoinAccepted,
  groupJoinRejected,
  unknown,
}

/// Mensaje recibido o enviado por el canal WebSocket.
class WsMessage {
  final WsMessageType type;
  final Map<String, dynamic> payload;

  const WsMessage({required this.type, required this.payload});

  factory WsMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? '';
    final type = _parseType(typeStr);
    return WsMessage(type: type, payload: json);
  }

  static WsMessageType _parseType(String raw) {
    switch (raw) {
      case 'connected':
        return WsMessageType.connected;
      case 'location':
        return WsMessageType.location;
      case 'sos':
        return WsMessageType.sos;
      case 'sos_cancelled':
        return WsMessageType.sosCancelled;
      case 'sos_escalated':
        return WsMessageType.sosEscalated;
      case 'ping':
        return WsMessageType.ping;
      case 'reaction':
        return WsMessageType.reaction;
      case 'message':
        return WsMessageType.message;
      case 'error':
        return WsMessageType.error;
      case 'group_join_request':
        return WsMessageType.groupJoinRequest;
      case 'group_join_accepted':
        return WsMessageType.groupJoinAccepted;
      case 'group_join_rejected':
        return WsMessageType.groupJoinRejected;
      default:
        return WsMessageType.unknown;
    }
  }
}
