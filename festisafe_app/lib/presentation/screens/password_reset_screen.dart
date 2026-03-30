import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/password_recovery_provider.dart';
import '../../providers/auth_provider.dart';

enum PasswordResetMode { resetWithToken, changeObligatory }

class PasswordResetScreen extends ConsumerStatefulWidget {
  final PasswordResetMode mode;
  final String? token;

  /// Email del usuario — requerido en modo [PasswordResetMode.changeObligatory]
  /// para el login automático tras el cambio exitoso.
  final String? email;

  const PasswordResetScreen({
    super.key,
    required this.mode,
    this.token,
    this.email,
  });

  @override
  ConsumerState<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tokenCtrl;
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _obscureCurrent = true;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: widget.token ?? '');
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  bool get _isResetMode => widget.mode == PasswordResetMode.resetWithToken;

  Future<void> _submit() async {
    setState(() => _inlineError = null);
    if (!_formKey.currentState!.validate()) return;

    // Local validation: passwords must match
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      setState(() => _inlineError = 'Las contraseñas no coinciden');
      return;
    }

    final notifier = ref.read(passwordRecoveryProvider.notifier);

    if (_isResetMode) {
      await notifier.resetPassword(_tokenCtrl.text.trim(), _newPassCtrl.text);
    } else {
      await notifier.changePassword(_currentPassCtrl.text, _newPassCtrl.text);
    }

    if (!mounted) return;
    final state = ref.read(passwordRecoveryProvider);

    if (state is PasswordRecoverySuccess) {
      if (_isResetMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/login');
      } else {
        // Auto-login after obligatory change using the provided email
        if (widget.email != null && widget.email!.isNotEmpty) {
          await ref.read(authProvider.notifier).login(
                widget.email!,
                _newPassCtrl.text,
              );
        }
        if (!mounted) return;
        context.go('/home');
      }
    } else if (state is PasswordRecoveryError) {
      setState(() => _inlineError = state.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerState = ref.watch(passwordRecoveryProvider);
    final isLoading = providerState is PasswordRecoveryLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isResetMode ? 'Restablecer contraseña' : 'Cambiar contraseña'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _isResetMode ? Icons.lock_reset : Icons.lock_outline,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _isResetMode
                      ? 'Introduce el token recibido por email y tu nueva contraseña.'
                      : 'Introduce tu contraseña actual y elige una nueva.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Token field (resetWithToken mode only)
                if (_isResetMode) ...[
                  TextFormField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Token de recuperación',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requerido';
                      if (v.trim().length != 64) return 'El token debe tener 64 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Current password field (changeObligatory mode only)
                if (!_isResetMode) ...[
                  TextFormField(
                    controller: _currentPassCtrl,
                    obscureText: _obscureCurrent,
                    decoration: InputDecoration(
                      labelText: 'Contraseña actual',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureCurrent ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Requerido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // New password field
                TextFormField(
                  controller: _newPassCtrl,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Requerido';
                    if (v.length < 12) return 'Mínimo 12 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm password field
                TextFormField(
                  controller: _confirmPassCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Requerido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Inline error message
                if (_inlineError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _inlineError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                FilledButton(
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isResetMode ? 'Restablecer contraseña' : 'Cambiar contraseña'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
