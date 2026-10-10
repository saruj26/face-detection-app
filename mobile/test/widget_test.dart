import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glasses_tryon/app.dart';
import 'package:glasses_tryon/providers/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke test: the app starts, falls back to the bundled catalogue when the
/// backend is unreachable (HTTP is blocked in widget tests), and navigates.
void main() {
  testWidgets('app starts and shows the offline catalogue', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        retry: (_, _) => null,
        child: const GlassesTryOnApp(),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    expect(find.text('Frame Finder'), findsOneWidget);
    expect(find.text('Start live try-on'), findsOneWidget);

    await tester.tap(find.text('Catalogue'));
    await tester.pumpAndSettle();
    expect(find.text('Eyeglass catalogue'), findsOneWidget);
    expect(find.textContaining("Couldn't reach the catalogue server"), findsOneWidget);
    expect(find.text('Aviator Classic'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pumpAndSettle();
    expect(prefs.getStringList('favorite_glasses_ids'), ['1']);
  });
}
