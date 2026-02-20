import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const PosiMobileApp());
}

class PosiMobileApp extends StatelessWidget {
  const PosiMobileApp({super.key});

  static const _seed = Color(0xFF1E88E5); // fresh blue

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POSI Mobile',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Color(0xFF143155)),
          titleLarge: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF143155)),
          bodyMedium: TextStyle(height: 1.4, color: Color(0xFF1E2F45)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F8FF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD4E4FF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1E88E5)),
          ),
          hintStyle: const TextStyle(color: Color(0xFF7B8CA7)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E88E5),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF1E88E5),
          unselectedItemColor: Color(0xFF8CA2C3),
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide.none,
          labelStyle: const TextStyle(color: Color(0xFF143155)),
          backgroundColor: const Color(0xFFEAF2FF),
          selectedColor: const Color(0xFF1E88E5),
        ),
      ),
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _loggedIn = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: _loggedIn
          ? MainShell(onLogout: () => setState(() => _loggedIn = false))
          : LoginScreen(onLogin: () => setState(() => _loggedIn = true)),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF071226), Color(0xFF0D1D39), Color(0xFF0A1F3F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'POSI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Login untuk mulai ngobrol dengan admin dan pantau tiket Anda.',
                  style: TextStyle(color: Color(0xFF9AB3D7)),
                ),
                const SizedBox(height: 36),
                const Text('Email', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const TextField(
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'nama@contoh.com',
                    prefixIcon: Icon(Icons.mail_outline, color: Color(0xFF6E8BB6)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Password', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: Icon(Icons.lock_outline, color: Color(0xFF6E8BB6)),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onLogin,
                  child: const Text('Masuk'),
                ),
                const SizedBox(height: 14),
                _GoogleLoginButton(onPressed: onLogin),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    'Lupa password?',
                    style: TextStyle(color: Color(0xFF8CB7FF)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 2; // default to Home in the middle

  final _pages = const [
    ChatTab(),
    InfoTab(),
    HomeTab(),
    SupportTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            ..._pages,
            SettingsTab(onLogout: widget.onLogout),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: 'Chat'),
          const BottomNavigationBarItem(icon: Icon(Icons.info_rounded), label: 'Informasi'),
          BottomNavigationBarItem(icon: _HomeIcon(active: _index == 2), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.support_agent_rounded), label: 'Support'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profil'),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return _GradientBackground(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitleRow(title: 'Selamat datang 👋'),
            const SizedBox(height: 16),
            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Pantau kompetisi & dukungan'),
                  SizedBox(height: 8),
                  Text(
                    'Akses cepat ke tiket chat, pengumuman, dan informasi terbaru POSI.',
                    style: TextStyle(color: Color(0xFF526380)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                _MetricCard(label: 'Tiket aktif', value: '3', accent: Color(0xFF4CC2FF)),
                SizedBox(width: 12),
                _MetricCard(label: 'Selesai', value: '12', accent: Color(0xFF7CE7C7)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class Ticket {
  Ticket({
    required this.id,
    required this.title,
    required this.user,
    required this.summary,
    required this.status,
    required this.lastMessage,
    required this.topic,
    required this.time,
    required this.unread,
    required this.avatarColor,
    this.pinned = false,
  });

  final int id;
  final String title;
  final String user;
  final String summary;
  final String status; // Baru | Proses | Selesai
  final String lastMessage;
  final String topic;
  final String time; // e.g. 07.26
  final int unread;
  final Color avatarColor;
  final bool pinned;
}

class ChatMessage {
  ChatMessage(this.from, this.text, this.time);

  final String from; // admin/user
  final String text;
  final String time;
}

class _ChatTabState extends State<ChatTab> {
  final _tickets = [
    Ticket(
      id: 1,
      title: 'Tiket #1023',
      user: 'Alya N.',
      summary: 'Verifikasi pembayaran',
      status: 'Proses',
      lastMessage: 'Kami sudah terima bukti transfernya ya.',
      topic: 'Pemesanan',
      time: '07.26',
      unread: 2,
      avatarColor: const Color(0xFF4CC2FF),
      pinned: true,
    ),
    Ticket(
      id: 2,
      title: 'Tiket #1018',
      user: 'Rafi S.',
      summary: 'Ganti tim lomba online',
      status: 'Baru',
      lastMessage: 'Halo admin, saya mau ganti anggota tim.',
      topic: 'Pendaftaran',
      time: '16/02',
      unread: 0,
      avatarColor: const Color(0xFF7CE7C7),
      pinned: true,
    ),
    Ticket(
      id: 3,
      title: 'Tiket #0999',
      user: 'POSI Admin',
      summary: 'Jadwal final onsite',
      status: 'Selesai',
      lastMessage: 'Terima kasih, jadwal final sudah jelas.',
      topic: 'Lainnya',
      time: '24/01',
      unread: 0,
      avatarColor: const Color(0xFF8CA2C3),
    ),
    Ticket(
      id: 4,
      title: 'Tiket #1044',
      user: 'Dewi K.',
      summary: 'Tukar jadwal sesi',
      status: 'Baru',
      lastMessage: 'Boleh tukar jadwal sesi interview?',
      topic: 'Lainnya',
      time: '05.31',
      unread: 1,
      avatarColor: const Color(0xFF1B4B9E),
    ),
  ];

  final _messages = <int, List<ChatMessage>>{
    1: [
      ChatMessage('user', 'Selamat siang admin, saya sudah transfer.', '09.12'),
      ChatMessage('admin', 'Kami sudah terima bukti transfernya ya.', '09.14'),
    ],
    2: [
      ChatMessage('user', 'Halo admin, saya mau ganti anggota tim.', '08.40'),
    ],
    3: [
      ChatMessage('admin', 'Jadwal final onsite sudah rilis, cek dashboard ya.', '10.10'),
      ChatMessage('user', 'Terima kasih, jadwal final sudah jelas.', '10.12'),
    ],
    4: [
      ChatMessage('user', 'Boleh tukar jadwal sesi interview?', '05.31'),
    ],
  };

  int _activeId = 1;
  bool _showDetail = false;
  final _controller = TextEditingController();
  final _newSummaryCtrl = TextEditingController();
  String _newTopic = 'Pendaftaran';
  String _newCompetition = 'Pilih kompetisi';

  @override
  void dispose() {
    _controller.dispose();
    _newSummaryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTicket = _tickets.firstWhere((t) => t.id == _activeId, orElse: () => _tickets.first);
    final msgs = _messages[activeTicket.id] ?? [];

    return _GradientBackground(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _showDetail
            ? Column(
                key: const ValueKey('detail'),
                children: [
                  _ChatAppBar(
                    title: activeTicket.user,
                    subtitle: activeTicket.title,
                    color: activeTicket.avatarColor,
                    onBack: () => setState(() => _showDetail = false),
                  ),
                  Expanded(
                      child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD4E4FF)),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                              child: ListView.builder(
                              itemCount: msgs.length,
                              reverse: false,
                              itemBuilder: (_, i) {
                                final m = msgs[i];
                                final isMe = m.from == 'admin';
                                return Align(
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                    constraints: const BoxConstraints(maxWidth: 300),
                                    decoration: BoxDecoration(
                                      color: isMe ? const Color(0xFF1E88E5) : const Color(0xFFEFF4FF),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.text,
                                          style: TextStyle(
                                            height: 1.3,
                                            color: isMe ? Colors.white : const Color(0xFF1A2F4D),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              m.time,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.6),
                                                fontSize: 11,
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 6),
                                              Icon(Icons.done_all,
                                                  size: 16, color: Colors.white.withOpacity(0.7)),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Row(
                            children: [
                              SizedBox(
                                width: 46,
                                height: 46,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    side: const BorderSide(color: Color(0xFFD4E4FF)),
                                    backgroundColor: Colors.white,
                                  ),
                                  onPressed: () => _showAttachSheet(context),
                                  child: const Icon(Icons.add, color: Color(0xFF1E88E5)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  decoration: const InputDecoration(
                                    hintText: 'Ketik pesan',
                                    contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 48,
                                width: 48,
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (_controller.text.trim().isEmpty) return;
                                    setState(() {
                                      msgs.add(ChatMessage('admin', _controller.text.trim(), 'Now'));
                                      _messages[activeTicket.id] = msgs;
                                      _controller.clear();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: const Icon(Icons.send_rounded, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                key: const ValueKey('list'),
                children: [
                  const _TitleRow(title: 'Chat'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F8FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD4E4FF)),
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Cari chat atau tiket',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF7B8CA7)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
                      itemBuilder: (_, i) {
                        final t = _tickets[i];
                        return _ChatListItem(
                          ticket: t,
                          onTap: () => setState(() {
                            _activeId = t.id;
                            _showDetail = true;
                          }),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemCount: _tickets.length,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 20, bottom: 20),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: FloatingActionButton.extended(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add),
                        label: const Text('Buat percakapan'),
                        onPressed: _openNewChatPage,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _openNewChatPage() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NewChatPage(
        initialTopic: _newTopic,
        initialCompetition: _newCompetition,
        onCreate: (topic, competition, summary) {
          _newTopic = topic;
          _newCompetition = competition;
          _newSummaryCtrl.text = summary;
          _createNewChat();
        },
      ),
      fullscreenDialog: true,
    ));
  }

  void _createNewChat() {
    final summary = _newSummaryCtrl.text.trim();
    if (summary.isEmpty) return;
    final nextId = (_tickets.map((e) => e.id).fold<int>(0, (p, c) => c > p ? c : p)) + 1;
    final newTicket = Ticket(
      id: nextId,
      title: 'Tiket #$nextId',
      user: 'Anda',
      summary: summary,
      status: 'Baru',
      lastMessage: summary,
      topic: _newTopic,
      time: 'Now',
      unread: 0,
      avatarColor: const Color(0xFF25D366),
    );
    setState(() {
      _tickets.insert(0, newTicket);
      _messages[nextId] = [ChatMessage('user', summary, 'Now')];
      _activeId = nextId;
      _showDetail = true;
      _newSummaryCtrl.clear();
      _newTopic = 'Pendaftaran';
      _newCompetition = 'Pilih kompetisi';
    });
  }

  void _showAttachSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Wrap(
            runSpacing: 12,
            children: [
              const Text('Kirim lampiran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.attach_file, color: Color(0xFF1E88E5)),
                title: const Text('File'),
                onTap: () async {
                  await _pickFile(context);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Color(0xFF1E88E5)),
                title: const Text('Gambar'),
                onTap: () async {
                  await _pickImage(context);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, color: Color(0xFF1E88E5)),
                title: const Text('Video'),
                onTap: () async {
                  await _pickVideo(context);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      _addAttachmentMessage(result.files.first.name);
    } else {
      _showInfo(context, 'Pemilihan file dibatalkan');
    }
  }

  Future<void> _pickImage(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      _addAttachmentMessage(result.files.first.name);
    } else {
      _showInfo(context, 'Pemilihan gambar dibatalkan');
    }
  }

  Future<void> _pickVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      _addAttachmentMessage(result.files.first.name);
    } else {
      _showInfo(context, 'Pemilihan video dibatalkan');
    }
  }

  void _addAttachmentMessage(String name) {
    final activeTicket = _tickets.firstWhere((t) => t.id == _activeId, orElse: () => _tickets.first);
    final msgs = _messages[activeTicket.id] ?? [];
    setState(() {
      msgs.add(ChatMessage('admin', 'Lampiran: $name', 'Now'));
      _messages[activeTicket.id] = msgs;
    });
  }

  void _showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }
}

class InfoTab extends StatelessWidget {
  const InfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    return _GradientBackground(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _TitleRow(title: 'Informasi'),
            SizedBox(height: 12),
            _GlassCard(
              child: Text('Tempatkan pengumuman, jadwal kompetisi, atau FAQ di sini.'),
            ),
          ],
        ),
      ),
    );
  }
}

class SupportTab extends StatelessWidget {
  const SupportTab({super.key});

  @override
  Widget build(BuildContext context) {
    return _GradientBackground(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _TitleRow(title: 'Support'),
            SizedBox(height: 12),
            _GlassCard(child: Text('Daftar kanal bantuan (email, WhatsApp, knowledge base) akan ditempatkan di sini.')),
          ],
        ),
      ),
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return _GradientBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TitleRow(title: 'Profil'),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E88E5), Color(0xFF6CC5FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Color(0x331E88E5), blurRadius: 16, offset: Offset(0, 10)),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'AN',
                              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('Alya Nabila', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('alya.nabila@email.com', style: TextStyle(color: Color(0xFF526380))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _GlassCard(
                    child: Column(
                      children: [
                        _ProfileRow(label: 'Nomor telepon', value: '+62 812 3456 7890'),
                        const Divider(height: 20, color: Color(0xFFE0E8F5)),
                        _ProfileRow(label: 'Institusi', value: 'Universitas Panca Abadi'),
                        const Divider(height: 20, color: Color(0xFFE0E8F5)),
                        _ProfileRow(label: 'Peran', value: 'Peserta'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GlassCard(
                    child: Column(
                      children: const [
                        _SettingRow(label: 'Ubah kata sandi'),
                        Divider(height: 20, color: Color(0xFFE0E8F5)),
                        _SettingRow(label: 'Bahasa'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Keluar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onLogout,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD4E4FF)),
          ),
          child: const Text('POSI', style: TextStyle(color: Color(0xFF1E88E5), fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ),
      ],
    );
  }
}

class _GradientBackground extends StatelessWidget {
  const _GradientBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Color(0xFFF4F8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4E4FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1E88E5),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HomeIcon extends StatelessWidget {
  const _HomeIcon({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color bg = active ? const Color(0xFF1E88E5) : const Color(0xFFB8D8FF);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          if (active)
            BoxShadow(
              color: const Color(0xFF1E88E5).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: const Icon(
        Icons.home_filled,
        size: 24,
        color: Colors.white,
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget {
  const _ChatAppBar({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withOpacity(0.2),
            child: Text(title.isNotEmpty ? title[0] : '?', style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: Color(0xFF9AB3D7), fontSize: 12)),
            ],
          ),
          const Spacer(),
          IconButton(onPressed: () {}, icon: const Icon(Icons.videocam_outlined)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
        ],
      ),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  const _ChatListItem({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE3F2FF),
            child: Text(ticket.user.isNotEmpty ? ticket.user[0] : '?',
                style: const TextStyle(color: Color(0xFF1A2F4D), fontWeight: FontWeight.w700)),
          ),
          if (ticket.pinned)
            const Positioned(
              right: -2,
              bottom: -2,
              child: Icon(Icons.push_pin, size: 16, color: Color(0xFF8CA2C3)),
            ),
        ],
      ),
      title: Text(ticket.user, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0A1F3F))),
      subtitle: Text(
        ticket.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF526380)),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(ticket.time, style: const TextStyle(color: Color(0xFF526380), fontSize: 12)),
          const SizedBox(height: 6),
          if (ticket.unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                ticket.unread.toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _GoogleLoginButton extends StatelessWidget {
  const _GoogleLoginButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          side: const BorderSide(color: Color(0xFF1E88E5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E88E5),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            _GoogleMark(),
            SizedBox(width: 10),
            Text(
              'Masuk dengan Google',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF202124),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFBDC1C6)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Positioned(
            left: 5,
            child: Text(
              'G',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF4285F4),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({
    super.key,
    required this.onCreate,
    required this.initialTopic,
    required this.initialCompetition,
  });

  final void Function(String topic, String competition, String summary) onCreate;
  final String initialTopic;
  final String initialCompetition;

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  late String _topic;
  late String _competition;
  final _summaryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _topic = widget.initialTopic;
    _competition = widget.initialCompetition;
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF1E2F45)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Chat Admin', style: TextStyle(color: Color(0xFF1E2F45))),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Row(
              children: const [
                Icon(Icons.chat_bubble_outline, color: Color(0xFF1E2F45)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tanyakan apa saja terkait kendala yang anda alami',
                    style: TextStyle(color: Color(0xFF1E2F45)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD4E4FF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A1E88E5),
                    blurRadius: 16,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Halo selamat datang, sebelum kami membantu anda, silahkan isi dulu permasalahan yang ingin anda tanyakan ke admin.',
                      style: TextStyle(color: Color(0xFF1E2F45)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Nama kompetisi', style: TextStyle(color: Color(0xFF1A2F4D))),
                  const SizedBox(height: 6),
                  _SelectBox(
                    value: _competition,
                    items: const ['Pilih kompetisi', 'POSI Online 2026', 'POSI Onsite 2026'],
                    onChanged: (v) => setState(() => _competition = v ?? 'Pilih kompetisi'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Perihal', style: TextStyle(color: Color(0xFF1A2F4D))),
                  const SizedBox(height: 6),
                  _SelectBox(
                    value: _topic,
                    items: const ['Pendaftaran', 'Pemesanan', 'Lainnya'],
                    onChanged: (v) => setState(() => _topic = v ?? 'Pendaftaran'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Ringkasan masalah', style: TextStyle(color: Color(0xFF1A2F4D))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _summaryCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFFF8FBFF),
                      hintText: 'Tuliskan singkat masalah yang ingin ditanyakan',
                      hintStyle: TextStyle(color: Color(0xFF7B8CA7)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: Color(0xFFD4E4FF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: Color(0xFFD4E4FF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: Color(0xFF1E88E5)),
                      ),
                    ),
                    style: const TextStyle(color: Color(0xFF1A2F4D)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A2F4D),
                          side: const BorderSide(color: Color(0xFF1E88E5)),
                          minimumSize: const Size(110, 44),
                          backgroundColor: Colors.white,
                        ),
                        child: const Text('Batal'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          widget.onCreate(_topic, _competition, _summaryCtrl.text.trim());
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(140, 44),
                          backgroundColor: const Color(0xFF1E88E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                        child: const Text('Mulai Chat'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.value, required this.items, required this.onChanged});

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = items.contains(value) ? value : (items.isNotEmpty ? items.first : null);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4E4FF)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButton<String>(
        value: safeValue,
        dropdownColor: Colors.white,
        style: const TextStyle(color: Color(0xFF1A2F4D)),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF7B8CA7)),
        onChanged: onChanged,
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Color(0xFF1A2F4D)))))
            .toList(),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD4E4FF)),
          boxShadow: const [
            BoxShadow(color: Color(0x141E88E5), blurRadius: 12, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF526380))),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF143155))),
                const SizedBox(width: 8),
                Icon(Icons.trending_up, color: accent, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF1A2F4D), fontWeight: FontWeight.w600)),
        const Icon(Icons.chevron_right, color: Color(0xFF7B8CA7)),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF526380))),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Color(0xFF143155), fontWeight: FontWeight.w700)),
          ],
        ),
        const Icon(Icons.edit_outlined, color: Color(0xFF7B8CA7)),
      ],
    );
  }
}
