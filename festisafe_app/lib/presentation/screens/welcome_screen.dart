import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/auth_provider.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _codeController = TextEditingController();
  bool _loadingGuest = false;
  bool _showScanner = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _guestLogin(String code) async {
    if (code.length != 6) {
      _showError('El código debe tener 6 dígitos');
      return;
    }
    setState(() => _loadingGuest = true);
    final eventId = await ref.read(authProvider.notifier).guestLogin(code);
    if (!mounted) return;
    setState(() => _loadingGuest = false);
    if (eventId != null) {
      context.go('/home');
    } else {
      final state = ref.read(authProvider);
      if (state is AuthError) _showError(state.message);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _showScanner
            ? _buildScanner()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo / título
                    Image.asset(
                      'assets/images/rave_logo.png',
                      width: 180,
                      height: 180,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'FestiSafe',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tu compañero de seguridad en festivales',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Botones principales
                    FilledButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('Iniciar sesión'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => context.push('/register'),
                      child: const Text('Registrarse'),
                    ),
                    const SizedBox(height: 32),

                    // Divisor
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'o entra como invitado',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 16),

                    // Campo código invitado
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                      decoration: InputDecoration(
                        hintText: '000000',
                        counterText: '',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'Escanear QR',
                          onPressed: () => setState(() => _showScanner = true),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _loadingGuest
                          ? null
                          : () => _guestLogin(_codeController.text.trim()),
                      child: _loadingGuest
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar como invitado'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue == null) return;
            final value = barcode!.rawValue!;
            // Extraer código de 6 dígitos del QR
            final match = RegExp(r'\b(\d{6})\b').firstMatch(value);
            if (match != null) {
              setState(() => _showScanner = false);
              _guestLogin(match.group(1)!);
            } else {
              setState(() => _showScanner = false);
              _showError('QR no reconocido');
            }
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          child: IconButton.filled(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _showScanner = false),
          ),
        ),
        const Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 2),
                ),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
