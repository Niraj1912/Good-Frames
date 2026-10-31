import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/widgets/swipe_card.dart';

const _face = Key('card face');

// The card on its own, 400 wide, so the swipe threshold is 120 pixels.
void main() {
  late List<SwipeDirection> swipes;
  late GlobalKey<SwipeCardState> cardKey;

  setUp(() {
    swipes = [];
    cardKey = GlobalKey<SwipeCardState>();
  });

  Future<void> showCard(WidgetTester tester, {String cardId = 'a'}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: SwipeCard(
              key: cardKey,
              cardId: cardId,
              onSwiped: swipes.add,
              child: const ColoredBox(key: _face, color: Colors.blue),
            ),
          ),
        ),
      ),
    );
  }

  Offset cardCorner(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(_face));

  double stampOpacity(WidgetTester tester, String label) => tester
      .widget<Opacity>(
        find.ancestor(of: find.text(label), matching: find.byType(Opacity)),
      )
      .opacity;

  testWidgets('a long drag swipes in that direction', (tester) async {
    await showCard(tester);

    await tester.drag(find.byType(SwipeCard), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(swipes, [SwipeDirection.right]);

    await showCard(tester, cardId: 'b');
    await tester.drag(find.byType(SwipeCard), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(swipes, [SwipeDirection.right, SwipeDirection.left]);
  });

  testWidgets('a short drag springs back to the middle', (tester) async {
    await showCard(tester);
    final start = cardCorner(tester);

    await tester.drag(find.byType(SwipeCard), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(swipes, isEmpty);
    expect(cardCorner(tester), start);
  });

  testWidgets('a quick flick counts even if it is short', (tester) async {
    await showCard(tester);

    await tester.fling(find.byType(SwipeCard), const Offset(-60, 0), 2000);
    await tester.pumpAndSettle();

    expect(swipes, [SwipeDirection.left]);
  });

  testWidgets('the stamp for the drag direction fades in', (tester) async {
    await showCard(tester);
    expect(stampOpacity(tester, 'KEEP'), 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeCard)),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();

    expect(stampOpacity(tester, 'KEEP'), 1);
    expect(stampOpacity(tester, 'DELETE'), 0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('code can swipe it, and a new photo resets it', (tester) async {
    await showCard(tester);
    final start = cardCorner(tester);

    cardKey.currentState!.swipe(SwipeDirection.right);
    await tester.pumpAndSettle();
    expect(swipes, [SwipeDirection.right]);
    expect(cardCorner(tester).dx, greaterThan(400)); // Off to the right.

    await showCard(tester, cardId: 'b');
    expect(cardCorner(tester), start);
  });
}
