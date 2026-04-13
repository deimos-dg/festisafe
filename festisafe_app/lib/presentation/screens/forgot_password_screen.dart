import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/api_client.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _sent = false;
  String? _debugToken; // token visible cuando SMTP no está configurado

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final response = await ApiClient().dio.post(
        '/auth/forgot-password',
        data: {'email': _emailCtrl.text.trim()},
      );
      // Si el backend devuelve debug_token (sin SMTP), mostrarlo en pantalla
      final data = response.data as Map<String, dynamic>?;
      final token = data?['debug_token'] as String?;
      if (mounted) {
        setState(() {
          _sent = true;
          _debugToken = token;
        });
      }
    } catch (e) {
      // Respuesta genérica — no revelar si el email existe
      if (mounted) setState(() => _sent = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent
            ? _SuccessView(debugToken: _debugToken)
            : _FormView(
                emailCtrl: _emailCtrl,
                formKey: _formKey,
                loading: _loading,
                onSubmit: _submit,
              ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  final TextEditingController emailCtrl;
  final GlobalKey<FormState> formKey;
  final bool loading;
  final VoidCallback onSubmit;

  const _FormView({
    required this.emailCtrl,
    required this.formKey,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_reset, size: 56, color: Colors.blue),
          const SizedBox(height: 16),
          Text(
            'Ingresa tu email y te enviaremos instrucciones para recuperar tu contraseña.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requerido';
              if (!v.contains('@')) return 'Email inválido';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Enviar instrucciones'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String? debugToken;
  const _SuccessView({this.debugToken});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            'Instrucciones enviadas',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Si el email está registrado, recibirás instrucciones. '
            'Úsalas para iniciar sesión y luego cambia tu contraseña desde el perfil.',
            textAlign: TextAlign.center,
          ),

          // Token de debug — visible solo cuando SMTP no está configurado
          if (debugToken != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Modo desarrollo — SMTP no configurado',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Usa este token para restablecer tu contraseña:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: debugToken!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Token copiado al portapapeles')),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              debugToken!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const Icon(Icons.copy, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        '/reset-password?token=$debugToken',
                      ),
                      icon: const Icon(Icons.lock_reset, size: 16),
                      label: const Text('Restablecer contraseña ahora'),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('Ir al login'),
            ),
          ),
        ],
      ),
    );
  }
}
