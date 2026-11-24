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
  bool connected = false;
  int callSeconds = 0;
  Timer? _ringStopTimer;
  Timer? _endCheckTimer;
  Timer? _durationTimer;
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
    _durationTimer?.cancel();
    FlutterRingtonePlayer().stop();
    super.dispose();
  }

  String _formatTimer(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
      await http.delete(Uri.parse(callSyncUrl + '/webrtc_' + widget.room + '/signal'));
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  String _buildWhatsAppCallHtml() {
    final facing = frontCam ? 'user' : 'environment';
    final wantVid = isVideoMode ? 'true' : 'false';
    final sigUrl = callSyncUrl + '/webrtc_' + widget.room + '/signal';
    final isCaller = widget.room.startsWith(widget.myId) ? 'true' : 'false';

    return '''
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0b141a;overflow:hidden;width:100vw;height:100vh}
video::-webkit-media-controls{display:none !important}
.big{position:fixed;top:0;left:0;width:100vw;height:100vh;object-fit:cover;z-index:1;background:#0b141a}
.small{position:fixed;bottom:108px;right:16px;width:110px;height:155px;object-fit:cover;border-radius:14px;border:2px solid #25d366;z-index:10;background:#111;box-shadow:0 4px 12px rgba(0,0,0,.6)}
</style></head><body>
<video id="remoteVid" class="big" autoplay playsinline></video>
<video id="localVid" class="small" autoplay playsinline muted onclick="swapVideos()"></video>
<audio id="remoteAud" autoplay></audio>
<script>
let localStream, pc, swapped = false;
const rv = document.getElementById('remoteVid');
const lv = document.getElementById('localVid');
const ra = document.getElementById('remoteAud');

function swapVideos(){
  swapped = !swapped;
  rv.className = swapped ? 'small' : 'big';
  lv.className = swapped ? 'big' : 'small';
  rv.onclick = swapped ? swapVideos : null;
  lv.onclick = swapped ? null : swapVideos;
}

async function start(){
  try{
    localStream = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video: $wantVid ? {facingMode: '$facing'} : false
    });
    if($wantVid) lv.srcObject = localStream;
    else lv.style.display = 'none';

        pc = new RTCPeerConnection({
      iceServers: [
        { urls: 'stun:://google.com' },
        { urls: 'stun:openrelay.metered.ca:80' },
        { urls: 'turn:openrelay.metered.ca:80', username: 'openrelayproject', credential: 'openrelayproject' },
        { urls: 'turn:openrelay.metered.ca:443', username: 'openrelayproject', credential: 'openrelayproject' }
      ]
    });
    localStream.getTracks().forEach(t => pc.addTrack(t, localStream));

    const remoteStream = new MediaStream();
    rv.srcObject = remoteStream;
    ra.srcObject = remoteStream;
    pc.ontrack = e => {
      remoteStream.addTrack(e.track);
      rv.play().catch(()=>{});
      ra.play().catch(()=>{});
      if(window.CallBridge) CallBridge.postMessage('connected');
    };
    
    let cands = [];
    pc.onicecandidate = e => { if(e.candidate) cands.push(e.candidate); };

    if($isCaller){
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await new Promise(r => setTimeout(r, 1500));
      await fetch('$sigUrl', {
        method: 'PATCH',
        headers: {'Content-Type':'application/json'},
        body: JSON.stringify({fields:{
          offer:{stringValue: JSON.stringify(pc.localDescription)},
          cands:{stringValue: JSON.stringify(cands)},
          ts:{integerValue: String(Date.now())}
        }})
      });
      const poll = setInterval(async () => {
        const res = await fetch('$sigUrl');
        if(res.ok){
          const d = await res.json();
          const ans = d.fields?.answer?.stringValue;
          if(ans && !pc.currentRemoteDescription){
            await pc.setRemoteDescription(new RTCSessionDescription(JSON.parse(ans)));
            const rc = JSON.parse(d.fields?.acands?.stringValue || '[]');
            for(const c of rc) await pc.addIceCandidate(new RTCIceCandidate(c));
            clearInterval(poll);
          }
        }
      }, 1500);
    } else {
      const poll = setInterval(async () => {
        const res = await fetch('$sigUrl');
        if(res.ok){
          const d = await res.json();
          const off = d.fields?.offer?.stringValue;
          if(off && !pc.currentRemoteDescription){
            await pc.setRemoteDescription(new RTCSessionDescription(JSON.parse(off)));
            const ans = await pc.createAnswer();
            await pc.setLocalDescription(ans);
            await new Promise(r => setTimeout(r, 1500));
            await fetch('$sigUrl?updateMask.fieldPaths=answer&updateMask.fieldPaths=acands', {
              method: 'PATCH',
              headers: {'Content-Type':'application/json'},
              body: JSON.stringify({fields:{
                answer:{stringValue: JSON.stringify(pc.localDescription)},
                acands:{stringValue: JSON.stringify(cands)}
              }})
            });
            const rc = JSON.parse(d.fields?.cands?.stringValue || '[]');
            for(const c of rc) await pc.addIceCandidate(new RTCIceCandidate(c));
            clearInterval(poll);
          }
        }
      }, 1500);
    }
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
      ..addJavaScriptChannel('CallBridge', onMessageReceived: (msg) {
        if (msg.message == 'connected' && !connected && mounted) {
          FlutterRingtonePlayer().stop();
          setState(() => connected = true);
          _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => callSeconds++);
          });
        }
      })
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
    final statusText = connected ? _formatTimer(callSeconds) : 'Calling...';
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
                              const SizedBox(height: 4),
                              Text(statusText, style: TextStyle(color: connected ? Colors.greenAccent : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
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
                    const SizedBox(height: 3),
                    Text(statusText, style: TextStyle(color: connected ? Colors.greenAccent : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 6, color: Colors.black)])),
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
