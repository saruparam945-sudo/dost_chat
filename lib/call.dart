import 'package:flutter/material.dart';
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
    _setupInAppCall();
  }

  Future<void> _setupInAppCall() async {
    await [Permission.camera, Permission.microphone].request();
    final safeRoom = 'DostChat_' + widget.room.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final videoFlag = widget.isVideo ? 'false' : 'true';
    final callUrl = 'https://meet' + '.' + 'jit' + '.' + 'si/' + safeRoom +
        '#config.prejoinPageEnabled=false&config.startWithVideoMuted=' + videoFlag +
        '&config.disableDeepLinking=true';

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B141A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        title: Text((widget.isVideo ? '📹 ' : '📞 ') + widget.friendName, style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.redAccent, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (loading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.greenAccent),
                  SizedBox(height: 14),
                  Text('कॉल जुड़ रही है...', style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
