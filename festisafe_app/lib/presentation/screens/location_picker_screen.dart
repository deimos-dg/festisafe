import 'dart:async';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Resultado de la selección de ubicación.
class LocationPickerResult {
  final double latitude;
  final double longitude;
  final String displayName; // nombre legible devuelto por Nominatim

  const LocationPickerResult({
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });
}

/// Pantalla de selección de ubicación con:
/// - Búsqueda por texto (Nominatim / OpenStreetMap — sin API key)
/// - Mapa interactivo donde el usuario puede tocar para fijar el pin
/// - Botón "Usar mi ubicación actual" (opcional)
class LocationPickerScreen extends StatefulWidget {
  /// Posición inicial del mapa. Si es null, centra en Madrid.
  final LatLng? initialPosition;

  const LocationPickerScreen({super.key, this.initialPosition});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _dio = Dio(BaseOptions(
    baseUrl: 'https://nominatim.openstreetmap.org',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      // Nominatim requiere un User-Agent identificable
      'User-Agent': 'FestiSafe/1.0 (festisafe@example.com)',
      'Accept-Language': 'es',
    },
  ));

  LatLng? _selectedPin;
  String _selectedName = '';
  List<_SearchResult> _searchResults = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedPin = widget.initialPosition;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Búsqueda con debounce de 600ms
  // -------------------------------------------------------------------------

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final res = await _dio.get('/search', queryParameters: {
        'q': query,
        'format': 'json',
        'limit': 5,
        'addressdetails': 1,
      });
      final list = (res.data as List<dynamic>).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _searchResults = list.map(_SearchResult.fromJson).toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectResult(_SearchResult result) {
    final pos = LatLng(result.lat, result.lng);
    setState(() {
      _selectedPin = pos;
      _selectedName = result.displayName;
      _searchResults = [];
      _searchCtrl.text = result.shortName;
    });
    _searchFocus.unfocus();
    _mapController.move(pos, 15);
  }

  // -------------------------------------------------------------------------
  // Tap en el mapa para fijar pin manualmente
  // -------------------------------------------------------------------------

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _selectedPin = point;
      _selectedName = '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    });
    // Reverse geocoding para obtener el nombre del lugar
    _reverseGeocode(point);
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final res = await _dio.get('/reverse', queryParameters: {
        'lat': point.latitude,
        'lon': point.longitude,
        'format': 'json',
      });
      final data = res.data as Map<String, dynamic>;
      final name = data['display_name'] as String? ?? '';
      if (mounted && name.isNotEmpty) {
        setState(() => _selectedName = name);
      }
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Confirmar selección
  // -------------------------------------------------------------------------

  void _confirm() {
    if (_selectedPin == null) return;
    Navigator.of(context).pop(LocationPickerResult(
      latitude: _selectedPin!.latitude,
      longitude: _selectedPin!.longitude,
      displayName: _selectedName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialPosition ?? const LatLng(19.4326, -99.1332); // CDMX por defecto

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar ubicación'),
        actions: [
          if (_selectedPin != null)
            TextButton(
              onPressed: _confirm,
              child: const Text('Confirmar'),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Mapa
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPin ?? initial,
              initialZoom: _selectedPin != null ? 15 : 5,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.festisafe.festisafe',
              ),
              if (_selectedPin != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPin!,
                      width: 48,
                      height: 56,
                      child: const _PinMarker(),
                    ),
                  ],
                ),
            ],
          ),

          // Barra de búsqueda + resultados
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // Campo de búsqueda
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar lugar (ej: Tomorrowland, Boom)',
                      prefixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchResults = []);
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),

                // Lista de resultados
                if (_searchResults.isNotEmpty)
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _searchResults[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined,
                                size: 20),
                            title: Text(r.shortName,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(r.country,
                                style: const TextStyle(fontSize: 11)),
                            onTap: () => _selectResult(r),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Panel inferior con coordenadas seleccionadas
          if (_selectedPin != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedName.isNotEmpty
                                  ? _selectedName
                                  : 'Ubicación seleccionada',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_selectedPin!.latitude.toStringAsFixed(6)}, ${_selectedPin!.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _confirm,
                          icon: const Icon(Icons.check),
                          label: const Text('Confirmar esta ubicación'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Hint cuando no hay pin
          if (_selectedPin == null)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Busca un lugar o toca el mapa para fijar la ubicación',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marcador de pin rojo
// ---------------------------------------------------------------------------
class _PinMarker extends StatelessWidget {
  const _PinMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.location_on, color: Colors.white, size: 18),
        ),
        // Punta del pin
        CustomPaint(
          size: const Size(12, 8),
          painter: _PinTailPainter(),
        ),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.red;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ---------------------------------------------------------------------------
// Modelo de resultado de búsqueda Nominatim
// ---------------------------------------------------------------------------
class _SearchResult {
  final double lat;
  final double lng;
  final String displayName;
  final String shortName;
  final String country;

  const _SearchResult({
    required this.lat,
    required this.lng,
    required this.displayName,
    required this.shortName,
    required this.country,
  });

  factory _SearchResult.fromJson(Map<String, dynamic> json) {
    final address = json['address'] as Map<String, dynamic>? ?? {};
    final name = json['name'] as String? ??
        json['display_name'] as String? ??
        '';
    final city = address['city'] as String? ??
        address['town'] as String? ??
        address['village'] as String? ??
        '';
    final country = address['country'] as String? ?? '';

    return _SearchResult(
      lat: double.parse(json['lat'] as String),
      lng: double.parse(json['lon'] as String),
      displayName: json['display_name'] as String? ?? name,
      shortName: city.isNotEmpty ? '$name, $city' : name,
      country: country,
    );
  }
}
