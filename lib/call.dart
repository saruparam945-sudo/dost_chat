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
  bool loading = true;

  @override
  void initState() {
    super.initState();
    FlutterRingtonePlayer().playRingtone(looping: true, asAlarm: false);
    _setupInAppCall();
  }

  @override
  void dispose() {
    FlutterRingtonePlayer().stop();
    super.dispose();
  }

  Future<void> _setupInAppCall() async {
    await [Permission.camera, Permission.microphone].request();
    final safeRoom = 'DostChatLive' + widget.room.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final videoFlag = widget.isVideo ? 'false' : 'true';
    final callUrl = 'https://meet' + '.' + 'jit' + '.' + 'si/' + safeRoom +
        '#config.prejoinConfig.enabled=false&config.prejoinPageEnabled=false' +
        '&config.startWithVideoMuted=' + videoFlag +
        '&config.disableDeepLinking=true&config.toolbarButtons=[]' +
        '&interfaceConfig.SHOW_JITSI_WATERMARK=false&interfaceConfig.SHOW_WATERMARK_FOR_GUESTS=false' +
        '&userInfo.displayName="Dost"';

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B141A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            FlutterRingtonePlayer().stop();
            if (mounted) setState(() => loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(callUrl));

    if (ctrl.platform is AndroidWebViewController) {
      final androidCtrl = ctrl.platform as AndroidWebViewController;
      await androidCtrl.setMediaPlaybackRequiresUserGesture(false);
      await androidCtrl.setOnPlatformPermissionRequest((request) {
        request.grant();
      });
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
            if (loading)
              Container(
                color: const Color(0xFF0B141A),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircleAvatar(radius: 52, backgroundColor: Color(0xFF00897B), child: Icon(Icons.person, size: 60, color: Colors.white)),
                      const SizedBox(height: 18),
                      Text(widget.friendName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Ringing... कॉल जुड़ रही है', style: TextStyle(color: Colors.greenAccent, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: CircleAvatar(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
