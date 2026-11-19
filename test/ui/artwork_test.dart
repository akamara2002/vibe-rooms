import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vibe_rooms/features/player/presentation/artwork.dart';

Widget _app(Widget child, {double dpr = 2}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(devicePixelRatio: dpr),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('no url: a placeholder, no network image', (tester) async {
    await tester.pumpWidget(_app(const Artwork(url: null, size: 56)));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });

  testWidgets('decodes at the displayed size in device pixels', (tester) async {
    await tester.pumpWidget(
      _app(const Artwork(url: 'https://example.com/a.jpg', size: 56)),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 112);
    expect(image.placeholder, isNotNull);
    expect(image.errorWidget, isNotNull);
  });

  testWidgets('a huge display size is capped', (tester) async {
    await tester.pumpWidget(
      _app(const Artwork(url: 'https://example.com/a.jpg', size: 900), dpr: 3),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, maxArtworkDecodePx);
  });
}
