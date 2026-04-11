import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:festisafe_app/app.dart';

void main() {
  testWidgets('App simple load test', (WidgetTester tester) async {
    // Envolvemos la app en un ProviderScope porque usamos Riverpod
    await tester.pumpWidget(
      const ProviderScope(
        child: FestiSafeApp(),
      ),
    );

    // Verificamos que al menos la app se inicialice (sin buscar el contador que ya no existe)
    expect(find.byType(ProviderScope), findsOneWidget);
  });
}
