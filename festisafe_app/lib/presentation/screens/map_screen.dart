import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import '../../providers/ble_provider.dart';
import '../../providers/group_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  final String eventId;
  const MapScreen({super.key, required this.eventId});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  late AnimationController _pulseController;
  StreamSubscription? _wsSub;
  StreamSubscription? _wsStateSub;  // para monitorear estado WS y activar BLE
  Timer? _fallbackTimer;
  Timer? _bleActivationTimer;       // delay antes de activar BLE
  String? _currentReaction;
  String? _reactionSender;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _init();
  }

  Future<void> _init() async {
    final granted = await ref.read(locationProvider.notifier).requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permiso de ubicación denegado. El mapa funcionará sin tu posición.'),
          ),
        );
      }
    } else {
      await ref.read(locationProvider.notifier).startTracking();
    }

    final token = await SecureStorage().getAccessToken();
    if (token != null) {
      await ref.read(wsProvider.notifier).connect(widget.eventId, token);
    }

    _wsSub = ref.read(wsClientProvider).messageStream.listen(_onWsMessage);
    _wsStateSub = ref.read(wsClientProvider).stateStream.listen(_onWsStateChange);
    _loadInitialLocations();
    _syncSosState();
    _syncPendingSos();
    Future.delayed(const Duration(seconds: 5), _checkFallback);
  }

  // (Mantengo lógica de sincronización igual para no romper funcionalidad)
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
    } catch (_) {}
  }

  Future<void> _syncSosState() async {
    try {
      final alerts = await SosService().getActiveSos(widget.eventId);
      final authState = ref.read(authProvider);
      final myId = authState is AuthAuthenticated ? authState.user.id : (authState is AuthGuest ? authState.user.id : null);
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
      case WsMessageType.sosCancelled:
        final userId = msg.payload['user_id'] as String;
        ref.read(sosProvider.notifier).onSosCancelled(userId);
      case WsMessageType.reaction:
        setState(() { 
          _currentReaction = msg.payload['reaction']; 
          _reactionSender = msg.payload['name']; 
        });
      default: break;
    }
  }

  void _showSosNotification(SosAlert alert) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🆘 SOS de ${alert.userName}', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Localizar',
          textColor: Colors.white,
          onPressed: () => _mapController.move(LatLng(alert.latitude, alert.longitude), 17),
        ),
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
            updatedAt: p['last_seen'] != null ? DateTime.parse(p['last_seen']) : DateTime.now(),
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
    _fallbackTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        final pos = ref.read(locationProvider).currentPosition;
        if (pos != null) {
          try { await LocationService().sendFallbackLocation(widget.eventId, pos); } catch (_) {}
        }
    });
  }

  /// Opción C — BLE como fallback: se activa cuando el WS lleva >15s desconectado.
  void _onWsStateChange(WsConnectionState wsState) {
    if (wsState == WsConnectionState.connected) {
      // WS recuperado — cancelar timer de activación y detener BLE si estaba activo
      _bleActivationTimer?.cancel();
      _stopBle();
    } else if (wsState == WsConnectionState.disconnected) {
      // Esperar 15s antes de activar BLE para no encenderlo en reconexiones rápidas
      _bleActivationTimer?.cancel();
      _bleActivationTimer = Timer(const Duration(seconds: 15), _startBle);
    }
  }

  Future<void> _startBle() async {
    if (!mounted) return;
    final authState = ref.read(authProvider);
    final userId = authState is AuthAuthenticated
        ? authState.user.id
        : (authState is AuthGuest ? authState.user.id : null);
    if (userId == null) return;

    // groupProvider puede estar vacío si BLE se activa antes de que cargue el grupo.
    // Reintentamos hasta 3 veces con 3s de espera entre intentos.
    GroupModel? group;
    for (int i = 0; i < 3; i++) {
      group = ref.read(groupProvider).group;
      if (group != null) break;
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
    }
    if (group == null) return; // Sin grupo — BLE no aplica

    await ref.read(bleProvider.notifier).start(
      userId: userId,
      groupId: group.id,
      eventId: widget.eventId,
    );

    // Conectar el callback de SOS BLE al provider de SOS
    ref.read(bleProvider.notifier).onSosReceived = (data) {
      final alert = SosAlert(
        userId: data['userId'] as String,
        userName: 'BLE',
        latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
        batteryLevel: data['batteryLevel'] as int? ?? 0,
        activatedAt: DateTime.now(),
      );
      ref.read(sosProvider.notifier).onSosReceived(alert);
    };
  }

  void _stopBle() {
    if (ref.read(bleProvider).isActive) {
      ref.read(bleProvider.notifier).stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _wsSub?.cancel();
    _wsStateSub?.cancel();
    _fallbackTimer?.cancel();
    _bleActivationTimer?.cancel();
    _stopBle();
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
    final isOnline = ref.watch(isOnlineProvider);
    final authState = ref.watch(authProvider);

    final currentUserId = authState is AuthAuthenticated ? authState.user.id : (authState is AuthGuest ? authState.user.id : null);
    final myPos = locationState.currentPosition;
    final center = myPos != null ? LatLng(myPos.latitude, myPos.longitude) : const LatLng(0, 0);

    return Scaffold(
      backgroundColor: const Color(0xFF030712), // Dark Global Background
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: Colors.black.withOpacity(0.3),
              elevation: 0,
              title: const Text('CENTRO DE COMANDO', 
                style: TextStyle(letterSpacing: 2, fontSize: 16, fontWeight: FontWeight.w900, color: Colors.indigoAccent)),
              actions: [
                const BatteryIndicator(),
                const SizedBox(width: 12),
                _StatusBadge(wsState: wsState),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Mapa con Filtro de Color (Cyber-Dark)
          ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              -1,  0,  0, 0, 255,
               0, -1,  0, 0, 255,
               0,  0, -1, 0, 255,
               0,  0,  0, 1, 0,
            ]),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
                MarkerLayer(
                  markers: [
                    if (myPos != null)
                      Marker(
                        point: LatLng(myPos.latitude, myPos.longitude),
                        width: 80, height: 80,
                        child: _PulseMarker(color: Colors.indigoAccent, animation: _pulseController),
                      ),
                    ...locations.entries.where((e) => e.key != currentUserId).map((e) => Marker(
                      point: LatLng(e.value.latitude, e.value.longitude),
                      width: 60, height: 70,
                      child: MemberMarker(member: e.value, onTap: () => _showMemberPanel(e.value)),
                    )),
                    ...sosState.activeAlerts.map((alert) => Marker(
                      point: LatLng(alert.latitude, alert.longitude),
                      width: 100, height: 100,
                      child: _SosRadarMarker(alert: alert, animation: _pulseController),
                    )),
                  ],
                ),
              ],
            ),
          ),

          // Overlay de Gradiente para profundidad
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                ),
              ),
            ),
          ),

          // Banner Offline Glass
          if (!isOnline)
            Positioned(
              top: 100, left: 20, right: 20,
              child: _GlassCard(
                color: Colors.orange.withOpacity(0.2),
                borderColor: Colors.orangeAccent,
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 16),
                    SizedBox(width: 12),
                    Text('MODO OFFLINE ACTIVADO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          // Panel de Control Flotante (Glassmorphism)
          Positioned(
            bottom: 30, left: 0, right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ReactionPanel(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _QuickAction(icon: Icons.chat_bubble_outline, label: 'Chat', onTap: () => context.push('/chat/${widget.eventId}')),
                            SosButton(eventId: widget.eventId),
                            _QuickAction(icon: Icons.settings_outlined, label: 'Ajustes', onTap: () {}),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMemberPanel(MemberLocation member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GlassMemberPanel(member: member, distance: _calcDistance(member)),
    );
  }

  double? _calcDistance(MemberLocation member) {
    final pos = ref.read(locationProvider).currentPosition;
    if (pos == null) return null;
    return const Distance().as(LengthUnit.Meter, LatLng(pos.latitude, pos.longitude), LatLng(member.latitude, member.longitude));
  }
}

// ---------------------------------------------------------------------------
// WIDGETS DE DISEÑO PREMIUM (CYBER-DARK)
// ---------------------------------------------------------------------------

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final Color borderColor;
  const _GlassCard({required this.child, required this.color, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor.withOpacity(0.5)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final WsConnectionState wsState;
  const _StatusBadge({required this.wsState});

  @override
  Widget build(BuildContext context) {
    final color = wsState == WsConnectionState.connected ? Colors.greenAccent : (wsState == WsConnectionState.reconnecting ? Colors.orangeAccent : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(wsState.name.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}

class _PulseMarker extends StatelessWidget {
  final Color color;
  final Animation<double> animation;
  const _PulseMarker({required this.color, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 40 * animation.value,
            height: 40 * animation.value,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(1 - animation.value)),
          ),
          Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}

class _SosRadarMarker extends StatelessWidget {
  final SosAlert alert;
  final Animation<double> animation;
  const _SosRadarMarker({required this.alert, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 80 * animation.value, height: 80 * animation.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.redAccent.withOpacity(1 - animation.value), width: 2),
            ),
          ),
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
        ],
      ),
    );
  }
}

class _GlassMemberPanel extends StatelessWidget {
  final MemberLocation member;
  final double? distance;
  const _GlassMemberPanel({required this.member, this.distance});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 35, backgroundColor: Colors.indigoAccent.withOpacity(0.2), child: Text(member.initials, style: const TextStyle(color: Colors.indigoAccent, fontSize: 24, fontWeight: FontWeight.bold))),
            const SizedBox(height: 16),
            Text(member.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            if (distance != null) Text('DISTANCIA: ~${distance!.toStringAsFixed(0)}m', style: const TextStyle(color: Colors.indigoAccent, letterSpacing: 1, fontSize: 12)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(context); context.push('/compass/${member.userId}'); },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                icon: const Icon(Icons.explore_rounded, color: Colors.white),
                label: const Text('INICIAR RASTREO TÁCTICO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

  double? _calcDistance(MemberLocation member) {
    final pos = ref.read(locationProvider).currentPosition;
    if (pos == null) return null;
    const dist = Distance();
    return dist.as(LengthUnit.Meter,
        LatLng(pos.latitude, pos.longitude),
        LatLng(member.latitude, member.longitude)    );
  }
}
