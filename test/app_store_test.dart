import 'package:flutter_test/flutter_test.dart';
import 'package:rumpun/app_store.dart';

void main() {
  test('stores account metadata, timeline cache, media index, and weights', () {
    final store = AppStore.at((_) => ':memory:');
    addTearDown(store.close);

    expect(store.preferredInstance, 'mastodon.social');
    store.setPreferredInstance('social.example');
    expect(store.preferredInstance, 'social.example');
    store.saveAccount(id: '42@social.example', instance: 'https://social.example',
        username: 'reader');
    store.cacheStatuses('home', [
      {'id': 'post-1', 'content': 'hello'},
    ]);
    store.indexMedia(url: 'https://cdn.example/image.jpg', mimeType: 'image/jpeg');
    store.incrementWeight('post-1');
    store.incrementWeight('post-1', 2);

    expect(store.accounts().single['username'], 'reader');
    expect(store.cachedStatuses('home').single['content'], 'hello');
    expect(store.indexDb.select('SELECT url FROM media').single['url'],
        'https://cdn.example/image.jpg');
    expect(store.weight('post-1'), 3);
  });

  test('language preference and cache clearing round-trip', () {
    final store = AppStore.at((_) => ':memory:');
    addTearDown(store.close);

    expect(store.preferredLanguage, 'system');
    store.setPreferredLanguage('id');
    expect(store.preferredLanguage, 'id');

    store.cacheStatuses('feed-0', [
      {'id': 'p1', 'content': 'x'},
      {'id': 'p2', 'content': 'y'},
    ]);
    expect(store.cachedStatuses('feed-0'), isNotEmpty);
    store.clearCaches();
    expect(store.cachedStatuses('feed-0'), isEmpty);
    // Accounts/settings survive a cache wipe.
    expect(store.preferredInstance, 'mastodon.social');
  });

  test('persists composer drafts and keeps shared statuses across timelines', () {
    final store = AppStore.at((_) => ':memory:');
    addTearDown(store.close);

    expect(store.draft('compose'), isNull);
    store.saveDraft('compose', text: 'halo dunia', spoiler: 'cw', visibility: 'unlisted');
    expect(store.draft('compose'), {
      'text': 'halo dunia',
      'spoiler': 'cw',
      'visibility': 'unlisted',
      'in_reply_to_id': null,
      'in_reply_to_acct': null,
      'media_count': 0,
    });
    store.deleteDraft('compose');
    expect(store.draft('compose'), isNull);

    store.cacheStatuses('feed-0', [{'id': 'shared', 'content': 'a'}]);
    store.cacheStatuses('feed-1', [{'id': 'shared', 'content': 'a'}]);
    expect(store.cachedStatuses('feed-0').single['id'], 'shared');
    expect(store.cachedStatuses('feed-1').single['id'], 'shared');
  });
}
