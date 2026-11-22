import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String ludoBaseUrl = 'https://googleapis.com';

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
  bool canMove = false;
  String statusMsg = 'पासा (Roll Dice) फेंकें!';
  Timer? syncTimer;
  final List<int> safeSpots = List.of({0, 8, 13, 21, 26, 34, 39, 47});

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
    bool valid = myTokens.any((p) => (p == -1 && rolled == 6) || (p >= 0 && p < 52 && (p + rolled) <= 52));
    setState(() {
      dice = rolled;
      canMove = valid;
      statusMsg = valid ? '🎲 ' + rolled.toString() + ' आया! गोटी चुनें' : '🎲 ' + rolled.toString() + ' आया — दोस्त की बारी!';
    });
    _pushState();
  }

  void _moveToken(int idx) {
    if (!canMove) return;
    int pos = myTokens[idx];
    if (pos == -1 && dice == 6) {
      myTokens[idx] = 0;
    } else if (pos >= 0 && pos < 52 && (pos + dice) <= 52) {
      myTokens[idx] = pos + dice;
    } else {
      return;
    }
    int newPos = myTokens[idx];
    bool bonus = (dice == 6 || newPos == 52);
    if (newPos > 0 && newPos < 52 && !safeSpots.contains(newPos)) {
      int enemyPos = (newPos + 26) % 52;
      for (int i = 0; i < 4; i++) {
        if (friendTokens[i] == enemyPos) {
          friendTokens[i] = -1;
          bonus = true;
          statusMsg = '💥 गोटी काट दी! एक्स्ट्रा चाल!';
        }
      }
    }
    setState(() {
      canMove = false;
      if (!statusMsg.contains('काट')) statusMsg = bonus ? '🎉 एक्स्ट्रा चाल मिली!' : 'दोस्त की बारी';
    });
    _pushState();
  }

  Future<void> _resetGame() async {
    setState(() {
      myTokens = [-1, -1, -1, -1];
      friendTokens = [-1, -1, -1, -1];
      dice = 1;
      canMove = false;
    });
    await http.delete(Uri.parse(ludoBaseUrl + '/ludo4_' + widget.room + '/state'));
  }

  @override
  Widget build(BuildContext context) {
    final int myHome = myTokens.where((p) => p == 52).length;
    final int fHome = friendTokens.where((p) => p == 52).length;
    final bool won = myHome == 4 || fHome == 4;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: Text('Ludo: आप vs ' + widget.friendName), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _resetGame)]),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            if (won)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Colors.amber.shade200, borderRadius: BorderRadius.circular(12)),
                child: Text(myHome == 4 ? '🏆 बधाई हो! आप जीत गए!' : '👑 ' + widget.friendName + ' जीत गया!', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('🟢 आप अंदर: ' + myHome.toString() + '/4', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      Text('🔴 दोस्त अंदर: ' + fHome.toString() + '/4', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(4, (i) {
                      final p = myTokens[i];
                      final ok = canMove && ((p == -1 && dice == 6) || (p >= 0 && p < 52 && (p + dice) <= 52));
                      return GestureDetector(
                        onTap: () => _moveToken(i),
                        child: Container(
                          width: 60,
                          height: 55,
                          decoration: BoxDecoration(color: ok ? Colors.green.shade100 : Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: ok ? Colors.green : Colors.grey)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(p == 52 ? Icons.emoji_events : Icons.circle, color: Colors.green, size: 20),
                              Text(p == -1 ? 'घर' : (p == 52 ? 'अंदर' : p.toString()), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                itemCount: 52,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 4, mainAxisSpacing: 4),
                itemBuilder: (_, idx) {
                  final safe = safeSpots.contains(idx);
                  final hasMy = myTokens.contains(idx);
                  final hasF = friendTokens.contains((idx + 26) % 52);
                  return Container(
                    decoration: BoxDecoration(color: safe ? Colors.amber.shade100 : Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(safe ? '⭐' : (idx + 1).toString(), style: const TextStyle(fontSize: 9, color: Colors.black45)),
                        if (hasMy) const Positioned(top: 2, left: 2, child: CircleAvatar(radius: 6, backgroundColor: Colors.green)),
                        if (hasF) const Positioned(bottom: 2, right: 2, child: CircleAvatar(radius: 6, backgroundColor: Colors.redAccent)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(statusMsg, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B))),
            const SizedBox(height: 6),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48)),
              onPressed: won ? _resetGame : _rollDice,
              icon: const Icon(Icons.casino),
              label: Text(won ? 'New Game' : 'पासा फेंकें (Dice: ' + dice.toString() + ')', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
