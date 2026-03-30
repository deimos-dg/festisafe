import 'package:flutter/material.dart';

/// Paleta de colores predefinida para el modo personalizado.
class ColorPalette {
  final String name;
  final Color primary;
  final Color secondary;
  final Color accent;

  const ColorPalette({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.accent,
  });
}

/// Las 6 paletas predefinidas de FestiSafe.
const List<ColorPalette> kPalettes = [
  ColorPalette(
    name: 'Azul marino',
    primary: Color(0xFF0D1B4B),
    secondary: Color(0xFF1A3A6B),
    accent: Color(0xFF2962FF),
  ),
  ColorPalette(
    name: 'Naranja energía',
    primary: Color(0xFFFF6B35),
    secondary: Color(0xFFFF8C5A),
    accent: Color(0xFFFFCC02),
  ),
  ColorPalette(
    name: 'Verde naturaleza',
    primary: Color(0xFF2D9B4E),
    secondary: Color(0xFF4CAF50),
    accent: Color(0xFF8BC34A),
  ),
  ColorPalette(
    name: 'Azul noche',
    primary: Color(0xFF1A3A6B),
    secondary: Color(0xFF2962FF),
    accent: Color(0xFF40C4FF),
  ),
  ColorPalette(
    name: 'Rojo fuego',
    primary: Color(0xFFD32F2F),
    secondary: Color(0xFFE53935),
    accent: Color(0xFFFF6D00),
  ),
  ColorPalette(
    name: 'Rosa neón',
    primary: Color(0xFFE91E8C),
    secondary: Color(0xFFF06292),
    accent: Color(0xFFFF4081),
  ),
];
