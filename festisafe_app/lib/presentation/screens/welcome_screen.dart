import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _scannerVisible = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleGuestLogin() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    setState(() => _loading = true);
    try {
      // ✅ Corregido: El método correcto es guestLogin
      await ref.read(authProvider.notifier).guestLogin(code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQRDetected(String code) {
    _codeController.text = code;
    setState(() => _scannerVisible = false);
    _handleGuestLogin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: _scannerVisible ? _buildScanner() : _buildContent(),
    );
  }

  Widget _buildContent() {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 60),

                    // HEADER
                    Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withOpacity(0.4),
                                blurRadius: 40,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/rave_logo.png',
                            width: 120,
                            height: 120,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'FestiSafe',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Seguridad inteligente en festivales',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // BOTONES
                    Column(
                      children: [
                        FilledButton(
                          onPressed: () => context.push('/login'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: const Text('Iniciar sesión'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => context.push('/register'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: const Text('Crear cuenta'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // DIVIDER
                    Row(
                      children: const [
                        Expanded(child: Divider(color: Colors.white24)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'modo invitado',
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.white24)),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // INPUT
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        letterSpacing: 6,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        hintText: '••••••',
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () => setState(() => _scannerVisible = true),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // BOTÓN INVITADO
                    FilledButton.tonal(
                      onPressed: _loading ? null : _handleGuestLogin,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar al evento'),
                    ),

                    const Spacer(),

                    Text(
                      'Powered by FestiSafe',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white24),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue == null) return;
            _onQRDetected(barcode!.rawValue!);
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          child: IconButton.filled(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _scannerVisible = false),
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
