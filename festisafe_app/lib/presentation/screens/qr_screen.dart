import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/event_provider.dart';
import '../../data/models/guest_code.dart';

class QrScreen extends ConsumerStatefulWidget {
  final String eventId;
  const QrScreen({super.key, required this.eventId});

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen> {
  GuestCodeModel? _code;
  bool _loading = false;
  String? _error;
  int _expiresHours = 24;

  // Opciones de expiración disponibles
  static const _expiryOptions = [
    (label: '1 hora', hours: 1),
    (label: '6 horas', hours: 6),
    (label: '24 horas', hours: 24),
    (label: '48 horas', hours: 48),
    (label: '7 días', hours: 168),
  ];

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await ref.read(eventServiceProvider).generateGuestCode(
            widget.eventId,
            expiresHours: _expiresHours,
          );
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _share() {
    if (_code == null) return;
    SharePlus.instance.share(
      ShareParams(
        text: '🎪 Te invito a unirte a FestiSafe\n\n'
            'Toca el enlace o ingresa el código:\n'
            '👉 festisafe://join/${_code!.code}\n\n'
            'Código: ${_code!.code}\n'
            '⚠️ Código de un solo uso — válido hasta: ${_fmtDate(_code!.expiresAt)}',
        subject: 'Invitación personal a FestiSafe',
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _showNewCodeDialog() async {
    int selectedHours = _expiresHours;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Generar nuevo código OTP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Este código es de un solo uso — solo una persona podrá canjearlo.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text('Válido por:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _expiryOptions.map((opt) {
                  final selected = selectedHours == opt.hours;
                  return ChoiceChip(
                    label: Text(opt.label),
                    selected: selected,
                    onSelected: (_) => setDialogState(() => selectedHours = opt.hours),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Generar'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() => _expiresHours = selectedHours);
      await _generate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Código OTP de invitado'),
        actions: [
          if (_code != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Compartir',
              onPressed: _share,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 8),
                        Text('Error: $_error'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _generate,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : _code == null
                    ? const SizedBox.shrink()
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Badge OTP
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline,
                                    size: 14, color: Colors.orange),
                                SizedBox(width: 4),
                                Text(
                                  'Un solo uso · Una persona',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.orange),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // QR
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: _code!.code,
                                version: QrVersions.auto,
                                size: 200,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Código en texto con estilo OTP
                          Text(
                            _code!.code,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 10,
                            ),
                          ),
                          const SizedBox(height: 8),

                          Text(
                            'Expira: ${_fmtDate(_code!.expiresAt)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                          const SizedBox(height: 32),

                          // Acciones
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _share,
                                  icon: const Icon(Icons.share),
                                  label: const Text('Compartir'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _showNewCodeDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Nuevo código'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Genera un código diferente para cada persona que quieras invitar.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
      ),
    );
  }
}
