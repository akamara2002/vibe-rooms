import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibe_rooms/features/player/data/audius_catalog.dart';
import 'package:vibe_rooms/features/player/domain/audius_failure.dart';

Map<String, dynamic> rawTrack(String id) => {
  'id': id,
  'title': 'Song $id',
  'duration': 100,
  'is_streamable': true,
  'is_delete': false,
  'is_unlisted': false,
  'access': {'stream': true},
  'artwork': {'480x480': 'https://cdn.test/$id.jpg'},
  'user': {'name': 'Artist'},
  'permalink': '/artist/$id',
};

http.Response ok(List<String> ids) => http.Response(
  jsonEncode({
    'data': [for (final id in ids) rawTrack(id)],
  }),
  200,
);

AudiusCatalog catalogFor(
  MockClientHandler handler, {
  String apiKey = '',
  List<Uri>? hosts,
  DateTime Function()? now,
}) => AudiusCatalog(
  client: MockClient(handler),
  hosts: hosts,
  apiKey: apiKey,
  retryDelay: Duration.zero,
  timeout: const Duration(milliseconds: 100),
  now: now,
);

void main() {
  group('requests', () {
    test(
      'search sends query and limit to the right path, no custom headers',
      () async {
        late http.Request seen;
        final catalog = catalogFor((request) async {
          seen = request;
          return ok(['a']);
        });
        final tracks = await catalog.search('  lo fi  ', limit: 5);

        expect(seen.method, 'GET');
        expect(seen.url.host, 'api.audius.co');
        expect(seen.url.path, '/v1/tracks/search');
        expect(seen.url.queryParameters['query'], 'lo fi');
        expect(seen.url.queryParameters['limit'], '5');
        expect(seen.url.queryParameters['app_name'], 'vibe_rooms');
        // No custom headers means browsers never need a CORS preflight.
        expect(
          seen.headers.keys.where((k) => k.toLowerCase() != 'content-length'),
          isEmpty,
        );
        expect(tracks.single.id, 'a');
      },
    );

    test('an empty query makes no request', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return ok([]);
      });
      expect(await catalog.search('   '), isEmpty);
      expect(calls, 0);
    });

    test('trending requests the weekly list', () async {
      late Uri seen;
      final catalog = catalogFor((request) async {
        seen = request.url;
        return ok(['t1', 't2']);
      });
      final tracks = await catalog.trending(limit: 2);
      expect(seen.path, '/v1/tracks/trending');
      expect(seen.queryParameters['time'], 'week');
      expect(tracks.map((t) => t.id), ['t1', 't2']);
    });

    test('the api key is sent only when set', () async {
      final seen = <Uri>[];
      Future<http.Response> handler(http.Request r) async {
        seen.add(r.url);
        return ok([]);
      }

      await catalogFor(handler).trending();
      await catalogFor(handler, apiKey: 'k123').trending();
      expect(seen[0].queryParameters.containsKey('api_key'), isFalse);
      expect(seen[1].queryParameters['api_key'], 'k123');
    });
  });

  group('streamUri', () {
    test('builds the stream URL for a track id', () {
      final uri = catalogFor((_) async => ok([])).streamUri('Ma0blKV');
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.audius.co');
      expect(uri.path, '/v1/tracks/Ma0blKV/stream');
    });

    test('an odd id can never change the path', () {
      final uri = catalogFor((_) async => ok([])).streamUri('../../evil?x=1#y');
      expect(uri.host, 'api.audius.co');
      expect(uri.pathSegments.length, 4);
      expect(uri.path, startsWith('/v1/tracks/'));
      expect(uri.path, endsWith('/stream'));
      expect(uri.fragment, isEmpty);
      expect(uri.queryParameters.containsKey('x'), isFalse);
    });
  });

  group('failures and retries', () {
    test('429 then success: retried once and succeeds', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return calls == 1 ? http.Response('slow down', 429) : ok(['a']);
      });
      expect((await catalog.search('x')).single.id, 'a');
      expect(calls, 2);
    });

    test('repeated 429 becomes rateLimited after one retry', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return http.Response('no', 429);
      });
      await expectLater(
        catalog.search('x'),
        throwsA(
          isA<AudiusFailure>().having(
            (f) => f.kind,
            'kind',
            AudiusFailureKind.rateLimited,
          ),
        ),
      );
      expect(calls, 2);
    });

    test('500 then success is retried', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return calls == 1 ? http.Response('x', 503) : ok(['a']);
      });
      expect(await catalog.trending(), hasLength(1));
      expect(calls, 2);
    });

    test('repeated 500 becomes a network failure', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return http.Response('x', 500);
      });
      await expectLater(
        catalog.search('x'),
        throwsA(
          isA<AudiusFailure>().having(
            (f) => f.kind,
            'kind',
            AudiusFailureKind.network,
          ),
        ),
      );
      expect(calls, 2);
    });

    test('a timeout is retried once, then fails as network', () async {
      var calls = 0;
      final catalog = catalogFor((_) {
        calls++;
        return Completer<http.Response>().future; // never answers
      });
      await expectLater(
        catalog.search('x'),
        throwsA(
          isA<AudiusFailure>().having(
            (f) => f.kind,
            'kind',
            AudiusFailureKind.network,
          ),
        ),
      );
      expect(calls, 2);
    });

    test('a network error is retried once, then fails as network', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        throw http.ClientException('offline');
      });
      await expectLater(
        catalog.search('x'),
        throwsA(
          isA<AudiusFailure>().having(
            (f) => f.kind,
            'kind',
            AudiusFailureKind.network,
          ),
        ),
      );
      expect(calls, 2);
    });

    test('a malformed body is an unknown failure, not a crash', () async {
      final catalog = catalogFor((_) async => http.Response('<html>nope', 200));
      await expectLater(
        catalog.search('x'),
        throwsA(
          isA<AudiusFailure>().having(
            (f) => f.kind,
            'kind',
            AudiusFailureKind.unknown,
          ),
        ),
      );
    });

    test('an unexpected JSON shape gives no tracks', () async {
      final catalog = catalogFor(
        (_) async => http.Response('{"data": 5}', 200),
      );
      expect(await catalog.search('x'), isEmpty);
    });

    test('404 is notFound and is not retried', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return http.Response('', 404);
      });
      await expectLater(
        catalog.search('x'),
        throwsA(
          isA<AudiusFailure>().having(
            (f) => f.kind,
            'kind',
            AudiusFailureKind.notFound,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('other 4xx is unknown and is not retried', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return http.Response('', 400);
      });
      await expectLater(
        catalog.search('x'),
        throwsA(
          isA<AudiusFailure>().having(
            (f) => f.kind,
            'kind',
            AudiusFailureKind.unknown,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('Retry-After is honoured but capped at two seconds', () async {
      var calls = 0;
      final catalog = AudiusCatalog(
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('x', 429, headers: {'retry-after': '9999'})
              : ok(['a']);
        }),
        retryDelay: Duration.zero,
      );
      final started = DateTime.now();
      // Cannot wait 9999 s in a test: it must be capped at 2 s.
      await catalog.search('x');
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 4)),
      );
      expect(calls, 2);
    });
  });

  group('hosts', () {
    test('a failing host falls over to the next one', () async {
      final seenHosts = <String>[];
      final catalog = catalogFor((request) async {
        seenHosts.add(request.url.host);
        return request.url.host == 'one.test'
            ? http.Response('x', 500)
            : ok(['a']);
      }, hosts: [Uri.parse('https://one.test'), Uri.parse('https://two.test')]);
      expect((await catalog.search('x')).single.id, 'a');
      expect(seenHosts, ['one.test', 'one.test', 'two.test']);
    });

    test('notFound does not try other hosts', () async {
      final seenHosts = <String>[];
      final catalog = catalogFor((request) async {
        seenHosts.add(request.url.host);
        return http.Response('', 404);
      }, hosts: [Uri.parse('https://one.test'), Uri.parse('https://two.test')]);
      await expectLater(catalog.search('x'), throwsA(isA<AudiusFailure>()));
      expect(seenHosts, ['one.test']);
    });
  });

  group('trending cache', () {
    test('a second call within the TTL does not hit the network', () async {
      var calls = 0;
      var clock = DateTime(2026);
      final catalog = catalogFor((_) async {
        calls++;
        return ok(['a']);
      }, now: () => clock);
      await catalog.trending();
      clock = clock.add(const Duration(minutes: 1));
      await catalog.trending();
      expect(calls, 1);

      clock = clock.add(const Duration(minutes: 5));
      await catalog.trending();
      expect(calls, 2);
    });

    test('failures are not cached', () async {
      var calls = 0;
      final catalog = catalogFor((_) async {
        calls++;
        return calls <= 2 ? http.Response('x', 500) : ok(['a']);
      });
      await expectLater(catalog.trending(), throwsA(isA<AudiusFailure>()));
      expect(await catalog.trending(), hasLength(1));
    });
  });
}
