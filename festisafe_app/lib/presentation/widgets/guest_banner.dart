import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

/// Banner que se muestra cuando el usuario está en modo invitado.
/// Permite convertir la cuenta a permanente.
class GuestBanner extends ConsumerStatefulWidget {
  const GuestBanner({super.key});

  @override
  ConsumerState<GuestBanner> createState() => _GuestBannerState();
}

class _GuestBannerState extends ConsumerState<GuestBanner> {
  void _showConvertDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Crear cuenta permanente'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || !v.contains('@')) return 'Correo inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                await ref.read(authProvider.notifier).convertGuest(
                      email: emailCtrl.text.trim(),
                      password: passCtrl.text,
                      phone: phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                    );
                if (!mounted) return;
                final state = ref.read(authProvider);
                if (state is AuthError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Crear cuenta'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.onTertiaryContainer, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Estás como invitado — Crea una cuenta para guardar tu progreso',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onTertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: _showConvertDialog,
            child: const Text('Crear cuenta'),
          ),
        ],
      ),
    );
  }
}
