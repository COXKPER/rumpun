import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun/main.dart';

void main() {
  testWidgets('navigates all main screens', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RumpunApp());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Federated'), findsOneWidget);
    expect(find.textContaining('Beautiful morning'), findsOneWidget);

    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    expect(find.text('Trending hashtags'), findsOneWidget);
    expect(find.text('Linux'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Raka replied to your post'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('@kamu@ruang.id'), findsOneWidget);
    expect(find.text('128 Followers'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
  });

  testWidgets('opens compose modal with CW, visibility, and alt text',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RumpunApp());

    await tester.tap(find.text('What do you want to share?'));
    await tester.pumpAndSettle();
    expect(find.text('Write Post'), findsOneWidget);
    expect(find.text('Add CW'), findsOneWidget);
    expect(find.text('Sensitive'), findsOneWidget);
    expect(find.text('Has photo'), findsOneWidget);

    // Toggle CW - should show the CW TextField
    await tester.tap(find.text('Add CW'));
    await tester.pumpAndSettle();
    expect(find.text('Content warning'), findsOneWidget);

    // Close by tapping outside
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(find.text('Write Post'), findsNothing);
  });

  testWidgets('search bar filters results', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RumpunApp());

    // Go to Explore
    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();

    // Switch to Accounts category
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();

    // Type search query
    await tester.enterText(find.byType(SearchBar), 'nadia');
    await tester.pumpAndSettle();

    // Should show results
    expect(find.text('Nadia Putri'), findsOneWidget);
  });

  testWidgets('collapses and reveals content warning posts', (tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RumpunApp());

    // Ensure the CW post is visible (it's below the fold)
    await tester.ensureVisible(find.text('Citra Dewi'));
    await tester.pumpAndSettle();

    // The CW post should show warning button
    expect(find.text('View post'), findsOneWidget);

    // Tap to reveal
    await tester.tap(find.text('View post'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Personal reflection'), findsOneWidget);
  });

  testWidgets('opens thread conversation sheet', (tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RumpunApp());

    // Tap the first post (Nadia Putri) which has no CW
    await tester.tap(find.textContaining('Beautiful morning').first);
    await tester.pumpAndSettle();

    // Thread sheet should show
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Raka Wirawan'), findsOneWidget);
    expect(find.textContaining('Agreed! It is wonderful'), findsOneWidget);

    // Close the thread
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Conversation'), findsNothing);
  });

  testWidgets('profile tabs switch content', (tester) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RumpunApp());

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    // Posts tab should be active by default
    expect(find.text('Posts'), findsWidgets);

    // Switch to Replies
    await tester.tap(find.text('Replies'));
    await tester.pumpAndSettle();
    expect(find.text('Your replies will appear here'), findsOneWidget);

    // Switch to Media
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(find.text('Media you upload will appear here'), findsOneWidget);
  });
}
