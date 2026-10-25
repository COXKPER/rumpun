import 'package:flutter/material.dart';

void main() => runApp(const RumpunApp());

const _green = Color(0xFF236B55);
const _mint = Color(0xFF83C9AE);

class RumpunApp extends StatelessWidget {
  const RumpunApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Rumpun',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: _green, brightness: Brightness.light),
          useMaterial3: true,
          fontFamily: '.SF Pro Text',
          scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: _mint, brightness: Brightness.dark),
          useMaterial3: true,
          fontFamily: '.SF Pro Text',
        ),
        home: const RumpunShell(),
      );
}

// --- Domain models ---

class Post {
  final String name, handle, text, time, avatar;
  final String? contentWarning;
  const Post(this.name, this.handle, this.text, this.time,
      {this.avatar = '', this.contentWarning});
}

const _posts = [
  Post(
      'Nadia Putri',
      '@nadia@ruang.id',
      'Beautiful morning for reading and sharing ideas. Hope your day is wonderful! ☀️',
      '12m'),
  Post(
      'Bima Santoso',
      '@bima@mastodon.social',
      'Just discovered a great local community. It feels nice when the internet feels like a place of your own.',
      '34m'),
  Post(
      'Ayu Lestari',
      '@ayu@ruang.id',
      'Accessibility tip: add image descriptions before posting. Alt text helps more people enjoy your content.',
      '1h'),
  Post(
      'Citra Dewi',
      '@citra@ruang.id',
      'Personal reflection: sometimes we need to be quiet and listen before we speak. 🌿',
      '2h',
      contentWarning: 'Personal'),
];

const _trendingHashtags = [
  'Linux',
  'Photography',
  'Fediverse',
  'Design',
  'Books',
];

const _searchResultsAccounts = [
  _SearchResultAccount('Nadia Putri', '@nadia@ruang.id'),
  _SearchResultAccount('Bima Santoso', '@bima@mastodon.social'),
];

const _searchResultsPosts = [
  _SearchResultPost('flutter tips for desktop', '@dev@ruang.id'),
  _SearchResultPost('open source community', '@dev@ruang.id'),
];

class _SearchResultAccount {
  final String name, handle;
  const _SearchResultAccount(this.name, this.handle);
}

class _SearchResultPost {
  final String title, handle;
  const _SearchResultPost(this.title, this.handle);
}

// --- Root shell with navigation ---

class RumpunShell extends StatefulWidget {
  const RumpunShell({super.key});
  @override
  State<RumpunShell> createState() => _RumpunShellState();
}

class _RumpunShellState extends State<RumpunShell> {
  int _page = 0;
  void _go(int page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final screens = [
      HomeScreen(onOpenThread: (post) => _openThread(post)),
      const ExploreScreen(),
      const ActivityScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _OwnedBar(onProfile: () => _go(3)),
          Expanded(
              child: Row(children: [
            if (wide)
              NavigationRail(
                extended: MediaQuery.sizeOf(context).width >= 1050,
                selectedIndex: _page,
                onDestinationSelected: _go,
                destinations: const [
                  NavigationRailDestination(
                      icon: Icon(Icons.home_outlined), label: Text('Home')),
                  NavigationRailDestination(
                      icon: Icon(Icons.search), label: Text('Explore')),
                  NavigationRailDestination(
                      icon: Icon(Icons.notifications_outlined),
                      label: Text('Activity')),
                  NavigationRailDestination(
                      icon: Icon(Icons.person_outline), label: Text('Profile')),
                ],
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: screens[_page],
                ),
              ),
            ),
          ])),
        ]),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: _go,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined), label: 'Home'),
                NavigationDestination(
                    icon: Icon(Icons.search), label: 'Explore'),
                NavigationDestination(
                    icon: Icon(Icons.notifications_outlined),
                    label: 'Activity'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline), label: 'Profile'),
              ],
            ),
    );
  }

  void _openThread(Post post) {
    showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: 'Close',
      transitionBuilder: (context, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (context, anim, _) => _ThreadSheet(post: post),
    );
  }
}

// --- App-owned chrome ---

class _OwnedBar extends StatelessWidget {
  final VoidCallback onProfile;
  const _OwnedBar({required this.onProfile});
  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
                bottom: BorderSide(
                    color: Theme.of(context)
                        .dividerColor
                        .withValues(alpha: .12)))),
        child: Row(children: [
          Icon(Icons.hub,
              size: 19, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          Text('rumpun',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          const Icon(Icons.circle, size: 8, color: Color(0xFF38A979)),
          const SizedBox(width: 7),
          const Text('ruang.id'),
          const SizedBox(width: 12),
          InkWell(
              onTap: onProfile,
              borderRadius: BorderRadius.circular(14),
              child: const CircleAvatar(
                  radius: 13, child: Text('K', style: TextStyle(fontSize: 11))))
        ]),
      );
}

// --- Thread conversation sheet ---

class _ThreadSheet extends StatelessWidget {
  final Post post;
  const _ThreadSheet({required this.post});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 24,
                    offset: Offset(0, 12))
              ]),
          child: Column(children: [
            // Drag indicator
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium!
                          .color!
                          .withValues(alpha: .24),
                      borderRadius: BorderRadius.circular(2))),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
              child: Row(children: [
                const Icon(Icons.forum_outlined),
                const SizedBox(width: 8),
                Text('Conversation',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 1),
            // Conversation content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Parent post with highlight
                      _ThreadPostTile(
                          post: post, borderColor: cs.primary, borderWidth: 2),
                      const SizedBox(height: 16),
                      // Guide line
                      _buildGuideLine(context),
                      const SizedBox(height: 12),
                      // Reply
                      const _ThreadPostTile(
                          post: Post(
                              'Raka Wirawan',
                              '@raka@ruang.id',
                              'Agreed! It is wonderful to see communities sharing good things.',
                              '8m'),
                          indent: true),
                    ]),
              ),
            ),
            // Reply composer
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: .08)))),
              child: Row(children: [
                const CircleAvatar(radius: 14, child: Text('K')),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                        hintText: 'Type a reply...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .3)),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildGuideLine(BuildContext context) => Padding(
      padding: const EdgeInsets.only(left: 26),
      child: Column(children: [
        Container(
            width: 2,
            height: 24,
            color: Theme.of(context)
                .textTheme
                .bodyMedium!
                .color!
                .withValues(alpha: .12)),
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .color!
                    .withValues(alpha: .24))),
      ]));
}

class _ThreadPostTile extends StatelessWidget {
  final Post post;
  final bool indent;
  final double borderWidth;
  final Color? borderColor;
  const _ThreadPostTile(
      {required this.post,
      this.indent = false,
      this.borderWidth = 0,
      this.borderColor});
  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(left: indent ? 24 : 0),
        decoration: borderWidth > 0
            ? BoxDecoration(
                border: Border(
                    left: BorderSide(color: borderColor!, width: borderWidth)),
                borderRadius: BorderRadius.circular(12))
            : null,
        child: Card(
            elevation: 0,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                            radius: 14,
                            child: Text(post.avatar.isEmpty
                                ? post.name.characters.first
                                : post.avatar)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(post.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text('${post.handle} · ${post.time}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ])),
                        if (post.contentWarning != null)
                          const Icon(Icons.visibility_outlined),
                      ]),
                      const SizedBox(height: 10),
                      Text(post.text),
                      const SizedBox(height: 8),
                      Row(children: [
                        IconButton(
                            tooltip: 'Reply',
                            iconSize: 20,
                            onPressed: () {},
                            icon: const Icon(Icons.mode_comment_outlined)),
                        IconButton(
                            tooltip: 'Like',
                            iconSize: 20,
                            onPressed: () {},
                            icon: const Icon(Icons.favorite_border)),
                        IconButton(
                            tooltip: 'Repost',
                            iconSize: 20,
                            onPressed: () {},
                            icon: const Icon(Icons.repeat)),
                      ]),
                    ]))),
      );
}

// --- Home / Timeline screen ---

class HomeScreen extends StatefulWidget {
  final ValueChanged<Post> onOpenThread;
  const HomeScreen({super.key, required this.onOpenThread});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _feed = 0;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _PageTitle(
            title: 'Home',
            action: IconButton(
                tooltip: 'Write post',
                onPressed: _compose,
                icon: const Icon(Icons.edit_square))),
        _TimelineFilter(
            selected: _feed,
            options: const ['Following', 'Local', 'Federated'],
            onSelect: (i) => setState(() => _feed = i)),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
                child: ListTile(
                    leading: const CircleAvatar(child: Text('K')),
                    title: const Text('What do you want to share?'),
                    trailing: const Icon(Icons.add),
                    onTap: _compose)),
            for (final post in _posts)
              _PostTile(post: post, onTap: () => widget.onOpenThread(post)),
          ]),
        ),
      ]);

  void _compose() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _ComposeSheet(
        textController: _text,
        onDismiss: () {
          _text.clear();
          Navigator.pop(sheetContext);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Post added (local preview)')));
        },
      ),
    );
  }
}

class _ComposeSheet extends StatefulWidget {
  final TextEditingController textController;
  final VoidCallback onDismiss;
  const _ComposeSheet({required this.textController, required this.onDismiss});
  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  bool _cw = false;
  String _visibility = 'Public';
  bool _hasSensitive = false;
  bool _hasAltText = false;

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Write Post', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
                controller: widget.textController,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                decoration: const InputDecoration(
                    hintText: 'What do you want to share?',
                    border: OutlineInputBorder(),
                    counterText: '')),
            if (_cw)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: TextField(
                      decoration: InputDecoration(
                          labelText: 'Content warning',
                          border: OutlineInputBorder()))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterChip(
                  label: const Text('Add CW'),
                  selected: _cw,
                  onSelected: (v) => setState(() => _cw = v)),
              DropdownButton<String>(
                  value: _visibility,
                  items: const ['Public', 'Unlisted', 'Followers', 'Direct']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => _visibility = v!)),
              FilterChip(
                  label: const Text('Sensitive'),
                  selected: _hasSensitive,
                  onSelected: (v) => setState(() => _hasSensitive = v)),
              FilterChip(
                  label: const Text('Has photo'),
                  selected: _hasAltText,
                  onSelected: (v) {
                    setState(() => _hasAltText = v);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Add image alt text after selecting a photo')));
                  }),
            ]),
            if (_hasAltText)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: TextField(
                      decoration: InputDecoration(
                          labelText: 'Image description (alt text)',
                          border: OutlineInputBorder(),
                          hintText:
                              'Describe what is visible in the image...'))),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: () {
                    if (widget.textController.text.trim().isEmpty) return;
                    setState(() {
                      _cw = false;
                      _hasSensitive = false;
                      _hasAltText = false;
                    });
                    widget.onDismiss();
                  },
                  child: const Text('Send')),
            ),
          ]));
}

// --- Timeline filter pills ---

class _TimelineFilter extends StatelessWidget {
  final int selected;
  final List<String> options;
  final ValueChanged<int> onSelect;
  const _TimelineFilter({
    required this.selected,
    required this.options,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? Theme.of(context).textTheme.bodyLarge!.color!.withValues(alpha: .6)
        : Theme.of(context).textTheme.bodyLarge!.color!.withValues(alpha: .6);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color:
                (isDark ? Colors.white : Colors.black).withValues(alpha: .05),
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => onSelect(i),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      options[i],
                      style: TextStyle(
                        fontWeight:
                            selected == i ? FontWeight.bold : FontWeight.normal,
                        color: selected == i ? _green : inactiveColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (selected == i)
                      Container(
                        height: 3,
                        width: 36,
                        decoration: BoxDecoration(
                          color: _green,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Explore / Search screen ---

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _searchCtrl = TextEditingController();
  String _category = 'Hashtags';
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_SearchResultAccount> get _accountMatches =>
      _searchResultsAccounts.where((a) {
        final q = _query.toLowerCase();
        return a.name.toLowerCase().contains(q) ||
            a.handle.toLowerCase().contains(q);
      }).toList();

  List<_SearchResultPost> get _postMatches => _searchResultsPosts.where((p) {
        final q = _query.toLowerCase();
        return p.title.toLowerCase().contains(q) ||
            p.handle.toLowerCase().contains(q);
      }).toList();

  bool get _showResults => _query.isNotEmpty;

  @override
  Widget build(BuildContext context) => Column(children: [
        const _PageTitle(title: 'Explore'),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBar(
                controller: _searchCtrl,
                leading: const Icon(Icons.search),
                hintText: 'Search accounts, hashtags, or posts',
                onChanged: (v) => setState(() => _query = v))),
        if (_showResults) ...[
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(_query.isEmpty ? '' : 'Results for "$_query"',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600))),
          if (_category == 'Accounts' && _accountMatches.isNotEmpty) ...[
            for (final a in _accountMatches)
              ListTile(
                  leading: CircleAvatar(child: Text(a.name.characters.first)),
                  title: Text(a.name),
                  subtitle: Text(a.handle),
                  trailing: OutlinedButton(
                      onPressed: () {}, child: const Text('Follow'))),
          ],
          if (_category == 'Posts' && _postMatches.isNotEmpty) ...[
            for (final p in _postMatches)
              ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(p.title),
                  subtitle: Text(p.handle),
                  trailing: const Icon(Icons.chevron_right)),
          ],
          if (_accountMatches.isEmpty && _postMatches.isEmpty)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No results found'))),
        ] else ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final cat in const ['Hashtags', 'Accounts', 'Posts'])
                  Padding(
                      padding: const EdgeInsets.only(left: 20, right: 12),
                      child: ChoiceChip(
                          label: Text(cat),
                          selected: _category == cat,
                          onSelected: (_) => setState(() => _category = cat))),
              ],
            ),
          ),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Trending hashtags',
                      style: TextStyle(fontWeight: FontWeight.bold)))),
          Expanded(
            child: ListView(children: [
              for (final tag in _trendingHashtags)
                ListTile(
                    leading: const Icon(Icons.tag),
                    title: Text(tag),
                    subtitle: Text('${_trendingVolume(tag)} posts today'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {}),
              const Divider(),
              for (final a in _searchResultsAccounts)
                ListTile(
                    leading: CircleAvatar(child: Text(a.name.characters.first)),
                    title: Text(a.name),
                    subtitle: Text(a.handle),
                    trailing: OutlinedButton(
                        onPressed: () {}, child: const Text('Follow'))),
            ]),
          ),
        ],
      ]);

  static String _trendingVolume(String tag) {
    const vol = {
      'Linux': '2.4K',
      'Photography': '1.8K',
      'Fediverse': '920',
      'Design': '756',
      'Books': '432',
    };
    return vol[tag] ?? '100';
  }
}

// --- Activity / Notifications screen ---

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  int filter = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        const _PageTitle(title: 'Activity'),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(segments: const [
              ButtonSegment(value: 0, label: Text('All')),
              ButtonSegment(value: 1, label: Text('Mentions')),
              ButtonSegment(value: 2, label: Text('Likes')),
            ], selected: {
              filter
            }, onSelectionChanged: (v) => setState(() => filter = v.first))),
        Expanded(
          child: ListView(children: const [
            ListTile(
                leading: CircleAvatar(child: Text('R')),
                title: Text('Raka replied to your post'),
                subtitle: Text(
                    'Agreed! It is wonderful to see communities sharing good things. · 8m'),
                trailing:
                    Icon(Icons.mode_comment_outlined, color: Colors.blue)),
            ListTile(
                leading: CircleAvatar(child: Text('A')),
                title: Text('Ayu liked your post'),
                subtitle: Text('Sharing accessibility tips · 20m'),
                trailing: Icon(Icons.favorite, color: Colors.pink)),
            ListTile(
                leading: CircleAvatar(child: Text('B')),
                title: Text('Bima followed you'),
                subtitle: Text('@bima@mastodon.social · 1h'),
                trailing: Icon(Icons.person_add_alt_1)),
          ]),
        ),
      ]);
}

// --- Profile screen with tabs ---

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(children: [
          const _PageTitle(title: 'Profile'),
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
                radius: 44,
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withAlpha(30),
                child: const CircleAvatar(
                    radius: 40,
                    child: Text('K', style: TextStyle(fontSize: 28)))),
          ),
          const SizedBox(height: 12),
          Text('You',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Text('@kamu@ruang.id',
              style: TextStyle(color: Color(0xFF9AA4A0))),
          const SizedBox(height: 8),
          const Text(
              'Happy to share stories, ideas, and small things that make the day better.',
              style: TextStyle(color: Color(0xFF9AA4A0)),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const Wrap(alignment: WrapAlignment.center, spacing: 20, children: [
            Text('24 Following'),
            Text('128 Followers'),
            Text('36 Posts'),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _ProfileTabBar(
              tabs: const ['Posts', 'Replies', 'Media'],
              selected: _tab,
              onTap: (i) => setState(() => _tab = i)),
          const SizedBox(height: 8),
          _buildTabContent(),
          const SizedBox(height: 24),
        ]),
      );

  Widget _buildTabContent() {
    switch (_tab) {
      case 1:
        return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Your replies will appear here')));
      case 2:
        return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Media you upload will appear here')));
      default:
        return Column(children: [
          for (final post in _posts) _PostTile(post: post, onTap: () {}),
        ]);
    }
  }
}

class _ProfileTabBar extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onTap;
  const _ProfileTabBar(
      {required this.tabs, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < tabs.length; i++)
          Expanded(
              child: Center(
                  child: Column(children: [
            InkWell(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(tabs[i],
                        style: TextStyle(
                            fontWeight: selected == i
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: selected == i ? _green : null)))),
            if (selected == i)
              Container(
                  height: 3,
                  width: 32,
                  decoration: BoxDecoration(
                      color: _green, borderRadius: BorderRadius.circular(2))),
          ]))),
      ]);
}

// --- Reused widgets ---

class _PageTitle extends StatelessWidget {
  final String title;
  final Widget? action;
  const _PageTitle({required this.title, this.action});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
      child: Row(children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        if (action != null) action!
      ]));
}

class _PostTile extends StatefulWidget {
  final Post post;
  final VoidCallback onTap;
  const _PostTile({required this.post, required this.onTap});
  @override
  State<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<_PostTile> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final hasCW = widget.post.contentWarning != null;
    final reveal = _reveal || !hasCW;
    return Card(
        elevation: 0,
        child: InkWell(
            onTap: reveal ? widget.onTap : () => setState(() => _reveal = true),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                            child: Text(widget.post.avatar.isEmpty
                                ? widget.post.name.characters.first
                                : widget.post.avatar)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(widget.post.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  '${widget.post.handle} · ${widget.post.time}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ])),
                        const Icon(Icons.more_horiz),
                      ]),
                      if (hasCW && !reveal) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.warning_amber_outlined, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                'Content Warning: ${widget.post.contentWarning}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        TextButton(
                            onPressed: () => setState(() => _reveal = true),
                            child: const Text('View post')),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(widget.post.text),
                        const SizedBox(height: 8),
                        Row(children: [
                          IconButton(
                              tooltip: 'Reply',
                              onPressed: widget.onTap,
                              icon: const Icon(Icons.mode_comment_outlined)),
                          IconButton(
                              tooltip: 'Like',
                              onPressed: () {},
                              icon: const Icon(Icons.favorite_border)),
                          IconButton(
                              tooltip: 'Repost',
                              onPressed: () {},
                              icon: const Icon(Icons.repeat)),
                        ]),
                      ],
                    ]))));
  }
}
