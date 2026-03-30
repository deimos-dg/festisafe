import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/event_provider.dart';
import '../screens/location_picker_screen.dart';

/// Formulario reutilizable de creación de evento.
/// Usado tanto en HomeScreen como en OrganizerDashboardScreen.
class CreateEventForm extends ConsumerStatefulWidget {
  final VoidCallback? onCreated;
  const CreateEventForm({super.key, this.onCreated});

  @override
  ConsumerState<CreateEventForm> createState() => _CreateEventFormState();
}

class _CreateEventFormState extends ConsumerState<CreateEventForm> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController(text: '500');
  final _formKey = GlobalKey<FormState>();

  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  DateTime _endDate = DateTime.now().add(const Duration(days: 2));

  double? _lat;
  double? _lng;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialPosition: null,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
        // Usar el nombre del lugar como location_name si el campo está vacío
        if (_locationCtrl.text.trim().isEmpty) {
          // Tomar solo la primera parte del nombre (antes de la primera coma)
          _locationCtrl.text = result.displayName.split(',').first.trim();
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(eventServiceProvider).createEvent({
        'name': _nameCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        'location_name': _locationCtrl.text.trim(),
        if (_lat != null) 'latitude': _lat,
        if (_lng != null) 'longitude': _lng,
        'max_participants': int.parse(_capacityCtrl.text),
        'starts_at': _startDate.toIso8601String(),
        'ends_at': _endDate.toIso8601String(),
      });
      ref.invalidate(myEventsProvider);
      widget.onCreated?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al crear evento: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nombre
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre del evento',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.festival_outlined),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),

          // Descripción
          TextFormField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // Ubicación — campo de texto + botón de mapa
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _locationCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nombre del lugar',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    // Indicador visual de que hay coordenadas seleccionadas
                    suffixIcon: _lat != null
                        ? const Tooltip(
                            message: 'Coordenadas seleccionadas',
                            child: Icon(Icons.check_circle,
                                color: Colors.green, size: 20),
                          )
                        : null,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
              ),
              const SizedBox(width: 8),
              // Botón para abrir el mapa
              Tooltip(
                message: 'Seleccionar en mapa',
                child: InkWell(
                  onTap: _pickLocation,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _lat != null
                            ? Colors.green
                            : Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: _lat != null
                          ? Colors.green.withValues(alpha: 0.08)
                          : null,
                    ),
                    child: Icon(
                      Icons.map_outlined,
                      color: _lat != null
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Coordenadas seleccionadas (informativo)
          if (_lat != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed, size: 12, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 11, color: Colors.green),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() {
                      _lat = null;
                      _lng = null;
                    }),
                    child: const Text(
                      'Quitar',
                      style: TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Capacidad
          TextFormField(
            controller: _capacityCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Capacidad máxima',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.people_outlined),
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 1) return 'Número válido requerido';
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Fecha inicio
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('Inicio: ${_fmtDate(_startDate)}'),
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (p != null) {
                  setState(() {
                    _startDate = p;
                    if (_endDate.isBefore(_startDate)) {
                      _endDate = _startDate.add(const Duration(days: 1));
                    }
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 8),

          // Fecha fin
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text('Fin: ${_fmtDate(_endDate)}'),
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: _endDate.isAfter(_startDate)
                      ? _endDate
                      : _startDate.add(const Duration(days: 1)),
                  firstDate: _startDate,
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (p != null) setState(() => _endDate = p);
              },
            ),
          ),
          const SizedBox(height: 20),

          // Botón crear
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add),
              label: const Text('Crear evento'),
            ),
          ),
        ],
      ),
    );
  }
}
