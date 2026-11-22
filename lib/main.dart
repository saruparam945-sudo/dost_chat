import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String projectId = 'dostchat-e903a';
const String baseUrl = 'https://googleapis.com';

void main() {
  runApp(const DostChatApp());
}

class DostChatApp extends StatelessWidget {
  const DostChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DostChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0E0E),
        primaryColor: const Color(0xFF00BFA5),
      ),
      home: const AuthCheckScreen(),
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  String? _userId;
  String? _userName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkSavedUser();
  }

  Future<void> _checkSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getString('userId');
      _userName = prefs.getString('userName');
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_userId != null && _userName != null) {
      return HomeScreen(myId: _userId!, myName: _userName!);
    }
    return const LoginScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _isSaving = false;

  Future<void> _joinNow() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final String uid = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final String name = _nameCtrl.text.trim();
    final String city = _cityCtrl.text.trim().isEmpty ? 'India' : _cityCtrl.text.trim();

    try {
      await http.patch(
        Uri.parse('$baseUrl/users/$uid'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fields': {
            'uid': {'stringValue': uid},
            'name': {'stringValue': name},
            'city': {'stringValue': city},
          }
        }),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', uid);
      await prefs.setString('userName', name);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(myId: uid, myName: name)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_rounded, size: 75, color: Color(0xFF00BFA5)),
            const SizedBox(height: 16),
            const Text('DostChat', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const Text('नए दोस्त बनाएं • लाइफटाइम फ्री चैट', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'अपना नाम लिखें',
                filled: true,
                fillColor: const Color(0xFF1F1F1F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityCtrl,
              decoration: InputDecoration(
                hintText: 'आपका शहर (जैसे: जयपुर, दिल्ली)',
                filled: true,
                fillColor: const Color(0xFF1F1F1F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            _isSaving
                ? const CircularProgressIndicator(color: Color(0xFF00BFA5))
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BFA5),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _joinNow,
                      child: const Text('Start Chatting (Free)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
class HomeScreen extends StatefulWidget {
  final String myId;
  final String myName;
  const HomeScreen({super.key, required this.myId, required this.myName});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, String>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/users'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = data['documents'] as List<dynamic>? ?? [];
        List<Map<String, String>> loaded = [];
        for (var doc in docs) {
          final fields = doc['fields'] ?? {};
          final uid = fields['uid']?['stringValue'] ?? '';
          if (uid.isNotEmpty && uid != widget.myId) {
            loaded.add({
              'uid': uid,
              'name': fields['name']?['stringValue'] ?? 'Dost',
              'city': fields['city']?['stringValue'] ?? 'India',
            });
          }
        }
        setState(() => _users = loaded);
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('DostChat (${widget.myName})'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchUsers),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00BFA5)))
          : _users.isEmpty
              ? const Center(child: Text('अभी कोई दूसरा दोस्त ऑनलाइन नहीं है।\nदूसरे फोन से भी नाम डालकर जुड़ें!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final u = _users[index];
                    return ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0xFF00BFA5), child: Icon(Icons.person, color: Colors.black)),
                      title: Text(u['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${u['city']} • Online', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA5), foregroundColor: Colors.black),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ChatScreen(myId: widget.myId, friendId: u['uid']!, friendName: u['name']!)),
                        ),
                        child: const Text('Chat'),
                      ),
                    );
                  },
                ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String myId;
  final String friendId;
  final String friendName;
  const ChatScreen({super.key, required this.myId, required this.friendId, required this.friendName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  List<Map<String, String>> _messages = [];
  Timer? _timer;

  String get _roomId {
    final ids = [widget.myId, widget.friendId]..sort();
    return ids.join('_');
  }

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _syncAndDelete());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_$_roomId');
    if (raw != null) {
      final list = json.decode(raw) as List;
      setState(() => _messages = list.map((e) => Map<String, String>.from(e)).toList());
    }
  }

  Future<void> _saveLocal(Map<String, String> msg) async {
    final prefs = await SharedPreferences.getInstance();
    _messages.add(msg);
    await prefs.setString('chat_$_roomId', json.encode(_messages));
    if (mounted) setState(() {});
  }

  Future<void> _syncAndDelete() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/chats_$_roomId'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final docs = data['documents'] as List<dynamic>? ?? [];
        for (var doc in docs) {
          final fields = doc['fields'] ?? {};
          final receiver = fields['receiverId']?['stringValue'] ?? '';
          if (receiver == widget.myId) {
            final text = fields['text']?['stringValue'] ?? '';
            final sender = fields['senderId']?['stringValue'] ?? '';
            await _saveLocal({'text': text, 'senderId': sender});
            final docName = doc['name'];
            await http.delete(Uri.parse('https://googleapis.com'));
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    await _saveLocal({'text': text, 'senderId': widget.myId});
    await http.post(
      Uri.parse('$baseUrl/chats_$_roomId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'fields': {
          'text': {'stringValue': text},
          'senderId': {'stringValue': widget.myId},
          'receiverId': {'stringValue': widget.friendId},
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.friendName), backgroundColor: const Color(0xFF1A1A1A)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isMe = m['senderId'] == widget.myId;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF00BFA5) : const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(m['text'] ?? '', style: TextStyle(color: isMe ? Colors.black : Colors.white)),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(hintText: 'मैसेज लिखें...', border: InputBorder.none),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send, color: Color(0xFF00BFA5)), onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
