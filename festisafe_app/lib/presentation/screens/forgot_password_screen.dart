import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/api_client.dart';

/// Pantalla de recuperación de contraseña.
/// El usuario ingresa su email y recibe una contraseña temporal.
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ApiClient().dio.post(
        '/auth/forgot-password',
        data: {'email': _emailCtrl.text.trim()},
      );
    } catch (_) {
      // Respuesta genérica — no revelar si el email existe
    } finally {
      if (mounted) setState(() { _loading = false; _sent = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent ? const _SuccessView() : _FormView(
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
            'Ingresa tu email y te enviaremos una contraseña temporal.',
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'Instrucciones enviadas',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Si el email está registrado, recibirás una contraseña temporal. Úsala para iniciar sesión y luego cámbiala desde tu perfil.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Ir al login'),
          ),
        ),
      ],
    );
  }
}
