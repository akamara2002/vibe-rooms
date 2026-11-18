/// What the sync chip shows.
enum SyncStatus { inSync, syncing, reconnecting, waitingForSound, ended }

/// For the debug panel.
class SyncDebug {
  const SyncDebug({
    this.offsetMs,
    this.rttMs,
    this.driftMs,
    this.lastAction = 'none',
    this.loadedTrack = false,
  });

  final int? offsetMs;
  final int? rttMs;
  final int? driftMs;
  final String lastAction;
  final bool loadedTrack;
}
