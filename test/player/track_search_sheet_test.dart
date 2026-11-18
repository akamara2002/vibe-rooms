import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/player/domain/audius_failure.dart';
import 'package:vibe_rooms/features/player/domain/track.dart';
import 'package:vibe_rooms/features/player/presentation/player_providers.dart';
import 'package:vibe_rooms/features/player/presentation/track_search_sheet.dart';

import '../fakes/fakes.dart';

/// Opens the sheet over a bare app. Returns the tracks the callback received.
Future<List<Track>> openSheet(
  WidgetTester tester,
  FakeMusicCatalog catalog,
) async {
  final selected = <Track>[];
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [musicCatalogProvider.overrideWithValue(catalog)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showTrackSearchSheet(
                  context,
                  title: 'Pick a track',
                  onTrackSelected: selected.add,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return selected;
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> pastDebounce(WidgetTester tester) async {
  await tester.pump(searchDebounce + const Duration(milliseconds: 10));
  await tester.pump();
}

void main() {
  addModeTests();
  final trending = [
    fakeTrack(
      id: 'tr1',
      title: 'Trending One',
      artist: 'Ann',
      durationMs: 195000,
    ),
    fakeTrack(
      id: 'tr2',
      title: 'Trending Two',
      artist: 'Bob',
      durationMs: 61000,
    ),
  ];

  testWidgets(
    'shows the title, trending tracks and the Audius footer when empty',
    (tester) async {
      final catalog = FakeMusicCatalog(trendingTracks: trending);
      await openSheet(tester, catalog);

      expect(find.text('Pick a track'), findsOneWidget);
      expect(find.text('Trending'), findsOneWidget);
      expect(find.text('Trending One'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('3:15'), findsOneWidget);
      expect(find.text('1:01'), findsOneWidget);
      expect(find.text('Music via Audius'), findsOneWidget);
      expect(catalog.calls, ['trending']);
    },
  );

  testWidgets('typing searches after the 400 ms debounce, not before', (
    tester,
  ) async {
    final catalog = FakeMusicCatalog(
      trendingTracks: trending,
      results: {
        'lofi': [fakeTrack(id: 'l1', title: 'Lofi Beat', artist: 'Chill')],
      },
    );
    await openSheet(tester, catalog);

    await type(tester, 'lofi');
    await tester.pump(const Duration(milliseconds: 300));
    expect(catalog.calls.where((c) => c.startsWith('search')), isEmpty);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(catalog.calls.where((c) => c.startsWith('search')), ['search:lofi']);
    expect(find.text('Results for "lofi"'), findsOneWidget);
    expect(find.text('Lofi Beat'), findsOneWidget);
    expect(find.text('Trending One'), findsNothing);
  });

  testWidgets('rapid typing sends only the final query', (tester) async {
    final catalog = FakeMusicCatalog(
      trendingTracks: trending,
      results: {
        'lofi': [fakeTrack(id: 'l1', title: 'Lofi Beat')],
      },
    );
    await openSheet(tester, catalog);

    for (final text in ['l', 'lo', 'lof', 'lofi']) {
      await type(tester, text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pastDebounce(tester);

    expect(catalog.calls.where((c) => c.startsWith('search')), ['search:lofi']);
  });

  testWidgets('a stale response arriving late is ignored', (tester) async {
    final slow = Completer<void>();
    final catalog = FakeMusicCatalog(
      trendingTracks: trending,
      results: {
        'old': [fakeTrack(id: 'o1', title: 'Old Result')],
        'new': [fakeTrack(id: 'n1', title: 'New Result')],
      },
    )..searchGates['old'] = slow;
    await openSheet(tester, catalog);

    await type(tester, 'old');
    await pastDebounce(tester); // 'old' is now in flight and slow
    await type(tester, 'new');
    await pastDebounce(tester); // 'new' answers at once
    expect(find.text('New Result'), findsOneWidget);

    slow.complete(); // the old answer finally arrives
    await tester.pump();
    await tester.pump();

    expect(find.text('New Result'), findsOneWidget);
    expect(find.text('Old Result'), findsNothing);
    expect(find.text('Results for "new"'), findsOneWidget);
  });

  testWidgets(
    'a response for text that was typed over before the debounce is ignored',
    (tester) async {
      final slow = Completer<void>();
      final catalog = FakeMusicCatalog(
        trendingTracks: trending,
        results: {
          'a': [fakeTrack(id: 'a1', title: 'A Result')],
        },
      )..searchGates['a'] = slow;
      await openSheet(tester, catalog);

      await type(tester, 'a');
      await pastDebounce(tester); // 'a' in flight
      await type(tester, 'ab'); // typed on; debounce for 'ab' not fired yet
      slow.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('A Result'), findsNothing);
    },
  );

  testWidgets(
    'clearing the field shows trending again and drops in-flight results',
    (tester) async {
      final slow = Completer<void>();
      final catalog = FakeMusicCatalog(
        trendingTracks: trending,
        results: {
          'q': [fakeTrack(id: 'q1', title: 'Q Result')],
        },
      )..searchGates['q'] = slow;
      await openSheet(tester, catalog);

      await type(tester, 'q');
      await pastDebounce(tester);
      await type(tester, '');
      expect(find.text('Trending One'), findsOneWidget);

      slow.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Q Result'), findsNothing);
      expect(find.text('Trending One'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a result calls the callback with that track and closes the sheet',
    (tester) async {
      final catalog = FakeMusicCatalog(trendingTracks: trending);
      final selected = await openSheet(tester, catalog);

      await tester.tap(find.text('Trending Two'));
      await tester.pumpAndSettle();

      expect(selected.map((t) => t.id), ['tr2']);
      expect(find.text('Pick a track'), findsNothing); // sheet closed
    },
  );

  testWidgets('no results shows "No tracks found"', (tester) async {
    final catalog = FakeMusicCatalog(trendingTracks: trending);
    await openSheet(tester, catalog);

    await type(tester, 'zzzzqqqq');
    await pastDebounce(tester);

    expect(find.text('No tracks found'), findsOneWidget);
    expect(find.text('Trending One'), findsNothing);
  });

  testWidgets('a search error shows a message and Retry searches again', (
    tester,
  ) async {
    final catalog = FakeMusicCatalog(
      trendingTracks: trending,
      results: {
        'lofi': [fakeTrack(id: 'l1', title: 'Lofi Beat')],
      },
    )..searchFailure = const AudiusFailure(AudiusFailureKind.network);
    await openSheet(tester, catalog);

    await type(tester, 'lofi');
    await pastDebounce(tester);
    expect(
      find.text(const AudiusFailure(AudiusFailureKind.network).message),
      findsOneWidget,
    );

    catalog.searchFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Lofi Beat'), findsOneWidget);
    expect(catalog.calls.where((c) => c == 'search:lofi'), hasLength(2));
  });

  testWidgets('a trending error shows a message and Retry reloads it', (
    tester,
  ) async {
    final catalog = FakeMusicCatalog(trendingTracks: trending)
      ..trendingFailure = const AudiusFailure(AudiusFailureKind.rateLimited);
    await openSheet(tester, catalog);

    expect(
      find.text(const AudiusFailure(AudiusFailureKind.rateLimited).message),
      findsOneWidget,
    );

    catalog.trendingFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Trending One'), findsOneWidget);
  });

  testWidgets('rows are accessible: title, artist and length in one label', (
    tester,
  ) async {
    final catalog = FakeMusicCatalog(trendingTracks: trending);
    await openSheet(tester, catalog);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Trending One by Ann, 3:15'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
    'a screen reader can activate a row (the semantic button has a tap action)',
    (tester) async {
      final catalog = FakeMusicCatalog(trendingTracks: trending);
      final selected = await openSheet(tester, catalog);
      final handle = tester.ensureSemantics();

      tester.semantics.tap(find.semantics.byLabel('Trending Two by Bob, 1:01'));
      await tester.pumpAndSettle();
      expect(selected.map((t) => t.id), ['tr2']);
      handle.dispose();
    },
  );
}

/// Add mode: opens the sheet like the Queue tab does.
Future<void> _openAddSheet(
  WidgetTester tester, {
  required FakeMusicCatalog catalog,
  required Future<String?> Function(Track) onAdd,
  void Function(Track)? onPlayNow,
  Set<String> queued = const {},
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [musicCatalogProvider.overrideWithValue(catalog)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showTrackSearchSheet(
                  context,
                  title: 'Add songs',
                  onAdd: onAdd,
                  onPlayNow: onPlayNow,
                  queuedTrackIds: queued,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void addModeTests() {
  final tracks = [
    fakeTrack(id: 'a', title: 'Alpha'),
    fakeTrack(id: 'b', title: 'Beta'),
  ];

  group('add mode', () {
    testWidgets('+ adds the track, shows Added, and the sheet stays open', (
      tester,
    ) async {
      final added = <String>[];
      await _openAddSheet(
        tester,
        catalog: FakeMusicCatalog(trendingTracks: tracks),
        onAdd: (t) async {
          added.add(t.id);
          return null;
        },
      );
      expect(find.byTooltip('Add to queue'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Add to queue').first);
      await tester.pumpAndSettle();

      expect(added, ['a']);
      expect(find.text('Added'), findsOneWidget);
      expect(find.byTooltip('Add to queue'), findsOneWidget);
      // Still open: several songs can be added in a row.
      expect(find.text('Add songs'), findsOneWidget);
      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pumpAndSettle();
      expect(added, ['a', 'b']);
      expect(find.text('Added'), findsNWidgets(2));
    });

    testWidgets('a track that is already added cannot be added twice', (
      tester,
    ) async {
      var calls = 0;
      await _openAddSheet(
        tester,
        catalog: FakeMusicCatalog(trendingTracks: tracks),
        onAdd: (t) async {
          calls++;
          return null;
        },
        queued: {'a'},
      );
      expect(find.text('Added'), findsOneWidget);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('tapping the row adds too', (tester) async {
      final added = <String>[];
      await _openAddSheet(
        tester,
        catalog: FakeMusicCatalog(trendingTracks: tracks),
        onAdd: (t) async {
          added.add(t.id);
          return null;
        },
      );
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(added, ['b']);
    });

    testWidgets('a duplicate or a limit shows the message in a snackbar and '
        'the + comes back', (tester) async {
      await _openAddSheet(
        tester,
        catalog: FakeMusicCatalog(trendingTracks: tracks),
        onAdd: (t) async => 'Already in the queue',
      );
      await tester.tap(find.byTooltip('Add to queue').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The messenger shows it on the page and in the sheet's own Scaffold.
      expect(find.text('Already in the queue'), findsWidgets);
      expect(find.text('Added'), findsNothing);
      expect(find.byTooltip('Add to queue'), findsNWidgets(2));
    });

    testWidgets('shows a spinner while a track is being added', (tester) async {
      final gate = Completer<String?>();
      await _openAddSheet(
        tester,
        catalog: FakeMusicCatalog(trendingTracks: tracks),
        onAdd: (t) => gate.future,
      );
      await tester.tap(find.byTooltip('Add to queue').first);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // A second tap while adding does nothing.
      gate.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Added'), findsOneWidget);
    });

    testWidgets('the host sees Play now on every result, a member does not', (
      tester,
    ) async {
      final played = <String>[];
      await _openAddSheet(
        tester,
        catalog: FakeMusicCatalog(trendingTracks: tracks),
        onAdd: (t) async => null,
        onPlayNow: (t) => played.add(t.id),
      );
      expect(find.text('Play now'), findsNWidgets(2));
      await tester.tap(find.text('Play now').last);
      await tester.pumpAndSettle();
      expect(played, ['b']);
      expect(find.text('Add songs'), findsNothing); // Play now closes the sheet
    });

    testWidgets('a member only has the add action', (tester) async {
      await _openAddSheet(
        tester,
        catalog: FakeMusicCatalog(trendingTracks: tracks),
        onAdd: (t) async => null,
      );
      expect(find.text('Play now'), findsNothing);
      expect(find.byTooltip('Add to queue'), findsNWidgets(2));
    });
  });
}
