import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/sos_alert.dart';

class SosState {
  /// true si el usuario actual tiene un SOS activo.
  final bool isSosActive;

  /// Alertas SOS activas recibidas de otros miembros del grupo.
  final List<SosAlert> activeAlerts;

  const SosState({
    this.isSosActive = false,
    this.activeAlerts = const [],
  });

  SosState copyWith({bool? isSosActive, List<SosAlert>? activeAlerts}) {
    return SosState(
      isSosActive: isSosActive ?? this.isSosActive,
      activeAlerts: activeAlerts ?? this.activeAlerts,
    );
  }
}

class SosNotifier extends StateNotifier<SosState> {
  SosNotifier() : super(const SosState());

  void setSosActive(bool active) {
    state = state.copyWith(isSosActive: active);
  }

  /// Procesa un mensaje WS de tipo "sos".
  void onSosReceived(SosAlert alert) {
    final updated = [...state.activeAlerts];
    final idx = updated.indexWhere((a) => a.userId == alert.userId);
    if (idx >= 0) {
      updated[idx] = alert;
    } else {
      updated.add(alert);
    }
    state = state.copyWith(activeAlerts: updated);
  }

  /// Procesa un mensaje WS de tipo "sos_cancelled".
  void onSosCancelled(String userId) {
    state = state.copyWith(
      activeAlerts: state.activeAlerts.where((a) => a.userId != userId).toList(),
    );
  }

  /// Procesa un mensaje WS de tipo "sos_escalated".
  void onSosEscalated(String userId) {
    final updated = state.activeAlerts.map((a) {
      return a.userId == userId ? a.copyWith(isEscalated: true) : a;
    }).toList();
    state = state.copyWith(activeAlerts: updated);
  }

  void setActiveAlerts(List<SosAlert> alerts) {
    state = state.copyWith(activeAlerts: alerts);
  }
}

final sosProvider = StateNotifierProvider<SosNotifier, SosState>(
  (ref) => SosNotifier(),
);
