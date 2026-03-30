/// IT-01: Health checks del backend
library;

import 'package:flutter_test/flutter_test.dart';
import 'integration_helper.dart';

void main() {
  final dio = buildDio();

  group('IT-01 Health', () {
    test('GET /health/ retorna 200 y status ok', () async {
      final res = await dio.get(
        'http://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/health/',
      );
      expect(res.statusCode, 200);
      expect(res.data['status'], 'ok');
      expect(res.data['version'], isNotEmpty);
    });

    test('GET /health/db retorna 200 y BD conectada', () async {
      final res = await dio.get(
        'http://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/health/db',
      );
      expect(res.statusCode, 200);
      expect(res.data['status'], 'healthy');
    });
  });
}
