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
  late bool isVideoMode;
  bool micMuted = false;
  bool speakerOn = true;
  bool frontCam = true;
  bool beautyFilter = false;
  Timer? _ringStopTimer;
  Timer? _endCheckTimer;
  final int _callStartTime = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    isVideoMode = widget.isVideo;
    FlutterRingtonePlayer().playNotification(looping: true);
    _ringStopTimer = Timer(const Duration(seconds: 8), () => FlutterRingtonePlayer().stop());
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

  Future<void> _checkRemoteHangup() async {
    try {
      final res = await http.get(Uri.parse(callSyncUrl + '/hangup_' + widget.room + '/state'));
      if (res.statusCode == 200 && mounted) {
        final f = json.decode(res.body)['fields'];
        final endedAt = int.tryParse(f?['endedAt']?['integerValue'] ?? '0') ?? 0;
        if (endedAt > _callStartTime) {
          FlutterRingtonePlayer().stop();
          Navigator.pop(context);
        }
      }
    } catch (_) {}
  }

  Future<void> _hangupAndNotify() async {
    FlutterRingtonePlayer().stop();
    try {
      await http.patch(
        Uri.parse(callSyncUrl + '/hangup_' + widget.room + '/state'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'fields': {'endedAt': {'integerValue': DateTime.now().millisecondsSinceEpoch.toString()}}}),
      );
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  String _buildWhatsAppCallHtml() {
    final safeRoom = 'dc_' + widget.room.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final parts = widget.room.split('_');
    final id1 = parts.length > 1 ? parts.elementAt(1) : widget.myId;
    final id2 = parts.length > 2 ? parts.elementAt(2) : widget.myId;
    final cleanMy = widget.myId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanFriend = (widget.myId.contains(id1) ? id2 : id1).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final myPeer = safeRoom + '_' + cleanMy;
    final friendPeer = safeRoom + '_' + cleanFriend;
    final facing = frontCam ? 'user' : 'environment';
    final wantVid = isVideoMode ? 'true' : 'false';

    return '''
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<script src="https://unpkg.com"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0b141a;overflow:hidden;width:100vw;height:100vh}
#remoteVid{width:100vw;height:100vh;object-fit:cover;background:#0b141a}
#localVid{position:fixed;bottom:105px;right:16px;width:105px;height:150px;object-fit:cover;border-radius:14px;border:2px solid #25d366;z-index:10;background:#111}
</style></head><body>
<video id="remoteVid" autoplay playsinline></video>
<video id="localVid" autoplay playsinline muted></video>
<script>
let localStream;
async function start(){
  try{
    localStream = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video: $wantVid ? {facingMode: '$facing'} : false
    });
    if($wantVid) document.getElementById('localVid').srcObject = localStream;
    else document.getElementById('localVid').style.display = 'none';
    const peer = new Peer('$myPeer');
    peer.on('open', () => {
      setInterval(() => {
        const call = peer.call('$friendPeer', localStream);
        if(call) call.on('stream', rs => { document.getElementById('remoteVid').srcObject = rs; });
      }, 2500);
    });
    peer.on('call', call => {
      call.answer(localStream);
      call.on('stream', rs => { document.getElementById('remoteVid').srcObject = rs; });
    });
  }catch(e){}
}
start();
</script></body></html>
''';
  }

  Future<void> _initCustomCall() async {
    await [Permission.camera, Permission.microphone].request();
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B141A))
      ..loadHtmlString(_buildWhatsAppCallHtml(), baseUrl: 'https://dostchat.app');

    if (ctrl.platform is AndroidWebViewController) {
      final androidCtrl = ctrl.platform as AndroidWebViewController;
      await androidCtrl.setMediaPlaybackRequiresUserGesture(false);
      await androidCtrl.setOnPlatformPermissionRequest((request) => request.grant());
    }

    if (mounted) setState(() => _controller = ctrl);
  }
    Widget _roundBtn(IconData icon, String label, {bool active = false, Color? bg, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: bg ?? (active ? Colors.white : const Color(0xFF2A3942)),
            child: Icon(icon, color: active && bg == null ? Colors.black : Colors.white, size: 24),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null)
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: beautyFilter
                      ? const ColorFilter.matrix([1.1, 0, 0, 0, 12, 0, 1.08, 0, 0, 10, 0, 0, 1.05, 0, 8, 0, 0, 0, 1, 0])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: WebViewWidget(controller: _controller!),
                ),
              ),
            if (!isVideoMode)
              Container(
                color: const Color(0xFF0B141A),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          CircleAvatar(backgroundColor: const Color(0xFF1F2C34), child: IconButton(icon: const Icon(Icons.close_fullscreen, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
                          Column(
                            children: [
                              Text(widget.friendName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              const Row(children: [Icon(Icons.lock, color: Colors.white54, size: 12), SizedBox(width: 4), Text('End-to-end encrypted', style: TextStyle(color: Colors.white54, fontSize: 12))]),
                            ],
                          ),
                          const CircleAvatar(backgroundColor: Color(0xFF1F2C34), child: Icon(Icons.person_add, color: Colors.white, size: 20)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    CircleAvatar(
                      radius: 68,
                      backgroundColor: const Color(0xFF00897B),
                      child: Text(widget.friendName.isNotEmpty ? widget.friendName.toUpperCase() : 'D', style: const TextStyle(fontSize: 52, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    Container(
                      margin: const EdgeInsets.all(14),
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(color: const Color(0xFF1F2C34), borderRadius: BorderRadius.circular(28)),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _roundBtn(Icons.volume_up, 'Speaker', active: speakerOn, onTap: () => setState(() => speakerOn = !speakerOn)),
                              _roundBtn(Icons.videocam, 'Video', onTap: () {
                                setState(() => isVideoMode = true);
                                _controller?.loadHtmlString(_buildWhatsAppCallHtml(), baseUrl: 'https://dostchat.app');
                              }),
                              _roundBtn(micMuted ? Icons.mic_off : Icons.mic, 'Mute', active: micMuted, onTap: () {
                                setState(() => micMuted = !micMuted);
                                _controller?.runJavaScript("if(localStream) localStream.getAudioTracks().forEach(t=>t.enabled=" + (!micMuted).toString() + ");");
                              }),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _roundBtn(Icons.more_horiz, 'More', onTap: () {}),
                              _roundBtn(Icons.ios_share, 'Share', onTap: () {}),
                              _roundBtn(Icons.call_end, 'End', bg: const Color(0xFFE53935), onTap: _hangupAndNotify),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (isVideoMode) ...[
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text(widget.friendName, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                    const SizedBox(height: 2),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Icon(Icons.lock, color: Colors.white70, size: 12), SizedBox(width: 4), Text('End-to-end encrypted', style: TextStyle(color: Colors.white70, fontSize: 12, shadows: [Shadow(blurRadius: 6, color: Colors.black)]))],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 14,
                right: 12,
                child: Column(
                  children: [
                    const CircleAvatar(radius: 22, backgroundColor: Colors.black54, child: Icon(Icons.person_add, color: Colors.white, size: 20)),
                    const SizedBox(height: 12),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 20),
                        onPressed: () {
                          setState(() => frontCam = !frontCam);
                          _controller?.loadHtmlString(_buildWhatsAppCallHtml(), baseUrl: 'https://dostchat.app');
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: beautyFilter ? Colors.white : Colors.black54,
                      child: IconButton(
                        icon: Icon(Icons.auto_fix_high, color: beautyFilter ? Colors.black : Colors.white, size: 20),
                        onPressed: () => setState(() => beautyFilter = !beautyFilter),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 22,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(color: const Color(0xFF1F2C34).withOpacity(0.92), borderRadius: BorderRadius.circular(36)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      const CircleAvatar(radius: 22, backgroundColor: Color(0xFF2A3942), child: Icon(Icons.more_horiz, color: Colors.white)),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF2A3942),
                        child: IconButton(
                          icon: const Icon(Icons.videocam, color: Colors.white),
                          onPressed: () {
                            setState(() => isVideoMode = false);
                            _controller?.loadHtmlString(_buildWhatsAppCallHtml(), baseUrl: 'https://dostchat.app');
                          },
                        ),
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: speakerOn ? Colors.white : const Color(0xFF2A3942),
                        child: IconButton(
                          icon: Icon(Icons.volume_up, color: speakerOn ? Colors.black : Colors.white),
                          onPressed: () => setState(() => speakerOn = !speakerOn),
                        ),
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: micMuted ? Colors.white : const Color(0xFF2A3942),
                        child: IconButton(
                          icon: Icon(micMuted ? Icons.mic_off : Icons.mic, color: micMuted ? Colors.black : Colors.white),
                          onPressed: () {
                            setState(() => micMuted = !micMuted);
                            _controller?.runJavaScript("if(localStream) localStream.getAudioTracks().forEach(t=>t.enabled=" + (!micMuted).toString() + ");");
                          },
                        ),
                      ),
                                            CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFE53935),
                        child: IconButton(icon: const Icon(Icons.call_end, color: Colors.white), onPressed: _hangupAndNotify),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
