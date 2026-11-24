import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class NativeCallPage extends StatefulWidget {
  final String room, myId, friendName;
  final bool isVideo;
  const NativeCallPage({super.key, required this.room, required this.myId, required this.friendName, required this.isVideo});
  @override
  State<NativeCallPage> createState() => _NativeCallPageState();
}

class _NativeCallPageState extends State<NativeCallPage> {
  WebViewController? _controller;
  bool micMuted = false;
  Timer? _ringStopTimer;

  @override
  void initState() {
    super.initState();
    FlutterRingtonePlayer().playNotification(looping: true);
    _ringStopTimer = Timer(const Duration(seconds: 12), () {
      FlutterRingtonePlayer().stop();
    });
    _initCustomCall();
  }

  @override
  void dispose() {
    _ringStopTimer?.cancel();
    FlutterRingtonePlayer().stop();
    super.dispose();
  }

  Future<void> _initCustomCall() async {
    await [Permission.camera, Permission.microphone].request();
    final safeRoom = 'dc_' + widget.room.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final pushId = safeRoom + '_' + widget.myId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final media = widget.isVideo ? '&webcam&quality=1' : '&novideo';
    final url = 'https://vdo' + '.' + 'ninja/?room=' + safeRoom + '&push=' + pushId + media + '&autostart&cleanoutput&noheader&nofooter&fullscreen&transparent';

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B141A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            Future.delayed(const Duration(seconds: 3), () => FlutterRingtonePlayer().stop());
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    if (ctrl.platform is AndroidWebViewController) {
      final androidCtrl = ctrl.platform as AndroidWebViewController;
      await androidCtrl.setMediaPlaybackRequiresUserGesture(false);
      await androidCtrl.setOnPlatformPermissionRequest((request) => request.grant());
    }

    if (mounted) setState(() => _controller = ctrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null) Positioned.fill(child: WebViewWidget(controller: _controller!)),
            if (!widget.isVideo)
              Container(
                color: const Color(0xFF0B141A),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircleAvatar(radius: 55, backgroundColor: Color(0xFF00897B), child: Icon(Icons.person, size: 65, color: Colors.white)),
                      const SizedBox(height: 18),
                      Text(widget.friendName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('🔊 Audio Call Connected', style: TextStyle(color: Colors.greenAccent, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text((widget.isVideo ? '📹 ' : '📞 ') + widget.friendName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white24,
                    child: IconButton(
                      icon: Icon(micMuted ? Icons.mic_off : Icons.mic, color: Colors.white, size: 28),
                      onPressed: () {
                        setState(() => micMuted = !micMuted);
                        _controller?.runJavaScript("document.querySelectorAll('audio,video').forEach(e=>e.muted=" + micMuted.toString() + ");");
                      },
                    ),
                  ),
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.red,
                    child: IconButton(
                      icon: const Icon(Icons.call_end, color: Colors.white, size: 32),
                      onPressed: () {
                        FlutterRingtonePlayer().stop();
                        Navigator.pop(context);
                      },
                    ),
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
