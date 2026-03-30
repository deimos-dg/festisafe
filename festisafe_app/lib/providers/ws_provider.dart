import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/ws_client.dart';
import '../data/models/ws_message.dart';

class WsNotifier extends StateNotifier<WsConnectionState> {
  final WsClient _client;

  WsNotifier(this._client) : super(WsConnectionState.disconnected) {
    _client.stateStream.listen((s) => state = s);
  }

  Future<void> connect(String eventId, String token) async {
    await _client.connect(eventId, token);
  }

  void disconnect() => _client.disconnect();

  void sendLocation(double lat, double lng, double? accuracy) =>
      _client.sendLocation(lat, lng, accuracy);

  void sendReaction(String reaction) => _client.sendReaction(reaction);

  void sendMessage(String text) => _client.sendMessage(text);

  Stream<WsMessage> get messageStream => _client.messageStream;

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }
}

final wsClientProvider = Provider<WsClient>((ref) {
  final client = WsClient();
  ref.onDispose(client.dispose);
  return client;
});

final wsProvider = StateNotifierProvider<WsNotifier, WsConnectionState>(
  (ref) => WsNotifier(ref.watch(wsClientProvider)),
);
