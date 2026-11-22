import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

const String watchBaseUrl = 'https://googleapis.com';

class WatchTogetherPage extends StatefulWidget {
  final String room, myId, friendName;
  const WatchTogetherPage({super.key, required this.room, required this.myId, required this.friendName});
  @override
  State<WatchTogetherPage> createState() => _WatchTogetherPageState();
}

class _WatchTogetherPageState extends State<WatchTogetherPage> {
  final urlCtrl = TextEditingController();
  YoutubePlayerController? _ytCtrl;
  String currentVideoId = 'dQw4w9WgXcQ';
  bool isPlaying = true;
  Timer? syncTimer;

  @override
  void initState() {
    super.initState();
    _initPlayer(currentVideoId);
    _syncVideo();
    syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _syncVideo());
  }

  void _initPlayer(String videoId) {
    _ytCtrl?.dispose();
    _ytCtrl = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(autoPlay: true, mute: false),
    );
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    _ytCtrl?.dispose();
    super.dispose();
  }

  Future<void> _syncVideo() async {
    try {
      final res = await http.get(Uri.parse(watchBaseUrl + '/watch_' + widget.room + '/state'));
      if (res.statusCode == 200) {
        final f = json.decode(res.body)['fields'];
        if (f != null && mounted) {
          final remoteVid = f['vid']?['stringValue'] ?? '';
          final remotePlay = f['play']?['booleanValue'] ?? true;
          if (remoteVid.isNotEmpty && remoteVid != currentVideoId) {
            setState(() {
              currentVideoId = remoteVid;
              _ytCtrl?.load(remoteVid);
            });
          }
          if (remotePlay != isPlaying) {
            isPlaying = remotePlay;
            remotePlay ? _ytCtrl?.play() : _ytCtrl?.pause();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _pushVideo(String vid, bool play) async {
    try {
      await http.patch(
        Uri.parse(watchBaseUrl + '/watch_' + widget.room + '/state'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fields': {
            'vid': {'stringValue': vid},
            'play': {'booleanValue': play},
          }
        }),
      );
    } catch (_) {}
  }

  void _loadFromLink() {
    final id = YoutubePlayer.convertUrlToId(urlCtrl.text.trim());
    if (id != null && id.isNotEmpty) {
      setState(() {
        currentVideoId = id;
        isPlaying = true;
        _ytCtrl?.load(id);
      });
      _pushVideo(id, true);
      urlCtrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कृपया सही YouTube वीडियो लिंक डालें!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('🎬 Watch with ' + widget.friendName),
        backgroundColor: const Color(0xFF00897B),
      ),
      body: Column(
        children: [
          if (_ytCtrl != null)
            YoutubePlayer(
              controller: _ytCtrl!,
              showVideoProgressIndicator: true,
              progressIndicatorColor: const Color(0xFF00897B),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1A1A1A),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: urlCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'YouTube फिल्म या गाने का लिंक पेस्ट करें...',
                          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF2C2C2C),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16)),
                      onPressed: _loadFromLink,
                      child: const Text('चलाएं'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() => isPlaying = true);
                        _ytCtrl?.play();
                        _pushVideo(currentVideoId, true);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('दोनों के लिए Play'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                      onPressed: () {
                        setState(() => isPlaying = false);
                        _ytCtrl?.pause();
                        _pushVideo(currentVideoId, false);
                      },
                      icon: const Icon(Icons.pause),
                      label: const Text('दोनों के लिए Pause'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '💡 टिप: YouTube से किसी भी मूवी या गाने का Share -> Copy Link करें और ऊपर पेस्ट करके "चलाएं" दबाएं—दोनों दोस्तों के फोन में एक साथ चलेगा!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
