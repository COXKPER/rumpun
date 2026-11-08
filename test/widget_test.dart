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
    expect(find.text('Tweets'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
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
    // Field, top-bar host, and the confirmation snackbar all show it.
    expect(find.text('social.example'), findsWidgets);
  });

  testWidgets('Tweets Fediverse tab and opening a profile work without RangeError', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FediverseApi('mastodon.social', client: MockClient((request) async {
      if (request.url.path == '/api/v1/accounts/lookup') {
        return http.Response(jsonEncode({
          'id': '99',
          'username': 'raka',
          'acct': 'raka',
          'display_name': 'Raka',
          'note': '<p>Hello</p>',
        }), 200);
      }
      if (request.url.path == '/api/v1/statuses/orig-1/context') {
        return http.Response(jsonEncode({'ancestors': [], 'descendants': []}), 200);
      }
      if (request.url.path.startsWith('/api/v1/timelines/') ||
          request.url.path == '/api/v1/trends/statuses') {
        return http.Response(jsonEncode([
          {
            'id': 'reblog-99',
            'account': {'id': '88', 'username': 'budi', 'acct': 'budi', 'display_name': 'Budi'},
            'reblog': {
              'id': 'orig-1',
              'content': '<p>Post body</p>',
              'account': {'id': '99', 'username': 'raka', 'acct': 'raka', 'display_name': 'Raka'},
              'media_attachments': [
                {'id': 'm1', 'type': 'gifv', 'url': 'https://cdn.example/clip.mp4', 'description': 'Looping clip'},
                {'id': 'm2', 'type': 'audio', 'url': 'https://cdn.example/song.mp3', 'description': 'Audio track'},
              ],
            },
          }
        ]), 200);
      }
      return http.Response(jsonEncode([]), 200);
    }));
    final store = AppStore.at((_) => ':memory:');
    await tester.pumpWidget(RumpunApp(api: api, store: store));
    await tester.pumpAndSettle();

    expect(find.text('Budi reposted'), findsOneWidget);
    expect(find.text('GIF'), findsOneWidget);
    expect(find.byIcon(Icons.audio_file_outlined), findsOneWidget);
    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();
    expect(find.text('Budi reposted'), findsOneWidget);
    // Tapping the active pill again triggers scroll-to-top + silent refresh cleanly.
    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();
    // Tapping the signed-out public timeline banner opens the login dialog.
    await tester.tap(find.text('Public timeline · Sign in to follow accounts and post'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post body'));
    await tester.pumpAndSettle();
    expect(find.text('Conversation'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Switch to the Tweets (Fediverse posts) tab and verify its Trending pill.
    await tester.tap(find.text('Tweets'));
    await tester.pumpAndSettle();
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Post body'), findsOneWidget);
    await tester.tap(find.text('Trending'));
    await tester.pumpAndSettle();
    expect(find.text('Post body'), findsOneWidget);

    await tester.tap(find.text('Raka'));
    await tester.pumpAndSettle();
    expect(find.text('@raka'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('You'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
