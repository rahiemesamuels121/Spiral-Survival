import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/firebase_config.dart';
import 'package:spiral_pass_play/features/multiplayer/presentation/online_room_screen.dart';

void main() {
  testWidgets('Online lobby is available in a standard build', (tester) async {
    expect(FirebaseConfig.configured, isTrue);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const OnlineRoomScreen()),
    );
    expect(find.text('CREATE ROOM'), findsOneWidget);
    expect(find.text('JOIN ROOM'), findsOneWidget);
    expect(find.textContaining('not enabled in this build'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Alex');
    expect(find.text('Alex'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
