import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream del nivel de batería actualizado cada 30 segundos.
final batteryProvider = StreamProvider<int>((ref) async* {
  final battery = Battery();

  // Emitir nivel inicial
  yield await battery.batteryLevel;

  // Actualizar cada 30 segundos
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    yield await battery.batteryLevel;
  }
});
