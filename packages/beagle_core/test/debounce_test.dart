import 'dart:async';

import 'package:beagle_core/beagle_core.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('Debouncer fires once after taps stop', () {
    fakeAsync((async) {
      final d = Debouncer(delay: const Duration(milliseconds: 100));
      var fires = 0;
      void tap() => d.tap(() => fires++);
      tap();
      async.elapse(const Duration(milliseconds: 50));
      tap();
      async.elapse(const Duration(milliseconds: 50));
      tap();
      async.elapse(const Duration(milliseconds: 99));
      expect(fires, 0);
      async.elapse(const Duration(milliseconds: 2));
      expect(fires, 1);
    });
  });

  test('Debouncer respects maxWait under continuous taps', () {
    fakeAsync((async) {
      final d = Debouncer(
        delay: const Duration(milliseconds: 100),
        maxWait: const Duration(milliseconds: 250),
      );
      var fires = 0;
      // Tap every 50ms forever — without maxWait this would never fire.
      // Use Timer (which fakeAsync controls) rather than Future.delayed
      // (which it does too via runZonedGuarded but is less direct here).
      var ticks = 0;
      void schedule() {
        d.tap(() => fires++);
        ticks++;
        if (ticks < 20) {
          Timer(const Duration(milliseconds: 50), schedule);
        }
      }

      schedule();
      async.elapse(const Duration(milliseconds: 300));
      // First tap at t=0, max-wait of 250ms means the action must fire at
      // t≤250ms even though taps keep arriving every 50ms.
      expect(fires, greaterThan(0));
    });
  });
}
