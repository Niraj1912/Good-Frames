import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_swipe/widgets/swipe_card.dart';

// The sort screen has no buttons for deciding: photos are swiped. These
// do what the user's thumb does, in screen directions (so with Keep on the
// right, swipeRight keeps).
Future<void> swipeRight(WidgetTester tester) => _swipe(tester, 400, 0);
Future<void> swipeLeft(WidgetTester tester) => _swipe(tester, -400, 0);
Future<void> swipeUp(WidgetTester tester) => _swipe(tester, 0, -400);

Future<void> _swipe(WidgetTester tester, double dx, double dy) async {
  await tester.drag(find.byType(SwipeCard), Offset(dx, dy));
  await tester.pumpAndSettle();
}

/// The photo on top of the pile. Its file name isn't shown on screen, but it
/// is what a screen reader announces, so tests find the photo by that.
Finder showing(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == name &&
      widget.properties.image == true,
);
