import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/api_client.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _events = [];
  bool _loadingStats = true;
  bool _loadingUsers = true;
  bool _loadingEvents = true;
  String _userSearch = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadStats();
    _loadUsers();
    _loadEvents();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final res = await ApiClient().dio.get('/admin/stats');
      if (mounted) setState(() => _stats = res.data as Map<String, dynamic>);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _loadUsers({String? q}) async {
    setState(() => _loadingUsers = true);
    try {
      final res = await ApiClient().dio.get('/admin/users', queryParameters: {
        'limit': 100,
        if (q != null && q.isNotEmpty) 'q': q,
      });
      if (mounted) {
        setState(() => _users = (res.data as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _loadingEvents = true);
    try {
      final res = await ApiClient().dio.get('/admin/events', queryParameters: {'limit': 100});
      if (mounted) {
        setState(() => _events = (res.data as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  Future<void> _toggleUser(Map<String, dynamic> user) async {
    final isActive = user['is_active'] as bool;
    final userId = user['id'] as String;
    try {
      await ApiClient().dio.patch(
        '/admin/users/$userId/${isActive ? 'deactivate' : 'activate'}',
      );
      _loadUsers(q: _userSearch.isNotEmpty ? _userSearch : null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _unlockUser(String userId) async {
    try {
      await ApiClient().dio.patch('/admin/users/$userId/unlock');
      _loadUsers(q: _userSearch.isNotEmpty ? _userSearch : null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario desbloqueado')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de administración'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Stats'),
            Tab(icon: Icon(Icons.people), text: 'Usuarios'),
            Tab(icon: Icon(Icons.festival), text: 'Eventos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _StatsTab(stats: _stats, loading: _loadingStats),
          _UsersTab(
            users: _users,
            loading: _loadingUsers,
            onSearch: (q) {
              _userSearch = q;
              _loadUsers(q: q.isNotEmpty ? q : null);
            },
            onToggle: _toggleUser,
            onUnlock: _unlockUser,
          ),
          _EventsTab(events: _events, loading: _loadingEvents),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab de estadísticas
// ---------------------------------------------------------------------------
class _StatsTab extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final bool loading;
  const _StatsTab({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (stats == null) return const Center(child: Text('Sin datos'));

    final items = [
      ('Usuarios totales', stats!['total_users'], Icons.people, Colors.blue),
      ('Usuarios activos', stats!['active_users'], Icons.check_circle, Colors.green),
      ('Cuentas bloqueadas', stats!['locked_users'], Icons.lock, Colors.orange),
      ('Eventos totales', stats!['total_events'], Icons.festival, Colors.purple),
      ('Eventos activos', stats!['active_events'], Icons.play_circle, Colors.teal),
      ('SOS activos', stats!['active_sos'], Icons.sos, Colors.red),
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final (label, value, icon, color) = items[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab de usuarios
// ---------------------------------------------------------------------------
class _UsersTab extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final bool loading;
  final void Function(String) onSearch;
  final void Function(Map<String, dynamic>) onToggle;
  final void Function(String) onUnlock;

  const _UsersTab({
    required this.users,
    required this.loading,
    required this.onSearch,
    required this.onToggle,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre o email',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: onSearch,
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : users.isEmpty
                  ? const Center(child: Text('Sin usuarios'))
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final isActive = u['is_active'] as bool? ?? false;
                        final isLocked = u['is_locked'] as bool? ?? false;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isActive
                                ? Colors.green.shade100
                                : Colors.grey.shade200,
                            child: Text(
                              (u['name'] as String? ?? '?')[0].toUpperCase(),
                            ),
                          ),
                          title: Text(u['name'] as String? ?? ''),
                          subtitle: Text(u['email'] as String? ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isLocked)
                                IconButton(
                                  icon: const Icon(Icons.lock_open,
                                      color: Colors.orange),
                                  tooltip: 'Desbloquear',
                                  onPressed: () => onUnlock(u['id'] as String),
                                ),
                              IconButton(
                                icon: Icon(
                                  isActive
                                      ? Icons.block
                                      : Icons.check_circle_outline,
                                  color: isActive ? Colors.red : Colors.green,
                                ),
                                tooltip: isActive ? 'Desactivar' : 'Activar',
                                onPressed: () => onToggle(u),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab de eventos
// ---------------------------------------------------------------------------
class _EventsTab extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final bool loading;
  const _EventsTab({required this.events, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (events.isEmpty) return const Center(child: Text('Sin eventos'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: events.length,
      itemBuilder: (_, i) {
        final e = events[i];
        final isActive = e['is_active'] as bool? ?? false;
        final count = e['participant_count'] as int? ?? 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isActive
                  ? Colors.green.shade100
                  : Colors.grey.shade200,
              child: Icon(
                Icons.festival,
                color: isActive ? Colors.green : Colors.grey,
              ),
            ),
            title: Text(e['name'] as String? ?? ''),
            subtitle: Text('$count participantes · ${isActive ? 'Activo' : 'Inactivo'}'),
            trailing: Chip(
              label: Text(isActive ? 'Activo' : 'Inactivo'),
              backgroundColor: isActive
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.grey.withValues(alpha: 0.12),
            ),
          ),
        );
      },
    );
  }
}
