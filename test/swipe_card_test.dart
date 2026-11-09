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

  Future<void> showCard(
    WidgetTester tester, {
    String cardId = 'a',
    SwipeDirection? enterFrom,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: SwipeCard(
              key: cardKey,
              cardId: cardId,
              enterFrom: enterFrom,
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

  double stampOpacity(WidgetTester tester, String label) =>
      tester.widget<SwipeWash>(find.byKey(ValueKey(label))).opacity;

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

  testWidgets('a thin card can be dragged from anywhere in its area', (
    tester,
  ) async {
    // Like a panorama: a 400 x 60 card in a 400 x 600 area.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: SwipeCard(
              key: cardKey,
              cardId: 'a',
              onSwiped: swipes.add,
              child: const SizedBox(width: 400, height: 60),
            ),
          ),
        ),
      ),
    );

    // Starting well below the card itself.
    final area = tester.getRect(find.byType(SwipeCard));
    await tester.dragFrom(
      area.bottomCenter - const Offset(0, 40),
      const Offset(250, 0),
    );
    await tester.pumpAndSettle();

    expect(swipes, [SwipeDirection.right]);
  });

  testWidgets('a quick flick counts even if it is short', (tester) async {
    await showCard(tester);

    await tester.fling(find.byType(SwipeCard), const Offset(-60, 0), 2000);
    await tester.pumpAndSettle();

    expect(swipes, [SwipeDirection.left]);
  });

  testWidgets('a drag up swipes up; a crooked sideways one goes sideways', (
    tester,
  ) async {
    await showCard(tester);
    await tester.drag(find.byType(SwipeCard), const Offset(30, -250));
    await tester.pumpAndSettle();
    expect(swipes, [SwipeDirection.up]);

    await showCard(tester, cardId: 'b');
    await tester.drag(find.byType(SwipeCard), const Offset(250, -100));
    await tester.pumpAndSettle();
    expect(swipes, [SwipeDirection.up, SwipeDirection.right]);
  });

  testWidgets('a drag down springs back', (tester) async {
    await showCard(tester);
    final start = cardCorner(tester);

    await tester.drag(find.byType(SwipeCard), const Offset(0, 250));
    await tester.pumpAndSettle();

    expect(swipes, isEmpty);
    expect(cardCorner(tester), start);
  });

  testWidgets('going up shows only the LATER stamp', (tester) async {
    await showCard(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeCard)),
    );
    await gesture.moveBy(const Offset(0, -40));
    await gesture.moveBy(const Offset(20, -200));
    await tester.pump();

    expect(stampOpacity(tester, 'LATER'), 1);
    expect(stampOpacity(tester, 'KEEP'), 0);
    expect(stampOpacity(tester, 'DELETE'), 0);
    await gesture.up();
    await tester.pumpAndSettle();
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

  testWidgets('an undone photo slides back in from its side', (tester) async {
    await showCard(tester);
    final start = cardCorner(tester);

    // Undo after a delete: the photo comes back from the left.
    await showCard(tester, cardId: 'b', enterFrom: SwipeDirection.left);
    expect(cardCorner(tester).dx, lessThan(0)); // Starts off to the left.

    await tester.pumpAndSettle();
    expect(cardCorner(tester), start);
  });

  testWidgets('a photo put off and undone comes back from the top', (
    tester,
  ) async {
    await showCard(tester);
    final start = cardCorner(tester);

    await showCard(tester, cardId: 'b', enterFrom: SwipeDirection.up);
    expect(cardCorner(tester).dy, lessThan(0)); // Starts above.

    await tester.pumpAndSettle();
    expect(cardCorner(tester), start);
  });
}
