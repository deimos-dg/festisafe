import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../data/services/event_service.dart';
import '../../data/services/group_service.dart';
import '../../data/services/api_client.dart';
import '../../data/models/group_member.dart';

/// Pantalla de participantes con toggle:
/// - Organizador: ve TODOS los participantes del evento
/// - Miembro con grupo: puede alternar entre "Mi grupo" y "Todos"
/// - Miembro sin grupo: ve todos los participantes
class ParticipantsScreen extends ConsumerStatefulWidget {
  final String eventId;
  const ParticipantsScreen({super.key, required this.eventId});

  @override
  ConsumerState<ParticipantsScreen> createState() => _ParticipantsScreenState();
}

class _ParticipantsScreenState extends ConsumerState<ParticipantsScreen> {
  // true = ver solo mi grupo, false = ver todos
  bool _showMyGroupOnly = false;

  List<_ParticipantItem> _allParticipants = [];
  List<GroupMemberModel> _myGroupMembers = [];
  String? _myGroupId;
  String? _myGroupName;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ApiClient();

      // Cargar todos los participantes del evento
      final eventService = EventService();
      final rawParticipants = await eventService.getParticipants(widget.eventId);
      _allParticipants = rawParticipants
          .map((p) => _ParticipantItem(
                userId: p['user_id'] as String,
                name: p['name'] as String? ?? '',
                role: p['role'] as String? ?? 'user',
              ))
          .toList();

      // Intentar cargar mi grupo (puede no existir)
      try {
        final groupRes = await client.dio.get('/groups/my/${widget.eventId}');
        _myGroupId = groupRes.data['group_id'] as String?;
        _myGroupName = groupRes.data['name'] as String?;

        if (_myGroupId != null) {
          _myGroupMembers =
              await GroupService().getMembers(_myGroupId!);
          // Si tengo grupo, empezar mostrando solo el grupo
          _showMyGroupOnly = true;
        }
      } catch (_) {
        // Sin grupo — mostrar todos
        _myGroupId = null;
        _showMyGroupOnly = false;
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ParticipantItem> get _displayList {
    if (_showMyGroupOnly && _myGroupMembers.isNotEmpty) {
      // Convertir GroupMemberModel a _ParticipantItem
      return _myGroupMembers
          .map((m) => _ParticipantItem(
                userId: m.userId,
                name: m.name,
                role: m.isAdmin ? 'group_admin' : 'member',
              ))
          .toList();
    }
    return _allParticipants;
  }

  bool get _isOrganizer {
    final auth = ref.read(authProvider);
    return auth is AuthAuthenticated && auth.user.isOrganizer;
  }

  @override
  Widget build(BuildContext context) {
    final hasGroup = _myGroupId != null;
    final displayList = _displayList;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showMyGroupOnly && hasGroup
            ? (_myGroupName ?? 'Mi grupo')
            : 'Todos los participantes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : Column(
                  children: [
                    // Toggle — solo visible si el usuario tiene grupo
                    if (hasGroup || _isOrganizer)
                      _ToggleBar(
                        showMyGroup: _showMyGroupOnly,
                        hasGroup: hasGroup,
                        groupName: _myGroupName,
                        allCount: _allParticipants.length,
                        groupCount: _myGroupMembers.length,
                        onToggle: (val) => setState(() => _showMyGroupOnly = val),
                      ),

                    // Contador
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.people_outline,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            '${displayList.length} ${displayList.length == 1 ? 'persona' : 'personas'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),

                    // Lista
                    Expanded(
                      child: displayList.isEmpty
                          ? const Center(
                              child: Text('No hay participantes aún'),
                            )
                          : ListView.builder(
                              itemCount: displayList.length,
                              itemBuilder: (_, i) {
                                final p = displayList[i];
                                return _ParticipantTile(participant: p);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle bar
// ---------------------------------------------------------------------------
class _ToggleBar extends StatelessWidget {
  final bool showMyGroup;
  final bool hasGroup;
  final String? groupName;
  final int allCount;
  final int groupCount;
  final ValueChanged<bool> onToggle;

  const _ToggleBar({
    required this.showMyGroup,
    required this.hasGroup,
    required this.groupName,
    required this.allCount,
    required this.groupCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.group, size: 16),
            label: Text(
              hasGroup ? (groupName ?? 'Mi grupo') : 'Mi grupo',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.people, size: 16),
            label: Text('Todos ($allCount)'),
          ),
        ],
        selected: {showMyGroup},
        onSelectionChanged: (s) => onToggle(s.first),
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de participante
// ---------------------------------------------------------------------------
class _ParticipantTile extends StatelessWidget {
  final _ParticipantItem participant;
  const _ParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    final isGroupAdmin = participant.role == 'group_admin';
    final isOrganizer = participant.role == 'organizer';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isOrganizer
            ? Theme.of(context).colorScheme.primaryContainer
            : isGroupAdmin
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          participant.initials,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isOrganizer
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      title: Text(participant.name),
      trailing: _RoleChip(role: participant.role),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'organizer' => ('Organizador', Colors.blue),
      'group_admin' => ('Admin grupo', Colors.purple),
      _ => ('Asistente', Colors.grey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo interno
// ---------------------------------------------------------------------------
class _ParticipantItem {
  final String userId;
  final String name;
  final String role;

  const _ParticipantItem({
    required this.userId,
    required this.name,
    required this.role,
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
