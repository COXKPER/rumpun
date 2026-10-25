import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumpun/app_store.dart';
import 'package:rumpun/fediverse_api.dart';
import 'package:rumpun/main.dart';

RumpunApp testApp() {
  final api = FediverseApi('mastodon.social', client: MockClient((_) async =>
      http.Response(jsonEncode([]), 200)));
  final store = AppStore.at((_) => ':memory:');
  return RumpunApp(api: api, store: store);
}

void main() {
  testWidgets('signed-out shell shows live browsing and login, not fixtures', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Federated'), findsOneWidget);
    expect(find.text('Beautiful morning'), findsNothing);
    expect(find.text('Raka replied to your post'), findsNothing);
    expect(find.byTooltip('Log in'), findsOneWidget);
    await tester.tap(find.byTooltip('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('mastodon.social'), findsWidgets);
  });

  testWidgets('settings lets user change default public server', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Default instance'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'social.example');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('social.example'), findsOneWidget);
  });
}
