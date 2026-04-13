import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../data/services/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/color_palettes.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;
  int? _selectedAvatar;
  String? _customPhotoPath; // ruta local de la foto personalizada

  // ---------------------------------------------------------------------------
  // Avatares temáticos de festival — 12 iconos
  // ---------------------------------------------------------------------------
  static const _avatarColors = [
    Color(0xFF7B1FA2), // púrpura — auriculares
    Color(0xFFE53935), // rojo — micrófono
    Color(0xFF1976D2), // azul — nota musical
    Color(0xFF00897B), // teal — teclado
    Color(0xFFF57C00), // naranja — caramelo
    Color(0xFFFFB300), // ámbar — rayo
    Color(0xFF43A047), // verde — USB
    Color(0xFF039BE5), // azul claro — pelota
    Color(0xFFD81B60), // rosa — estrella
    Color(0xFF6D4C41), // marrón — cohete
    Color(0xFF546E7A), // gris azul — trofeo
    Color(0xFF00ACC1), // cyan — celebración
  ];

  static const _avatarIcons = [
    Icons.headphones,           // auriculares
    Icons.mic,                  // micrófono
    Icons.music_note,           // nota musical
    Icons.piano,                // teclado
    Icons.icecream,             // caramelo/helado
    Icons.bolt,                 // rayo
    Icons.usb,                  // USB
    Icons.sports_soccer,        // pelota
    Icons.star,                 // estrella
    Icons.rocket_launch,        // cohete
    Icons.emoji_events,         // trofeo
    Icons.celebration,          // celebración
  ];

  static const _avatarLabels = [
    'Auriculares', 'Micrófono', 'Nota', 'Teclado',
    'Caramelo', 'Rayo', 'USB', 'Pelota',
    'Estrella', 'Cohete', 'Trofeo', 'Fiesta',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final auth = ref.read(authProvider);
    if (auth is AuthAuthenticated) {
      _nameCtrl.text = auth.user.name;
      _phoneCtrl.text = auth.user.phone ?? '';
      _selectedAvatar = auth.user.avatarIndex;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('avatar_index');
    final photoPath = prefs.getString('avatar_custom_photo');
    if (mounted) {
      setState(() {
        if (saved != null) _selectedAvatar = saved;
        _customPhotoPath = photoPath;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final client = ApiClient();
      await client.dio.patch('/users/me', data: {
        'name': _nameCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
      });
      // Guardar avatar localmente
      if (_selectedAvatar != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('avatar_index', _selectedAvatar!);
        if (_selectedAvatar == AppConstants.avatarCustomPhoto && _customPhotoPath != null) {
          await prefs.setString('avatar_custom_photo', _customPhotoPath!);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado')),
      );
      // Refrescar sesión
      await ref.read(authProvider.notifier).checkSession();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Esta acción es permanente. Se eliminarán todos tus datos, participaciones en eventos y grupos. ¿Estás seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar permanentemente'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient().dio.delete('/users/me');
      await ref.read(authProvider.notifier).logout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickCustomPhoto() async {    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,   // tamaño óptimo para avatar circular
      maxHeight: 256,
      imageQuality: 85,
    );
    if (picked == null) return;

    // Copiar a directorio de documentos para persistencia
    final appDir = await getApplicationDocumentsDirectory();
    final dest = File('${appDir.path}/avatar_custom.jpg');
    await File(picked.path).copy(dest.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatar_custom_photo', dest.path);
    await prefs.setInt('avatar_index', AppConstants.avatarCustomPhoto);

    if (mounted) {
      setState(() {
        _customPhotoPath = dest.path;
        _selectedAvatar = AppConstants.avatarCustomPhoto;
      });
    }
  }

  Future<void> _becomeOrganizer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Convertirte en organizador'),
        content: const Text(
          'Podrás crear y gestionar tus propios eventos. '
          'Este cambio es permanente (solo un admin puede revertirlo).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final client = ApiClient();
      await client.dio.post('/users/me/become-organizer');
      await ref.read(authProvider.notifier).checkSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ahora eres organizador. Ya puedes crear eventos.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _changePassword() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña actual',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña',
                  helperText: 'Mínimo 12 caracteres',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.length < 12) ? 'Mínimo 12 caracteres' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context);
              try {
                final client = ApiClient();
                await client.dio.post('/users/me/change-password', data: {
                  'current_password': currentCtrl.text,
                  'new_password': newCtrl.text,
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contraseña actualizada')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final authState = ref.watch(authProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rol actual
            if (user != null)
              Row(
                children: [
                  const Icon(Icons.badge_outlined, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      user.role == 'admin'
                          ? 'Administrador'
                          : user.role == 'organizer'
                              ? 'Organizador'
                              : 'Asistente',
                    ),
                    avatar: Icon(
                      user.role == 'admin'
                          ? Icons.shield_outlined
                          : user.role == 'organizer'
                              ? Icons.manage_accounts_outlined
                              : Icons.person_outlined,
                      size: 16,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            if (user != null) const SizedBox(height: 16),
            // Selector de avatar
            Text('Avatar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            // Foto personalizada — slot especial al inicio
            Row(
              children: [
                // Slot de foto personalizada
                GestureDetector(
                  onTap: _pickCustomPhoto,
                  child: Tooltip(
                    message: 'Subir foto',
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: _selectedAvatar == AppConstants.avatarCustomPhoto
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              )
                            : Border.all(
                                color: Theme.of(context).colorScheme.outline,
                                width: 1.5,
                              ),
                      ),
                      child: ClipOval(
                        child: _customPhotoPath != null &&
                                File(_customPhotoPath!).existsSync()
                            ? Image.file(
                                File(_customPhotoPath!),
                                fit: BoxFit.cover,
                                width: 56,
                                height: 56,
                              )
                            : Icon(
                                Icons.add_a_photo_outlined,
                                size: 24,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedAvatar == AppConstants.avatarCustomPhoto
                        ? 'Foto personalizada activa'
                        : 'Toca para subir tu foto',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Grid de avatares predefinidos
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(AppConstants.avatarCount, (i) {
                final isSelected = _selectedAvatar == i;
                return Tooltip(
                  message: _avatarLabels[i],
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedAvatar = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _avatarColors[i],
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              )
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _avatarColors[i].withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(_avatarIcons[i], color: Colors.white, size: 26),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // Datos personales
            Text('Datos personales', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono (opcional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _changePassword,
              icon: const Icon(Icons.lock_outlined),
              label: const Text('Cambiar contraseña'),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Ajustes de tema
            Text('Tema', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('Auto'),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Claro'),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Oscuro'),
                ),
                ButtonSegment(
                  value: AppThemeMode.custom,
                  icon: Icon(Icons.palette),
                  label: Text('Custom'),
                ),
              ],
              selected: {themeState.mode},
              onSelectionChanged: (s) {
                ref.read(themeProvider.notifier).setMode(s.first);
              },
            ),

            // Selector de paleta — solo visible en modo Custom
            if (themeState.mode == AppThemeMode.custom) ...[
              const SizedBox(height: 16),
              Text(
                'Paleta de colores',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(kPalettes.length, (i) {
                  final palette = kPalettes[i];
                  final isSelected = themeState.paletteIndex == i;
                  return GestureDetector(
                    onTap: () => ref.read(themeProvider.notifier).setPalette(i),
                    child: Tooltip(
                      message: palette.name,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              palette.primary,
                              palette.secondary,
                              palette.accent,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: isSelected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 3,
                                )
                              : Border.all(
                                  color: Colors.transparent,
                                  width: 3,
                                ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: palette.primary.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 22)
                            : null,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                kPalettes[themeState.paletteIndex.clamp(0, kPalettes.length - 1)].name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // Convertirse en organizador (solo para rol "user")
            if (ref.watch(authProvider) case AuthAuthenticated(user: final u)
                when u.role == 'user') ...[
              Text('Cuenta', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '¿Quieres organizar eventos?',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Cambia tu rol a Organizador para crear y gestionar tus propios eventos.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _becomeOrganizer,
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Convertirme en organizador'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
            ],

            // Panel de administración — solo visible para admins
            if (ref.watch(authProvider) case AuthAuthenticated(user: final u)
                when u.role == 'admin') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                  onPressed: () => context.push('/admin'),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Panel de administración'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Cerrar sesión
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => ref.read(authProvider.notifier).logout(),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ),
            const SizedBox(height: 12),
            // Eliminar cuenta (GDPR)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
                onPressed: () => _deleteAccount(),
                child: const Text('Eliminar mi cuenta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
