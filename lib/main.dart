import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'http_adapter.dart' as http_adapter;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _notifChannel = AndroidNotificationChannel(
  'posi_chat',
  'POSI Chat',
  description: 'Notifikasi pesan POSI',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // OS akan menampilkan notifikasi jika payload mengandung "notification".
}

Future<void> _initPush() async {
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _fln.initialize(initSettings);
  await _fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_notifChannel);

  await FirebaseMessaging.instance
      .setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  FirebaseMessaging.onMessage.listen(_showLocalNotification);
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  final notification = message.notification;
  final androidDetails = AndroidNotificationDetails(
    _notifChannel.id,
    _notifChannel.name,
    channelDescription: _notifChannel.description,
    importance: Importance.high,
    priority: Priority.high,
  );
  final details = NotificationDetails(android: androidDetails);
  await _fln.show(
    notification.hashCode,
    notification?.title ?? 'Pesan baru',
    notification?.body ?? (message.data['body'] as String? ?? 'Ada pesan baru'),
    details,
    payload: message.data['ticketId']?.toString(),
  );
}

Future<void> _registerFcmTokenIfAuthenticated() async {
  try {
    final perm = await FirebaseMessaging.instance.requestPermission();
    if (perm.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && apiClient.authToken != null) {
      final platform = kIsWeb
          ? 'web'
          : (Platform.isIOS
              ? 'ios'
              : (Platform.isAndroid ? 'android' : Platform.operatingSystem));
      await apiClient.registerDeviceToken(
        token,
        platform: platform,
        app: kIsWeb ? 'posi-web' : 'posi-mobile',
      );
    }
  } catch (_) {}
}

/// Simple API client to hit the POSI web backend and keep session cookies.
class ApiClient {
  ApiClient({String? baseUrl})
      : _baseUrl = baseUrl ??
            const String.fromEnvironment(
              'POSI_API_BASE',
              defaultValue: '',
            ) {
    final envBase = dotenv.maybeGet('POSI_API_BASE') ?? '';
    final fallback = envBase.isNotEmpty
        ? envBase
        : (_baseUrl.isNotEmpty
            ? _baseUrl
            : (kIsWeb
                ? '${Uri.base.scheme}://${Uri.base.host}:4000'
                : 'http://10.0.2.2:4000'));
    _baseUrlResolved = fallback;
    final jar = CookieJar();
    _cookieJar = jar;
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrlResolved,
        followRedirects:
            false, // avoid cross-site redirect CORS in web; handle 302 manually
        validateStatus: (code) => code != null && code < 500,
        extra: const {'withCredentials': true},
      ),
    );
    _dio.httpClientAdapter = http_adapter.createAdapter();
    if (!kIsWeb) {
      _dio.interceptors.add(CookieManager(jar));
    }
  }

  late final Dio _dio;
  final String _baseUrl;
  late final String _baseUrlResolved;
  String? _authToken;
  IO.Socket? _socket;
  // Persisted auth token for auto-login across app restarts.
  static const _tokenPrefsKey = 'posi_token';
  final Set<int> _joinedRooms = {};
  IO.Socket? get socket => _socket;
  CookieJar? _cookieJar;

  String get baseUrl => _baseUrlResolved;
  String? get authToken => _authToken;

  Future<void> loadPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenPrefsKey);
    if (saved != null && saved.isNotEmpty) {
      _authToken = saved;
      _dio.options.headers['Authorization'] = 'Bearer $saved';
    }
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenPrefsKey, token);
  }

  Future<void> clearPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenPrefsKey);
  }

  Future<List<TicketData>> fetchTickets() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/chat/tickets',
        queryParameters: {'mine': 1});
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw Exception('Gagal memuat tiket (${res.statusCode})');
    }
    final list = (res.data?['tickets'] as List?) ?? [];
    return list
        .map((e) => TicketData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessageData>> fetchMessages(int ticketId) async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/chat/tickets/$ticketId/messages');
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw Exception('Gagal memuat pesan (${res.statusCode})');
    }
    final list = (res.data?['messages'] as List?) ?? [];
    return list
        .map((e) => ChatMessageData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendMessage(int ticketId, String text) async {
    await _dio
        .post('/api/chat/tickets/$ticketId/messages', data: {'text': text});
  }

  Future<TicketData> createTicket(
      int? competitionId, String topic, String summary) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/chat/tickets',
      data: {
        'competition_id': competitionId,
        'topic': topic,
        'summary': summary,
        'message': summary,
      },
    );
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw Exception('Gagal membuat tiket (${res.statusCode})');
    }
    final t = res.data?['ticket'] as Map<String, dynamic>? ?? {};
    final firstMsg = res.data?['firstMessage'] as Map<String, dynamic>?;
    final ticket = TicketData.fromJson(t)
      ..lastMessage = firstMsg != null ? firstMsg['text'] as String? : null;
    return ticket;
  }

  Future<ProfileData> fetchProfile() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/profile',
      options: Options(
        headers: {
          'Accept': 'application/json',
        },
      ),
    );
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw Exception('Gagal memuat profil (${res.statusCode})');
    }
    final Map<String, dynamic> data =
        res.data ?? (jsonDecode(res.data.toString()) as Map<String, dynamic>);
    return ProfileData.fromJson(data);
  }

  Future<LoginResult> login(String email, String password) async {
    try {
      debugPrint('Login request => $baseUrl');
      final res = await _dio.post<Map<String, dynamic>>(
        '/login',
        data: {
          'email': email,
          'password': password,
          'redirectTo': '/',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      Map<String, dynamic>? data;
      final ct = res.headers.value('content-type') ?? '';
      try {
        if (ct.contains('application/json')) {
          if (res.data is Map<String, dynamic>) {
            data = res.data as Map<String, dynamic>;
          } else if (res.data is String) {
            data = jsonDecode(res.data as String) as Map<String, dynamic>;
          }
        }
      } catch (_) {
        // ignore JSON parse errors for non-JSON responses (e.g., redirected HTML)
      }

      final code = res.statusCode ?? 0;
      if (code >= 400) {
        final msgFromServer = data != null ? data['message'] as String? : null;
        final msg = msgFromServer?.isNotEmpty == true
            ? msgFromServer
            : (code == 401
                ? 'Email atau password salah'
                : 'Login gagal (${res.statusCode})');
        return LoginResult(false, msg);
      }

      // simpan token jika tersedia
      final token = data?['token'] as String?;
      if (token != null) {
        _authToken = token;
        _dio.options.headers['Authorization'] = 'Bearer $token';
        await _saveToken(token);
      }

      if (data != null && data['errors'] != null) {
        final errors = data['errors'] as Map;
        final msg = errors['form'] as String? ??
            errors['email'] as String? ??
            errors['password'] as String?;
        return LoginResult(false, msg ?? 'Email atau password salah');
      }

      // Treat 2xx or 3xx as success; cookie should already be set by browser
      return LoginResult(true, null);
    } catch (_) {
      return LoginResult(false, 'Tidak bisa terhubung ke server');
    }
  }

  Future<LoginResult> loginWithGoogle(String idToken) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/google',
        data: {'idToken': idToken},
        options: Options(headers: {'Accept': 'application/json'}),
      );
      final data = res.data;
      if (res.statusCode != null && res.statusCode! >= 400) {
        final msg = data?['message'] as String? ?? 'Login Google gagal';
        return LoginResult(false, msg);
      }
      final token = data?['token'] as String?;
      if (token != null) {
        _authToken = token;
        _dio.options.headers['Authorization'] = 'Bearer $token';
        await _saveToken(token);
      }
      return LoginResult(true, null);
    } catch (e) {
      return LoginResult(false, 'Login Google gagal: $e');
    }
  }
  Future<LoginResult> loginWithGoogleAccess(String accessToken) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/google',
        data: {'accessToken': accessToken},
        options: Options(headers: {'Accept': 'application/json'}),
      );
      final data = res.data;
      if (res.statusCode != null && res.statusCode! >= 400) {
        final msg = data?['message'] as String? ?? 'Login Google gagal';
        return LoginResult(false, msg);
      }
      final token = data?['token'] as String?;
      if (token != null) {
        _authToken = token;
        _dio.options.headers['Authorization'] = 'Bearer $token';
      }
      return LoginResult(true, null);
    } catch (e) {
      return LoginResult(false, 'Login Google gagal: $e');
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/logout');
    } catch (_) {
      // ignore
    }
    _authToken = null;
    _dio.options.headers.remove('Authorization');
    _socket?.disconnect();
    _socket = null;
    await clearPersistedToken();
  }
  Future<List<CompetitionOption>> fetchCompetitions() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/competitions');
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw Exception('Gagal memuat kompetisi (${res.statusCode})');
    }
    final list = (res.data?['competitions'] as List?) ??
        (res.data?['data'] as List?) ??
        [];
    return list
        .map((e) => CompetitionOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // -------- Socket.IO --------
  Future<void> ensureSocket({
    void Function(ChatMessageData message, int ticketId)? onMessage,
  }) async {
    if (_socket != null) return;
    String? token = _authToken;
    if (token == null && _cookieJar != null) {
      try {
        final cookies = await _cookieJar!
            .loadForRequest(Uri.parse(_baseUrlResolved));
        for (final c in cookies) {
          if (c.name.toLowerCase() == 'token' && c.value.isNotEmpty) {
            token = c.value;
            break;
          }
        }
      } catch (_) {}
    }
    final query = {
      'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      if (token != null) 'token': token,
    };

    final builder = IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .enableForceNew()
        .enableAutoConnect();

    if (!kIsWeb && token != null) {
      builder.setExtraHeaders({'Authorization': 'Bearer $token'});
    }
    builder.setQuery(query);

    final opts = builder.build();
    _socket = IO.io(_baseUrlResolved, opts);

    _socket!.onConnect((_) {
      debugPrint('Socket connected');
      for (final id in _joinedRooms) {
        _socket!.emit('join-ticket', id);
      }
    });
    _socket!.onReconnect((_) {
      debugPrint('Socket reconnected');
      for (final id in _joinedRooms) {
        _socket!.emit('join-ticket', id);
      }
    });
    _socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
    _socket!.onError((err) => debugPrint('Socket error: $err'));

    _socket!.on('message:new', (data) {
      if (data is Map) {
        final message =
            ChatMessageData.fromJson(data.cast<String, dynamic>());
        final rawId = data['ticket_id'] ?? data['ticketId'];
        final ticketId = rawId is int
            ? rawId
            : (rawId is String ? int.tryParse(rawId) ?? 0 : 0);
        if (onMessage != null) onMessage(message, ticketId);
      }
    });
  }

  void joinTicketRoom(int ticketId) {
    _joinedRooms.add(ticketId);
    _socket?.emit('join-ticket', ticketId);
  }

  Future<void> markTicketRead(int ticketId) async {
    try {
      await _dio.patch('/api/chat/tickets/$ticketId/read');
    } catch (_) {
      // non-fatal
    }
  }

  void sendSocketMessage(int ticketId, String text) {
    _socket?.emit('message:send', {'ticketId': ticketId, 'text': text});
  }

  Future<void> registerDeviceToken(String token,
      {String platform = 'android', String? app}) async {
    try {
      await _dio.post('/api/devices',
          data: {'token': token, 'platform': platform, 'app': app});
    } catch (_) {
      // non-fatal; bisa dicoba ulang nanti
    }
  }
}

class LoginResult {
  LoginResult(this.ok, this.message);
  final bool ok;
  final String? message;
}

final apiClient = ApiClient();
late final GoogleSignIn _googleSignIn;

class CompetitionOption {
  CompetitionOption({required this.id, required this.title});
  final int id;
  final String title;

  factory CompetitionOption.fromJson(Map<String, dynamic> json) =>
      CompetitionOption(
        id: json['id'] ?? 0,
        title: (json['title'] ?? json['name'] ?? '').toString(),
      );
}

class TicketData {
  TicketData({
    required this.id,
    required this.topic,
    required this.summary,
    required this.status,
    required this.competitionTitle,
    this.lastMessage,
    this.lastMessageAt,
  });

  final int id;
  final String topic;
  final String summary;
  String status;
  final String competitionTitle;
  String? lastMessage;
  String? lastMessageAt;

  factory TicketData.fromJson(Map<String, dynamic> json) => TicketData(
        id: json['id'] ?? 0,
        topic: (json['topic'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        competitionTitle:
            (json['competitionTitle'] ?? 'Tanpa Kompetisi').toString(),
        lastMessage: json['lastMessage'] is Map
            ? (json['lastMessage']?['text'] as String?)
            : (json['lastMessage'] as String?) ?? json['summary']?.toString(),
        lastMessageAt:
            (json['lastMessageAt'] ?? json['updatedAt']) as String?,
      );
}

class ChatMessageData {
  ChatMessageData({
    required this.id,
    required this.senderType,
    required this.text,
    required this.createdAt,
  });

  final int id;
  final String senderType; // 'user' | 'admin'
  final String text;
  final String createdAt;

  factory ChatMessageData.fromJson(Map<String, dynamic> json) =>
      ChatMessageData(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch,
        senderType: (json['senderType'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? '').toString(),
      );
}

class ProfileData {
  ProfileData({
    required this.id,
    required this.name,
    required this.email,
    required this.whatsapp,
    required this.levelName,
    required this.kelasName,
    required this.tanggalLahir,
    required this.agama,
    required this.jenisKelamin,
    required this.provinsiName,
    required this.kabupatenName,
    required this.kecamatanName,
    required this.namaSekolah,
  });

  final int id;
  final String name;
  final String email;
  final String whatsapp;
  final String levelName;
  final String kelasName;
  final String tanggalLahir;
  final String agama;
  final String jenisKelamin;
  final String provinsiName;
  final String kabupatenName;
  final String kecamatanName;
  final String namaSekolah;

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final levels = (json['levels'] as List?) ?? [];
    final kelas = (json['kelas'] as List?) ?? [];
    final geo = (json['geographic'] as Map<String, dynamic>?) ?? {};
    final provinces =
        (geo['provinces'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final cities = (geo['cities'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final districts =
        (geo['districts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    String levelName = '';
    if (user['level_id'] != null) {
      levelName = levels
              .map((e) => e as Map<String, dynamic>)
              .firstWhere((e) => e['id'] == user['level_id'], orElse: () => {})
              .cast<String, dynamic>()['level_name'] ??
          '';
    }
    String kelasName = '';
    if (user['kelas_id'] != null) {
      kelasName = kelas
              .map((e) => e as Map<String, dynamic>)
              .firstWhere((e) => e['id'] == user['kelas_id'], orElse: () => {})
              .cast<String, dynamic>()['nama_kelas'] ??
          '';
    }

    String pick(v) => (v ?? '').toString().trim();

    return ProfileData(
      id: user['id'] ?? 0,
      name: pick(user['name']),
      email: pick(user['email']),
      whatsapp: pick(user['whatsapp']),
      levelName: levelName,
      kelasName: kelasName,
      tanggalLahir: pick(user['tanggal_lahir']),
      agama: pick(user['agama']),
      jenisKelamin: pick(user['jenis_kelamin']),
      provinsiName: provinces.firstWhere(
            (p) => p['code'] == user['provinsi'],
            orElse: () => const {'name': ''},
          )['name'] as String? ??
          '',
      kabupatenName: cities.firstWhere(
            (c) => c['code'] == user['kabupaten'],
            orElse: () => const {'name': ''},
          )['name'] as String? ??
          '',
      kecamatanName: districts.firstWhere(
            (d) => d['code'] == user['kecamatan'],
            orElse: () => const {'name': ''},
          )['name'] as String? ??
          '',
      namaSekolah: pick(user['nama_sekolah']),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await _initPush();
  await apiClient.loadPersistedToken();
  final googleClientId = dotenv.maybeGet('GOOGLE_WEB_CLIENT_ID') ??
      const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');
  _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    clientId: googleClientId.isNotEmpty ? googleClientId : null,
  );
  await _registerFcmTokenIfAuthenticated();
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
          headlineMedium: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: Color(0xFF143155)),
          titleLarge:
              TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF143155)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          ? MainShell(
              onLogout: () async {
                await apiClient.logout();
                if (mounted) setState(() => _loggedIn = false);
              },
            )
          : LoginScreen(onLogin: () => setState(() => _loggedIn = true)),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email dan password wajib diisi');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await apiClient.login(email, password);
      if (!mounted) return;
      if (result.ok) {
        setState(() {
          _loading = false;
          _error = null;
        });
        await _registerFcmTokenIfAuthenticated();
        widget.onLogin();
      } else {
        setState(() {
          _error = result.message ?? 'Email atau password salah';
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        String msg = 'Gagal login';
        if (e.response != null) {
          final status = e.response?.statusCode;
          final data = e.response?.data;
          final serverMsg = (data is Map && data['message'] is String)
              ? data['message'] as String
              : null;
          if (serverMsg != null && serverMsg.isNotEmpty) {
            msg = serverMsg;
          } else if (status == 401) {
            msg = 'Email atau password salah';
          } else if (status != null) {
            msg = 'Server error ($status)';
          }
        } else if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          msg = 'Server sibuk / timeout, coba lagi';
        } else {
          msg = e.message ?? msg;
        }
        _error = msg;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal login: $e';
        _loading = false;
      });
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      final acct = await _googleSignIn.signIn();
      if (acct == null) {
        setState(() => _googleLoading = false);
        return;
      }
      final auth = await acct.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;
      if (idToken == null && accessToken == null) {
        setState(() {
          _googleLoading = false;
          _error = 'Token Google tidak ditemukan';
        });
        return;
      }
      LoginResult result;
      if (idToken != null) {
        result = await apiClient.loginWithGoogle(idToken);
      } else {
        result = await apiClient.loginWithGoogleAccess(accessToken!);
      }
      if (!mounted) return;
      if (result.ok) {
        setState(() => _googleLoading = false);
        await _registerFcmTokenIfAuthenticated();
        widget.onLogin();
      } else {
        setState(() {
          _googleLoading = false;
          _error = result.message ?? 'Login Google gagal';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _error = 'Login Google gagal: $e';
      });
    }
  }

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
                const SizedBox(height: 24),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE57373)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFCDD2)),
                    ),
                  ),
                const Text('Email',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    hintText: 'nama@contoh.com',
                    prefixIcon:
                        Icon(Icons.mail_outline, color: Color(0xFF6E8BB6)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Password',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    hintText: '********',
                    prefixIcon:
                        Icon(Icons.lock_outline, color: Color(0xFF6E8BB6)),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _handleLogin,
                  child: _loading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Sedang masuk...'),
                          ],
                        )
                      : const Text('Masuk'),
                ),
                const SizedBox(height: 14),
                _GoogleLoginButton(
                  onPressed:
                      (_loading || _googleLoading) ? null : _handleGoogleLogin,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : () {},
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
  const MainShell({super.key, required this.onLogout, this.initialIndex = 4});

  final VoidCallback onLogout;
  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index; // default set in initState

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

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
          const BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded), label: 'Chat'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.info_rounded), label: 'Informasi'),
          BottomNavigationBarItem(
              icon: _HomeIcon(active: _index == 2), label: 'Home'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.support_agent_rounded), label: 'Support'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profil'),
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
            _TitleRow(title: 'Selamat datang Ã°Å¸â€˜â€¹'),
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
                _MetricCard(
                    label: 'Tiket aktif',
                    value: '3',
                    accent: Color(0xFF4CC2FF)),
                SizedBox(width: 12),
                _MetricCard(
                    label: 'Selesai', value: '12', accent: Color(0xFF7CE7C7)),
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

class _ChatTabState extends State<ChatTab> {
  List<TicketData> _tickets = [];
  final _messages = <int, List<ChatMessageData>>{};
  String _ticketsSig = '';
  final _messageSigs = <int, String>{};
  String _search = '';
  int? _activeId;
  bool _showDetail = false;
  bool _forceScrollNextLoad = false;
  final _controller = TextEditingController();
  final _msgScroll = ScrollController();
  final _newSummaryCtrl = TextEditingController();
  String _newTopic = 'Pendaftaran';
  bool _loadingTickets = true;
  bool _loadingMessages = false;
  bool _sending = false;
  Timer? _ticketsTimer;
  Timer? _messagesTimer;
  ProfileData? _profile;
  final Set<int> _unreadTickets = {};
  bool _socketConnected = false;

  DateTime? _parseTs(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    return dt.isUtc ? dt.toLocal() : dt;
  }

int _tsMillis(String? ts) {
  if (ts == null || ts.isEmpty) return 0;
  final dt = _parseTs(ts);
  if (dt == null) return 0;
  return dt.millisecondsSinceEpoch;
}

DateTime? _parseTsLocal(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final dt = DateTime.tryParse(raw);
  if (dt == null) return null;
  return dt.isUtc ? dt.toLocal() : dt;
}

  void _sortTickets() {
    _tickets.sort((a, b) {
      final at = _tsMillis(a.lastMessageAt);
      final bt = _tsMillis(b.lastMessageAt);
      return bt.compareTo(at);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _msgScroll.dispose();
    _newSummaryCtrl.dispose();
    _ticketsTimer?.cancel();
    _messagesTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadTickets().whenComplete(_startSocket);
  }

  void _startSocket() {
    apiClient.ensureSocket(onMessage: (msg, ticketId) {
      final nowTs = DateTime.now().toIso8601String();
      bool updated = false;
      debugPrint('[socket] message:new ticket=$ticketId text=${msg.text}');
      setState(() {
        final list = _messages[ticketId] ?? [];
        _messages[ticketId] = [
          ...list,
          ChatMessageData(
            id: msg.id,
            senderType: msg.senderType,
            text: msg.text,
            createdAt: msg.createdAt.isNotEmpty ? msg.createdAt : nowTs,
          )
        ];
        _messageSigs[ticketId] = _sigMessages(_messages[ticketId]!);
        _tickets = _tickets
            .map((t) => t.id == ticketId
                ? TicketData(
                    id: t.id,
                    topic: t.topic,
                    summary: t.summary,
                    status: t.status,
                    competitionTitle: t.competitionTitle,
                    lastMessage: msg.text,
                    lastMessageAt: nowTs, // gunakan waktu terima lokal untuk mengurutkan
                  )
                : t)
            .toList();
        updated = _tickets.any((t) => t.id == ticketId);
        _sortTickets();
        if (_activeId != ticketId || !_showDetail) {
          _unreadTickets.add(ticketId);
        }
      });
      if (!updated) {
        // jika tiket belum ada (misal baru dibuat), refresh ringan tanpa spinner
        _loadTickets(withLoading: false);
      } else {
        // pastikan room yang aktif tetap ter-join jika datang pesan pertama kali
        apiClient.joinTicketRoom(ticketId);
      }
      _maybeScrollToBottom();
    });

    apiClient.socket?.onConnect((_) {
      debugPrint('[socket] connected');
      setState(() => _socketConnected = true);
      _messagesTimer?.cancel();
    });
    apiClient.socket?.onDisconnect((_) {
      debugPrint('[socket] disconnected');
      setState(() => _socketConnected = false);
      _startFallbackPolling();
    });
    apiClient.socket?.onConnectError((err) {
      debugPrint('[socket] connect_error $err');
    });
    apiClient.socket?.onError((err) {
      debugPrint('[socket] error $err');
    });
  }

  Future<void> _loadProfile() async {
    try {
      final p = await apiClient.fetchProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      // ignore; profil tidak wajib untuk chat
    }
  }

  Future<void> _loadTickets({bool withLoading = true}) async {
    if (withLoading) setState(() => _loadingTickets = true);
    try {
      final res = await apiClient.fetchTickets();
      res.sort((a, b) {
        final at = DateTime.tryParse(a.lastMessageAt ?? '')?.millisecondsSinceEpoch ?? 0;
        final bt = DateTime.tryParse(b.lastMessageAt ?? '')?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      final newSig = _sigTickets(res);
      if (newSig != _ticketsSig) {
        setState(() {
          _tickets = res;
          _ticketsSig = newSig;
          if (_tickets.isNotEmpty) {
            _activeId ??= _tickets.first.id;
          }
        });
        // join semua room agar dapat notifikasi realtime di list
        for (final t in res) {
          apiClient.joinTicketRoom(t.id);
        }
      }
      if (_activeId != null) {
        final currentId = _activeId!;
        apiClient.joinTicketRoom(currentId); // pastikan room aktif ter-join
        _loadMessages(currentId);
      }
    } catch (_) {
      // ignore for now
    } finally {
      if (mounted && withLoading) setState(() => _loadingTickets = false);
    }
  }

  Future<void> _loadMessages(int ticketId, {bool withLoading = true}) async {
    if (withLoading) setState(() => _loadingMessages = true);
    try {
      final res = await apiClient.fetchMessages(ticketId);
      final newSig = _sigMessages(res);
      if (_messageSigs[ticketId] != newSig) {
        setState(() {
          _messages[ticketId] = res;
          _messageSigs[ticketId] = newSig;
        });
        _maybeScrollToBottom(force: _forceScrollNextLoad);
        _forceScrollNextLoad = false;
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted && withLoading) setState(() => _loadingMessages = false);
    }
  }

  void _startFallbackPolling() {
    _messagesTimer?.cancel();
    _messagesTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_socketConnected) return;
      if (_activeId != null) _loadMessages(_activeId!, withLoading: false);
    });
  }


  void _maybeScrollToBottom({bool force = false}) {
    if (!_msgScroll.hasClients) return;
    final distanceFromBottom =
        _msgScroll.position.maxScrollExtent - _msgScroll.position.pixels;
    if (force || distanceFromBottom < 120) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_msgScroll.hasClients) {
          _msgScroll.animateTo(
            _msgScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  String _sigTickets(List<TicketData> list) {
    final buf = StringBuffer(list.length);
    for (final t in list.take(50)) {
      buf.write('${t.id}:${t.status}:${t.lastMessageAt ?? ''}|');
    }
    return buf.toString();
  }

  String _sigMessages(List<ChatMessageData> list) {
    if (list.isEmpty) return '0';
    final last = list.last;
    return '${list.length}:${last.id}:${last.createdAt}:${last.senderType}';
  }

  List<_MessageEntry> _buildMessageEntries(List<ChatMessageData> msgs) {
    final result = <_MessageEntry>[];
    String? lastLabel;
    for (final m in msgs) {
      final label = _friendlyDate(m.createdAt);
      if (label != null && label != lastLabel) {
        result.add(_MessageEntry.date(label));
        lastLabel = label;
      }
      result.add(_MessageEntry.message(m));
    }
    return result;
  }

  String? _friendlyDate(String raw) {
    final dt = _parseTs(raw);
    if (dt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    final diff = dateOnly.difference(today).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == -1) return 'Kemarin';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _sendMessage() async {
    if (_activeId == null) return;
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final ticketId = _activeId!;
    final now = DateTime.now().toIso8601String();
    setState(() {
      _sending = true;
      final list = _messages[ticketId] ?? [];
      _messages[ticketId] = [
        ...list,
        ChatMessageData(id: DateTime.now().millisecondsSinceEpoch, senderType: 'user', text: text, createdAt: now)
      ];
      _controller.clear();
    });
    try {
      // kirim via REST (server akan broadcast ke socket)
      await apiClient.sendMessage(ticketId, text);
      // reload pesan untuk mengganti pesan optimistik dengan data real (id/timestamp)
      await _loadMessages(ticketId, withLoading: false);
      setState(() {
        _tickets = _tickets
            .map((t) => t.id == ticketId
                ? (TicketData(
                    id: t.id,
                    topic: t.topic,
                    summary: t.summary,
                    status: t.status,
                    competitionTitle: t.competitionTitle,
                    lastMessage: text,
                    lastMessageAt: now,
                  ))
                : t)
            .toList();
        _sortTickets();
      });
    } catch (_) {
      // rollback UI if failed
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    TicketData? activeTicket;
    if (_activeId != null) {
      for (final t in _tickets) {
        if (t.id == _activeId) {
          activeTicket = t;
          break;
        }
      }
      activeTicket ??= _tickets.isNotEmpty ? _tickets.first : null;
    }
    final msgs = activeTicket == null
        ? <ChatMessageData>[]
        : (_messages[activeTicket.id] ?? []);
    final entries = _buildMessageEntries(msgs);

    final filteredTickets = _search.isEmpty
        ? _tickets
        : _tickets
            .where((t) =>
                t.topic.toLowerCase().contains(_search) ||
                t.competitionTitle.toLowerCase().contains(_search) ||
                t.summary.toLowerCase().contains(_search))
            .toList();

    return _GradientBackground(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: (_showDetail && activeTicket != null)
            ? Builder(builder: (_) {
                final ticket = activeTicket!;
                return Column(
                  key: const ValueKey('detail'),
                  children: [
                    _ChatAppBar(
                      title: ticket.competitionTitle,
                      subtitle: ticket.topic,
                      color: const Color(0xFF1E88E5),
                      onBack: () => setState(() => _showDetail = false),
                    ),
                    if (_profile != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: _UserInfoCard(
                          profile: _profile!,
                          ticket: ticket,
                        ),
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
                                child: _loadingMessages
                                    ? const Center(
                                        child: CircularProgressIndicator())
                                    : ListView.builder(
                                        controller: _msgScroll,
                                        itemCount: entries.length,
                                        reverse: false,
                                        itemBuilder: (_, i) {
                                          final entry = entries[i];
                                          if (entry.type == _EntryType.date) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 10),
                                              child: Center(
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFEAF2FF),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Text(entry.label ?? '',
                                                      style: const TextStyle(
                                                          color:
                                                              Color(0xFF526380),
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                ),
                                              ),
                                            );
                                          }

                                          final m = entry.message!;
                                          final isMe = m.senderType == 'user';
                                          final time = _parseTs(m.createdAt);
                                          final timeText = time != null
                                              ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                                              : '';
                                          return Align(
                                            alignment: isMe
                                                ? Alignment.centerRight
                                                : Alignment.centerLeft,
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 6),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                      horizontal: 14),
                                              constraints:
                                                  const BoxConstraints(
                                                      maxWidth: 300),
                                              decoration: BoxDecoration(
                                                color: isMe
                                                    ? const Color(0xFF1E88E5)
                                                    : const Color(0xFFEFF4FF),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    m.text,
                                                    style: TextStyle(
                                                      height: 1.3,
                                                      color: isMe
                                                          ? Colors.white
                                                          : const Color(
                                                              0xFF1A2F4D),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    timeText,
                                                    style: TextStyle(
                                                      color: isMe
                                                          ? Colors.white
                                                              .withOpacity(0.8)
                                                          : const Color(
                                                                  0xFF1A2F4D)
                                                              .withOpacity(
                                                                  0.6),
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      )),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    enabled: !_sending,
                                    decoration: const InputDecoration(
                                      hintText: "Ketik pesan",
                                      contentPadding: EdgeInsets.symmetric(
                                          vertical: 12, horizontal: 14),
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 48,
                                  width: 48,
                                  child: ElevatedButton(
                                    onPressed: _sending ? null : _sendMessage,
                                    style: ElevatedButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                    ),
                                    child: _sending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.send_rounded,
                                            color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              })
            : Column(
                key: const ValueKey('list'),
                children: [
                  const _TitleRow(title: 'Chat'),
                  const SizedBox(height: 12),
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
                          prefixIcon: const Icon(Icons.search,
                              color: Color(0xFF7B8CA7)),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _loadingTickets
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
                            itemBuilder: (_, i) {
                              final t = filteredTickets[i];
                              return _ChatListItem(
                                ticket: t,
                                unread: _unreadTickets.contains(t.id),
                                onTap: () => setState(() {
                              _activeId = t.id;
                              _showDetail = true;
                              _forceScrollNextLoad = true;
                              apiClient.joinTicketRoom(t.id);
                              _unreadTickets.remove(t.id);
                              apiClient.markTicketRead(t.id);
                              _loadMessages(t.id);
                            }),
                      );
                    },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemCount: filteredTickets.length,
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
        initialCompetitionId: null,
        onCreate: (topic, competitionId, summary) {
          _newTopic = topic;
          _newSummaryCtrl.text = summary;
          _createNewChat(topic, competitionId, summary);
        },
      ),
      fullscreenDialog: true,
    ));
  }

  Future<void> _createNewChat(
      String topic, int? competitionId, String summary) async {
    final trimmed = summary.trim();
    if (trimmed.isEmpty) return;
    try {
      final ticket = await apiClient.createTicket(competitionId, topic, trimmed);
      setState(() {
        _tickets = [ticket, ..._tickets];
        _activeId = ticket.id;
        _showDetail = true;
        _newSummaryCtrl.clear();
        _newTopic = 'Pendaftaran';
      });
      await _loadMessages(ticket.id);
    } catch (_) {
      // ignore error for now
    }
  }
}

enum _EntryType { date, message }

class _MessageEntry {
  _MessageEntry.date(this.label)
      : type = _EntryType.date,
        message = null;
  _MessageEntry.message(this.message)
      : type = _EntryType.message,
        label = null;

  final _EntryType type;
  final String? label;
  final ChatMessageData? message;
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
              child: Text(
                  'Tempatkan pengumuman, jadwal kompetisi, atau FAQ di sini.'),
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
            _GlassCard(
                child: Text(
                    'Daftar kanal bantuan (email, WhatsApp, knowledge base) akan ditempatkan di sini.')),
          ],
        ),
      ),
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late Future<ProfileData> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = apiClient.fetchProfile();
  }

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].isNotEmpty ? parts[0][0] : '') +
        (parts[1].isNotEmpty ? parts[1][0] : '');
  }

  String _fmtDate(String raw) {
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return "${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}";
  }

  Widget _infoRow(String label, String value, {bool isDate = false}) {
    final shown = isDate ? _fmtDate(value) : (value.isEmpty ? '-' : value);
    return _ProfileRow(label: label, value: shown);
  }

  @override
  Widget build(BuildContext context) {
    return _GradientBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FutureBuilder<ProfileData>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Gagal memuat profil: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }
              final profile = snapshot.data!;
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
                                  colors: [
                                    Color(0xFF1E88E5),
                                    Color(0xFF6CC5FF)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x331E88E5),
                                      blurRadius: 16,
                                      offset: Offset(0, 10)),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _initials(profile.name),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                                profile.name.isEmpty
                                    ? 'Pengguna'
                                    : profile.name,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(profile.email,
                                style:
                                    const TextStyle(color: Color(0xFF526380))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _GlassCard(
                        child: Column(
                          children: [
                            _infoRow('Nomor telepon', profile.whatsapp),
                            const Divider(height: 20, color: Color(0xFFE0E8F5)),
                            _infoRow('Tanggal lahir', profile.tanggalLahir,
                                isDate: true),
                            const Divider(height: 20, color: Color(0xFFE0E8F5)),
                            _infoRow('Jenis kelamin', profile.jenisKelamin),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _GlassCard(
                        child: Column(
                          children: [
                            _infoRow('Agama', profile.agama),
                            const Divider(height: 20, color: Color(0xFFE0E8F5)),
                            _infoRow('Level', profile.levelName),
                            const Divider(height: 20, color: Color(0xFFE0E8F5)),
                            _infoRow('Kelas', profile.kelasName),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _GlassCard(
                        child: Column(
                          children: [
                            _infoRow('Provinsi', profile.provinsiName),
                            const Divider(height: 20, color: Color(0xFFE0E8F5)),
                            _infoRow('Kabupaten', profile.kabupatenName),
                            const Divider(height: 20, color: Color(0xFFE0E8F5)),
                            _infoRow('Kecamatan', profile.kecamatanName),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _GlassCard(
                        child: Column(
                          children: [
                            _infoRow('Sekolah/Institusi', profile.namaSekolah),
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: widget.onLogout,
                      ),
                    ],
                  ),
                ),
              );
            },
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
          child: const Text('POSI',
              style: TextStyle(
                  color: Color(0xFF1E88E5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3)),
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
            child: Text(title.isNotEmpty ? title[0] : '?',
                style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF9AB3D7), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
              onPressed: () {}, icon: const Icon(Icons.videocam_outlined)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
        ],
      ),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  const _ChatListItem({required this.ticket, required this.onTap, this.unread = false});

  final TicketData ticket;
  final VoidCallback onTap;
  final bool unread;

  DateTime? _parseTsLocalInline(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    return dt.isUtc ? dt.toLocal() : dt;
  }

  @override
  Widget build(BuildContext context) {
    String timeText = '';
    if (ticket.lastMessageAt != null) {
      final t = _parseTsLocalInline(ticket.lastMessageAt);
      if (t != null) {
        timeText =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      }
    }
    return ListTile(
      onTap: onTap,
      leading: const CircleAvatar(
        radius: 22,
        backgroundColor: Color(0xFFE3F2FF),
        child: Icon(Icons.chat_bubble_outline, color: Color(0xFF1A2F4D)),
      ),
      title: Text(
        _titleWithCompetition(ticket.topic, ticket.competitionTitle),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontWeight: FontWeight.w700, color: Color(0xFF0A1F3F)),
      ),
      subtitle: Text(
        ticket.lastMessage?.isNotEmpty == true
            ? ticket.lastMessage!
            : (ticket.summary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: const Color(0xFF526380),
            fontWeight: unread ? FontWeight.w700 : FontWeight.w400),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeText,
              style: const TextStyle(color: Color(0xFF526380), fontSize: 12)),
          const SizedBox(height: 6),
          unread
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E88E5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Baru',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                )
              : Text(
                  ticket.status,
                  style: const TextStyle(
                      color: Color(0xFF1E88E5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
        ],
      ),
    );
  }

  String _titleWithCompetition(String topic, String competition) {
    if (competition.isEmpty) return topic;
    const maxLen = 32;
    String comp = competition;
    if (comp.length > maxLen) comp = '${comp.substring(0, maxLen - 3)}...';
    return '$topic • $comp';
  }
}

class _UserInfoCard extends StatelessWidget {
  const _UserInfoCard({required this.profile, required this.ticket});

  final ProfileData profile;
  final TicketData ticket;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4E4FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF1E88E5),
                child: Text(
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF143155))),
                    const SizedBox(height: 2),
                    Text(profile.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF526380))),
                    if (profile.whatsapp.isNotEmpty)
                      Text(profile.whatsapp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF526380))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.competitionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFF143155)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  ticket.status,
                  style: const TextStyle(
                      color: Color(0xFF1E88E5), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Perihal: ${ticket.topic}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF526380)),
          ),
        ],
      ),
    );
  }
}

class _GoogleLoginButton extends StatelessWidget {
  const _GoogleLoginButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          side: const BorderSide(color: Color(0xFF1E88E5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    required this.initialCompetitionId,
  });

  final void Function(String topic, int? competitionId, String summary) onCreate;
  final String initialTopic;
  final int? initialCompetitionId;

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  late String _topic;
  int? _competitionId;
  final _summaryCtrl = TextEditingController();
  bool _loadingCompetitions = true;
  String? _competitionError;
  List<CompetitionOption> _competitions = [];

  @override
  void initState() {
    super.initState();
    _topic = widget.initialTopic;
    _competitionId = widget.initialCompetitionId;
    _loadCompetitions();
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCompetitions() async {
    try {
      final list = await apiClient.fetchCompetitions();
      setState(() {
        _competitions = list;
        _competitionId ??= list.isNotEmpty ? list.first.id : null;
        _competitionError = null;
      });
    } catch (_) {
      setState(() {
        _competitions = [];
        _competitionId = null;
        _competitionError = 'Daftar kompetisi tidak dapat dimuat (opsional).';
      });
    } finally {
      if (mounted) setState(() => _loadingCompetitions = false);
    }
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
        title: const Text('Chat Admin',
            style: TextStyle(color: Color(0xFF1E2F45))),
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
                  const Text('Nama kompetisi',
                      style: TextStyle(color: Color(0xFF1A2F4D))),
                  const SizedBox(height: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFD4E4FF)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        value: _competitionId,
                        hint: const Text('Tanpa kompetisi (opsional)'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Tanpa kompetisi'),
                          ),
                          ..._competitions.map((c) => DropdownMenuItem<int?>(
                                value: c.id,
                                child: Text(
                                  c.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                        ],
                        onChanged: _loadingCompetitions
                            ? null
                            : (v) => setState(() => _competitionId = v),
                      ),
                    ),
                  ),
                  if (_competitionError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _competitionError!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  if (_loadingCompetitions)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  const SizedBox(height: 12),
                  const Text('Perihal',
                      style: TextStyle(color: Color(0xFF1A2F4D))),
                  const SizedBox(height: 6),
                  _SelectBox(
                    value: _topic,
                    items: const ['Pendaftaran', 'Pemesanan', 'Lainnya'],
                    onChanged: (v) =>
                        setState(() => _topic = v ?? 'Pendaftaran'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Ringkasan masalah',
                      style: TextStyle(color: Color(0xFF1A2F4D))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _summaryCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFFF8FBFF),
                      hintText:
                          'Tuliskan singkat masalah yang ingin ditanyakan',
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
                          widget.onCreate(
                              _topic, _competitionId, _summaryCtrl.text.trim());
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(140, 44),
                          backgroundColor: const Color(0xFF1E88E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
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
  const _SelectBox(
      {required this.value, required this.items, required this.onChanged});

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue =
        items.contains(value) ? value : (items.isNotEmpty ? items.first : null);
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
            .map((e) => DropdownMenuItem(
                value: e,
                child:
                    Text(e, style: const TextStyle(color: Color(0xFF1A2F4D)))))
            .toList(),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.accent});

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
            BoxShadow(
                color: Color(0x141E88E5), blurRadius: 12, offset: Offset(0, 8)),
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
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF143155))),
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
        Text(label,
            style: const TextStyle(
                color: Color(0xFF1A2F4D), fontWeight: FontWeight.w600)),
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
            Text(value,
                style: const TextStyle(
                    color: Color(0xFF143155), fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}




