import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ws_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../data/services/ws_client.dart';
import '../../providers/location_provider.dart';
import '../../providers/sos_provider.dart';
import '../../providers/chat_provider.dart';
import '../../data/models/ws_message.dart';
import '../../data/models/member_location.dart';
import '../../data/models/sos_alert.dart';
import '../../data/models/chat_message.dart';
import '../../data/services/location_service.dart';
import '../../data/services/sos_service.dart';
import '../../data/services/offline_cache_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/storage/secure_storage.dart';
import '../../core/constants.dart';
import '../widgets/sos_button.dart';
import '../widgets/member_marker.dart';
import '../widgets/meeting_point_marker.dart';
import '../widgets/battery_indicator.dart';
import '../widgets/reaction_panel.dart';
import '../../providers/event_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  final String eventId;
  const MapScreen({super.key, required this.eventId});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  StreamSubscription? _wsSub;
  Timer? _fallbackTimer;
  Timer? _participantsRefresh;
  String? _currentReaction;
  String? _reactionSender;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final granted = await ref.read(locationProvider.notifier).requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permiso de ubicación denegado. El mapa funcionará sin tu posición.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      await ref.read(locationProvider.notifier).startTracking();
    }

    final token = await SecureStorage().getAccessToken();
    if (token != null) {
      await ref.read(wsProvider.notifier).connect(widget.eventId, token);
      /*await ref.read(backgroundProvider.notifier).start(
        eventId: widget.eventId,
        accessToken: token,
        wsBaseUrl: AppConstants.wsBaseUrl,
        apiBaseUrl: AppConstants.apiBaseUrl,
      );*/
    }

    _wsSub = ref.read(wsClientProvider).messageStream.listen(_onWsMessage);
    _loadInitialLocations();
    _syncSosState();
    _syncPendingSos();
    Future.delayed(const Duration(seconds: 5), _checkFallback);
  }

  Future<void> _syncPendingSos() async {
    final cache = OfflineCacheService();
    final pending = await cache.loadPendingSos();
    if (pending.isEmpty) return;
    try {
      for (final sos in pending) {
        await SosService().activateOffline(
          eventId: sos['eventId'] as String,
          latitude: (sos['latitude'] as num).toDouble(),
          longitude: (sos['longitude'] as num).toDouble(),
          accuracy: (sos['accuracy'] as num).toDouble(),
          batteryLevel: sos['batteryLevel'] as int,
        );
      }
      await cache.clearPendingSos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Alertas SOS pendientes sincronizadas'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _syncSosState() async {
    try {
      final alerts = await SosService().getActiveSos(widget.eventId);
      final authState = ref.read(authProvider);
      final myId = authState is AuthAuthenticated
          ? authState.user.id
          : authState is AuthGuest
              ? authState.user.id
              : null;
      if (myId != null) {
        final isMineActive = alerts.any((a) => a.userId == myId);
        ref.read(sosProvider.notifier).setSosActive(isMineActive);
      }
      ref.read(sosProvider.notifier).setActiveAlerts(alerts);
    } catch (_) {}
  }

  void _onWsMessage(WsMessage msg) {
    switch (msg.type) {
      case WsMessageType.location:
        final loc = MemberLocation.fromWsMessage(msg.payload);
        ref.read(memberLocationsProvider.notifier).updateLocation(loc);
      case WsMessageType.sos:
        final alert = SosAlert.fromWsMessage(msg.payload);
        ref.read(sosProvider.notifier).onSosReceived(alert);
        _showSosNotification(alert);
        NotificationService().showSosAlert(userName: alert.userName, eventId: widget.eventId);
      case WsMessageType.sosCancelled:
        final userId = msg.payload['user_id'] as String;
        ref.read(sosProvider.notifier).onSosCancelled(userId);
        final cancelledName = msg.payload['name'] as String? ?? 'Un compañero';
        NotificationService().showSosCancelled(cancelledName);
      case WsMessageType.sosEscalated:
        final userId = msg.payload['user_id'] as String;
        ref.read(sosProvider.notifier).onSosEscalated(userId);
      case WsMessageType.reaction:
        final reaction = msg.payload['reaction'] as String? ?? '';
        final name = msg.payload['name'] as String? ?? 'Alguien';
        setState(() { _currentReaction = reaction; _reactionSender = name; });
      case WsMessageType.message:
        final chatMsg = ChatMessage.fromWsMessage(msg.payload);
        ref.read(chatProvider.notifier).addMessage(chatMsg);
      default:
        break;
    }
  }

  void _showSosNotification(SosAlert alert) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🆘 SOS de ${alert.userName}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: alert.latitude != 0.0 || alert.longitude != 0.0
            ? SnackBarAction(
                label: 'Ver',
                textColor: Colors.white,
                onPressed: () => _mapController.move(LatLng(alert.latitude, alert.longitude), 16),
              )
            : null,
      ),
    );
  }

  Future<void> _loadInitialLocations() async {
    try {
      final service = ref.read(eventServiceProvider);
      final participants = await service.getParticipants(widget.eventId);
      for (final p in participants) {
        if (p['latitude'] != null && p['longitude'] != null) {
          final loc = MemberLocation(
            userId: p['user_id'] as String,
            name: p['name'] as String? ?? '',
            latitude: (p['latitude'] as num).toDouble(),
            longitude: (p['longitude'] as num).toDouble(),
            updatedAt: p['last_seen'] != null
                ? DateTime.parse(p['last_seen'] as String)
                : DateTime.now(),
          );
          ref.read(memberLocationsProvider.notifier).updateLocation(loc);
        }
      }
    } catch (_) {}
  }

  void _checkFallback() {
    if (ref.read(wsProvider) != WsConnectionState.connected) _startFallback();
  }

  void _startFallback() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(
      Duration(seconds: AppConstants.locationFallbackInterval),
      (_) async {
        final pos = ref.read(locationProvider).currentPosition;
        if (pos == null) return;
        try { await LocationService().sendFallbackLocation(widget.eventId, pos); } catch (_) {}
      },
    );
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _fallbackTimer?.cancel();
    _participantsRefresh?.cancel();
    ref.read(locationProvider.notifier).stopTracking();
    ref.read(wsProvider.notifier).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(memberLocationsProvider);
    final locationState = ref.watch(locationProvider);
    final wsState = ref.watch(wsProvider);
    final sosState = ref.watch(sosProvider);
    final authState = ref.watch(authProvider);
    final eventsAsync = ref.watch(myEventsProvider);
    //final bgState = ref.watch(backgroundProvider);
    final isOnline = ref.watch(isOnlineProvider);

    final currentUserId = authState is AuthAuthenticated
        ? authState.user.id
        : authState is AuthGuest ? authState.user.id : null;

    double? meetLat, meetLng;
    eventsAsync.whenData((events) {
      final event = events.where((e) => e.id == widget.eventId).firstOrNull;
      meetLat = event?.meetingPointLat;
      meetLng = event?.meetingPointLng;
    });

    final myPos = locationState.currentPosition;
    final center = myPos != null
        ? LatLng(myPos.latitude, myPos.longitude)
        : const LatLng(40.4168, -3.7038);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa del grupo'),
        actions: [
          /*if (bgState.isActive)
            Tooltip(
              message: 'Ubicación activa en segundo plano',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: const Icon(Icons.location_on, color: Colors.greenAccent, size: 20),
              ),
            ),*/
          const BatteryIndicator(),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              wsState == WsConnectionState.connected
                  ? Icons.wifi
                  : wsState == WsConnectionState.reconnecting
                      ? Icons.wifi_find
                      : Icons.wifi_off,
              color: wsState == WsConnectionState.connected
                  ? Colors.green
                  : wsState == WsConnectionState.reconnecting
                      ? Colors.orange
                      : Colors.red,
              size: 20,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Mapa con TileLayer cacheado — Nivel 2
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.festisafe.festisafe',
                tileProvider: NetworkTileProvider(),
              ),
              MarkerLayer(
                markers: [
                  if (myPos != null)
                    Marker(
                      point: LatLng(myPos.latitude, myPos.longitude),
                      width: 60,
                      height: 70,
                      child: currentUserId != null && locations.containsKey(currentUserId)
                          ? MemberMarker(member: locations[currentUserId]!, isSelf: true)
                          : const Icon(Icons.my_location, color: Colors.blue, size: 32),
                    ),
                  ...locations.entries
                      .where((e) => e.key != currentUserId)
                      .map((e) => Marker(
                            point: LatLng(e.value.latitude, e.value.longitude),
                            width: 60,
                            height: 70,
                            child: MemberMarker(member: e.value, onTap: () => _showMemberPanel(e.value)),
                          )),
                  if (meetLat != null && meetLng != null)
                    Marker(
                      point: LatLng(meetLat!, meetLng!),
                      width: 60,
                      height: 70,
                      child: MeetingPointMarker(latitude: meetLat!, longitude: meetLng!),
                    ),
                  ...sosState.activeAlerts.map((alert) => Marker(
                        point: LatLng(alert.latitude, alert.longitude),
                        width: 60,
                        height: 70,
                        child: _SosMarker(alert: alert),
                      )),
                ],
              ),
            ],
          ),

          // Banner offline — Nivel 1
          if (!isOnline)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _OfflineBanner(hasCache: locations.isNotEmpty),
            ),

          if (_currentReaction != null)
            Positioned(
              top: isOnline ? 8 : 44,
              left: 0,
              right: 0,
              child: Center(
                child: ReactionBanner(
                  senderName: _reactionSender ?? '',
                  reaction: _currentReaction!,
                  onDismiss: () => setState(() {
                    _currentReaction = null;
                    _reactionSender = null;
                  }),
                ),
              ),
            ),

          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ReactionPanel(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [SosButton(eventId: widget.eventId)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMemberPanel(MemberLocation member) {
    final distance = _calcDistance(member);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 24, child: Text(member.initials)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.name, style: Theme.of(context).textTheme.titleMedium),
                      if (distance != null)
                        Text('~${distance.toStringAsFixed(0)} m', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () { Navigator.pop(context); context.push('/compass/${member.userId}'); },
                icon: const Icon(Icons.explore),
                label: const Text('Guiarme hacia él'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double? _calcDistance(MemberLocation member) {
    final pos = ref.read(locationProvider).currentPosition;
    if (pos == null) return null;
    const dist = Distance();
    return dist.as(LengthUnit.Meter,
        LatLng(pos.latitude, pos.longitude),
        LatLng(member.latitude, member.longitude));
  }
}

// ---------------------------------------------------------------------------
// Banner offline
// ---------------------------------------------------------------------------
class _OfflineBanner extends StatelessWidget {
  final bool hasCache;
  const _OfflineBanner({required this.hasCache});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasCache
                  ? 'Sin conexión · mostrando última ubicación conocida'
                  : 'Sin conexión · GPS activo · mapa en caché',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marcador SOS
// ---------------------------------------------------------------------------
class _SosMarker extends StatelessWidget {
  final SosAlert alert;
  const _SosMarker({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: alert.isEscalated ? Colors.deepOrange : Colors.red,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 2)],
          ),
          child: const Icon(Icons.sos, color: Colors.white, size: 22),
        ),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(4)),
          child: Text(alert.userName.split(' ').first, style: const TextStyle(color: Colors.white, fontSize: 9)),
        ),
      ],
    );
  }
}
