/// Estimates the server's clock from `server_now()` samples.
///
/// `updated_at` is stamped by Postgres, so every client must interpret it with
/// server time, never with its own clock (a phone can be minutes off).
///
/// Per sample: offset = serverTime + rtt / 2 - localReceiveTime. The sample
/// with the smallest round trip is the most accurate, so it wins.
class ServerClock {
  ServerClock({
    required Future<DateTime> Function() fetchServerNow,
    DateTime Function()? localNow,
    this.samples = 5,
  }) : _fetch = fetchServerNow,
       _localNow = localNow ?? DateTime.now;

  final Future<DateTime> Function() _fetch;
  final DateTime Function() _localNow;
  final int samples;

  Duration _offset = Duration.zero;
  DateTime? _measuredAt;
  int? _rttMs;
  Future<bool>? _running;

  /// True once at least one measurement succeeded.
  bool get isMeasured => _rttMs != null;

  /// Round trip of the winning sample, or null before the first measurement.
  int? get lastRttMs => _rttMs;

  /// Server time minus local time, in milliseconds.
  int get offsetMs => _offset.inMilliseconds;

  /// The server's current time (UTC), from the local clock plus the offset.
  DateTime nowServer() => _localNow().toUtc().add(_offset);

  /// Measures the offset. Returns false (and keeps the old offset) if every
  /// sample failed. A call while one is running joins it.
  Future<bool> measure() => _running ??= _measure().whenComplete(() {
    _running = null;
  });

  Future<bool> _measure() async {
    Duration? bestOffset;
    Duration? bestRtt;
    for (var i = 0; i < samples; i++) {
      try {
        final sent = _localNow().toUtc();
        final server = (await _fetch()).toUtc();
        final received = _localNow().toUtc();
        final rtt = received.difference(sent);
        if (rtt.isNegative) continue; // the local clock jumped; unusable
        final offset = server.add(rtt ~/ 2).difference(received);
        if (bestRtt == null || rtt < bestRtt) {
          bestRtt = rtt;
          bestOffset = offset;
        }
      } catch (_) {
        // A failed sample is skipped; the others may still work.
      }
    }
    if (bestOffset == null || bestRtt == null) return false;

    // A much worse measurement (a bad network moment) must not replace a good
    // recent one.
    final old = _rttMs;
    final at = _measuredAt;
    final now = _localNow();
    final oldIsFresh =
        at != null && now.difference(at) < const Duration(minutes: 5);
    if (old != null && oldIsFresh && bestRtt.inMilliseconds > old * 3 + 100) {
      return false;
    }
    _offset = bestOffset;
    _rttMs = bestRtt.inMilliseconds;
    _measuredAt = now;
    return true;
  }
}
