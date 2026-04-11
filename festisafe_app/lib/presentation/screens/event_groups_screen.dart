import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/api_client.dart';
import '../../providers/auth_provider.dart';

/// Pantalla que lista los grupos disponibles de un evento.
/// Permite al usuario enviar una solicitud de unión con mensaje opcional.
class EventGroupsScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventGroupsScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventGroupsScreen> createState() => _EventGroupsScreenState();
}

class _EventGroupsScreenState extends ConsumerState<EventGroupsScreen> {
  List<_GroupItem> _groups = [];
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
      final res = await ApiClient().dio.get(
        '/groups/event/${widget.eventId}/available',
      );
      final list = (res.data as List<dynamic>).cast<Map<String, dynamic>>();
      setState(() {
        _groups = list.map(_GroupItem.fromJson).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestJoin(_GroupItem group) async {
    // Pedir mensaje opcional
    final msgCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Unirse a "${group.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${group.memberCount}/${group.maxMembers} miembros',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msgCtrl,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Mensaje para el admin (opcional)',
                hintText: 'Ej: Hola, vengo con mis amigos',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient().dio.post(
        '/groups/${group.groupId}/request-join',
        queryParameters: {
          if (msgCtrl.text.trim().isNotEmpty) 'message': msgCtrl.text.trim(),
        },
      );
      // Actualizar estado local
      setState(() {
        final idx = _groups.indexWhere((g) => g.groupId == group.groupId);
        if (idx != -1) {
          _groups[idx] = _groups[idx].copyWith(hasPendingRequest: true);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Solicitud enviada al admin de "${group.name}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = _parseError(e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _parseError(String e) {
    if (e.contains('400')) return 'Ya tienes una solicitud pendiente para este grupo.';
    if (e.contains('403')) return 'El grupo está lleno o cerrado.';
    return 'Error al enviar la solicitud.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grupos del evento'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _groups.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_off, size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('No hay grupos disponibles en este evento'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _groups.length,
                      itemBuilder: (_, i) {
                        final g = _groups[i];
                        return _GroupCard(
                          group: g,
                          onJoin: () => _requestJoin(g),
                          onView: g.isMember
                              ? () => context.push('/groups/${g.groupId}')
                              : null,
                        );
                      },
                    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card de grupo
// ---------------------------------------------------------------------------
class _GroupCard extends StatelessWidget {
  final _GroupItem group;
  final VoidCallback onJoin;
  final VoidCallback? onView;

  const _GroupCard({
    required this.group,
    required this.onJoin,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final isFull = group.isFull;
    final isMember = group.isMember;
    final hasPending = group.hasPendingRequest;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.people_outline,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '${group.memberCount}/${group.maxMembers}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          if (isFull)
                            _StatusChip(label: 'Lleno', color: Colors.red),
                          if (isMember)
                            _StatusChip(label: 'Tu grupo', color: Colors.green),
                          if (hasPending && !isMember)
                            _StatusChip(
                                label: 'Solicitud enviada',
                                color: Colors.orange),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (isMember && onView != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.group, size: 16),
                      label: const Text('Ver mi grupo'),
                    ),
                  )
                else if (!isMember && !hasPending && !isFull)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onJoin,
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: const Text('Solicitar unirse'),
                    ),
                  )
                else if (hasPending)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: null, // deshabilitado mientras espera
                      icon: const Icon(Icons.hourglass_empty, size: 16),
                      label: const Text('Esperando respuesta…'),
                    ),
                  )
                else if (isFull)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.block, size: 16),
                      label: const Text('Grupo lleno'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo interno
// ---------------------------------------------------------------------------
class _GroupItem {
  final String groupId;
  final String name;
  final int memberCount;
  final int maxMembers;
  final bool isMember;
  final bool hasPendingRequest;

  const _GroupItem({
    required this.groupId,
    required this.name,
    required this.memberCount,
    required this.maxMembers,
    required this.isMember,
    required this.hasPendingRequest,
  });

  bool get isFull => memberCount >= maxMembers;

  factory _GroupItem.fromJson(Map<String, dynamic> json) => _GroupItem(
        groupId: json['group_id'] as String,
        name: json['name'] as String,
        memberCount: json['member_count'] as int? ?? 0,
        maxMembers: json['max_members'] as int? ?? 8,
        isMember: json['is_member'] as bool? ?? false,
        hasPendingRequest: json['has_pending_request'] as bool? ?? false,
      );

  _GroupItem copyWith({bool? hasPendingRequest}) => _GroupItem(
        groupId: groupId,
        name: name,
        memberCount: memberCount,
        maxMembers: maxMembers,
        isMember: isMember,
        hasPendingRequest: hasPendingRequest ?? this.hasPendingRequest,
      );
}
