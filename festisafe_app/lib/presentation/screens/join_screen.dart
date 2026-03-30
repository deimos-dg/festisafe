import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../data/services/api_client.dart';

/// Pantalla que se abre al tocar un deep link festisafe://join/CODIGO.
/// Si el usuario no está autenticado, muestra login inline.
/// Si ya está autenticado, canjea el código directamente.
class JoinScreen extends ConsumerStatefulWidget {
  final String code;
  const JoinScreen({super.key, required this.code});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  bool _loading = false;
  String? _error;
  String? _eventName;

  @override
  void initState() {
    super.initState();
    // Validar formato del código antes de intentar canjearlo
    if (!_isValidCode(widget.code)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _error = 'Código inválido. Debe ser de 6 dígitos.');
      });
      return;
    }
    // Si ya está autenticado, canjear automáticamente
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth is AuthAuthenticated || auth is AuthGuest) {
        _redeem();
      }
    });
  }

  bool _isValidCode(String code) {
    return RegExp(r'^\d{6}$').hasMatch(code);
  }

  Future<void> _redeem() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Usar el endpoint de guest-login que canjea el código
      final res = await ApiClient().dio.post('/auth/guest-login', data: {
        'code': widget.code,
      });
      final eventId = res.data['event_id'] as String?;
      if (eventId != null && mounted) {
        context.go('/map/$eventId');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _parseError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('400') || msg.contains('invalid')) {
      return 'Código inválido o ya utilizado.';
    }
    if (msg.contains('404')) return 'Código no encontrado.';
    if (msg.contains('403')) return 'El evento está lleno o expiró.';
    return 'Error al unirse. Verifica tu conexión.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isAuth = auth is AuthAuthenticated || auth is AuthGuest;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Icon(
                  Icons.festival,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Unirse al evento',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Código: ${widget.code}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 32),

              if (_loading)
                const CircularProgressIndicator()
              else if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isAuth)
                  FilledButton(
                    onPressed: _redeem,
                    child: const Text('Reintentar'),
                  ),
              ] else if (!isAuth) ...[
                // No autenticado — ofrecer login o registro
                Text(
                  'Inicia sesión para unirte al evento',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Iniciar sesión'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Crear cuenta'),
                  ),
                ),
              ] else ...[
                // Autenticado — canjeo en progreso
                const Text('Procesando invitación…'),
              ],

              if (_eventName != null) ...[
                const SizedBox(height: 16),
                Text(
                  _eventName!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
