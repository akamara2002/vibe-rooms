import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:vibe_rooms/features/player/domain/server_clock.dart';

final _base = DateTime.utc(2026, 11, 18, 12);

/// A world with a true time, a device clock that is off by [deviceSkew] and a
/// `server_now()` whose legs are [up] and [down] long.
class _World {
  _World(this.async, {this.deviceSkew = Duration.zero});

  final FakeAsync async;
  Duration deviceSkew;
  int calls = 0;
  bool failing = false;

  /// Per call: (time to reach the server, time to come back).
  List<(int, int)> legs = [(20, 20)];

  DateTime trueNow() => _base.add(async.elapsed);
  DateTime deviceNow() => trueNow().add(deviceSkew);

  Future<DateTime> fetch() async {
    final (up, down) = legs[calls % legs.length];
    calls++;
    await Future<void>.delayed(Duration(milliseconds: up));
    if (failing) throw StateError('offline');
    final server = trueNow();
    await Future<void>.delayed(Duration(milliseconds: down));
    return server;
  }

  ServerClock clock({int samples = 5}) =>
      ServerClock(fetchServerNow: fetch, localNow: deviceNow, samples: samples);
}

Future<bool> _measure(FakeAsync async, ServerClock clock) {
  final future = clock.measure();
  async.elapse(const Duration(seconds: 30));
  async.flushMicrotasks();
  return future;
}

void main() {
  test('keeps the sample with the smallest round trip', () {
    fakeAsync((async) {
      final world = _World(async);
      // Only the third sample is symmetric (and fastest); the others are
      // lopsided, so using any of them would be off by tens of milliseconds.
      world.legs = [(180, 20), (160, 40), (10, 10), (20, 140), (90, 10)];
      final clock = world.clock();
      var ok = false;
      _measure(async, clock).then((value) => ok = value);
      async.flushMicrotasks();

      expect(ok, isTrue);
      expect(clock.lastRttMs, 20);
      expect(
        clock.nowServer().difference(world.trueNow()).inMilliseconds.abs(),
        lessThanOrEqualTo(1),
      );
    });
  });

  for (final skew in [
    const Duration(minutes: 5),
    const Duration(minutes: -5),
  ]) {
    test(
      'a device clock ${skew.inMinutes} minutes off still gives server time',
      () {
        fakeAsync((async) {
          final world = _World(async, deviceSkew: skew);
          final clock = world.clock();
          _measure(async, clock);
          async.flushMicrotasks();

          expect(clock.isMeasured, isTrue);
          expect(
            clock.offsetMs,
            (-skew.inMilliseconds).abs() * (skew.isNegative ? 1 : -1),
          );
          expect(
            clock.nowServer().difference(world.trueNow()).inMilliseconds.abs(),
            lessThanOrEqualTo(1),
          );
          // Time keeps passing: the estimate follows the device clock.
          async.elapse(const Duration(seconds: 10));
          expect(
            clock.nowServer().difference(world.trueNow()).inMilliseconds.abs(),
            lessThanOrEqualTo(1),
          );
        });
      },
    );
  }

  test('a failed measurement keeps the old offset', () {
    fakeAsync((async) {
      final world = _World(async, deviceSkew: const Duration(minutes: 3));
      final clock = world.clock();
      _measure(async, clock);
      async.flushMicrotasks();
      final offset = clock.offsetMs;
      final rtt = clock.lastRttMs;

      world.failing = true;
      var ok = true;
      _measure(async, clock).then((value) => ok = value);
      async.flushMicrotasks();

      expect(ok, isFalse);
      expect(clock.offsetMs, offset);
      expect(clock.lastRttMs, rtt);
      expect(clock.isMeasured, isTrue);
    });
  });

  test('before any success the clock is not measured', () {
    fakeAsync((async) {
      final world = _World(async)..failing = true;
      final clock = world.clock();
      var ok = true;
      _measure(async, clock).then((value) => ok = value);
      async.flushMicrotasks();
      expect(ok, isFalse);
      expect(clock.isMeasured, isFalse);
      expect(clock.lastRttMs, isNull);
    });
  });

  test('some failed samples are skipped', () {
    fakeAsync((async) {
      final world = _World(async);
      var n = 0;
      final clock = ServerClock(
        fetchServerNow: () async {
          if (n++ < 4) throw StateError('x');
          return world.fetch();
        },
        localNow: world.deviceNow,
      );
      _measure(async, clock);
      async.flushMicrotasks();
      expect(clock.isMeasured, isTrue);
    });
  });

  test('a much worse measurement does not replace a good recent one', () {
    fakeAsync((async) {
      final world = _World(async);
      final clock = world.clock();
      _measure(async, clock);
      async.flushMicrotasks();
      expect(clock.lastRttMs, 40);

      world.legs = [(600, 600)]; // a bad network moment
      var ok = true;
      _measure(async, clock).then((value) => ok = value);
      async.flushMicrotasks();
      expect(ok, isFalse);
      expect(clock.lastRttMs, 40);

      // Once the good one is old, the new one is better than nothing.
      async.elapse(const Duration(minutes: 6));
      _measure(async, clock).then((value) => ok = value);
      async.flushMicrotasks();
      expect(ok, isTrue);
      expect(clock.lastRttMs, 1200);
    });
  });

  test('a measurement that is already running is joined, not repeated', () {
    fakeAsync((async) {
      final world = _World(async);
      final clock = world.clock(samples: 2);
      final a = clock.measure();
      final b = clock.measure();
      expect(identical(a, b), isTrue);
      async.elapse(const Duration(seconds: 5));
      expect(world.calls, 2);
    });
  });
}
