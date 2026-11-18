/// Every number the sync algorithm uses, in one place.
class SyncConfig {
  const SyncConfig({
    this.driftThresholdMs = 300,
    this.driftHardLimitMs = 2000,
    this.driftCheckInterval = const Duration(seconds: 2),
    this.minSeekGap = const Duration(seconds: 5),
    this.hardSeekGap = const Duration(seconds: 1),
    this.clockRemeasureInterval = const Duration(seconds: 60),
    this.postLoadDriftCheck = const Duration(milliseconds: 1500),
    this.displayTick = const Duration(milliseconds: 500),
    this.clockSamples = 5,
    this.maxLatencyCompensationMs = 1500,
    this.endToleranceMs = 2500,
    this.reloadGap = const Duration(seconds: 5),
  });

  /// Drift (engine position minus expected) below this is ignored: seeking on
  /// a streamed MP3 is imprecise and slow, so small drift is cheaper to live
  /// with than to fix.
  final int driftThresholdMs;

  /// Drift beyond this is corrected even inside the thrash guard window.
  final int driftHardLimitMs;

  /// How often a playing client compares its engine with the room clock.
  final Duration driftCheckInterval;

  /// Minimum time between corrective seeks. Every seek on an Audius stream
  /// re-hits the 302 redirect, and the free plan allows 10 requests per
  /// second.
  final Duration minSeekGap;

  /// Even a hard-limit correction waits this long after the last seek, so a
  /// broken engine cannot seek on every tick.
  final Duration hardSeekGap;

  /// How often the server clock offset is measured again.
  final Duration clockRemeasureInterval;

  /// One more drift check this long after a load, because the first seek on a
  /// not yet buffered stream can land imprecisely.
  final Duration postLoadDriftCheck;

  /// How often the displayed position is refreshed.
  final Duration displayTick;

  /// `server_now()` samples per measurement; the one with the smallest round
  /// trip wins.
  final int clockSamples;

  /// The host adds half the round trip to a write made while playing, but
  /// never more than this, so one bad measurement cannot skew the room.
  final int maxLatencyCompensationMs;

  /// The audio can end this much before the track's stored duration, so an
  /// engine that completed this close to the end counts as the end.
  final int endToleranceMs;

  /// Minimum time between reload attempts after a load error.
  final Duration reloadGap;
}

const syncConfig = SyncConfig();
