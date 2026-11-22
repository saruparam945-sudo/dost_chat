import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCqb6i5QW_NVuzjVvAKrYUytC2IkHDLsE',
        appId: '1:793598560917:android:8f87daabf9c4cbbf41959c',
        messagingSenderId: '793598560917',
        projectId: 'dostchat-e903a',
      ),
    );
  } catch (e) {
    debugPrint('Firebase Init Error: $e');
  }
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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) return const HomeScreen();
          return const LoginScreen();
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      User? user = userCred.user;

      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': user.displayName ?? 'New Dost',
          'email': user.email ?? '',
          'photo': user.photoURL ?? '',
          'isOnline': true,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_rounded, size: 80, color: Color(0xFF00BFA5)),
            const SizedBox(height: 20),
            const Text('DostChat', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('नए दोस्त बनाएं, फ्री चैट और कॉल करें', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 40),
            _isLoading
                ? const CircularProgressIndicator(color: Color(0xFF00BFA5))
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('Continue with Google (Free)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _signInWithGoogle,
                  ),
          ],
        ),
      ),
    );
  }
}
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DostChat - नए दोस्त'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final users = snapshot.data!.docs.where((doc) => doc.id != currentUser.uid).toList();
          if (users.isEmpty) {
            return const Center(child: Text('अभी कोई दूसरा दोस्त ऑनलाइन नहीं है।', style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final data = users[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF00BFA5),
                  backgroundImage: (data['photo'] != null && data['photo'] != '') ? NetworkImage(data['photo']) : null,
                  child: (data['photo'] == null || data['photo'] == '') ? const Icon(Icons.person, color: Colors.black) : null,
                ),
                title: Text(data['name'] ?? 'Dost', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Online', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA5), foregroundColor: Colors.black),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ChatScreen(friendId: data['uid'], friendName: data['name'] ?? 'Dost')),
                  ),
                  child: const Text('Chat'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String friendId;
  final String friendName;
  const ChatScreen({super.key, required this.friendId, required this.friendName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final currentUser = FirebaseAuth.instance.currentUser!;
  List<Map<String, dynamic>> _localMessages = [];

  String get _chatRoomId {
    List<String> ids = [currentUser.uid, widget.friendId];
    ids.sort();
    return ids.join('_');
  }

  @override
  void initState() {
    super.initState();
    _loadLocalMessages();
    _listenAndDeleteFromServer();
  }

  Future<void> _loadLocalMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('chat_$_chatRoomId');
    if (saved != null) {
      setState(() => _localMessages = List<Map<String, dynamic>>.from(json.decode(saved)));
    }
  }

  Future<void> _saveMessageLocally(Map<String, dynamic> msg) async {
    final prefs = await SharedPreferences.getInstance();
    _localMessages.add(msg);
    await prefs.setString('chat_$_chatRoomId', json.encode(_localMessages));
    if (mounted) setState(() {});
  }

  void _listenAndDeleteFromServer() {
    FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatRoomId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) async {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        await _saveMessageLocally({'text': data['text'], 'senderId': data['senderId']});
        await doc.reference.delete();
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    await _saveMessageLocally({'text': text, 'senderId': currentUser.uid});
    await FirebaseFirestore.instance.collection('chats').doc(_chatRoomId).collection('messages').add({
      'text': text,
      'senderId': currentUser.uid,
      'receiverId': widget.friendId,
      'timestamp': FieldValue.serverTimestamp(),
    });
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
              itemCount: _localMessages.length,
              itemBuilder: (context, index) {
                final msg = _localMessages[index];
                final isMe = msg['senderId'] == currentUser.uid;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF00BFA5) : const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(msg['text'] ?? '', style: TextStyle(color: isMe ? Colors.black : Colors.white)),
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
                    controller: _msgController,
                    decoration: const InputDecoration(hintText: 'मैसेज लिखें...', border: InputBorder.none),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send, color: Color(0xFF00BFA5)), onPressed: _sendMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
