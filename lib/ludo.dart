import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
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

  RTCPeerConnection? _voicePc;
  MediaStream? _voiceStream;
  bool voiceMuted = false;
  bool voiceConnected = false;
  final Set<String> _voiceIceSet = {};

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
    _startLudoVoice();
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _syncState());
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    _stopLudoVoice();
    super.dispose();
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
    Future<void> _startLudoVoice() async {
    try {
      await [Permission.microphone].request();
      _voiceStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      _voicePc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun' + '.' + 'l' + '.' + 'google' + '.' + 'com:19302'},
        ]
      });
      _voiceStream!.getTracks().forEach((t) => _voicePc!.addTrack(t, _voiceStream!));
      _voicePc!.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected && mounted) {
          setState(() => voiceConnected = true);
        }
      };
      _voicePc!.onIceCandidate = (c) async {
        if (c.candidate != null) {
          http.post(Uri.parse(ludoBaseUrl + '/lv_ice_' + widget.room), headers: {'Content-Type': 'application/json'}, body: json.encode({'fields': {'from': {'stringValue': widget.myId}, 'data': {'stringValue': json.encode(c.toMap())}}}));
        }
      };
      final vUrl = Uri.parse(ludoBaseUrl + '/lv_' + widget.room + '/sig');
      final res = await http.get(vUrl);
      if (res.statusCode == 200 && json.decode(res.body)['fields']?['offer'] != null && json.decode(res.body)['fields']?['from']?['stringValue'] != widget.myId && json.decode(res.body)['fields']?['answer'] == null) {
        final f = json.decode(res.body)['fields'];
        final off = json.decode(f['offer']['stringValue']);
        await _voicePc!.setRemoteDescription(RTCSessionDescription(off['sdp'], off['type']));
        final ans = await _voicePc!.createAnswer();
        await _voicePc!.setLocalDescription(ans);
        await http.patch(vUrl, headers: {'Content-Type': 'application/json'}, body: json.encode({'fields': {'from': {'stringValue': f['from']['stringValue']}, 'offer': {'stringValue': f['offer']['stringValue']}, 'answer': {'stringValue': json.encode(ans.toMap())}}}));
      } else {
        final off = await _voicePc!.createOffer();
        await _voicePc!.setLocalDescription(off);
        await http.patch(vUrl, headers: {'Content-Type': 'application/json'}, body: json.encode({'fields': {'from': {'stringValue': widget.myId}, 'offer': {'stringValue': json.encode(off.toMap())}}}));
      }
      Timer.periodic(const Duration(seconds: 2), (t) async {
        if (!mounted || _voicePc == null) { t.cancel(); return; }
        try {
          final r = await http.get(vUrl);
          if (r.statusCode == 200) {
            final f = json.decode(r.body)['fields'];
            if (f != null && f['answer'] != null && f['from']?['stringValue'] == widget.myId && await _voicePc!.getRemoteDescription() == null) {
              final ans = json.decode(f['answer']['stringValue']);
              await _voicePc!.setRemoteDescription(RTCSessionDescription(ans['sdp'], ans['type']));
            }
          }
          final ir = await http.get(Uri.parse(ludoBaseUrl + '/lv_ice_' + widget.room));
          if (ir.statusCode == 200 && await _voicePc!.getRemoteDescription() != null) {
            for (var d in (json.decode(ir.body)['documents'] as List? ?? [])) {
              if (!_voiceIceSet.contains(d['name']) && d['fields']?['from']?['stringValue'] != widget.myId) {
                _voiceIceSet.add(d['name']);
                final cm = json.decode(d['fields']['data']['stringValue']);
                await _voicePc!.addCandidate(RTCIceCandidate(cm['candidate'].toString(), cm['sdpMid']?.toString() ?? '0', int.tryParse(cm['sdpMLineIndex'].toString()) ?? 0));
                http.delete(Uri.parse('https://firestore' + '.' + 'googleapis' + '.' + 'com/v1/' + d['name'].toString()));
              }
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _stopLudoVoice() async {
    try { await http.delete(Uri.parse(ludoBaseUrl + '/lv_' + widget.room + '/sig')); } catch (_) {}
    _voiceStream?.getTracks().forEach((t) => t.stop());
    await _voicePc?.close();
    _voicePc = null;
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🟢 आप (' + myHome.toString() + '/4)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(voiceConnected ? '🔊 Live Voice Connected' : '🎙️ Voice Room Active', style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: voiceMuted ? Colors.red : Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                  onPressed: () {
                    setState(() => voiceMuted = !voiceMuted);
                    _voiceStream?.getAudioTracks().forEach((t) => t.enabled = !voiceMuted);
                  },
                  icon: Icon(voiceMuted ? Icons.mic_off : Icons.mic, size: 18),
                  label: Text(voiceMuted ? 'Muted' : 'Mic On', style: const TextStyle(fontSize: 12)),
                ),
                Text('🔴 ' + widget.friendName + ' (' + fHome.toString() + '/4)', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
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
