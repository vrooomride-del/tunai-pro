import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_service.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import '../dsp/dsp_state.dart';
import '../dsp/dsp_controller.dart';

class ProCommunityScreen extends ConsumerStatefulWidget {
  const ProCommunityScreen({super.key});
  @override
  ConsumerState<ProCommunityScreen> createState() => _ProCommunityScreenState();
}

class _ProCommunityScreenState extends ConsumerState<ProCommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _presets = [];
  List<dynamic> _posts = [];
  bool _loadingPresets = true;
  bool _loadingPosts = true;
  String _sort = 'trending';
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadPresets();
    _loadPosts();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _loadPresets() async {
    setState(() => _loadingPresets = true);
    final res = _sort == 'trending'
        ? await ApiService.getTrending()
        : await ApiService.getPresets();
    setState(() {
      _presets = res['data'] ?? [];
      _loadingPresets = false;
    });
  }

  Future<void> _loadPosts() async {
    setState(() => _loadingPosts = true);
    final res = await ApiService.getPosts(category: _category);
    setState(() {
      _posts = res['data'] ?? [];
      _loadingPosts = false;
    });
  }

  void _applyPreset(Map<String, dynamic> preset) {
    final fps = preset['fps_json'] as List?;
    if (fps == null || fps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('필터 데이터가 없는 프리셋입니다.')));
      return;
    }
    // DSP 상태에 적용
    final ctrl = ref.read(dspProvider.notifier);
    final outIdx = ref.read(dspProvider).selectedOutput;
    final bands = fps.take(20).toList();
    for (int i = 0; i < bands.length; i++) {
      final b = bands[i];
      ctrl.updateOutputBand(outIdx, i, PeqBand(
        frequency: (b['frequency'] ?? b['f'] ?? 1000).toDouble(),
        gainDb: (b['gain'] ?? b['g'] ?? 0).toDouble(),
        q: (b['q'] ?? 2.0).toDouble(),
        enabled: true,
      ));
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${preset['title']} → DSP 적용 완료')));
  }

  Future<void> _shareCurrentDsp() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      showDialog(context: context, builder: (_) => const Dialog(child: AuthScreen()));
      return;
    }
    final dspState = ref.read(dspProvider);
    final out = dspState.outputs[dspState.selectedOutput];
    final fps = out.bands.map((b) => {
      'frequency': b.frequency, 'gain': b.gainDb, 'q': b.q,
    }).toList();

    final titleCtrl = TextEditingController(text: '${out.name} 프리셋');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('프리셋 공유',
            style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
        content: TextField(
          controller: titleCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: '제목',
            labelStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.uploadPreset(
                title: titleCtrl.text.trim(),
                description: 'TUNAI Pro ${out.name}',
                fps: fps.cast<Map<String, dynamic>>(),
              );
              if (!context.mounted) return;
              if (res['status'] == 'ok') {
                _loadPresets();
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('프리셋 공유됐습니다!')));
              }
            },
            child: const Text('공유', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              children: [
                const Text('COMMUNITY',
                    style: TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w200, letterSpacing: 6)),
                const Spacer(),
                GestureDetector(
                  onTap: _shareCurrentDsp,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white38, width: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('SHARE DSP',
                        style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 2)),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    if (!auth.isLoggedIn) {
                      showDialog(context: context, builder: (_) => const Dialog(child: AuthScreen()));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: auth.isLoggedIn ? Colors.white24 : Colors.white,
                          width: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      auth.isLoggedIn ? auth.nickname ?? 'ME' : 'LOGIN',
                      style: TextStyle(
                        color: auth.isLoggedIn ? Colors.white38 : Colors.white,
                        fontSize: 9, letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicatorColor: Colors.white,
              indicatorWeight: 1,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontSize: 9, letterSpacing: 2),
              tabs: const [Tab(text: 'PRESETS'), Tab(text: 'BOARD')],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // PRESETS 탭
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
                      child: Row(
                        children: [
                          _SortBtn('인기순', _sort == 'trending',
                              () { setState(() => _sort = 'trending'); _loadPresets(); }),
                          const SizedBox(width: 8),
                          _SortBtn('최신순', _sort == 'latest',
                              () { setState(() => _sort = 'latest'); _loadPresets(); }),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loadingPresets
                          ? const Center(child: CircularProgressIndicator(
                              color: Colors.white24, strokeWidth: 1))
                          : _presets.isEmpty
                              ? const Center(child: Text('프리셋이 없습니다.',
                                    style: TextStyle(color: Colors.white38)))
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                                  itemCount: _presets.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final p = _presets[i];
                                    return Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.white12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(p['title'] ?? '',
                                                    style: const TextStyle(
                                                        color: Colors.white, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Text('by ${p['nickname'] ?? ''}  ·  ↓${p['downloads'] ?? 0}  ·  ♥${p['likes'] ?? 0}',
                                                    style: const TextStyle(
                                                        color: Colors.white38, fontSize: 10)),
                                              ],
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _applyPreset(p),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: Colors.white38),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('APPLY',
                                                  style: TextStyle(color: Colors.white,
                                                      fontSize: 9, letterSpacing: 2)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),

                // BOARD 탭
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final c in [
                                    ['all', '전체'], ['tip', '튜닝팁'],
                                    ['review', '리뷰'], ['qna', 'Q&A'], ['general', '자유'],
                                  ])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _SortBtn(c[1], _category == c[0],
                                          () { setState(() => _category = c[0]); _loadPosts(); }),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showWriteDialog(),
                            child: const Icon(Icons.edit_outlined, color: Colors.white38, size: 16),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loadingPosts
                          ? const Center(child: CircularProgressIndicator(
                              color: Colors.white24, strokeWidth: 1))
                          : _posts.isEmpty
                              ? const Center(child: Text('게시글이 없습니다.',
                                    style: TextStyle(color: Colors.white38)))
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                                  itemCount: _posts.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(color: Colors.white12, height: 1),
                                  itemBuilder: (_, i) {
                                    final p = _posts[i];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(p['category'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.white38, fontSize: 9)),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(p['title'] ?? '',
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 12),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                          ),
                                          Text('${p['nickname'] ?? ''}',
                                              style: const TextStyle(
                                                  color: Colors.white38, fontSize: 10)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showWriteDialog() {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      showDialog(context: context, builder: (_) => const Dialog(child: AuthScreen()));
      return;
    }
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = 'general';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: const Text('글쓰기',
              style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 2)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in [
                      ['general', '자유'], ['tip', '튜닝팁'],
                      ['review', '리뷰'], ['qna', 'Q&A'],
                    ])
                      GestureDetector(
                        onTap: () => setS(() => category = c[0]),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: category == c[0] ? Colors.white : Colors.white24,
                                width: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(c[1],
                              style: TextStyle(
                                color: category == c[0] ? Colors.white : Colors.white38,
                                fontSize: 11,
                              )),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '제목',
                    labelStyle: TextStyle(color: Colors.white38, fontSize: 10),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: contentCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '내용',
                    labelStyle: TextStyle(color: Colors.white38, fontSize: 10),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24, width: 0.5)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white, width: 0.5)),
                    contentPadding: EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('취소', style: TextStyle(color: Colors.white38))),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ApiService.createPost(
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  category: category,
                );
                _loadPosts();
              },
              child: const Text('등록', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class ProProfileScreen extends ConsumerWidget {
  const ProProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: auth.isLoggedIn
            ? _LoggedInProfile(auth: auth)
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('PROFILE',
                        style: TextStyle(color: Colors.white38, fontSize: 13, letterSpacing: 4)),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: () => showDialog(context: context, builder: (_) => const Dialog(child: AuthScreen())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('LOGIN',
                            style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 4)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _LoggedInProfile extends ConsumerWidget {
  final dynamic auth;
  const _LoggedInProfile({required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PROFILE',
              style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 4)),
          const SizedBox(height: 24),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white12,
                child: Text(
                  (auth.nickname ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(auth.nickname ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(auth.email ?? '',
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),
          GestureDetector(
            onTap: () => ref.read(authProvider.notifier).logout(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('LOGOUT',
                  style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortBtn(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
            color: selected ? Colors.white : Colors.white24, width: 0.5),
        borderRadius: BorderRadius.circular(20),
        color: selected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
      ),
      child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white38, fontSize: 10)),
    ),
  );
}
