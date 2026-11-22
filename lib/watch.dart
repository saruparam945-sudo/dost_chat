import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String watchBaseUrl = 'https://firestore' + '.' + 'googleapis' + '.' + 'com/v1/projects/dostchat-e903a/databases/(default)/documents';

class WatchTogetherPage extends StatefulWidget {
  final String room, myId, friendName;
  const WatchTogetherPage({super.key, required this.room, required this.myId, required this.friendName});
  @override
  State<WatchTogetherPage> createState() => _WatchTogetherPageState();
}

class _WatchTogetherPageState extends State<WatchTogetherPage> {
  final urlCtrl = TextEditingController();
  String currentVideoId = '';
  String statusText = 'अभी कोई फिल्म नहीं चल रही है। नीचे YouTube लिंक डालें!';
  Timer? syncTimer;

  @override
  void initState() {
    super.initState();
    _syncVideo();
    syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _syncVideo());
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    super.dispose();
  }

  String _extractVideoId(String url) {
    if (url.contains('youtu.be/')) {
      return url.split('youtu.be/').last.split('?').first.split('&').first;
    }
    if (url.contains('v=')) {
      return url.split('v=').last.split('&').first;
    }
    if (url.contains('/shorts/')) {
      return url.split('/shorts/').last.split('?').first;
    }
    return '';
  }

  Future<void> _syncVideo() async {
    try {
      final res = await http.get(Uri.parse(watchBaseUrl + '/watch_' + widget.room + '/state'));
      if (res.statusCode == 200) {
        final f = json.decode(res.body)['fields'];
        if (f != null && mounted) {
          final remoteVid = f['vid']?['stringValue'] ?? '';
          if (remoteVid.isNotEmpty && remoteVid != currentVideoId) {
            setState(() {
              currentVideoId = remoteVid;
              statusText = '🎬 नई फिल्म लोड हो गई है! "Watch Now" दबाकर साथ देखें';
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _shareAndPlay() async {
    final vid = _extractVideoId(urlCtrl.text.trim());
    if (vid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कृपया सही YouTube वीडियो या फिल्म का लिंक पेस्ट करें!')));
      return;
    }
    setState(() {
      currentVideoId = vid;
      statusText = '🎬 फिल्म तैयार है! दोनों दोस्त एक साथ देख सकते हैं';
    });
    urlCtrl.clear();
    try {
      await http.patch(
        Uri.parse(watchBaseUrl + '/watch_' + widget.room + '/state'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fields': {
            'vid': {'stringValue': vid},
          }
        }),
      );
    } catch (_) {}
    _openYouTube(vid);
  }

  Future<void> _openYouTube(String vid) async {
    final url = Uri.parse('https://www' + '.' + 'youtube' + '.' + 'com/watch?v=' + vid);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('🎬 Watch with ' + widget.friendName),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
              child: Column(
                children: [
                  const Text('साथ में फिल्म या गाना देखें', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: InputDecoration(
                      hintText: 'YouTube लिंक यहाँ पेस्ट करें...',
                      prefixIcon: const Icon(Icons.link, color: Color(0xFF00897B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _shareAndPlay,
                    icon: const Icon(Icons.play_circle_fill),
                    label: const Text('दोनों के लिए फिल्म चलाएं', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (currentVideoId.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network('https://img' + '.' + 'youtube' + '.' + 'com/vi/' + currentVideoId + '/0.jpg', height: 180, width: double.infinity, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 12),
                    Text(statusText, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00897B))),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 48)),
                      onPressed: () => _openYouTube(currentVideoId),
                      icon: const Icon(Icons.smart_display),
                      label: const Text('अभी साथ में देखें (Watch Now)', style: TextStyle(fontWeight: FontWeight.bold)),
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
