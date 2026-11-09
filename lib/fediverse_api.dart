import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Mastodon-compatible REST client. Large JSON responses decode off the UI isolate.
class FediverseApi {
  FediverseApi(String instance, {http.Client? client})
      : instance = _normalizeInstance(instance),
        _client = client ?? http.Client();

  final Uri instance;
  final http.Client _client;
  String? accessToken;
  static const _secureStorage = FlutterSecureStorage();

  static Uri _normalizeInstance(String value) {
    final uri = Uri.parse(value.contains('://') ? value : 'https://$value');
    if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Enter a valid Fediverse server URL.');
    }
    return uri.replace(path: uri.path == '/' ? '' : uri.path);
  }

  Uri endpoint(String path, [Map<String, String>? query]) =>
      instance.resolve(path).replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<dynamic> _request(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final uri = endpoint(path, query);
    final headers = {..._headers, if (body != null) 'Content-Type': 'application/json'};
    final response = await (switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(uri, headers: headers, body: jsonEncode(body)),
      'PUT' => _client.put(uri, headers: headers, body: jsonEncode(body)),
      'PATCH' => _client.patch(uri, headers: headers, body: jsonEncode(body)),
      'DELETE' => _client.delete(uri, headers: headers),
      _ => throw ArgumentError.value(method, 'method'),
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FediverseException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) return null;
    return response.body.length > 50000
        ? await computeJsonDecode(response.body)
        : jsonDecode(response.body);
  }

  static String get defaultClientName {
    final os = Platform.isAndroid
        ? 'Android'
        : Platform.isLinux
            ? 'Linux'
            : Platform.isWindows
                ? 'Windows'
                : Platform.isMacOS
                    ? 'macOS'
                    : Platform.isIOS
                        ? 'iOS'
                        : 'Desktop';
    return 'Rumpun for $os';
  }

  Future<Map<String, dynamic>> registerApp(String redirectUri,
          {String? clientName}) async =>
      (await _request('POST', '/api/v1/apps', body: {
        'client_name': clientName ?? defaultClientName,
        'redirect_uris': redirectUri,
        'scopes': 'read write follow',
      })) as Map<String, dynamic>;

  Uri authorizationUri({required String clientId, required String redirectUri,
      required String state}) => endpoint('/oauth/authorize', {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': 'read write follow',
        'state': state,
      });

  Future<String> exchangeCode({required String clientId,
      required String clientSecret, required String code,
      required String redirectUri}) async {
    final result = await _request('POST', '/oauth/token', body: {
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'client_secret': clientSecret,
      'redirect_uri': redirectUri,
      'code': code,
    }) as Map<String, dynamic>;
    final token = result['access_token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('The server did not return an access token.');
    }
    return accessToken = token;
  }

  Future<void> saveToken(String accountId) async {
    final token = accessToken;
    if (token == null) throw StateError('No access token to store.');
    await _secureStorage.write(key: 'fediverse:$accountId', value: token);
  }

  Future<void> restoreToken(String accountId) async =>
      accessToken = await _secureStorage.read(key: 'fediverse:$accountId');

  Future<void> deleteToken(String accountId) async {
    await _secureStorage.delete(key: 'fediverse:$accountId');
    accessToken = null;
  }

  Future<List<Map<String, dynamic>>> timeline({String type = 'home',
      int limit = 20, String? maxId, bool local = true}) async {
    if (type != 'home' && type != 'public') {
      throw ArgumentError.value(type, 'type');
    }
    final data = await _request('GET', '/api/v1/timelines/$type', query: {
      'limit': '$limit',
      if (maxId != null) 'max_id': maxId,
      if (type == 'public') 'local': '$local',
    }) as List;
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> post(String content, {String visibility = 'public',
      String? spoilerText, String? inReplyToId, List<String> mediaIds = const [],
      bool sensitive = false, String? language, Map<String, dynamic>? poll}) async =>
      (await _request('POST', '/api/v1/statuses', body: {
        'status': content,
        'visibility': visibility,
        if (sensitive) 'sensitive': 'true',
        if (language != null) 'language': language,
        if (spoilerText?.isNotEmpty == true) 'spoiler_text': spoilerText,
        if (inReplyToId != null) 'in_reply_to_id': inReplyToId,
        if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
        if (poll != null) 'poll': poll,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> editStatus(String statusId, String content,
          {String? spoilerText,
          List<String>? mediaIds,
          bool? sensitive}) async =>
      (await _request('PUT', '/api/v1/statuses/$statusId', body: {
        'status': content,
        if (spoilerText != null) 'spoiler_text': spoilerText,
        if (mediaIds != null) 'media_ids': mediaIds,
        if (sensitive != null) 'sensitive': '$sensitive',
      })) as Map<String, dynamic>;

  Future<void> deleteStatus(String statusId) async =>
      _request('DELETE', '/api/v1/statuses/$statusId');

  Future<Map<String, dynamic>> action(String statusId, String action) async {
    const actions = {
      'like': 'favourite', 'unlike': 'unfavourite',
      'repost': 'reblog', 'unrepost': 'unreblog',
      'bookmark': 'bookmark', 'unbookmark': 'unbookmark',
    };
    final endpointAction = actions[action];
    if (endpointAction == null) throw ArgumentError.value(action, 'action');
    return (await _request('POST', '/api/v1/statuses/$statusId/$endpointAction', body: {}))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> search(String query, {String? type}) async =>
      (await _request('GET', '/api/v2/search', query: {
        'q': query,
        if (type != null) 'type': type,
        'resolve': 'true',
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> currentUser() async =>
      (await _request('GET', '/api/v1/accounts/verify_credentials')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> lookupAccount(String acct) async =>
      (await _request('GET', '/api/v1/accounts/lookup', query: {'acct': acct}))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> accountStatuses(String accountId,
          {int limit = 20, bool excludeReplies = true, bool onlyMedia = false}) async =>
      ((await _request('GET', '/api/v1/accounts/$accountId/statuses',
                  query: {
                    'limit': '$limit',
                    'exclude_replies': '$excludeReplies',
                    if (onlyMedia) 'only_media': 'true',
                  }))
              as List)
          .cast<Map<String, dynamic>>();

  /// `/relationships` answers `following` for many accounts at once; asking
  /// for a single id keeps the call site simple.
  Future<Map<String, dynamic>> relationship(String accountId) async =>
      ((await _request('GET', '/api/v1/accounts/relationships',
              query: {'id[]': accountId})) as List)
          .cast<Map<String, dynamic>>()
          .first;

  /// Follow/unfollow returns a Relationship object with `following` and
  /// `requested`; a locked account only ever flips `requested`.
  Future<Map<String, dynamic>> follow(String accountId, {bool follow = true}) async =>
      (await _request('POST', '/api/v1/accounts/$accountId/${follow ? 'follow' : 'unfollow'}',
              body: {})) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trendingTags({int limit = 10}) async =>
      ((await _request('GET', '/api/v1/trends/tags',
                  query: {'limit': '$limit'}))
              as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> trendingAccounts({int limit = 10}) async =>
      ((await _request('GET', '/api/v1/trends/people',
                  query: {'limit': '$limit'}))
              as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> trendingStatuses({int limit = 10}) async =>
      ((await _request('GET', '/api/v1/trends/statuses',
                  query: {'limit': '$limit'}))
              as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> searchAccounts(String query) async {
    final result = await _request('GET', '/api/v2/search', query: {
      'q': query,
      'type': 'accounts',
      'resolve': 'true',
    }) as Map<String, dynamic>;
    return (result['accounts'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> bookmarks({int limit = 20, String? maxId}) async =>
      ((await _request('GET', '/api/v1/bookmarks', query: {
        'limit': '$limit',
        if (maxId != null) 'max_id': maxId,
      })) as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> notifications({int limit = 20,
      String? maxId, List<String>? types, List<String>? excludeTypes}) async =>
      ((await _request('GET', '/api/v1/notifications', query: {
        'limit': '$limit',
        if (maxId != null) 'max_id': maxId,
        for (final type in types ?? const <String>[]) 'types[]': type,
        for (final type in excludeTypes ?? const <String>[]) 'exclude_types[]': type,
      })) as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> followRequestAuthorize(String accountId,
          {required bool authorize}) async =>
      (await _request('POST',
          '/api/v1/follow_requests/$accountId/${authorize ? 'authorize' : 'reject'}',
          body: {})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateMedia(String mediaId,
          {String? description}) async =>
      (await _request('PUT', '/api/v1/media/$mediaId',
              body: description == null
                  ? const <String, dynamic>{}
                  : <String, dynamic>{'description': description}))
          as Map<String, dynamic>;

  Future<void> dismissNotification(String notificationId) async =>
      _request('DELETE', '/api/v1/notifications/$notificationId');

  /// Registers an FCM / UnifiedPush / WebPush subscription with the server.
  Future<Map<String, dynamic>> registerPushSubscription({
    required String endpoint,
    String p256dh = 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkvMeAtA3LFgDzkrxZJjSgSnfckjBJuBkr3qBUYIHBQFLXYp5Nksh8U',
    String auth = 'UUQM042PCZrN2_2842b6vA',
    Map<String, bool>? alerts,
  }) async =>
      (await _request('POST', '/api/v1/push/subscription', body: {
        'subscription': {
          'endpoint': endpoint,
          'keys': {'p256dh': p256dh, 'auth': auth},
        },
        'data': {
          'alerts': alerts ??
              const {
                'mention': true,
                'status': true,
                'reblog': true,
                'follow': true,
                'follow_request': true,
                'favourite': true,
                'poll': true,
              },
        },
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> pushSubscription() async =>
      (await _request('GET', '/api/v1/push/subscription')) as Map<String, dynamic>;

  Future<void> deletePushSubscription() async =>
      _request('DELETE', '/api/v1/push/subscription');

  Future<List<Map<String, dynamic>>> customEmojis() async =>
      ((await _request('GET', '/api/v1/custom_emojis')) as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> thread(String statusId) async {
    final context = await _request('GET', '/api/v1/statuses/$statusId/context') as Map<String, dynamic>;
    return [...(context['ancestors'] as List).cast<Map<String, dynamic>>(),
      ...(context['descendants'] as List).cast<Map<String, dynamic>>()];
  }

  Future<Map<String, dynamic>> uploadMedia(File file, {String? description}) async {
    final request = http.MultipartRequest('POST', endpoint('/api/v2/media'))
      ..headers.addAll(_headers)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    if (description?.isNotEmpty == true) request.fields['description'] = description!;
    final response = await http.Response.fromStream(await _client.send(request));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FediverseException(response.statusCode, response.body);
    }
    return (jsonDecode(response.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> updateCredentials({
    File? avatar,
    File? header,
    String? displayName,
    String? note,
  }) async {
    final request = http.MultipartRequest(
        'PATCH', endpoint('/api/v1/accounts/update_credentials'))
      ..headers.addAll(_headers);
    if (avatar != null) {
      request.files.add(await http.MultipartFile.fromPath('avatar', avatar.path));
    }
    if (header != null) {
      request.files.add(await http.MultipartFile.fromPath('header', header.path));
    }
    if (displayName != null) request.fields['display_name'] = displayName;
    if (note != null) request.fields['note'] = note;
    final response = await http.Response.fromStream(await _client.send(request));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FediverseException(response.statusCode, response.body);
    }
    return (jsonDecode(response.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> votePoll(String pollId, List<int> choices) async =>
      (await _request('POST', '/api/v1/polls/$pollId/votes',
          body: {'choices': choices.map((c) => '$c').toList()}))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> tagTimeline(String tag,
      {int limit = 20, String? maxId}) async =>
      ((await _request('GET', '/api/v1/timelines/tag/$tag', query: {
        'limit': '$limit',
        if (maxId != null) 'max_id': maxId,
      })) as List)
          .cast<Map<String, dynamic>>();

  void close() => _client.close();
}

class FediverseException implements Exception {
  const FediverseException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return 'Fediverse API error ($statusCode): ${decoded['error']}';
      }
    } catch (_) {}
    return 'Fediverse API error ($statusCode): $body';
  }
}

// `Isolate.run` keeps large response parsing off the UI isolate without a dependency.
Future<dynamic> computeJsonDecode(String input) => Isolate.run(() => jsonDecode(input));
