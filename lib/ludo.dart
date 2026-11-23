import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String ludoBaseUrl = 'https://firestore' + '.' + 'googleapis' + '.' + 'com/v1/projects/dostchat-e903a/databases/(default)/documents';

class LudoGamePage extends StatefulWidget {
  final String room, myId, friendName;
  const LudoGamePage({super.key, required this.room, required this.myId, required this.friendName});
  @override
  State<LudoGamePage> createState() => _LudoGamePageState();
}

class _LudoGamePageState extends State<LudoGamePage> {
  List<int> myTokens = List.of({-1, -1, -1, -1});
  List<int> friendTokens = List.of({-1, -1, -1, -1});
  int dice = 1;
  bool canMove = false;
  String statusMsg = 'पासा फेंकें (Roll Dice)!';
  Timer? syncTimer;
  final List<int> safeSpots = List.of({0, 8, 13, 21, 26, 34, 39, 47});

  // बिना किसी स्क्वायर ब्रैकेट के 57 खानों का पक्का लूडो रास्ता
  static const String _gRaw = '13,6;12,6;11,6;10,6;9,6;8,5;8,4;8,3;8,2;8,1;8,0;7,0;6,0;6,1;6,2;6,3;6,4;6,5;5,6;4,6;3,6;2,6;1,6;0,6;0,7;0,8;1,8;2,8;3,8;4,8;5,8;6,9;6,10;6,11;6,12;6,13;6,14;7,14;8,14;8,13;8,12;8,11;8,10;8,9;9,8;10,8;11,8;12,8;13,8;14,8;14,7;13,7;12,7;11,7;10,7;9,7;8,7';
  static const String _rRaw = '6,1;6,2;6,3;6,4;6,5;5,6;4,6;3,6;2,6;1,6;0,6;0,7;0,8;1,8;2,8;3,8;4,8;5,8;6,9;6,10;6,11;6,12;6,13;6,14;7,14;8,14;8,13;8,12;8,11;8,10;8,9;9,8;10,8;11,8;12,8;13,8;14,8;14,7;14,6;13,6;12,6;11,6;10,6;9,6;8,5;8,4;8,3;8,2;8,1;8,0;7,0;7,1;7,2;7,3;7,4;7,5;7,6';

  int _gRow(int p) => int.parse(_gRaw.split(';')[p].split(',')[0]);
  int _gCol(int p) => int.parse(_gRaw.split(';')[p].split(',')[1]);
  int _rRow(int p) => int.parse(_rRaw.split(';')[p].split(',')[0]);
  int _rCol(int p) => int.parse(_rRaw.split(';')[p].split(',')[1]);
  
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
      final res = await http.get(Uri.parse(ludoBaseUrl + '/ludo4_' + widget.room + '/state'));
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
      final res = await http.get(Uri.parse(ludoBaseUrl + '/ludo4_' + widget.room + '/state'));
      Map<String, dynamic> fields = {};
      if (res.statusCode == 200) {
        fields = Map<String, dynamic>.from(json.decode(res.body)['fields'] ?? {});
      }
      fields[widget.myId] = {'stringValue': json.encode(myTokens)};
      final fKey = fields.keys.firstWhere((k) => k != widget.myId && k != 'dice', orElse: () => '');
      if (fKey.isNotEmpty) fields[fKey] = {'stringValue': json.encode(friendTokens)};
      fields['dice'] = {'integerValue': dice.toString()};

      await http.patch(
        Uri.parse(ludoBaseUrl + '/ludo4_' + widget.room + '/state'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fields': fields}),
      );
    } catch (_) {}
  }

  void _rollDice() {
    if (canMove) return;
    final rolled = (DateTime.now().millisecond % 6) + 1;
    bool valid = myTokens.any((p) => (p == -1 && rolled == 6) || (p >= 0 && p < 56 && (p + rolled) <= 56));
    setState(() {
      dice = rolled;
      canMove = valid;
      statusMsg = valid ? '🎲 ' + rolled.toString() + ' आया! हरी गोटी पर टैप करें' : '🎲 ' + rolled.toString() + ' आया — दोस्त की बारी!';
    });
    _pushState();
  }

  void _moveToken(int idx) {
    if (!canMove) return;
    int pos = myTokens[idx];
    if (pos == -1 && dice == 6) {
      myTokens[idx] = 0;
    } else if (pos >= 0 && pos < 56 && (pos + dice) <= 56) {
      myTokens[idx] = pos + dice;
    } else {
      return;
    }
    int newPos = myTokens[idx];
    bool bonus = (dice == 6 || newPos == 56);
    if (newPos >= 0 && newPos <= 50 && !safeSpots.contains(newPos)) {
      int mr = _gRow(newPos);
      int mc = _gCol(newPos);
      for (int i = 0; i < 4; i++) {
        int fp = friendTokens[i];
        if (fp >= 0 && fp <= 50 && _rRow(fp) == mr && _rCol(fp) == mc) {
          friendTokens[i] = -1;
          bonus = true;
          statusMsg = '💥 लाल गोटी काट दी! एक्स्ट्रा चाल!';
        }
      }
    }
    setState(() {
      canMove = false;
      if (!statusMsg.contains('काट')) statusMsg = bonus ? '🎉 एक्स्ट्रा चाल मिली! फिर से पासा फेंकें' : 'दोस्त की बारी';
    });
    _pushState();
  }

  Future<void> _resetGame() async {
    setState(() {
      myTokens = List.of({-1, -1, -1, -1});
      friendTokens = List.of({-1, -1, -1, -1});
      dice = 1;
      canMove = false;
      statusMsg = 'नया गेम शुरू! पासा फेंकें';
    });
    await http.delete(Uri.parse(ludoBaseUrl + '/ludo4_' + widget.room + '/state'));
  }
    Color _getCellColor(int r, int c) {
    if (r < 6 && c < 6) return Colors.red.shade600;
    if (r < 6 && c > 8) return Colors.blue.shade600;
    if (r > 8 && c < 6) return Colors.green.shade600;
    if (r > 8 && c > 8) return Colors.amber.shade500;
    if (r >= 6 && r <= 8 && c >= 6 && c <= 8) {
      if (r == 7 && c == 7) return Colors.deepPurple;
      if (r == 8 && c == 7) return Colors.green.shade600;
      if (r == 7 && c == 6) return Colors.red.shade600;
      if (r == 6 && c == 7) return Colors.blue.shade600;
      if (r == 7 && c == 8) return Colors.amber.shade500;
      return Colors.orange.shade200;
    }
    if ((c == 7 && r >= 9 && r <= 13) || (r == 13 && c == 6)) return Colors.green.shade400;
    if ((r == 7 && c >= 1 && c <= 5) || (r == 6 && c == 1)) return Colors.red.shade400;
    if ((c == 7 && r >= 1 && r <= 5) || (r == 1 && c == 8)) return Colors.blue.shade400;
    if ((r == 7 && c >= 9 && c <= 13) || (r == 8 && c == 13)) return Colors.amber.shade400;
    if ((r == 8 && c == 2) || (r == 2 && c == 6) || (r == 6 && c == 12) || (r == 12 && c == 8)) return Colors.grey.shade300;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final int myHome = myTokens.where((p) => p == 56).length;
    final int fHome = friendTokens.where((p) => p == 56).length;
    final bool won = myHome == 4 || fHome == 4;

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Text('Ludo: आप (🟢) vs ' + widget.friendName + ' (🔴)'),
        backgroundColor: const Color(0xFF00897B),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _resetGame)],
      ),
         body: SingleChildScrollView(
     child: Column(
       
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('🟢 आप अंदर: ' + myHome.toString() + '/4', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('🔴 दोस्त अंदर: ' + fHome.toString() + '/4', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
          if (won)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.amber,
              child: Text(myHome == 4 ? '🏆 बधाई हो! आप जीत गए!' : '👑 ' + widget.friendName + ' जीत गया!', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
            ),
                        Center(
            child: Builder(
              builder: (context) {
                final double boardSize = MediaQuery.of(context).size.width - 20;
                final double cellSize = boardSize / 15;
                return Container(
                  width: boardSize + 4,
                  height: boardSize + 4,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black, width: 2)),
                  child: Column(
                    children: List.generate(15, (r) {
                      return Row(
                        children: List.generate(15, (c) {
                          final cellColor = _getCellColor(r, c);
                          int greenHomeIdx = -1;
                          if (r == 10 && c == 1) greenHomeIdx = 0;
                          if (r == 10 && c == 4) greenHomeIdx = 1;
                          if (r == 13 && c == 1) greenHomeIdx = 2;
                          if (r == 13 && c == 4) greenHomeIdx = 3;

                          int redHomeIdx = -1;
                          if (r == 1 && c == 1) redHomeIdx = 0;
                          if (r == 1 && c == 4) redHomeIdx = 1;
                          if (r == 4 && c == 1) redHomeIdx = 2;
                          if (r == 4 && c == 4) redHomeIdx = 3;

                          int activeGreenIdx = -1;
                          for (int i = 0; i < 4; i++) {
                            int p = myTokens[i];
                            if (p >= 0 && p <= 56 && _gRow(p) == r && _gCol(p) == c) activeGreenIdx = i;
                          }

                          bool hasRedActive = false;
                          for (int i = 0; i < 4; i++) {
                            int p = friendTokens[i];
                            if (p >= 0 && p <= 56 && _rRow(p) == r && _rCol(p) == c) hasRedActive = true;
                          }

                          final bool isStar = (r == 8 && c == 2) || (r == 2 && c == 6) || (r == 6 && c == 12) || (r == 12 && c == 8) || (r == 13 && c == 6) || (r == 6 && c == 1) || (r == 1 && c == 8) || (r == 8 && c == 13);

                          return GestureDetector(
                            onTap: () {
                              if (greenHomeIdx != -1 && myTokens[greenHomeIdx] == -1) _moveToken(greenHomeIdx);
                              if (activeGreenIdx != -1) _moveToken(activeGreenIdx);
                            },
                            child: Container(
                              width: cellSize,
                              height: cellSize,
                              decoration: BoxDecoration(
                                color: cellColor,
                                border: (r < 6 && c < 6) || (r < 6 && c > 8) || (r > 8 && c < 6) || (r > 8 && c > 8)
                                    ? null
                                    : Border.all(color: Colors.black26, width: 0.4),
                              ),
                              child: Center(
                                child: activeGreenIdx != -1
                                    ? Container(width: cellSize * 0.75, height: cellSize * 0.75, decoration: BoxDecoration(color: Colors.green.shade800, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)))
                                    : hasRedActive
                                        ? Container(width: cellSize * 0.75, height: cellSize * 0.75, decoration: BoxDecoration(color: Colors.red.shade800, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)))
                                        : greenHomeIdx != -1
                                            ? Container(width: cellSize * 0.85, height: cellSize * 0.85, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: myTokens[greenHomeIdx] == -1 ? Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: Colors.green.shade700, shape: BoxShape.circle)) : null)
                                            : redHomeIdx != -1
                                                ? Container(width: cellSize * 0.85, height: cellSize * 0.85, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: friendTokens[redHomeIdx] == -1 ? Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: Colors.red.shade700, shape: BoxShape.circle)) : null)
                                                : (r == 7 && c == 7)
                                                    ? const Text('👑', style: TextStyle(fontSize: 10))
                                                    : isStar
                                                        ? const Icon(Icons.star_border, size: 11, color: Colors.black45)
                                                        : null,
                              ),
                            ),
                          );
                        }),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
          
    Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(statusMsg, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13))),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: won ? _resetGame : _rollDice,
                  icon: const Icon(Icons.casino, size: 26),
                  label: Text(won ? 'New Game' : 'Dice: ' + dice.toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
