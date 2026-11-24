import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';


import 'package:permission_handler/permission_handler.dart';

const String ludoBaseUrl = 'https://firestore' + '.' + 'googleapis' + '.' + 'com/v1/projects/dostchat-e903a/databases/(default)/documents';

class LudoGamePage extends StatefulWidget {
  final String room, myId, friendName;
  const LudoGamePage({super.key, required this.room, required this.myId, required this.friendName});
  @override
  State<LudoGamePage> createState() => _LudoGamePageState();
}

class _LudoGamePageState extends State<LudoGamePage> {
  List<int> myTokens = [-1, -1, -1, -1];
  List<int> friendTokens = [-1, -1, -1, -1];
  int dice = 1;
  bool myTurn = true;
  bool hasRolled = false;
  String statusMsg = 'आपकी बारी! Dice दबाएं';
  Timer? pollTimer;
  WebViewController? _voiceWeb;
bool micMuted = false;
  

  

  static const List<List<int>> mainPath = [
    [13,6],[12,6],[11,6],[10,6],[9,6],
    [8,5],[8,4],[8,3],[8,2],[8,1],[8,0],
    [7,0],[6,0],
    [6,1],[6,2],[6,3],[6,4],[6,5],
    [5,6],[4,6],[3,6],[2,6],[1,6],[0,6],
    [0,7],[0,8],
    [1,8],[2,8],[3,8],[4,8],[5,8],
    [6,9],[6,10],[6,11],[6,12],[6,13],[6,14],
    [7,14],[8,14],
    [8,13],[8,12],[8,11],[8,10],[8,9],
    [9,8],[10,8],[11,8],[12,8],[13,8],[14,8],
    [14,7],[14,6],
  ];

  static const List<List<int>> greenHomePath = [
    [13,7],[12,7],[11,7],[10,7],[9,7],[8,7],
  ];
  static const List<List<int>> redHomePath = [
    [1,7],[2,7],[3,7],[4,7],[5,7],[6,7],
  ];
  static const Set<int> safeSquares = {0, 8, 13, 21, 26, 34, 39, 47};
    @override
  void initState() {
    super.initState();
    _syncState(initial: true);
   _initVoiceRoom();
    
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _syncState());
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    
    super.dispose();
  }
    Future<void> _initVoiceRoom() async {
    await [Permission.microphone].request();
    final safeRoom = 'ludo_' + widget.room.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final parts = widget.room.split('_');
    final id1 = parts.length > 1 ? parts.elementAt(1) : widget.myId;
    final id2 = parts.length > 2 ? parts.elementAt(2) : widget.myId;
      
    final cleanMy = widget.myId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanFriend = (widget.myId.contains(id1) ? id2 : id1).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final url = 'https://vdo' + '.' + 'ninja/?room=' + safeRoom +
        '&push=' + safeRoom + '_' + cleanMy +
        '&view=' + safeRoom + '_' + cleanFriend +
        '&novideo&autostart&cleanoutput';
    final ctrl = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..loadRequest(Uri.parse(url));
    if (ctrl.platform is AndroidWebViewController) {
      final ac = ctrl.platform as AndroidWebViewController;
      await ac.setMediaPlaybackRequiresUserGesture(false);
      await ac.setOnPlatformPermissionRequest((r) => r.grant());
    }
    if (mounted) setState(() => _voiceWeb = ctrl);
    }
  
  
  Future<void> _syncState({bool initial = false}) async {
    try {
      final url = Uri.parse(ludoBaseUrl + '/ludo4_' + widget.room + '/state');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final f = json.decode(res.body)['fields'];
        if (f != null && mounted) {
          final lastBy = f['lastBy']?['stringValue'] ?? '';
          final p1 = (f['p1']?['stringValue'] ?? '-1,-1,-1,-1').split(',').map((e) => int.tryParse(e) ?? -1).toList();
          final p2 = (f['p2']?['stringValue'] ?? '-1,-1,-1,-1').split(',').map((e) => int.tryParse(e) ?? -1).toList();
          final d = int.tryParse(f['dice']?['integerValue'] ?? '1') ?? 1;
          final turnId = f['turn']?['stringValue'] ?? '';
          final ownerId = f['owner']?['stringValue'] ?? '';
          setState(() {
            if (ownerId == widget.myId) {
              myTokens = p1.length == 4 ? p1 : [-1, -1, -1, -1];
              friendTokens = p2.length == 4 ? p2 : [-1, -1, -1, -1];
            } else {
              myTokens = p2.length == 4 ? p2 : [-1, -1, -1, -1];
              friendTokens = p1.length == 4 ? p1 : [-1, -1, -1, -1];
            }
            dice = d;
            if (lastBy != widget.myId) {
              myTurn = (turnId == widget.myId || turnId.isEmpty);
              hasRolled = false;
              statusMsg = myTurn ? 'आपकी बारी! Dice दबाएं' : widget.friendName + ' की बारी...';
            }
          });
        }
      } else if (initial) {
        await _pushState(widget.myId, isOwnerInit: true);
      }
    } catch (_) {}
  }

  Future<void> _pushState(String nextTurnId, {bool isOwnerInit = false}) async {
    try {
      final url = Uri.parse(ludoBaseUrl + '/ludo4_' + widget.room + '/state');
      final res = await http.get(url);
      String ownerId = widget.myId;
      if (!isOwnerInit && res.statusCode == 200) {
        ownerId = json.decode(res.body)['fields']?['owner']?['stringValue'] ?? widget.myId;
      }
      final p1Str = (ownerId == widget.myId ? myTokens : friendTokens).join(',');
      final p2Str = (ownerId == widget.myId ? friendTokens : myTokens).join(',');
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fields': {
            'owner': {'stringValue': ownerId},
            'p1': {'stringValue': p1Str},
            'p2': {'stringValue': p2Str},
            'dice': {'integerValue': dice.toString()},
            'turn': {'stringValue': nextTurnId},
            'lastBy': {'stringValue': widget.myId},
          }
        }),
      );
    } catch (_) {}
  }

  void _rollDice() {
    if (!myTurn || hasRolled) return;
    final rolled = Random().nextInt(6) + 1;
    bool canMoveAny = false;
    for (int t in myTokens) {
      if (t == -1 && rolled == 6) canMoveAny = true;
      if (t >= 0 && t + rolled <= 56) canMoveAny = true;
    }
    setState(() {
      dice = rolled;
      if (!canMoveAny) {
        myTurn = false;
        hasRolled = false;
        statusMsg = 'Dice ' + rolled.toString() + ' आया, कोई चाल नहीं! दोस्त की बारी';
        _pushState('FRIEND');
      } else {
        hasRolled = true;
        statusMsg = 'Dice ' + rolled.toString() + ' आया! अपनी हरी गोटी पर टैप करें';
      }
    });
  }

  void _moveToken(int idx) {
    if (!myTurn || !hasRolled) return;
    int pos = myTokens[idx];
    if (pos == -1) {
      if (dice != 6) return;
      pos = 0;
    } else if (pos + dice <= 56) {
      pos += dice;
    } else {
      return;
    }
    bool captured = false;
    if (pos >= 0 && pos <= 50) {
      int myGlobal = pos % 52;
      if (!safeSquares.contains(myGlobal)) {
        for (int i = 0; i < 4; i++) {
          int fPos = friendTokens[i];
          if (fPos >= 0 && fPos <= 50 && ((fPos + 26) % 52) == myGlobal) {
            friendTokens[i] = -1;
            captured = true;
          }
        }
      }
    }
    bool extraTurn = (dice == 6 || captured || pos == 56);
    setState(() {
      myTokens[idx] = pos;
      hasRolled = false;
      myTurn = extraTurn;
      statusMsg = extraTurn ? 'वाह! एक और चाल मिली, Dice दबाएं' : widget.friendName + ' की बारी...';
    });
    _pushState(extraTurn ? widget.myId : 'FRIEND');
  }
    
  Color _getCellColor(int r, int c) {
    if (r < 6 && c < 6) return Colors.red.shade600;
    if (r < 6 && c > 8) return Colors.blue.shade600;
    if (r > 8 && c < 6) return Colors.green.shade600;
    if (r > 8 && c > 8) return Colors.amber.shade600;
    if (r >= 6 && r <= 8 && c >= 6 && c <= 8) return Colors.deepPurple.shade400;
    if (r == 7 && c >= 1 && c <= 5) return Colors.red.shade300;
    if (c == 7 && r >= 1 && r <= 5) return Colors.blue.shade300;
    if (c == 7 && r >= 9 && r <= 13) return Colors.green.shade300;
    if (r == 7 && c >= 9 && c <= 13) return Colors.amber.shade300;
    if (r == 6 && c == 1) return Colors.red.shade400;
    if (r == 1 && c == 8) return Colors.blue.shade400;
    if (r == 13 && c == 6) return Colors.green.shade400;
    if (r == 8 && c == 13) return Colors.amber.shade400;
    return Colors.white;
  }

  int _gRow(int p) => p <= 50 ? mainPath[p % 52][0] : greenHomePath[p - 51][0];
  int _gCol(int p) => p <= 50 ? mainPath[p % 52][1] : greenHomePath[p - 51][1];
  int _rRow(int p) => p <= 50 ? mainPath[(p + 26) % 52][0] : redHomePath[p - 51][0];
  int _rCol(int p) => p <= 50 ? mainPath[(p + 26) % 52][1] : redHomePath[p - 51][1];

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.of(context).size.width - 24;
    final double cell = (w - 4) / 15;
    int myHome = myTokens.where((e) => e == 56).length;
    int fHome = friendTokens.where((e) => e == 56).length;

    return Scaffold(
      backgroundColor: const Color(0xFF144D29),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D381D),
        foregroundColor: Colors.white,
        title: Text('🎲 Ludo vs ' + widget.friendName, style: const TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
                              Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('🟢 आप (' + myHome.toString() + '/4)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: micMuted ? Colors.red : Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                  onPressed: () {
                    setState(() => micMuted = !micMuted);
                    _voiceWeb?.runJavaScript("document.querySelectorAll('audio,video').forEach(e=>e.muted=" + micMuted.toString() + ");");
                  },
                  icon: Icon(micMuted ? Icons.mic_off : Icons.mic, size: 16),
                  label: Text(micMuted ? 'Muted' : 'Mic On', style: const TextStyle(fontSize: 12)),
                ),
                Text('🔴 दोस्त (' + fHome.toString() + '/4)', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                if (_voiceWeb != null) SizedBox(width: 1, height: 1, child: WebViewWidget(controller: _voiceWeb!)),
              ],
            ),
          ),
          
          
          const SizedBox(height: 10),
          Container(
            width: w,
            height: w,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black, width: 2)),
            child: Column(
              children: List.generate(15, (r) {
                return Row(
                  children: List.generate(15, (c) {
                    int gHome = (r == 10 && c == 1) ? 0 : (r == 10 && c == 4) ? 1 : (r == 13 && c == 1) ? 2 : (r == 13 && c == 4) ? 3 : -1;
                    int rHome = (r == 1 && c == 1) ? 0 : (r == 1 && c == 4) ? 1 : (r == 4 && c == 1) ? 2 : (r == 4 && c == 4) ? 3 : -1;
                    int activeG = -1;
                    for (int i = 0; i < 4; i++) {
                      if (myTokens[i] >= 0 && myTokens[i] <= 56 && _gRow(myTokens[i]) == r && _gCol(myTokens[i]) == c) activeG = i;
                    }
                    bool activeR = false;
                    for (int i = 0; i < 4; i++) {
                      if (friendTokens[i] >= 0 && friendTokens[i] <= 56 && _rRow(friendTokens[i]) == r && _rCol(friendTokens[i]) == c) activeR = true;
                    }
                    return GestureDetector(
                      onTap: () {
                        if (gHome != -1 && myTokens[gHome] == -1) _moveToken(gHome);
                        if (activeG != -1) _moveToken(activeG);
                      },
                      child: Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: _getCellColor(r, c),
                          border: Border.all(color: Colors.black12, width: 0.3),
                        ),
                        child: Center(
                          child: activeG != -1
                              ? CircleAvatar(radius: cell * 0.35, backgroundColor: Colors.green.shade900)
                              : activeR
                                  ? CircleAvatar(radius: cell * 0.35, backgroundColor: Colors.red.shade900)
                                  : gHome != -1
                                      ? CircleAvatar(radius: cell * 0.35, backgroundColor: Colors.white, child: myTokens[gHome] == -1 ? CircleAvatar(radius: cell * 0.22, backgroundColor: Colors.green.shade800) : null)
                                      : rHome != -1
                                                                    ? CircleAvatar(radius: cell * 0.35, backgroundColor: Colors.white, child: friendTokens[rHome] == -1 ? CircleAvatar(radius: cell * 0.22, backgroundColor: Colors.red.shade800) : null)
                                          : null,
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                Text(statusMsg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
                  onPressed: _rollDice,
                  icon: const Icon(Icons.casino, size: 28),
                  label: Text('Dice: ' + dice.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
