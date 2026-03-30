import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants.dart';
import '../models/ws_message.dart';

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

/// Cliente WebSocket con reconexión exponencial y respuesta automática a ping.
class WsClient {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get connectionState => _state;

  final _messageController = StreamController<WsMessage>.broadcast();
  Stream<WsMessage> get messageStream => _messageController.stream;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  Stream<WsConnectionState> get stateStream => _stateController.stream;

  String? _eventId;
  String? _token;
  int _reconnectAttempt = 0;

  /// Conecta al WebSocket del evento.
  Future<void> connect(String eventId, String token) async {
    _eventId = eventId;
    _token = token;
    _reconnectAttempt = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_eventId == null || _token == null) return;
    _setState(WsConnectionState.connecting);

    // El token se envía en el primer mensaje tras conectar, no en la URL,
    // para evitar que quede expuesto en logs de servidor y proxies.
    final uri = Uri.parse(
      '${AppConstants.wsBaseUrl}/location/$_eventId',
    );

    try {
      await _subscription?.cancel();
      _subscription = null;

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      // Autenticar enviando el token en el primer frame
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': _token}));

      _setState(WsConnectionState.connected);
      _reconnectAttempt = 0;

      _subscription = _channel!.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final msg = WsMessage.fromJson(json);

      // Responder automáticamente a ping con pong
      if (msg.type == WsMessageType.ping) {
        _send({'type': 'pong'});
        return;
      }

      // Cerrar sesión si el token es inválido
      if (msg.type == WsMessageType.error) {
        _messageController.add(msg);
        return;
      }

      _messageController.add(msg);
    } catch (_) {
      // JSON inválido — ignorar
    }
  }

  void _scheduleReconnect() {
    if (_state == WsConnectionState.disconnected) return;
    _setState(WsConnectionState.reconnecting);
    _subscription?.cancel();

    // Cancelar timer anterior antes de crear uno nuevo
    _reconnectTimer?.cancel();

    // Backoff exponencial: min(2^N * 2, 60) segundos
    final delay = min(
      pow(2, _reconnectAttempt).toInt() * AppConstants.wsReconnectBase,
      AppConstants.wsReconnectMax,
    );
    _reconnectAttempt++;

    _reconnectTimer = Timer(Duration(seconds: delay), _doConnect);
  }

  /// Envía la ubicación GPS al servidor.
  void sendLocation(double lat, double lng, double? accuracy) {
    _send({
      'type': 'location',
      'latitude': lat,
      'longitude': lng,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  /// Envía una reacción rápida al grupo.
  void sendReaction(String reaction) {
    _send({'type': 'reaction', 'reaction': reaction});
  }

  /// Envía un mensaje de chat al grupo.
  void sendMessage(String text) {
    _send({'type': 'message', 'text': text});
  }

  void _send(Map<String, dynamic> data) {
    if (_state == WsConnectionState.connected && _channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  /// Cierra la conexión de forma limpia.
  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _eventId = null;
    _token = null;
    _setState(WsConnectionState.disconnected);
  }

  void _setState(WsConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}
