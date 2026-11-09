import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_frames/models/keep_side.dart';
import 'package:good_frames/theme/app_theme.dart';
import 'package:good_frames/widgets/decision_buttons.dart';

import 'support/contrast.dart';

void main() {
  late ValueNotifier<double> drag;

  setUp(() {
    drag = ValueNotifier(0);
  });
  tearDown(() {
    drag.dispose();
  });

  Future<void> showButtons(
    WidgetTester tester, {
    KeepSide keepSide = KeepSide.right,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: DecisionButtons(
            onDelete: () {},
            onKeep: () {},
            onUndo: null,
            keepSide: keepSide,
            dragProgress: drag,
          ),
        ),
      ),
    );
  }

  Future<void> dragTo(WidgetTester tester, double progress) async {
    drag.value = progress;
    await tester.pumpAndSettle();
  }

  double scaleOf(WidgetTester tester, String label) => tester
      .widget<AnimatedScale>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedScale),
        ),
      )
      .scale;

  ButtonStyle styleOf(WidgetTester tester, String label) => tester
      .widget<FilledButton>(
        find.ancestor(
          of: find.text(label),
          // FilledButton.icon makes a subclass, so match on the type.
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      )
      .style!;

  Color backgroundOf(WidgetTester tester, String label) =>
      styleOf(tester, label).backgroundColor!.resolve({})!;

  testWidgets('the button the photo is heading for grows with the drag', (
    tester,
  ) async {
    await showButtons(tester);

    await dragTo(tester, -0.5); // Halfway to deleting.
    expect(scaleOf(tester, 'Delete'), greaterThan(1));
    expect(scaleOf(tester, 'Keep'), 1);

    await dragTo(tester, 0.5); // Halfway to keeping.
    expect(scaleOf(tester, 'Keep'), greaterThan(1));
    expect(scaleOf(tester, 'Delete'), 1);

    await dragTo(tester, 0); // Let go: both back to normal.
    expect(scaleOf(tester, 'Keep'), 1);
    expect(scaleOf(tester, 'Delete'), 1);
  });

  testWidgets('Delete fills in once letting go would delete', (tester) async {
    await showButtons(tester);
    final soft = backgroundOf(tester, 'Delete');

    await dragTo(tester, -0.9); // Not far enough yet.
    expect(backgroundOf(tester, 'Delete'), soft);

    await dragTo(tester, -1);
    expect(backgroundOf(tester, 'Delete'), SortColors.light.delete);

    await dragTo(tester, -0.9); // Pulled back: soft again.
    expect(backgroundOf(tester, 'Delete'), soft);
  });

  testWidgets('with the sides swapped, dragging left heads for Keep', (
    tester,
  ) async {
    await showButtons(tester, keepSide: KeepSide.left);

    await dragTo(tester, -1);
    expect(scaleOf(tester, 'Keep'), greaterThan(1));
    expect(scaleOf(tester, 'Delete'), 1);
    expect(backgroundOf(tester, 'Delete'), isNot(SortColors.light.delete));

    await dragTo(tester, 1);
    expect(backgroundOf(tester, 'Delete'), SortColors.light.delete);
  });

  testWidgets('the filled-in Delete label is readable in both themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await showButtons(tester, theme: theme);
      await dragTo(tester, -1);

      final style = styleOf(tester, 'Delete');
      expect(
        contrast(
          style.foregroundColor!.resolve({})!,
          style.backgroundColor!.resolve({})!,
        ),
        greaterThan(4.5),
        reason: theme.brightness.name,
      );
      await dragTo(tester, 0);
    }
  });
}
