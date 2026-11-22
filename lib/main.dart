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
// 🎲 असली 4-गोटी वाला लाइव 2-Player Ludo Game (0 सर्वर खर्च)
class LudoGamePage extends StatefulWidget {
  final String room, myId, friendName;
  const LudoGamePage({super.key, required this.room, required this.myId, required this.friendName});
  @override
  State<LudoGamePage> createState() => _LudoGamePageState();
}

class _LudoGamePageState extends State<LudoGamePage> {
  // -1 = घर में बंद, 0 से 51 = रास्ता, 52 = अंदर (Home/Won)
  List<int> myTokens = [-1, -1, -1, -1];
  List<int> friendTokens = [-1, -1, -1, -1];
  int dice = 1;
  bool canMove = false;
  String statusMsg = 'पासा (Roll Dice) फेंकें!';
  Timer? syncTimer;
  final List<int> safeSpots = List.of();

  @override
  void initState() {
    super.initState();
    _syncState();
    syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _syncState());
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncState() async {
    try {
      final res = await http.get(Uri.parse(baseUrl + '/ludo4_' + widget.room + '/state'));
      if (res.statusCode == 200) {
        final f = json.decode(res.body)['fields'];
        if (f != null && mounted) {
          setState(() {
            if (f[widget.myId] != null) {
              myTokens = (json.decode(f[widget.myId]['stringValue']) as List).map((e) => int.parse(e.toString())).toList();
            }
            final fKey = f.keys.firstWhere((k) => k != widget.myId && k != 'dice', orElse: () => '');
            if (fKey.isNotEmpty) {
              friendTokens = (json.decode(f[fKey]['stringValue']) as List).map((e) => int.parse(e.toString())).toList();
            }
            dice = int.tryParse(f['dice']?['integerValue'] ?? '1') ?? 1;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _pushState() async {
    try {
      final res = await http.get(Uri.parse(baseUrl + '/ludo4_' + widget.room + '/state'));
      Map<String, dynamic> fields = {};
      if (res.statusCode == 200) {
        fields = Map<String, dynamic>.from(json.decode(res.body)['fields'] ?? {});
      }
      fields[widget.myId] = {'stringValue': json.encode(myTokens)};
      final fKey = fields.keys.firstWhere((k) => k != widget.myId && k != 'dice', orElse: () => '');
      if (fKey.isNotEmpty) {
        fields[fKey] = {'stringValue': json.encode(friendTokens)};
      }
      fields['dice'] = {'integerValue': dice.toString()};

      await http.patch(
        Uri.parse(baseUrl + '/ludo4_' + widget.room + '/state'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fields': fields}),
      );
    } catch (_) {}
  }

  void _rollDice() {
    if (canMove) {
      setState(() => statusMsg = 'पहले अपनी गोटी पर टैप करके चाल चलें!');
      return;
    }
    final rolled = (DateTime.now().millisecond % 6) + 1;
    bool hasValidMove = false;
    for (int pos in myTokens) {
      if (pos == -1 && rolled == 6) hasValidMove = true;
      if (pos >= 0 && pos < 52 && (pos + rolled) <= 52) hasValidMove = true;
    }

    setState(() {
      dice = rolled;
      if (hasValidMove) {
        canMove = true;
        statusMsg = '🎲 ' + rolled.toString() + ' आया! चलने के लिए अपनी गोटी चुनें';
      } else {
        canMove = false;
        statusMsg = '🎲 ' + rolled.toString() + ' आया — कोई चाल नहीं, दोस्त की बारी!';
      }
    });
    _pushState();
  }

  void _moveToken(int idx) {
    if (!canMove) return;
    int pos = myTokens[idx];

    if (pos == -1) {
      if (dice != 6) return;
      myTokens[idx] = 0; // घर से बाहर निकली
    } else if (pos >= 0 && pos < 52 && (pos + dice) <= 52) {
      myTokens[idx] = pos + dice;
    } else {
      return;
    }

    int newPos = myTokens[idx];
    bool bonusTurn = (dice == 6 || newPos == 52);

    // दोस्त की गोटी काटने की जांच (Safe खानों को छोड़कर)
    if (newPos > 0 && newPos < 52 && !safeSpots.contains(newPos)) {
      int enemyRelPos = (newPos + 26) % 52;
      for (int i = 0; i < 4; i++) {
        if (friendTokens[i] == enemyRelPos) {
          friendTokens[i] = -1; // दोस्त की गोटी कटकर वापस घर!
          bonusTurn = true;
          statusMsg = '💥 आपने दोस्त की गोटी काट दी! एक्स्ट्रा चाल मिली!';
        }
      }
    }

    setState(() {
      canMove = false;
      if (newPos == 52) {
        statusMsg = '👑 आपकी गोटी अंदर (Home) पहुँच गई!';
      } else if (bonusTurn) {
        statusMsg = '🎉 एक्स्ट्रा चाल मिली! फिर से पासा फेंकें';
      } else {
        statusMsg = 'चाल चल दी गई — अब दोस्त की बारी';
      }
    });
    _pushState();
  }

  Future<void> _resetGame() async {
    setState(() {
      myTokens = [-1, -1, -1, -1];
      friendTokens = [-1, -1, -1, -1];
      dice = 1;
      canMove = false;
      statusMsg = 'नया गेम शुरू! पासा फेंकें';
    });
    await http.delete(Uri.parse(baseUrl + '/ludo4_' + widget.room + '/state'));
  }
  
  @override
  Widget build(BuildContext context) {
    final int myHomeCount = myTokens.where((p) => p == 52).length;
    final int friendHomeCount = friendTokens.where((p) => p == 52).length;
    final bool iWon = myHomeCount == 4;
    final bool friendWon = friendHomeCount == 4;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Ludo: आप vs ' + widget.friendName),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _resetGame)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            if (iWon || friendWon)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Colors.amber.shade200, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  iWon ? '🏆 बधाई हो! आपकी चारों गोटियाँ अंदर हो गईं — आप जीत गए!' : '👑 ' + widget.friendName + ' की चारों गोटियाँ अंदर — वह जीत गया!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            // आपकी 4 गोटियों का घर (चुनने और चलने के लिए)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.green.shade300)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('🟢 आपकी गोटियाँ (अंदर: ' + myHomeCount.toString() + '/4)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      Text('🔴 दोस्त अंदर: ' + friendHomeCount.toString() + '/4', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(4, (i) {
                      final p = myTokens[i];
                      final isMovable = canMove && ((p == -1 && dice == 6) || (p >= 0 && p < 52 && (p + dice) <= 52));
                      return GestureDetector(
                        onTap: () => _moveToken(i),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: p == 52 ? Colors.amber.shade100 : (isMovable ? Colors.green.shade100 : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isMovable ? Colors.green : Colors.grey.shade300, width: isMovable ? 2.5 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(p == 52 ? Icons.emoji_events : Icons.circle, color: p == 52 ? Colors.amber.shade800 : Colors.green, size: 24),
                              Text(
                                p == -1 ? 'घर में' : (p == 52 ? 'अंदर!' : p.toString() + '/52'),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 52 खानों का लाइव लूडो ट्रैक
            Expanded(
              child: GridView.builder(
                itemCount: 52,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 4, mainAxisSpacing: 4),
                itemBuilder: (_, idx) {
                  final bool isSafe = safeSpots.contains(idx);
                  final bool hasMy = myTokens.contains(idx);
                  final int enemyMapped = (idx + 26) % 52;
                  final bool hasFriend = friendTokens.contains(enemyMapped);

                  return Container(
                    decoration: BoxDecoration(
                      color: isSafe ? Colors.amber.shade100 : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(isSafe ? '⭐' : (idx + 1).toString(), style: const TextStyle(fontSize: 9, color: Colors.black45)),
                        if (hasMy) const Positioned(top: 2, left: 2, child: CircleAvatar(radius: 6, backgroundColor: Colors.green)),
                        if (hasFriend) const Positioned(bottom: 2, right: 2, child: CircleAvatar(radius: 6, backgroundColor: Colors.redAccent)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(statusMsg, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B), fontSize: 13)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: (iWon || friendWon) ? _resetGame : _rollDice,
              icon: const Icon(Icons.casino, size: 28),
              label: Text((iWon || friendWon) ? 'फिर से खेलें (New Game)' : 'पासा फेंकें (Dice: ' + dice.toString() + ')', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
              }
              
