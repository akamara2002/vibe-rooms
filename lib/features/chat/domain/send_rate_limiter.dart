/// At most [perSecond] messages in any second and [perMinute] in any minute.
/// Client-side only: the database does not limit messages.
///
/// A refused attempt does NOT count, so waiting is always enough.
class SendRateLimiter {
  SendRateLimiter({required this.now, this.perSecond = 1, this.perMinute = 20});

  final DateTime Function() now;
  final int perSecond;
  final int perMinute;
  final _sent = <DateTime>[];

  /// Records a send and returns true, or returns false if it would go over a
  /// limit.
  bool tryAcquire() {
    final current = now();
    _sent.removeWhere(
      (t) => current.difference(t) >= const Duration(minutes: 1),
    );
    final lastSecond = _sent
        .where((t) => current.difference(t) < const Duration(seconds: 1))
        .length;
    if (lastSecond >= perSecond || _sent.length >= perMinute) return false;
    _sent.add(current);
    return true;
  }
}
