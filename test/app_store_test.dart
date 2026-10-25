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
}
