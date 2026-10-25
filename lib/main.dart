import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_store.dart';
import 'fediverse_api.dart';
import 'image_cache.dart';
import 'oauth_callback.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const RumpunApp());
}

const _green = Color(0xFF236B55);
FediverseApi? _activeApi;
AppStore? _appStore;
Map<String, dynamic>? _currentAccount;
String? _currentAccountId;
String _instance = 'mastodon.social';

class RumpunApp extends StatefulWidget {
  const RumpunApp({super.key, this.api, this.store});
  final FediverseApi? api;
  final AppStore? store;
  @override
  State<RumpunApp> createState() => _RumpunAppState();
}

class _RumpunAppState extends State<RumpunApp> {
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final store = widget.store ?? await AppStore.open();
    _appStore = store;
    _instance = store.preferredInstance;
    if (widget.api != null) {
      _activeApi = widget.api;
      if (mounted) setState(() => _ready = true);
      return;
    }
    final accounts = store.accounts();
    if (accounts.isNotEmpty) {
      final saved = accounts.first;
      final api = FediverseApi(saved['instance'] as String);
      try {
        await api.restoreToken(saved['id'] as String);
        final account = await api.currentUser();
        _currentAccountId = saved['id'] as String;
        _currentAccount = account;
        _activeApi = api;
      } catch (_) {
        api.close();
        _activeApi = FediverseApi(_instance);
      }
    } else {
      _activeApi = FediverseApi(_instance);
    }
    if (mounted) setState(() => _ready = true);
  }

  /// Resolves the persisted language preference into a locale override.
  Locale? get _localeOverride {
    final tag = _appStore?.preferredLanguage ?? 'system';
    if (tag == 'system' || tag.isEmpty) return null;
    return Locale(tag);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Fediverse',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _green),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFFAFAF8),
          cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: _green, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        locale: _localeOverride,
        supportedLocales: const [Locale('en'), Locale('id')],
        home: _ready ? const RumpunShell() : const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
}

class Post {
  const Post(this.status, this.instance);
  final Map<String, dynamic> status;
  final String instance;

  Map<String, dynamic> get data =>
      status['reblog'] as Map<String, dynamic>? ?? status;
  Map<String, dynamic> get account =>
      data['account'] as Map<String, dynamic>? ?? {};
  String get id => data['id'] as String? ?? '';
  String get acct => account['acct'] as String? ?? 'unknown';
  String get handle => acct.contains('@') ? '@$acct' : '@$acct@$instance';
  String get name => (account['display_name'] as String?)?.isNotEmpty == true
      ? account['display_name'] as String
      : account['username'] as String? ?? acct;
  String get content => data['content'] as String? ?? '';
}

class RumpunShell extends StatefulWidget {
  const RumpunShell({super.key});
  @override
  State<RumpunShell> createState() => _RumpunShellState();
}

class _RumpunShellState extends State<RumpunShell> {
  final _homeKey = GlobalKey<_HomeScreenState>();
  int _page = 0;
  Map<String, dynamic>? _profileAccount;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final pages = [
      HomeScreen(key: _homeKey, onOpenProfile: _openProfile),
      ExploreScreen(onOpenProfile: _openProfile),
      const ActivityScreen(),
      _profileAccount == null
          ? ProfileScreen(account: _currentAccount, accountId: _currentAccountId,
              onOpenProfile: _openProfile)
          : ProfileScreen(account: _profileAccount,
              onOpenProfile: _openProfile),
    ];
    return Scaffold(
      floatingActionButton: _currentAccount == null
          ? null
          : FloatingActionButton(
              tooltip: 'New post',
              onPressed: _compose,
              child: const Icon(Icons.add)),
      body: SafeArea(
        child: Column(children: [
          _TopBar(onAccount: _openAccount, onSettings: _settings),
          Expanded(
            child: Row(children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _page,
                  onDestinationSelected: (i) => setState(() {
                    _page = i;
                    if (i != 3) _profileAccount = null;
                  }),
                  destinations: const [
                    NavigationRailDestination(
                        icon: Icon(Icons.home_outlined), label: Text('Home')),
                    NavigationRailDestination(
                        icon: Icon(Icons.search), label: Text('Explore')),
                    NavigationRailDestination(
                        icon: Icon(Icons.notifications_none), label: Text('Notifications')),
                    NavigationRailDestination(
                        icon: Icon(Icons.person_outline), label: Text('Account')),
                  ],
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: pages[_page],
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (i) => setState(() {
                _page = i;
                if (i != 3) _profileAccount = null;
              }),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
                NavigationDestination(
                    icon: Icon(Icons.notifications_none), label: 'Notifications'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline), label: 'Account'),
              ],
            ),
    );
  }

  Future<void> _compose() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => _ComposeSheet(
          onPosted: () async {
            if (sheetContext.mounted) Navigator.pop(sheetContext);
            setState(() => _page = 0);
            await _homeKey.currentState?._refresh(silent: true);
          },
        ),
      );

  Future<void> _openProfile(String acct) async {
    final api = _activeApi;
    if (api == null) return;
    try {
      final result = await api.lookupAccount(acct);
      if (!mounted) return;
      setState(() {
        _profileAccount = result;
        _page = 3;
      });
    } catch (error) {
      if (mounted) _message('Could not load profile: $error');
    }
  }

  void _openAccount() {
    if (_currentAccount != null) {
      setState(() {
        _profileAccount = _currentAccount;
        _page = 3;
      });
    } else {
      _login();
    }
  }

  Future<void> _login() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ConnectDialog(instance: _instance),
    );
    if (mounted) setState(() {});
  }

  Future<void> _settings() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _InstanceSettingsDialog(instance: _instance),
    );
    if (!mounted) return;
    // Rebuild even on Cancel: the language dropdown may have changed locale.
    setState(() {});
    if (value == null || value.isEmpty) return;
    try {
      final next = FediverseApi(value);
      _instance = next.instance.host;
      _appStore?.setPreferredInstance(_instance);
      if (_currentAccount == null) {
        _activeApi?.close();
        _activeApi = next;
      } else {
        next.close();
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _message('Invalid server address: $error');
    }
  }

  Future<void> _logout() async {
    final api = _activeApi;
    final id = _currentAccountId;
    if (api != null && id != null) await api.deleteToken(id);
    _appStore?.deleteAccount(id ?? '');
    api?.close();
    _currentAccount = null;
    _currentAccountId = null;
    _activeApi = FediverseApi(_instance);
    if (mounted) {
      setState(() {
        _page = 0;
        _profileAccount = null;
      });
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _settingsFromMenu() => _settings();
}

class _InstanceSettingsDialog extends StatefulWidget {
  const _InstanceSettingsDialog({required this.instance});
  final String instance;

  @override
  State<_InstanceSettingsDialog> createState() => _InstanceSettingsDialogState();
}

class _InstanceSettingsDialogState extends State<_InstanceSettingsDialog> {
  late final _controller = TextEditingController(text: widget.instance);
  late String _language = _appStore?.preferredLanguage ?? 'system';
  bool _clearing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    _appStore?.clearCaches();
    await CachedNetworkImage.wipe();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Default instance'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(labelText: 'Language'),
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System default')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'id', child: Text('Bahasa Indonesia')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _language = value);
                _appStore?.setPreferredLanguage(value);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _clearing ? null : _clearCache,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: Text(_clearing ? 'Clearing…' : 'Clear cache'),
              ),
              const Spacer(),
              if (_currentAccount != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () {
                    Navigator.pop(context);
                    context
                        .findAncestorStateOfType<_RumpunShellState>()
                        ?._logout();
                  },
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Log out'),
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onAccount, required this.onSettings});
  final VoidCallback onAccount;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
        child: Row(children: [
          const Icon(Icons.public, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_activeApi?.instance.host ?? _instance,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(width: 8),
          IconButton(
              tooltip: _currentAccount == null ? 'Log in' : 'My account',
              onPressed: onAccount,
              icon: _currentAccount == null
                  ? const Icon(Icons.account_circle_outlined)
                  : CircleAvatar(
                      radius: 14,
                      backgroundImage: CachedNetworkImage(
                          _currentAccount!['avatar'] as String? ?? '',
                          maxWidthPx: 56, maxHeightPx: 56),
                      onBackgroundImageError: (_, __) {},
                    ),
          ),
          IconButton(
              tooltip: 'Settings',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined)),
        ]),
      );
}

class _OAuthCancelled implements Exception {}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.onPosted});
  final Future<void> Function() onPosted;
  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _text = TextEditingController();
  final _spoiler = TextEditingController();
  final _attachments = <Map<String, dynamic>>[];
  bool _posting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _spoiler.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    const typeGroup = XTypeGroup(label: 'Media', extensions: [
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'webm', 'mov', 'mp3', 'ogg'
    ]);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    for (final file in files) {
      if (_attachments.length >= 4) break;
      setState(() => _attachments.add({'path': file.path, 'status': 'uploading'}));
      try {
        final media = await _activeApi!.uploadMedia(File(file.path));
        setState(() => _attachments[_attachments.indexOf(
            {'path': file.path, 'status': 'uploading'})] = {
          'path': file.path,
          'status': 'done',
          'id': media['id'],
          'preview': media['preview_url'] as String?,
        });
      } catch (error) {
        setState(() {
          _attachments.removeWhere((item) => item['path'] == file.path);
          _error = 'Upload failed: $error';
        });
      }
    }
  }

  Future<void> _submit() async {
    final content = _text.text.trim();
    if (content.isEmpty && _attachments.isEmpty || _posting) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await _activeApi!.post(
        content.isEmpty ? '.' : content,
        spoilerText: _spoiler.text,
        mediaIds: [
          for (final attachment in _attachments) attachment['id'] as String
        ],
      );
      _text.clear();
      _spoiler.clear();
      await widget.onPosted();
    } catch (error) {
      if (mounted) {
        setState(() {
          _posting = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('New post', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 4),
          TextField(
              controller: _text,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              maxLength: 500,
              decoration:
                  const InputDecoration(hintText: 'Write a post', border: OutlineInputBorder())),
          for (final attachment in _attachments)
            ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file),
              title: Text(attachment['path'].toString().split('/').last,
                  overflow: TextOverflow.ellipsis),
              trailing: attachment['status'] == 'done'
                  ? const Icon(Icons.check, color: Colors.green)
                  : const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          TextField(
              controller: _spoiler,
              decoration: const InputDecoration(
                  hintText: 'Content warning (optional)',
                  border: OutlineInputBorder())),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Row(children: [
            IconButton(
                tooltip: 'Attach media',
                onPressed: _attachments.length >= 4 || _posting ? null : _pickMedia,
                icon: const Icon(Icons.add_photo_alternate_outlined)),
            const Spacer(),
            FilledButton(
              onPressed: _text.text.trim().isEmpty && _attachments.isEmpty ||
                      _posting ||
                      _attachments.any((a) => a['status'] != 'done')
                  ? null
                  : _submit,
              child: Text(_posting ? 'Posting…' : 'Post'),
            ),
          ]),
        ]),
      );
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.instance});
  final String instance;
  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late final _instanceController = TextEditingController(text: widget.instance);
  bool _busy = false;
  String? _error;
  Completer<void>? _cancelOAuth;
  @override
  void dispose() {
    _instanceController.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_busy) {
      if (!(_cancelOAuth?.isCompleted ?? true)) _cancelOAuth!.complete();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _cancelOAuth = Completer<void>();
    final api = FediverseApi(_instanceController.text.trim());
    HttpServer? server;
    AppStore? store;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = 'http://127.0.0.1:${server.port}/oauth/callback';
      final random = Random.secure();
      final state = base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final callback = receiveOAuthCode(server, state);
      final app = await api.registerApp(redirectUri);
      final clientId = app['client_id'] as String?;
      final clientSecret = app['client_secret'] as String?;
      if (clientId == null || clientSecret == null) {
        throw const FormatException('The server did not return OAuth app credentials.');
      }
      if (!await launchUrl(
          api.authorizationUri(
              clientId: clientId, redirectUri: redirectUri, state: state),
          mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open the system browser.');
      }
      final code = await Future.any([
        callback.timeout(const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Authorization timed out.')),
        _cancelOAuth!.future.then<String>((_) => throw _OAuthCancelled()),
      ]);
      await api.exchangeCode(
          clientId: clientId,
          clientSecret: clientSecret,
          code: code,
          redirectUri: redirectUri);
      final account = await api.currentUser();
      final accountId = account['id'];
      if (accountId == null) throw const FormatException('The server returned no account ID.');
      final id = '$accountId@${api.instance.host}';
      await api.saveToken(id);
      store = _appStore ?? await AppStore.open();
      store.saveAccount(
          id: id,
          instance: api.instance.toString(),
          username: account['username'] as String?,
          displayName: account['display_name'] as String?);
      final oldApi = _activeApi;
      _activeApi = api;
      _appStore = store;
      _currentAccount = account;
      _currentAccountId = id;
      store.setPreferredInstance(api.instance.host);
      _instanceController.text = api.instance.host;
      _instance = api.instance.host;
      oldApi?.close();
      if (mounted) Navigator.pop(context);
    } on _OAuthCancelled {
      api.close();
    } catch (error) {
      store?.close();
      api.close();
      if (mounted) setState(() => _error = error.toString());
    } finally {
      await server?.close(force: true);
      _cancelOAuth = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Log in'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Choose your home server. Authorization opens in your browser.'),
            const SizedBox(height: 12),
            TextField(
                controller: _instanceController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Instance')),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: _cancel, child: const Text('Cancel')),
          FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? 'Waiting…' : 'Continue')),
        ],
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenProfile});
  final ValueChanged<String> onOpenProfile;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _feed = 0;
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    // Show the cached feed instantly; the network refresh then updates it.
    final cached = _appStore?.cachedStatuses('feed-0');
    if (cached != null && cached.isNotEmpty) {
      _statuses = cached;
      _loading = false;
    }
    _refresh();
  }

  Future<void> _refresh({bool silent = false}) async {
    final api = _activeApi;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await api.timeline(
          type: _feed == 0 && _currentAccount != null ? 'home' : 'public',
          local: _feed == 1);
      _appStore?.cacheStatuses('feed-$_feed', data);
      if (mounted) setState(() => _statuses = data);
    } catch (error) {
      if (mounted && !silent) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _PageTitle(title: _feed == 0 ? 'Home' : 'Public'),
        _TimelineFilter(
          selected: _feed,
          options: const ['Following', 'Local', 'Federated'],
          onSelect: (i) {
            setState(() => _feed = i);
            // Cached feed renders instantly; refresh reconciles in the background.
            final cached = _appStore?.cachedStatuses('feed-$i');
            if (cached != null && cached.isNotEmpty) {
              setState(() => _statuses = cached);
            } else {
              setState(() => _statuses = []);
            }
            _refresh(silent: true);
          },
        ),
        if (_currentAccount == null)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Public timeline · Sign in to follow accounts and post')),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _StateMessage(message: _error!, action: _refresh),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _statuses.length,
              // Ghost feeds the blur-ahead area so scrolling never shows blanks.
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _PostTile(
                post: Post(_statuses[i], _activeApi!.instance.host),
                onProfile: widget.onOpenProfile,
                onTap: () => _openThread(context, _statuses[i]),
              ),
            ),
          ),
        ),
      ]);

  Future<void> _openThread(BuildContext context, Map<String, dynamic> status) =>
      showDialog<void>(
        context: context,
        builder: (_) => FutureBuilder<List<Map<String, dynamic>>>(
          future: _activeApi?.thread(status['id'] as String? ?? ''),
          builder: (context, snapshot) => AlertDialog(
            title: const Text('Conversation'),
            content: SizedBox(
              width: 520,
              child: snapshot.hasError
                  ? Text('${snapshot.error}')
                  : snapshot.connectionState != ConnectionState.done
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            ...?snapshot.data?.map((item) => _PostTile(
                                  post: Post(item, _activeApi!.instance.host),
                                  onProfile: widget.onOpenProfile,
                                  onTap: () {},
                                )),
                            _PostTile(
                              post: Post(status, _activeApi!.instance.host),
                              onProfile: widget.onOpenProfile,
                              onTap: () {},
                            ),
                          ],
                        ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ),
        ),
      );
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.onOpenProfile});
  final ValueChanged<String> onOpenProfile;
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  String _category = 'Tags';
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _tags = [];
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _trending();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _trending() async {
    try {
      final api = _activeApi!;
      final results = await Future.wait([
        api.trendingTags(),
        api.trendingAccounts(),
        api.trendingStatuses(),
      ]);
      if (mounted) {
        setState(() {
          _tags = results[0];
          _people = results[1];
          _statuses = results[2];
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _doSearch(String query) async {
    setState(() {
      _query = query;
      _error = null;
    });
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    try {
      final data = await _activeApi!.searchAccounts(query.trim());
      if (mounted) setState(() => _results = data);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const _PageTitle(title: 'Explore'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBar(
            controller: _search,
            hintText: 'Search accounts',
            leading: const Icon(Icons.search),
            onSubmitted: _doSearch,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Tags', label: Text('Tags')),
            ButtonSegment(value: 'People', label: Text('People')),
            ButtonSegment(value: 'Posts', label: Text('Posts')),
          ],
          selected: {_category},
          onSelectionChanged: (value) => setState(() => _category = value.first),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _StateMessage(message: _error!, action: _trending),
        Expanded(
          child: _query.isNotEmpty && _category == 'People'
              ? ListView(children: [for (final account in _results) _AccountRow(account: account, onTap: () => widget.onOpenProfile(account['acct'] as String? ?? ''))])
              : ListView(children: [
                  if (_category == 'Tags')
                    for (final tag in _tags)
                      ListTile(
                        leading: const Icon(Icons.tag),
                        title: Text(tag['name'] as String? ?? ''),
                        subtitle: Text('${tag['history']?.length ?? 0} recent posts'),
                      ),
                  if (_category == 'People' && _query.isEmpty)
                    for (final item in _people)
                      _AccountRow(account: item['account'] as Map<String, dynamic>? ?? item, onTap: () => widget.onOpenProfile((item['account'] as Map<String, dynamic>?)?['acct'] as String? ?? '')),
                  if (_category == 'Posts')
                    for (final status in _statuses)
                      _PostTile(post: Post(status, _activeApi!.instance.host), onProfile: widget.onOpenProfile, onTap: () {}),
                ]),
        ),
      ]);
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_currentAccount == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await _activeApi!.notifications();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _PageTitle(
            title: 'Notifications',
            action: _currentAccount == null
                ? null
                : IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh))),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _StateMessage(message: _error!, action: _load),
        Expanded(
          child: _currentAccount == null
              ? Center(child: FilledButton.tonalIcon(
                  onPressed: () {
                    final shell =
                        context.findAncestorStateOfType<_RumpunShellState>();
                    shell?._openAccount();
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Log in to see notifications')))
              : _items.isEmpty && !_loading
                  ? const Center(child: Text('No notifications yet'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(children: [
                        for (final item in _items)
                          _NotificationTile(item: item),
                      ]),
                    ),
        ),
      ]);
}

/// Maps Mastodon notification types to readable text and icons.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final account = item['account'] as Map<String, dynamic>? ?? {};
    final name = (account['display_name'] as String?)?.isNotEmpty == true
        ? account['display_name'] as String
        : account['username'] as String? ??
            account['acct'] as String? ??
            'Someone';
    final status = item['status'] as Map<String, dynamic>?;
    final type = item['type'] as String? ?? '';
    final (icon, text) = switch (type) {
      'follow' => (Icons.person_add_alt, 'followed you'),
      'favourite' => (Icons.favorite_border, 'liked your post'),
      'reblog' => (Icons.repeat, 'boosted your post'),
      'mention' => (Icons.alternate_email, 'mentioned you'),
      'poll' => (Icons.poll_outlined, 'poll ended'),
      'follow_request' => (Icons.person_add_alt_1_outlined, 'requested to follow you'),
      'status' => (Icons.notifications_none, 'posted'),
      'update' => (Icons.edit_outlined, 'edited a post'),
      'admin.sign_up' => (Icons.how_to_reg_outlined, 'signed up'),
      _ => (Icons.notifications_none, type.isEmpty ? 'activity' : type),
    };
    return ListTile(
      leading: _Avatar(account: account),
      title: Text.rich(TextSpan(children: [
        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: ' $text'),
      ])),
      subtitle: status != null
          ? Text(_plainText(status['content'] as String? ?? ''),
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: status != null
          ? Text(_relativeTime(status['created_at'] as String?),
              style: Theme.of(context).textTheme.bodySmall)
          : null,
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.account, this.accountId,
      required this.onOpenProfile});
  final Map<String, dynamic>? account;
  final String? accountId;
  final ValueChanged<String> onOpenProfile;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account?['id'] != widget.account?['id']) _load();
  }

  Future<void> _load() async {
    final account = widget.account;
    if (account == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await _activeApi!.accountStatuses(account['id'] as String);
      if (mounted) {
        setState(() {
          _statuses = data;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (account == null) {
      return const Center(child: Text('Choose Log in to connect an account.'));
    }
    final acct = account['acct'] as String? ?? '';
    final host = acct.contains('@') ? acct.split('@').last : _activeApi!.instance.host;
    final header = account['header'] as String? ?? '';
    return Column(children: [
      const _PageTitle(title: 'Profile'),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          _ProfileBanner(header: header, account: account),
          const SizedBox(height: 54),
          Center(child: Text((account['display_name'] as String?)?.isNotEmpty == true ? account['display_name'] as String : account['username'] as String? ?? acct, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: Text('@$acct')),
          if (account['note'] is String && (account['note'] as String).isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_plainText(account['note'] as String), textAlign: TextAlign.center)),
          Center(child: Wrap(spacing: 18, children: [
            Text('${account['statuses_count'] ?? 0} posts'),
            Text('${account['following_count'] ?? 0} following'),
            Text('${account['followers_count'] ?? 0} followers'),
          ])),
          if (widget.accountId != null)
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(leading: const Icon(Icons.tune), title: const Text('Settings'), onTap: () { Navigator.pop(context); _settings(context); }),
                ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: () async { Navigator.pop(context); final shell = context.findAncestorStateOfType<_RumpunShellState>(); await shell?._logout(); }),
              ]))),
              icon: const Icon(Icons.more_horiz), label: const Text('Account'))),
          const Divider(height: 28),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text('Could not load posts: $_error'),
          if (_statuses.isEmpty && !_loading && _error == null)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No posts yet'))),
          for (final status in _statuses)
            _PostTile(post: Post(status, host), onProfile: widget.onOpenProfile, onTap: () {}),
        ]),
      ),
    ]);
  }

  Future<void> _settings(BuildContext context) async {
    final shell = context.findAncestorStateOfType<_RumpunShellState>();
    await shell?._settingsFromMenu();
  }
}

class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.header, required this.account});
  final String header;
  final Map<String, dynamic> account;

  void _preview(BuildContext context, String url) {
    if (MediaQuery.sizeOf(context).width >= 760) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog.fullscreen(
            child: _MediaPreview(
                attachments: [
                  {'url': url, 'preview_url': url, 'type': 'image'}
                ],
                initialIndex: 0)),
      );
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MediaPreview(
            attachments: [
              {'url': url, 'preview_url': url, 'type': 'image'}
            ],
            initialIndex: 0),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = (account['avatar_original'] as String?) ??
        account['avatar'] as String? ?? '';
    final hasHeader = header.isNotEmpty;
    return Stack(alignment: Alignment.bottomCenter, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 44),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 3,
            child: GestureDetector(
              onTap: hasHeader ? () => _preview(context, header) : null,
              child: hasHeader
                  ? Image(image: CachedNetworkImage(header, maxWidthPx: 1200),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _BannerFallback())
                  : const _BannerFallback(),
            ),
          ),
        ),
      ),
      GestureDetector(
        onTap: avatarUrl.isNotEmpty ? () => _preview(context, avatarUrl) : null,
        child: _Avatar(account: account, radius: 54),
      ),
    ]);
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _green.withValues(alpha: 0.55),
              _green.withValues(alpha: 0.18),
            ],
          ),
        ),
      );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.onTap});
  final Map<String, dynamic> account;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: _Avatar(account: account),
        title: Text(account['display_name'] as String? ?? account['username'] as String? ?? ''),
        subtitle: Text('@${account['acct'] ?? ''}'),
        onTap: onTap,
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.account, this.radius = 20});
  final Map<String, dynamic> account;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = account['avatar'] as String? ?? '';
    if (url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: Icon(Icons.person_outline, size: radius),
      );
    }
    // avatar_static is the smaller variant Mastodon serves for timelines.
    final small = (account['avatar_static'] as String?) ?? url;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (radius * 2 * dpr).round();
    return CircleAvatar(
      radius: radius,
      backgroundImage: CachedNetworkImage(small, maxWidthPx: px, maxHeightPx: px),
      onBackgroundImageError: (_, __) {},
    );
  }
}

class _TimelineFilter extends StatelessWidget {
  const _TimelineFilter({required this.selected, required this.options, required this.onSelect});
  final int selected;
  final List<String> options;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < options.length; i++)
              TextButton(
                onPressed: () => onSelect(i),
                child: Text(options[i],
                    style: TextStyle(
                        fontWeight: selected == i ? FontWeight.bold : FontWeight.normal,
                        color: selected == i ? _green : null)),
              ),
          ],
        ),
      );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Row(children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          if (action != null) action!,
        ]),
      );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.message, required this.action});
  final String message;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: action, child: const Text('Retry')),
        ]),
      );
}

class _PostTile extends StatefulWidget {
  const _PostTile({required this.post, required this.onProfile, required this.onTap});
  final Post post;
  final ValueChanged<String> onProfile;
  final VoidCallback onTap;
  @override
  State<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<_PostTile> {
  /// Local override for like/boost flags so the icon reacts before a refetch.
  final _optimistic = <String, bool>{};
  Post get post => widget.post;

  @override
  Widget build(BuildContext context) {
    final attachments = post.data['media_attachments'] as List<dynamic>? ?? const [];
    final spoiler = post.data['spoiler_text'] as String? ?? '';
    final favourited = _optimistic['favourited'] ?? post.data['favourited'] == true;
    final reblogged = _optimistic['reblogged'] ?? post.data['reblogged'] == true;
    final theme = Theme.of(context);
    final signedIn = _currentAccount != null;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => widget.onProfile(post.acct),
            child: Row(children: [
              _Avatar(account: post.account, radius: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(post.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(post.handle, style: theme.textTheme.bodySmall),
              ])),
              Text(_relativeTime(post.data['created_at'] as String?), style: theme.textTheme.bodySmall),
            ]),
          ),
          const SizedBox(height: 12),
          if (spoiler.isNotEmpty) _Spoiler(content: post.content, warning: spoiler)
          else _HtmlText(html: post.content),
          if (attachments.isNotEmpty)
            _MediaGallery(attachments: [
              for (final attachment in attachments)
                if (attachment is Map<String, dynamic> && attachment['url'] != null)
                  attachment,
            ]),
          Row(children: [
            IconButton(tooltip: 'Reply', onPressed: widget.onTap, icon: const Icon(Icons.mode_comment_outlined)),
            IconButton(
                tooltip: favourited ? 'Unlike' : 'Like',
                onPressed: signedIn ? () => _toggle('favourited', favourited, 'like', post.id) : null,
                icon: Icon(favourited ? Icons.favorite : Icons.favorite_border,
                    color: favourited ? const Color(0xFFE0245E) : null)),
            IconButton(
                tooltip: reblogged ? 'Undo boost' : 'Boost',
                onPressed: signedIn ? () => _toggle('reblogged', reblogged, 'repost', post.id) : null,
                icon: Icon(Icons.repeat, color: reblogged ? _green : null)),
            const Spacer(),
            IconButton(tooltip: 'Share', onPressed: () => _share(context, post), icon: const Icon(Icons.ios_share)),
          ]),
        ]),
      ),
    );
  }

  /// Calls the API, then flips the flag locally so the icon reacts instantly.
  Future<void> _toggle(String flag, bool on, String action, String id) async {
    try {
      final result = await _activeApi!.action(id, on ? 'un$action' : action);
      setState(() => _optimistic[flag] = result[flag] == true);
    } catch (_) {}
  }
}

Future<void> _share(BuildContext context, Post post) async {
  final url = post.data['url'] as String? ?? '';
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Copy link'),
          onTap: () async {
            Navigator.pop(sheetContext);
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied')));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.open_in_new),
          title: const Text('Open in browser'),
          onTap: () {
            Navigator.pop(sheetContext);
            if (url.isNotEmpty) {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
        ),
      ]),
    ),
  );
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.content, required this.warning});
  final String content;
  final String warning;
  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _show = false;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.warning, style: const TextStyle(fontWeight: FontWeight.w600)),
        TextButton(onPressed: () => setState(() => _show = !_show), child: Text(_show ? 'Hide sensitive content' : 'Show sensitive content')),
        if (_show) _HtmlText(html: widget.content),
      ]);
}

class _HtmlText extends StatelessWidget {
  const _HtmlText({required this.html});
  final String html;
  @override
  Widget build(BuildContext context) {
    final text = _plainText(html);
    // ponytail: SelectionArea over one Text per post; cheaper than per-post
    // SelectableText (each owns a selection overlay). Upgrade: html renderer.
    return SelectionArea(child: Text(text));
  }
}

String _plainText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .trim();

String _relativeTime(String? value) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return '';
  final age = DateTime.now().difference(date);
  if (age.inDays > 0) return '${age.inDays}d';
  if (age.inHours > 0) return '${age.inHours}h';
  if (age.inMinutes > 0) return '${age.inMinutes}m';
  return 'now';
}

/// Inline gallery for a post's media. Tapping a tile opens the fullscreen
/// preview; the play affordance lives there, not inline.
class _MediaGallery extends StatelessWidget {
  const _MediaGallery({required this.attachments});
  final List<Map<String, dynamic>> attachments;
  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final single = attachments.length == 1;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LayoutBuilder(builder: (context, box) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (index, attachment) in attachments.indexed)
          GestureDetector(
            onTap: () => _showPreview(context, attachments, index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: single
                    ? box.maxWidth
                    : (box.maxWidth - (attachments.length - 1) * 8) / attachments.length.clamp(2, 3),
                height: single ? null : 110,
                child: AspectRatio(
                  aspectRatio: single ? _attachmentAspect(attachment) : 1,
                  // contain on a muted ground: never stretched, never cropped,
                  // the clamped aspect keeps very tall/wide media bounded.
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Stack(fit: StackFit.expand, children: [
                      Image(
                          image: CachedNetworkImage(
                              attachment['preview_url'] as String? ??
                                  attachment['url'] as String,
                              maxWidthPx: 900),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                              attachment['type'] == 'audio'
                                  ? Icons.audio_file_outlined
                                  : attachment['type'] == 'video'
                                      ? Icons.videocam_outlined
                                      : Icons.image_outlined)),
                      if (attachment['type'] == 'video')
                        const Center(
                          child: Icon(Icons.play_circle_fill,
                              size: 44, shadows: [
                            Shadow(blurRadius: 8, color: Colors.black54)
                          ]),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ])),
    );
  }

  void _showPreview(BuildContext context,
      List<Map<String, dynamic>> attachments, int initialIndex) {
    if (MediaQuery.sizeOf(context).width >= 760) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog.fullscreen(
            child: _MediaPreview(attachments: attachments, initialIndex: initialIndex)),
      );
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MediaPreview(attachments: attachments, initialIndex: initialIndex),
      ));
    }
  }
}

/// Fullscreen viewer: swipeable pages, alt text, and open-in-browser.
class _MediaPreview extends StatefulWidget {
  const _MediaPreview({required this.attachments, required this.initialIndex});
  final List<Map<String, dynamic>> attachments;
  final int initialIndex;
  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  late int _index = widget.initialIndex;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          if (_altText.isNotEmpty)
            IconButton(
                icon: const Icon(Icons.closed_caption_outlined),
                tooltip: 'Alt text',
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                        title: const Text('Description'),
                        content: Text(_altText),
                        actions: [TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'))]))),
          IconButton(
              tooltip: 'Open in browser',
              onPressed: () => launchUrl(
                  Uri.parse(_current['url'] as String),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new)),
        ],
      ),
      body: GestureDetector(
        // Any tap that lands outside the media itself dismisses the preview;
        // taps on the image land on the child and are swallowed by it.
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(color: Colors.transparent, child: widget.attachments.length == 1
            ? _centered(_current)
            : PageView(
                controller: PageController(initialPage: widget.initialIndex),
                onPageChanged: (i) => setState(() => _index = i),
                children: [for (final attachment in widget.attachments) _centered(attachment)],
              ),
        ),
      ),
    );
  }

  Map<String, dynamic> get _current => widget.attachments[_index];

  String get _altText =>
      (_current['description'] as String? ?? '').trim();

  Widget _centered(Map<String, dynamic> attachment) {
    final type = attachment['type'] as String? ?? 'image';
    final src = attachment['url'] as String? ?? '';
    if ((type == 'video' || type == 'audio') && src.isNotEmpty) {
      return _VideoPlayerView(
        src: src,
        audioOnly: type == 'audio',
        poster: attachment['preview_url'] as String?,
      );
    }
    return Center(
      child: GestureDetector(
        // Swallow taps on the media so only background taps close.
        onTap: () {},
        child: InteractiveViewer(
          maxScale: 4,
          child: Image(
            image: CachedNetworkImage(
                attachment['preview_url'] as String? ??
                    attachment['url'] as String,
                maxWidthPx: 1600),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 48),
          ),
        ),
      ),
    );
  }
}

/// Single shared libmpv player per preview lifecycle.
class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({required this.src, this.audioOnly = false, this.poster});
  final String src;
  final bool audioOnly;
  final String? poster;
  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final _player = Player();
  late final _controller = VideoController(_player);
  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.src));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = Video(controller: _controller, controls: NoVideoControls);
    final themed = MaterialVideoControlsTheme(
      normal: _controlsTheme,
      fullscreen: _controlsTheme,
      child: video,
    );
    if (widget.audioOnly) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.audiotrack, size: 48, color: Colors.white54),
        const SizedBox(height: 8),
        SizedBox(width: 480, child: themed),
      ]);
    }
    return AspectRatio(aspectRatio: 16 / 9, child: themed);
  }

  static const _controlsTheme = MaterialVideoControlsThemeData(
      seekBarThumbColor: _green);
}

double _attachmentAspect(Map<String, dynamic> attachment) {
  final w = attachment['meta']?['small']?['width'];
  final h = attachment['meta']?['small']?['height'];
  if (w is num && h is num && h > 0) return (w / h).clamp(0.5, 3.0);
  return 16 / 9;
}
