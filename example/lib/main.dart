import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:jeefo_webrtc/plugin_video_call.dart';
import 'package:jeefo_webrtc/signaling.dart';
import 'package:jeefo_webrtc/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(key: ValueKey('myHomePage')),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  final Signaller signaller = Signaller();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  VideoCall? videoCall;
  String callToUsername = "";
  String callerUsername = "";

  bool isCalling = false;
  bool isIncomingCall = false;
  bool isCallAnswered = false;
  bool isAudioEnabled = true;
  bool isVideoEnabled = true;
  bool isDebugView = true;

  TextEditingController textCallToUsername = TextEditingController(text: '');

  bool get isHangable {
    return isCalling || isCallAnswered;
  }

  String get incomingRes {
    return videoCall?.stats.incomingVideoResolution.toString() ?? "0x0";
  }

  String get outgoingRes {
    return videoCall?.stats.outgoingVideoResolution.toString() ?? "0x0";
  }

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    textCallToUsername.addListener(() {
      setState(() {
        callToUsername = textCallToUsername.text.trim();
      });
    });

    initSignal();
  }

  Future<void> initSignal() async {
    await signaller.init("wss://longbinarycity.com:443/webrtc/janus");
    //signaller.logger.filterLevel = LogLevel.debug;

    VideoCall vc = await signaller.attach("video_call");
    vc.onRegistered = () {
      signaller.logger.info("video call registered.");
    };

    vc.onIncomingCall = (username) {
      setState(() {
        callerUsername = username;
        isIncomingCall = true;
      });
    };

    vc.onStatsUpdated = () {
      setState(() {});
    };

    vc.onCalling = () {
      setState(() {
        isCalling = true;
      });
    };

    vc.onCallStart = () {
      signaller.logger.info("video call started.");
      setState(() {
        isCallAnswered = true;
      });
    };

    vc.onHangup = () {
      signaller.logger.info("video call hangup.");
      setState(() {
        isCalling      = false;
        isCallAnswered = false;
        isIncomingCall = false;
        isAudioEnabled = true;
        isVideoEnabled = true;
      });
    };

    vc.onLocalStream = (stream) {
      setState(() {
        _localRenderer.srcObject = stream;
      });
    };

    vc.onRemoteStream = (stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    };

    vc.register("jeefo-android");
    videoCall = vc;
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget view;
    if (isIncomingCall && !isCallAnswered) {
      view = _incomingCallView();
    } else {
      view = Column(children: [
        Expanded(child: _videoRenderersView()),
        _statsView(),
        isHangable ? _callSettingsView() : _inputSettinsView(),
        _primaryButtonView(),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("jeefo WebRTC"),
        actions: [
          Switch(
            value: isDebugView,
            onChanged: (value) {
              setState(() {
                isDebugView = value;
              });
            },
            activeTrackColor   : Colors.lightGreen,
            activeColor        : Colors.green,
            inactiveThumbColor : Colors.grey,
            inactiveTrackColor : Colors.grey.shade300,
          ),
        ],
      ),
      body: view
    );
  }

  Widget _videoRenderersView() {
    Widget localView = RTCVideoView(_localRenderer, mirror: true);
    Widget remoteView = RTCVideoView(_remoteRenderer);
    if (isDebugView) {
      localView = Container(color: Colors.blue, child: localView);
      remoteView = Container(color: Colors.purpleAccent, child: remoteView);
    }

    Widget view = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: localView),
          Expanded(child: remoteView),
        ],
      ),
    );

    return isDebugView ? Container(color: Colors.brown, child: view) : view;
  }

  Widget _statsView() {
    Widget localView = Column(
      mainAxisSize: MainAxisSize.min, // Set the mainAxisSize to min
      children: [
        Text('Video res: $outgoingRes'),
        Text('Outgoing: ${videoCall?.stats.outgoingKbps ?? 0}kbps'),
      ],
    );
    Widget remoteView = Column(
      mainAxisSize: MainAxisSize.min, // Set the mainAxisSize to min
      children: [
        Text('Video res: $incomingRes'),
        Text('Incoming: ${videoCall?.stats.incomingKbps ?? 0}kbps'),
      ],
    );
    if (isDebugView) {
      localView = Container(color: Colors.blue, child: localView);
      remoteView = Container(color: Colors.purpleAccent, child: remoteView);
    }

    Widget view = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: localView),
          Expanded(child: remoteView),
        ],
      ),
    );

    return isDebugView ? Container(color: Colors.brown, child: view) : view;
  }

  Widget _inputSettinsView() {
    Widget view = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Call to:  "),
          Flexible(
            child: TextFormField(
              controller: textCallToUsername,
            ),
          )
        ],
      ),
    );
    return isDebugView ? Container(color: Colors.yellow, child: view) : view;
  }

  Widget _callSettingsView() {
    Widget view = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Audio:'),
        Switch(
          value: isAudioEnabled,
          onChanged: (bool value) {
            videoCall?.setAudio(value);
            setState(() {
              isAudioEnabled = value;
            });
          },
        ),
        const SizedBox(width: 16),
        const Text('Video:'),
        Switch(
          value: isVideoEnabled,
          onChanged: (bool value) {
            videoCall?.setVideo(value);
            setState(() {
              isVideoEnabled = value;
            });
          },
        ),
      ],
    );
    return isDebugView ? Container(color: Colors.green, child: view) : view;
  }

  Widget _primaryButtonView() {
    Widget view = Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: _onPressPrimaryButton(),
          style: isHangable ? ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ) : null,
          child: Text(isHangable ? "Hangup" : "Call"),
        ),
      ],
    ));
    return isDebugView ? Container(color: Colors.orange, child: view) : view;
  }

  Widget _incomingCallView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Incoming call: $callerUsername',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _onPressAnswer(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                ),
                child: const Text("Answer"),
              ),
              const SizedBox(width: 24),
              ElevatedButton(
                onPressed: _onPressDecline(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text("Decline"),
              )
            ],
          ),
        ],
      ),
    );
  }

  Function()? _onPressPrimaryButton() {
    if (isHangable) {
      return () {
        videoCall?.hangup();
      };
    } else if (callToUsername.isNotEmpty) {
      return () {
        videoCall?.call(callToUsername);
      };
    }
    return null;
  }

  Function()? _onPressAnswer() {
    if (isIncomingCall && !isCallAnswered) {
      return () {
        videoCall?.answer();
      };
    }
    return null;
  }

  Function()? _onPressDecline() {
    if (isIncomingCall || isCallAnswered) {
      return () {
        videoCall?.hangup();
      };
    }
    return null;
  }
}
