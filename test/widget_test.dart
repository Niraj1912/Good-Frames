import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/main.dart';

void main() {
  testWidgets('app starts and shows its name', (tester) async {
    await tester.pumpWidget(const PhotoSwipeApp());

    expect(find.text('SwipeSort'), findsOneWidget);
  });
}
