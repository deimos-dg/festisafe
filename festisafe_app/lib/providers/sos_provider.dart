import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';
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
    if (!mounted) return;
    state = state.copyWith(isSosActive: active);
  }

  void onSosReceived(SosAlert alert) {
    if (!mounted) return;
    final updated = [...state.activeAlerts];
    final idx = updated.indexWhere((a) => a.userId == alert.userId);
    if (idx >= 0) {
      updated[idx] = alert;
    } else {
      updated.add(alert);
    }
    state = state.copyWith(activeAlerts: updated);
  }

  void onSosCancelled(String userId) {
    if (!mounted) return;
    state = state.copyWith(
      activeAlerts: state.activeAlerts.where((a) => a.userId != userId).toList(),
    );
  }

  void onSosEscalated(String userId) {
    if (!mounted) return;
    final updated = state.activeAlerts.map((a) {
      return a.userId == userId ? a.copyWith(isEscalated: true) : a;
    }).toList();
    state = state.copyWith(activeAlerts: updated);
  }

  void setActiveAlerts(List<SosAlert> alerts) {
    if (!mounted) return;
    state = state.copyWith(activeAlerts: alerts);
  }
}

final sosProvider = StateNotifierProvider<SosNotifier, SosState>(
  (ref) => SosNotifier(),
);
