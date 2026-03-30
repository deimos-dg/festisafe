import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Marcador del punto de encuentro en el mapa.
class MeetingPointMarker extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? name;

  const MeetingPointMarker({
    super.key,
    required this.latitude,
    required this.longitude,
    this.name,
  });

  void _openMaps(BuildContext context) async {
    final label = Uri.encodeComponent(name ?? 'Punto de encuentro');
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&destination_place_id=$label',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la app de mapas')),
        );
      }
    }
  }

  void _showPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.green, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name ?? 'Punto de encuentro',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openMaps(context);
                },
                icon: const Icon(Icons.directions),
                label: const Text('Cómo llegar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPanel(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.flag, color: Colors.white, size: 20),
          ),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.green.shade700,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Encuentro',
              style: TextStyle(color: Colors.white, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}
