import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/group_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ws_provider.dart';
import '../../data/models/group_member.dart';
import '../../data/services/group_service.dart';
import '../../data/services/api_client.dart';
import '../../core/constants.dart';
import 'chat_screen.dart';

class GroupScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  List<_JoinRequest> _pendingRequests = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    Future.microtask(() async {
      await ref.read(groupProvider.notifier).loadMembers(widget.groupId);
      if (_isAdmin) _loadPendingRequests();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String? get _currentUserId {
    final auth = ref.read(authProvider);
    if (auth is AuthAuthenticated) return auth.user.id;
    if (auth is AuthGuest) return auth.user.id;
    return null;
  }

  bool get _isAdmin {
    final group = ref.read(groupProvider).group;
    if (group == null) return false;
    final me = group.members.where((m) => m.userId == _currentUserId).firstOrNull;
    return me?.isAdmin ?? false;
  }

  Future<void> _loadPendingRequests() async {
    if (!_isAdmin) return;
    try {
      final res = await ApiClient().dio.get('/groups/${widget.groupId}/requests');
      final list = (res.data as List<dynamic>).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() => _pendingRequests = list.map(_JoinRequest.fromJson).toList());
      }
    } catch (_) {}
  }

  Future<void> _acceptRequest(_JoinRequest req) async {
    try {
      await ApiClient().dio.post(
        '/groups/${widget.groupId}/requests/${req.requestId}/accept',
      );
      setState(() => _pendingRequests.removeWhere((r) => r.requestId == req.requestId));
      await ref.read(groupProvider.notifier).loadMembers(widget.groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${req.userName} fue agregado al grupo')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectRequest(_JoinRequest req) async {
    try {
      await ApiClient().dio.post(
        '/groups/${widget.groupId}/requests/${req.requestId}/reject',
      );
      setState(() => _pendingRequests.removeWhere((r) => r.requestId == req.requestId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Solicitud de ${req.userName} rechazada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showAddMemberDialog() async {
    final userIdCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar miembro'),
        content: TextField(
          controller: userIdCtrl,
          decoration: const InputDecoration(
            labelText: 'ID del usuario',
            hintText: 'UUID del participante del evento',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final id = userIdCtrl.text.trim();
              if (id.isEmpty) return;
              Navigator.pop(context);
              try {
                await GroupService().addMember(widget.groupId, id);
                await ref.read(groupProvider.notifier).loadMembers(widget.groupId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Miembro agregado')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  Future<void> _transferAdmin(GroupMemberModel member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Transferir administración'),
        content: Text('¿Transferir el rol de admin a ${member.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Transferir')),
        ],
      ),
    );
    if (confirm == true) {
      await ref
          .read(groupProvider.notifier)
          .transferAdmin(widget.groupId, member.userId);
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Salir del grupo'),
        content: const Text('¿Estás seguro de que quieres salir del grupo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ref.read(groupProvider.notifier).leaveGroup(widget.groupId);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content:
            const Text('Esta acción no se puede deshacer. ¿Eliminar el grupo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ref.read(groupProvider.notifier).deleteGroup(widget.groupId);
      if (mounted) Navigator.pop(context);
    }
  }

  void _showPendingRequestsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Solicitudes (${_pendingRequests.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        await _loadPendingRequests();
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _pendingRequests.isEmpty
                    ? const Center(child: Text('Sin solicitudes pendientes'))
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: _pendingRequests.length,
                        itemBuilder: (_, i) {
                          final req = _pendingRequests[i];
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(req.userName.isNotEmpty
                                  ? req.userName[0].toUpperCase()
                                  : '?'),
                            ),
                            title: Text(req.userName),
                            subtitle: (req.message != null &&
                                    req.message!.isNotEmpty)
                                ? Text(req.message!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)
                                : const Text('Sin mensaje'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline,
                                      color: Colors.green),
                                  tooltip: 'Aceptar',
                                  onPressed: () async {
                                    await _acceptRequest(req);
                                    setSheetState(() {});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined,
                                      color: Colors.red),
                                  tooltip: 'Rechazar',
                                  onPressed: () async {
                                    await _rejectRequest(req);
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupState = ref.watch(groupProvider);
    final group = groupState.group;

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.name ?? 'Grupo'),
        actions: [
          if (_isAdmin && _pendingRequests.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: 'Solicitudes pendientes',
                  onPressed: _showPendingRequestsSheet,
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        '${_pendingRequests.length}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Agregar miembro',
              onPressed: _showAddMemberDialog,
            ),
          if (_isAdmin)
            PopupMenuButton(
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'delete', child: Text('Eliminar grupo')),
              ],
              onSelected: (v) {
                if (v == 'delete') _deleteGroup();
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Miembros'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
          ],
        ),
      ),
      body: groupState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _MembersTab(
                  members: group?.members ?? [],
                  currentUserId: _currentUserId,
                  isAdmin: _isAdmin,
                  onTransfer: _transferAdmin,
                  onLeave: _leaveGroup,
                ),
                // Chat reutiliza ChatScreen en modo embebido (sin Scaffold)
                ChatScreen(eventId: widget.groupId, embedded: true),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pestaña de miembros
// ---------------------------------------------------------------------------
class _MembersTab extends StatelessWidget {
  final List<GroupMemberModel> members;
  final String? currentUserId;
  final bool isAdmin;
  final void Function(GroupMemberModel) onTransfer;
  final VoidCallback onLeave;

  const _MembersTab({
    required this.members,
    required this.currentUserId,
    required this.isAdmin,
    required this.onTransfer,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                '${members.length}/${AppConstants.maxGroupMembers} miembros',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: members.length,
            itemBuilder: (_, i) {
              final m = members[i];
              final isMe = m.userId == currentUserId;
              return ListTile(
                leading: CircleAvatar(child: Text(m.initials)),
                title: Text('${m.name}${isMe ? ' (tú)' : ''}'),
                subtitle: Text(m.isAdmin ? 'Admin' : 'Miembro'),
                trailing: isAdmin && !isMe
                    ? IconButton(
                        icon: const Icon(Icons.swap_horiz),
                        tooltip: 'Transferir admin',
                        onPressed: () => onTransfer(m),
                      )
                    : null,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: onLeave,
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Salir del grupo'),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo de solicitud de unión
// ---------------------------------------------------------------------------
class _JoinRequest {
  final String requestId;
  final String userId;
  final String userName;
  final String? message;

  const _JoinRequest({
    required this.requestId,
    required this.userId,
    required this.userName,
    this.message,
  });

  factory _JoinRequest.fromJson(Map<String, dynamic> json) => _JoinRequest(
        requestId: json['request_id'] as String,
        userId: json['user_id'] as String,
        userName: json['user_name'] as String,
        message: json['message'] as String?,
      );
}
