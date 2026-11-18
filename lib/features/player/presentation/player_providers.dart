import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config.dart';
import '../data/audius_catalog.dart';
import '../data/just_audio_engine.dart';
import '../domain/audio_engine.dart';
import '../domain/music_catalog.dart';
import '../domain/track.dart';

final musicCatalogProvider = Provider<MusicCatalog>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AudiusCatalog(client: client, apiKey: config.audiusApiKey);
});

/// Builds a NEW engine each time. A plain `Provider<AudioEngine>` would hand
/// the same (already disposed) engine to the next room visit.
final audioEngineFactoryProvider = Provider<AudioEngine Function()>(
  (_) => JustAudioEngine.new,
);

final trendingProvider = FutureProvider.autoDispose<List<Track>>(
  (ref) => ref.watch(musicCatalogProvider).trending(),
  retry: (_, _) => null,
);

/// Browsers block audio until the user taps something. True on web only
/// (overridable in tests).
final soundGateRequiredProvider = Provider<bool>((_) => kIsWeb);

/// Whether sound is allowed. On web it starts false and the sound gate turns it
/// on; elsewhere it starts true. Being autoDispose, it resets when the user
/// leaves the room.
class SoundEnabled extends Notifier<bool> {
  @override
  bool build() => !ref.watch(soundGateRequiredProvider);

  void enable() => state = true;
}

final soundEnabledProvider = NotifierProvider.autoDispose<SoundEnabled, bool>(
  SoundEnabled.new,
);
