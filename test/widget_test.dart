import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/main.dart';

void main() {
  testWidgets('App starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicPlayerApp());
    expect(find.text('音乐播放器'), findsOneWidget);
  });
}
