import 'package:flutter/material.dart';
import '../../data/models/member_location.dart';

const _memberColor = Color(0xFF7B2FBE); // Morado festival

/// Marcador de un miembro del grupo en el mapa.
/// Muestra avatar (si disponible) o iniciales, con estado visual según inactividad.
class MemberMarker extends StatelessWidget {
  final MemberLocation member;
  final bool isSelf;
  final VoidCallback? onTap;

  const MemberMarker({
    super.key,
    required this.member,
    this.isSelf = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final state = member.markerState;
    final opacity = state == MarkerState.dimmed
        ? 0.5
        : state == MarkerState.noSignal
            ? 0.3
            : 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelf
                        ? Colors.blue
                        : _memberColor,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: member.avatarIndex != null
                      ? ClipOval(
                          child: _AvatarImage(index: member.avatarIndex!),
                        )
                      : Center(
                          child: Text(
                            member.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                ),
                // Indicador de estado
                if (state == MarkerState.dimmed)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orange,
                      ),
                      child: const Icon(Icons.access_time, size: 10, color: Colors.white),
                    ),
                  ),
                if (state == MarkerState.noSignal)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey,
                      ),
                      child: const Icon(Icons.signal_wifi_off, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            // Nombre
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                member.name.split(' ').first,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Imagen de avatar prediseñado por índice.
class _AvatarImage extends StatelessWidget {
  final int index;
  const _AvatarImage({required this.index});

  static const _colors = [
    Colors.purple, Colors.orange, Colors.green, Colors.blue,
    Colors.red, Colors.pink, Colors.teal, Colors.amber,
    Colors.indigo, Colors.cyan, Colors.lime, Colors.deepOrange,
  ];

  static const _icons = [
    Icons.star, Icons.favorite, Icons.bolt, Icons.local_fire_department,
    Icons.music_note, Icons.sports_soccer, Icons.pets, Icons.eco,
    Icons.diamond, Icons.rocket_launch, Icons.emoji_events, Icons.celebration,
  ];

  @override
  Widget build(BuildContext context) {
    final i = index.clamp(0, 11);
    return Container(
      color: _colors[i],
      child: Icon(_icons[i], color: Colors.white, size: 22),
    );
  }
}
