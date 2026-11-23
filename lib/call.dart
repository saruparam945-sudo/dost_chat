import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const String callBaseUrl = 'https://firestore' + '.' + 'googleapis' + '.' + 'com/v1/projects/dostchat-e903a/databases/(default)/documents';

class NativeCallPage extends StatefulWidget {
  final String room, myId, friendName;
  final bool isVideo;
  const NativeCallPage({super.key, required this.room, required this.myId, required this.friendName, required this.isVideo});
  @override
  State<NativeCallPage> createState() => _NativeCallPageState();
}

class _NativeCallPageState extends State<NativeCallPage> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool micMuted = false;
  bool connected = false;
  String callStatus = 'कैमरा और माइक चालू हो रहे हैं...';
  Timer? pollTimer;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    await [Permission.camera, Permission.microphone].request();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo ? {'facingMode': 'user'} : false,
      });
      _localRenderer.srcObject = _localStream;
      if (mounted) setState(() => callStatus = 'Ringing... दोस्त के जुड़ने का इंतज़ार');
    } catch (e) {
      if (mounted) setState(() => callStatus = 'Permission Error: Settings से Camera/Mic Allow करें');
      return;
    }

    final config = {
      'iceServers': [
        {'urls': 'stun:://google.com'},
        {'urls': 'stun:://google.com'},
      ]
    };
    _pc = await createPeerConnection(config);
    _localStream!.getTracks().forEach((track) => _pc!.addTrack(track, _localStream!));

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remoteRenderer.srcObject = event.streams.first;
          connected = true;
          callStatus = 'Connected (लाइव बात चल रही है)';
        });
      }
    };

    _pc!.onIceCandidate = (RTCIceCandidate c) async {
      if (c.candidate != null) {
        await http.post(
          Uri.parse(callBaseUrl + '/call_' + widget.room + '_ice'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'fields': {
              'from': {'stringValue': widget.myId},
              'data': {'stringValue': json.encode(c.toMap())},
            }
          }),
        );
      }
    };

    final roomUrl = Uri.parse(callBaseUrl + '/call_' + widget.room + '/signal');
    final checkRes = await http.get(roomUrl);
    if (checkRes.statusCode == 200) {
      final f = json.decode(checkRes.body)['fields'];
      if (f != null && f['offer'] != null && f['from']?['stringValue'] != widget.myId) {
        final offerMap = json.decode(f['offer']['stringValue']);
        await _pc!.setRemoteDescription(RTCSessionDescription(offerMap['sdp'], offerMap['type']));
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await http.patch(
          roomUrl,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'fields': {
              'from': {'stringValue': f['from']['stringValue']},
              'offer': {'stringValue': f['offer']['stringValue']},
              'answer': {'stringValue': json.encode(answer.toMap())},
            }
          }),
        );
        if (mounted) setState(() => connected = true);
      } else {
        await _createOffer(roomUrl);
      }
    } else {
      await _createOffer(roomUrl);
    }

    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollSignals(roomUrl));
  }

  Future<void> _createOffer(Uri roomUrl) async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await http.patch(
      roomUrl,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'fields': {
          'from': {'stringValue': widget.myId},
          'offer': {'stringValue': json.encode(offer.toMap())},
        }
      }),
    );
  }

  Future<void> _pollSignals(Uri roomUrl) async {
    try {
      final res = await http.get(roomUrl);
      if (res.statusCode == 200) {
        final f = json.decode(res.body)['fields'];
        if (f != null && f['answer'] != null && f['from']?['stringValue'] == widget.myId) {
          final remoteDesc = await _pc!.getRemoteDescription();
          if (remoteDesc == null) {
            final ans = json.decode(f['answer']['stringValue']);
            await _pc!.setRemoteDescription(RTCSessionDescription(ans['sdp'], ans['type']));
            if (mounted) setState(() => connected = true);
          }
        }
      }
      final iceRes = await http.get(Uri.parse(callBaseUrl + '/call_' + widget.room + '_ice'));
      if (iceRes.statusCode == 200) {
        for (var d in (json.decode(iceRes.body)['documents'] as List? ?? [])) {
          final f = d['fields'];
          if (f != null && f['from']?['stringValue'] != widget.myId) {
            final cMap = json.decode(f['data']['stringValue']);
            await _pc!.addCandidate(RTCIceCandidate(cMap['candidate'], cMap['sdpMid'], cMap['sdpMLineIndex']));
            await http.delete(Uri.parse('https://firestore' + '.' + 'googleapis' + '.' + 'com/v1/' + d['name'].toString()));
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _endCall() async {
    pollTimer?.cancel();
    await http.delete(Uri.parse(callBaseUrl + '/call_' + widget.room + '/signal'));
    _localStream?.getTracks().forEach((t) => t.stop());
    await _pc?.close();
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    pollTimer?.cancel();
    _localStream?.dispose();
    _pc?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.isVideo && connected)
              Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircleAvatar(radius: 52, backgroundColor: Color(0xFF00897B), child: Icon(Icons.person, size: 60, color: Colors.white)),
                    const SizedBox(height: 18),
                    Text(widget.friendName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(callStatus, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  ],
                ),
              ),
            if (widget.isVideo && _localStream != null)
              Positioned(
                top: 20,
                right: 16,
                width: 115,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
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
                        _localStream?.getAudioTracks().forEach((t) => t.enabled = !micMuted);
                      },
                    ),
                  ),
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.red,
                    child: IconButton(icon: const Icon(Icons.call_end, color: Colors.white, size: 32), onPressed: _endCall),
                  ),
                  if (widget.isVideo)
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white24,
                      child: IconButton(
                        icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 28),
                        onPressed: () => Helper.switchCamera(_localStream!.getVideoTracks().first),
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
