import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/password_recovery_service.dart';

// --- States ---

sealed class PasswordRecoveryState {
  const PasswordRecoveryState();
}

class PasswordRecoveryIdle extends PasswordRecoveryState {
  const PasswordRecoveryIdle();
}

class PasswordRecoveryLoading extends PasswordRecoveryState {
  const PasswordRecoveryLoading();
}

class PasswordRecoverySuccess extends PasswordRecoveryState {
  final String message;
  const PasswordRecoverySuccess(this.message);
}

class PasswordRecoveryError extends PasswordRecoveryState {
  final String message;
  const PasswordRecoveryError(this.message);
}

// --- Notifier ---

class PasswordRecoveryNotifier extends StateNotifier<PasswordRecoveryState> {
  final PasswordRecoveryService _service;

  PasswordRecoveryNotifier(this._service) : super(const PasswordRecoveryIdle());

  Future<void> forgotPassword(String email) async {
    state = const PasswordRecoveryLoading();
    final result = await _service.forgotPassword(email);
    state = result.success
        ? PasswordRecoverySuccess(result.message)
        : PasswordRecoveryError(result.message);
  }

  Future<void> resetPassword(String token, String newPassword) async {
    state = const PasswordRecoveryLoading();
    final result = await _service.resetPassword(token, newPassword);
    state = result.success
        ? PasswordRecoverySuccess(result.message)
        : PasswordRecoveryError(result.message);
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    state = const PasswordRecoveryLoading();
    final result = await _service.changePassword(currentPassword, newPassword);
    state = result.success
        ? PasswordRecoverySuccess(result.message)
        : PasswordRecoveryError(result.message);
  }

  void reset() {
    state = const PasswordRecoveryIdle();
  }
}

// --- Provider ---

final passwordRecoveryProvider =
    StateNotifierProvider<PasswordRecoveryNotifier, PasswordRecoveryState>(
  (ref) => PasswordRecoveryNotifier(PasswordRecoveryService()),
);
