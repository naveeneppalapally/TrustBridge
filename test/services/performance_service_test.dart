import 'package:flutter_test/flutter_test.dart';
import 'package:trustbridge_app/services/performance_service.dart';

void main() {
  group('PerformanceService', () {
    test('is a singleton', () {
      final a = PerformanceService();
      final b = PerformanceService();
      expect(identical(a, b), isTrue);
    });

    test('traceOperation completes without error', () async {
      final service = PerformanceService();
      final result = await service.traceOperation<int>(
        'test_trace_operation',
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 42;
        },
      );
      expect(result, 42);
    });

    test('startTrace and stopTrace are safe in test mode', () async {
      final service = PerformanceService();
      final trace = await service.startTrace('test_manual_trace');
      await service.setMetric(trace, 'sample_metric', 1);
      await service.incrementMetric(trace, 'sample_metric', 2);
      await service.setAttribute(trace, 'sample_attr', 'ok');
      await service.stopTrace(trace);
      expect(trace.name, 'test_manual_trace');
    });
  });
}
