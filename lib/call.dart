import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const String callSyncUrl = 'https://firestore' + '.' + 'googleapis' + '.' + 'com/v1/projects/dostchat-e903a/databases/(default)/documents';

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
  bool frontCam = true;
  Timer? _ringStopTimer;
  Timer? _endCheckTimer;

  @override
  void initState() {
    super.initState();
    FlutterRingtonePlayer().playNotification(looping: true);
    _ringStopTimer = Timer(const Duration(seconds: 10), () => FlutterRingtonePlayer().stop());
    _clearOldEndSignal();
    _initCustomCall();
    _endCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkRemoteHangup());
  }

  @override
  void dispose() {
    _ringStopTimer?.cancel();
    _endCheckTimer?.cancel();
    FlutterRingtonePlayer().stop();
    super.dispose();
  }

  Future<void> _clearOldEndSignal() async {
    try { await http.delete(Uri.parse(callSyncUrl + '/hangup_' + widget.room + '/state')); } catch (_) {}
  }

  Future<void> _checkRemoteHangup() async {
    try {
      final res = await http.get(Uri.parse(callSyncUrl + '/hangup_' + widget.room + '/state'));
      if (res.statusCode == 200 && mounted) {
        await _clearOldEndSignal();
        FlutterRingtonePlayer().stop();
        Navigator.pop(context);
      }
    } catch (_) {}
  }

  Future<void> _hangupAndNotify() async {
    FlutterRingtonePlayer().stop();
    try {
      await http.patch(
        Uri.parse(callSyncUrl + '/hangup_' + widget.room + '/state'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fields': {'ended': {'booleanValue': true}}}),
      );
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  String _getCallUrl() {
    final safeRoom = 'dc_' + widget.room.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final parts = widget.room.split('_');
    final id1 = parts.length > 1 ? parts[1] : widget.myId;
    final id2 = parts.length > 2 ? parts[2] : widget.myId;
    final cleanMy = widget.myId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanFriend = (widget.myId.contains(id1) ? id2 : id1).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final camParam = widget.isVideo ? (frontCam ? '&webcam&front&quality=1' : '&webcam&back&quality=1') : '&novideo';
    return 'https://vdo' + '.' + 'ninja/?room=' + safeRoom +
        '&push=' + safeRoom + '_' + cleanMy +
        '&view=' + safeRoom + '_' + cleanFriend +
        camParam + '&autostart&cleanoutput&noheader&nofooter&fullscreen&transparent';
  }

  Future<void> _initCustomCall() async {
    await [Permission.camera, Permission.microphone].request();
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B141A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            Future.delayed(const Duration(seconds: 2), () => FlutterRingtonePlayer().stop());
          },
        ),
      )
      ..loadRequest(Uri.parse(_getCallUrl()));

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
                      onPressed: _hangupAndNotify,
                    ),
                  ),
                  if (widget.isVideo)
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white24,
                      child: IconButton(
                        icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 28),
                        onPressed: () {
                          setState(() => frontCam = !frontCam);
                          _controller?.loadRequest(Uri.parse(_getCallUrl()));
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
