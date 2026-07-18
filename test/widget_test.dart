import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:music_player/main.dart';
import 'package:music_player/pages/player_page.dart';
import 'package:music_player/services/music_service.dart';

void main() {
  testWidgets('App starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicPlayerApp());
    expect(find.text('HenkMusic'), findsOneWidget);
  });

  test('TTML parser keeps word spans and background vocals readable', () {
    const content =
        '<tt xmlns="http://www.w3.org/ns/ttml" '
        'xmlns:ttm="http://www.w3.org/ns/ttml#metadata">'
        '<body dur="03:46.278"><div begin="00:14.070" end="03:46.278">'
        '<p begin="00:56.024" end="01:01.553">'
        '<span begin="00:56.024" end="00:56.470">所</span>'
        '<span begin="00:56.470" end="00:56.916">以</span>'
        '<span begin="00:56.916" end="00:57.264">爱</span>'
        '<span begin="00:57.264" end="00:58.689">错</span>'
        '<span ttm:role="x-bg" begin="00:57.719" end="01:01.553">'
        '<span begin="00:57.719" end="00:58.155">(所</span>'
        '<span begin="00:58.155" end="00:58.592">以</span>'
        '<span begin="00:58.592" end="00:58.926">爱</span>'
        '<span begin="00:58.926" end="01:01.553">错)</span>'
        '</span></p>'
        '<p begin="01:43.805" end="01:48.327">'
        '<span begin="01:43.805" end="01:44.189">原</span>'
        '<span begin="01:44.189" end="01:44.573">来</span>'
        '<span begin="01:44.573" end="01:44.973">是</span>'
        '<span begin="01:44.973" end="01:48.327">我</span>'
        '</p></div></body></tt>';

    final lyrics = MusicService.parseTtml(content);
    final richLyrics = MusicService.parseTtmlLines(content);

    expect(lyrics, hasLength(2));
    expect(lyrics.first.key, const Duration(seconds: 56, milliseconds: 24));
    expect(lyrics.first.value, '所以爱错\n(所以爱错)');
    expect(
      richLyrics.first.words.map((word) => word.text).join(),
      '所以爱错\n(所以爱错)',
    );
    expect(
      richLyrics.first.words.first.begin,
      const Duration(seconds: 56, milliseconds: 24),
    );
    expect(
      richLyrics.first.words.first.end,
      const Duration(seconds: 56, milliseconds: 470),
    );
    expect(
      lyrics.last.key,
      const Duration(minutes: 1, seconds: 43, milliseconds: 805),
    );
    expect(lyrics.last.value, '原来是我');
  });

  for (final layout in <({String name, Size size, String key})>[
    (
      name: 'phone portrait',
      size: const Size(390, 844),
      key: 'player-phone-portrait',
    ),
    (
      name: 'phone landscape',
      size: const Size(844, 390),
      key: 'player-phone-landscape',
    ),
    (
      name: 'tablet portrait',
      size: const Size(834, 1194),
      key: 'player-tablet-portrait',
    ),
    (
      name: 'tablet landscape',
      size: const Size(1194, 834),
      key: 'player-tablet-landscape',
    ),
  ]) {
    testWidgets('PlayerPage renders the ${layout.name} layout', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = layout.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
      await tester.pump();

      expect(find.byKey(Key(layout.key)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Phone portrait switches between artwork and lyrics', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    expect(find.byKey(const ValueKey('portrait-artwork')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.lyrics_rounded));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('portrait-lyrics')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
