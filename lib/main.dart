import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

const String baseUrl = 'https://googleapis.com';

void main() => runApp(const DostChatPro());

class DostChatPro extends StatelessWidget {
  const DostChatPro({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DostChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        primaryColor: const Color(0xFF00897B),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00897B),
          foregroundColor: Colors.white,
          elevation: 1,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? uid, name, city;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      setState(() {
        uid = p.getString('uid');
        name = p.getString('name');
        city = p.getString('city');
        loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF00897B))));
    return uid == null ? const LoginPage() : HomePage(myId: uid!, myName: name!, myCity: city ?? 'India');
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final nameCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  bool busy = false;

  Future<void> join() async {
    if (nameCtrl.text.trim().isEmpty) return;
    setState(() => busy = true);
    final id = 'u_${DateTime.now().millisecondsSinceEpoch}';
    final n = nameCtrl.text.trim();
    final c = cityCtrl.text.trim().isEmpty ? 'India' : cityCtrl.text.trim();
    try {
      await http.patch(
        Uri.parse('$baseUrl/users/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fields': {'uid': {'stringValue': id}, 'name': {'stringValue': n}, 'city': {'stringValue': c}}}),
      );
      final p = await SharedPreferences.getInstance();
      await p.setString('uid', id);
      await p.setString('name', n);
      await p.setString('city', c);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomePage(myId: id, myName: n, myCity: c)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.forum_rounded, size: 64, color: Color(0xFF00897B)),
              ),
              const SizedBox(height: 20),
              const Text('DostChat', style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('नए दोस्त बनाएं • फ्री कॉल और चैट करें', style: TextStyle(color: Colors.grey, fontSize: 15)),
              const SizedBox(height: 32),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'आपका शुभ नाम',
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF00897B)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cityCtrl,
                decoration: InputDecoration(
                  labelText: 'आपका शहर (जैसे: जयपुर, दिल्ली)',
                  prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF00897B)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 26),
              busy
                  ? const CircularProgressIndicator(color: Color(0xFF00897B))
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: join,
                      child: const Text('आगे बढ़ें (100% Free)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
class HomePage extends StatefulWidget {
  final String myId, myName, myCity;
  const HomePage({super.key, required this.myId, required this.myName, required this.myCity});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, String>> users = [];
  List<String> blockedIds = [];
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBlockedAndUsers();
  }

  Future<void> _loadBlockedAndUsers() async {
    final p = await SharedPreferences.getInstance();
    blockedIds = p.getStringList('blocked') ?? [];
    await loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/users'));
      if (res.statusCode == 200) {
        final docs = (json.decode(res.body)['documents'] as List?) ?? [];
        setState(() {
          users = docs
              .map((d) => d['fields'])
              .where((f) => f != null && f['uid']?['stringValue'] != widget.myId && !blockedIds.contains(f['uid']?['stringValue']))
              .map((f) => {
                    'uid': f['uid']['stringValue'].toString(),
                    'name': (f['name']?['stringValue'] ?? 'Dost').toString(),
                    'city': (f['city']?['stringValue'] ?? 'India').toString(),
                  })
              .toList();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filtered = users.where((u) => u['name']!.toLowerCase().contains(searchQuery.toLowerCase()) || u['city']!.toLowerCase().contains(searchQuery.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DostChat', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: loadUsers),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(widget.myName),
                content: Text('शहर: ${widget.myCity}\nID: ${widget.myId}'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ठीक है'))],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(
                hintText: 'नाम या शहर से नए दोस्त खोजें...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00897B)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
class HomePage extends StatefulWidget {
  final String myId, myName, myCity;
  const HomePage({super.key, required this.myId, required this.myName, required this.myCity});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, String>> users = [];
  List<String> blockedIds = [];
  String searchQuery = '';
  String? nextPageToken;
  bool isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadBlockedAndUsers();
  }

  Future<void> _loadBlockedAndUsers() async {
    final p = await SharedPreferences.getInstance();
    blockedIds = p.getStringList('blocked') ?? [];
    await loadUsers(reset: true);
  }

  // एक बार में केवल 20 यूज़र्स ही लाएगा (Pagination - 0 लिमिट बर्बादी)
  Future<void> loadUsers({bool reset = false}) async {
    if (isLoadingMore) return;
    setState(() => isLoadingMore = true);
    if (reset) {
      users.clear();
      nextPageToken = null;
    }
    try {
      String url = baseUrl + '/users?pageSize=20';
      if (nextPageToken != null && nextPageToken!.isNotEmpty) {
        url += '&pageToken=' + nextPageToken!;
      }
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final docs = (decoded['documents'] as List?) ?? [];
        nextPageToken = decoded['nextPageToken'];

        final newBatch = docs
            .map((d) => d['fields'])
            .where((f) => f != null && f['uid']?['stringValue'] != widget.myId && !blockedIds.contains(f['uid']?['stringValue']))
            .map((f) => {
                  'uid': f['uid']['stringValue'].toString(),
                  'name': (f['name']?['stringValue'] ?? 'Dost').toString(),
                  'city': (f['city']?['stringValue'] ?? 'India').toString(),
                })
            .toList();

        setState(() => users.addAll(newBatch));
      }
    } catch (_) {}
    setState(() => isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = users.where((u) => u['name']!.toLowerCase().contains(searchQuery.toLowerCase()) || u['city']!.toLowerCase().contains(searchQuery.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DostChat', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => loadUsers(reset: true)),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(widget.myName),
                content: Text('शहर: ' + widget.myCity + '\nID: ' + widget.myId),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ठीक है'))],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(
                hintText: 'नाम या शहर से नए दोस्त खोजें...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00897B)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty && !isLoadingMore
                ? const Center(child: Text('कोई नया दोस्त नहीं मिला।\nऊपर रिफ्रेश दबाएं या दूसरे फोन से जुड़ें!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length + (nextPageToken != null ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: isLoadingMore
                                ? const CircularProgressIndicator(color: Color(0xFF00897B))
                                : OutlinedButton.icon(
                                    onPressed: () => loadUsers(reset: false),
                                    icon: const Icon(Icons.expand_more, color: Color(0xFF00897B)),
                                    label: const Text('और नए दोस्त देखें (Load More)', style: TextStyle(color: Color(0xFF00897B))),
                                  ),
                          ),
                        );
                      }
                      final u = filtered[i];
                      return Card(
                        color: Colors.white,
                        elevation: 0.5,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE0F2F1),
                            child: Text(u['name']!.toUpperCase(), style: const TextStyle(color: Color(0xFF00897B), fontWeight: FontWeight.bold)),
                          ),
                          title: Text(u['name']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                          subtitle: Row(
                            children: [
                              const Icon(Icons.circle, size: 10, color: Colors.green),
                              const SizedBox(width: 5),
                              Text(u['city']! + ' • Online', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(myId: widget.myId, friendId: u['uid']!, friendName: u['name']!))).then((_) => _loadBlockedAndUsers()),
                            child: const Text('Chat / Call'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
              
class ChatPage extends StatefulWidget {
  final String myId, friendId, friendName;
  const ChatPage({super.key, required this.myId, required this.friendId, required this.friendName});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final msgCtrl = TextEditingController();
  List<Map<String, String>> msgs = [];
  Timer? timer;

  String get room => ([widget.myId, widget.friendId]..sort()).join('_');

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final raw = p.getString('c_' + room);
      if (raw != null) setState(() => msgs = (json.decode(raw) as List).map((e) => Map<String, String>.from(e)).toList());
    });
    timer = Timer.periodic(const Duration(seconds: 3), (_) => sync());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> save(Map<String, String> m) async {
    final p = await SharedPreferences.getInstance();
    msgs.add(m);
    await p.setString('c_' + room, json.encode(msgs));
    if (mounted) setState(() {});
  }

  Future<void> sync() async {
    try {
      final res = await http.get(Uri.parse(baseUrl + '/c_' + room));
      if (res.statusCode == 200) {
        for (var d in (json.decode(res.body)['documents'] as List? ?? [])) {
          final f = d['fields'];
          if (f != null && f['to']?['stringValue'] == widget.myId) {
            await save({'t': f['t']?['stringValue'] ?? '', 'img': f['img']?['stringValue'] ?? '', 's': f['s']['stringValue']});
            final docPath = d['name'].toString();
            await http.delete(Uri.parse('https://googleapis.com' + docPath));
          }
        }
      }
    } catch (_) {}
  }

  Future<void> send({String text = '', String imgBase64 = ''}) async {
    if (text.isEmpty && imgBase64.isEmpty) return;
    msgCtrl.clear();
    await save({'t': text, 'img': imgBase64, 's': widget.myId});
    await http.post(
      Uri.parse(baseUrl + '/c_' + room),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'fields': {
          't': {'stringValue': text},
          'img': {'stringValue': imgBase64},
          's': {'stringValue': widget.myId},
          'to': {'stringValue': widget.friendId},
        }
      }),
    );
  }

  Future<void> pickAndSendPhoto() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 35, maxWidth: 600);
    if (file != null) {
      final bytes = await file.readAsBytes();
      await send(text: '📷 Photo', imgBase64: base64Encode(bytes));
    }
  }

  Future<void> startFreeCall(bool isVideo) async {
    final callType = isVideo ? '📹 Video Call शुरू की है — जॉइन करने के लिए ऊपर Video बटन दबाएं!' : '📞 Audio Call शुरू की है — जॉइन करने के लिए ऊपर Call बटन दबाएं!';
    await send(text: callType);
    final suffix = isVideo ? '' : '#config.startWithVideoMuted=true';
    final url = Uri.parse('https://jit.si_' + room + suffix);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> blockUser() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('blocked') ?? [];
    list.add(widget.friendId);
    await p.setStringList('blocked', list);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        title: Text(widget.friendName),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: () => startFreeCall(false)),
          IconButton(icon: const Icon(Icons.videocam), onPressed: () => startFreeCall(true)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'block') blockUser();
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'block', child: Text('Block User'))],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                final me = m['s'] == widget.myId;
                final hasImg = (m['img'] ?? '').isNotEmpty;
                return Align(
                  alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 260),
                    decoration: BoxDecoration(
                      color: me ? const Color(0xFFDCF8C6) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasImg) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(m['img']!), fit: BoxFit.cover)),
                        if ((m['t'] ?? '').isNotEmpty) Padding(padding: EdgeInsets.only(top: hasImg ? 6 : 0), child: Text(m['t']!, style: const TextStyle(color: Colors.black87, fontSize: 15))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.photo_camera, color: Color(0xFF00897B)), onPressed: pickAndSendPhoto),
                Expanded(child: TextField(controller: msgCtrl, decoration: const InputDecoration(hintText: 'मैसेज लिखें...', border: InputBorder.none))),
                CircleAvatar(backgroundColor: const Color(0xFF00897B), child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: () => send(text: msgCtrl.text.trim()))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

