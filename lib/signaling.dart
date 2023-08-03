import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:math';
import 'dart:async';
import 'plugin_video_call.dart';
import 'logger.dart';

typedef IncomingMessageCallback = void Function(Map<String, dynamic> message);

class Signaller {
  // Janus things
  WebSocketChannel? channel;
  int sessionId = 0;
  String transaction = "empty";
  Timer? keepAliveTimer;
  VideoCall? videoCaller;
  List<IncomingMessageCallback> messageListeners = [];
  Logger logger = Logger();

  // WebRTC things
  Map<String, dynamic> rtcPeerConfig = {
    // 'iceServers': [
    //   {
    //     'urls': ['turn:62.210.189.244:3478'],
    //     'username': 'testUser',
    //     'credential': 'testPassword',
    //   },
    //   {
    //     'urls': ['stun:62.210.189.244:3478'],
    //     'username': 'testUser',
    //     'credential': 'testPassword',
    //   },
    //   {
    //     'urls': ['turn:turn-test.codeda.com:443?transport=tcp'],
    //     'username': 'testUser',
    //     'credential': 'testPassword',
    //   },
    // ],
    'iceTransportPolicy': 'all',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan',
  };

  void dispose() {
    keepAliveTimer?.cancel();
    channel?.sink.close();
  }

  Future<void> init(String url) async {
    logger.debug("connecting to url: $url");
    Uri uri = Uri.parse(url);
    channel = IOWebSocketChannel.connect(uri, protocols: ['janus-protocol']);

    Completer<void> sessionIdCompleter = Completer<void>();

    channel!.stream.listen(
      (receivedString) {
        Map<String, dynamic> message = jsonDecode(receivedString);
        logger.debug(" IN: $message");

        if (sessionId == 0 && message['janus'] == 'success') {
          if (message.containsKey('data') && message['data'] is Map) {
            Map<String, dynamic> data = message['data'];
            if (data.containsKey('id') && data['id'] is int) {
              sessionId = data['id'];
              _startKeepAlive();
              sessionIdCompleter.complete();
            }
          }
        } else if (message['janus'] == 'error') {
          logger.error("Error: ${message['error']}");
        } else if (message['janus'] != 'ack') {
          for (var listener in messageListeners) {
            listener(message);
          }
        }
      },
      onError: (error) {
        logger.error("error: $error");
        // Perform any necessary error handling, e.g.,
        // reconnect or show an error message.
      },
      onDone: () {
        logger.debug("connection closed");
      }
    );

    transaction = _generateTransactionId(12);
    // Send the payload to the WebSocket server
    send({
      "janus": "create",
      "transaction": transaction,
    });

    return sessionIdCompleter.future;
  }

  Future<VideoCall> attach(String plugin) async {
    switch (plugin) {
      case "video_call":
        videoCaller = VideoCall(this);
        await videoCaller!.init();
        break;
      default: // TODO: later add other plugins
        break;
    }
    return videoCaller!;
  }

  void send(Map payload) {
    String message = jsonEncode(payload);
    channel!.sink.add(message);
    logger.debug("OUT: $message");
  }

  String _generateTransactionId(int length) {
    const String charSet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final Random random = Random();
    String result = '';
    for (int i = 0; i < length; i++) {
      result += charSet[random.nextInt(charSet.length)];
    }
    return result;
  }

  void _startKeepAlive() {
    const keepAliveInterval = Duration(seconds: 25);
    if (keepAliveTimer != null && keepAliveTimer!.isActive) {
      keepAliveTimer!.cancel();
    }
    keepAliveTimer = Timer.periodic(keepAliveInterval, (_) {
      _sendKeepAlive();
    });
  }

  void _sendKeepAlive() {
    send({
      'janus': 'keepalive',
      'session_id': sessionId,
      'transaction': transaction,
    });
  }

  Future<RTCPeerConnection> createPeer() async {
    RTCPeerConnection peer = await createPeerConnection(rtcPeerConfig);

    bool debug = true;
    if (debug) {
      peer.onIceGatheringState = (RTCIceGatheringState state) {
        logger.debug('onIceGatheringState: $state');
      };

      peer.onConnectionState = (RTCPeerConnectionState state) {
        logger.debug('onConnectionState: $state');
      };

      peer.onSignalingState = (RTCSignalingState state) {
        logger.debug('onSignalingState: $state');
      };

      peer.onIceGatheringState = (RTCIceGatheringState state) {
        logger.debug('onIceGatheringState: $state');
      };
    }

    return peer;
  }
}