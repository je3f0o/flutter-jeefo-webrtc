import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'logger.dart';
import 'signaling.dart';

class VideoCallResolution {
  int width  = 0;
  int height = 0;

  @override
  String toString() {
    return '${width}x$height';
  }

  void reset() {
    width  = 0;
    height = 0;
  }
}

class VideoCallStats {
  int incomingKbps = 0;
  int outgoingKbps = 0;
  int lastIncomingBytes = 0;
  int lastOutgoingBytes = 0;
  VideoCallResolution incomingVideoResolution = VideoCallResolution();
  VideoCallResolution outgoingVideoResolution = VideoCallResolution();
  DateTime? lastUpdated;

  void reset() {
    incomingKbps = 0;
    outgoingKbps = 0;
    lastIncomingBytes = 0;
    lastOutgoingBytes = 0;
    incomingVideoResolution.reset();
    outgoingVideoResolution.reset();
    lastUpdated = null;
  }
}

class VideoCall {
  Signaller signaller;
  Logger logger;
  int handleId = 0;
  String callerName = "";
  dynamic remoteJSEP;

  VideoCallStats stats = VideoCallStats();
  Timer? statsUpdateTimer;

  RTCPeerConnection? peer;
  RTCSessionDescription? localSDP;
  RTCSessionDescription? remoteSDP;
  MediaStream? localStream;
  MediaStream? remoteStream;

  Function()? onRegistered;
  Function(String)? onIncomingCall;
  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function()? onStatsUpdated;
  Function()? onCalling;
  Function()? onCallStart;
  Function()? onHangup;

  // Function(dynamic medium, bool on, String mid)? onMediaState;
  Function(bool on)? onConnectionStateChange;

  VideoCall(Signaller signal): signaller = signal, logger = signal.logger;

  Future<void> init() {
    Completer<void> idCompleter = Completer<void>();

    signaller.send({
      "janus": "attach",
      "transaction": signaller.transaction,
      "session_id": signaller.sessionId,
      "plugin": "janus.plugin.videocall",
    });

    signaller.messageListeners.add((Map message) {
      if (handleId == 0 && message['janus'] == 'success') {
        if (message.containsKey('data') && message['data'] is Map) {
          Map<String, dynamic> data = message['data'];
          if (data.containsKey('id') && data['id'] is int) {
            handleId = data['id'];
            idCompleter.complete();
          }
        }
      } else {
        switch (message['janus']) {
          case 'event':
            _handleEvent(message);
            break;
          case "media":
            logger.debug('got ${message['type']} media.');
            break;
          case "hangup":
            logger.debug('janus hangup???');
            break;
          case "webrtcup":
            break;
          default:
            assert(false, "unreachable");
        }
      }
    });

    return idCompleter.future;
  }

  void register(String username) {
    _send({"request": "register", "username": username});
  }

  void call(String username) async {
    RTCPeerConnection pc = await _createPeer();

    localSDP = await pc.createOffer();
    await pc.setLocalDescription(localSDP!);

    signaller.send({
      "janus": "message",
      "transaction": signaller.transaction,
      "session_id": signaller.sessionId,
      "handle_id": handleId,
      "body": {"request": "call", "username": username},
      "jsep": {
        "sdp": localSDP!.sdp,
        "type": localSDP!.type,
      }
    });
  }

  void answer() async {
    RTCPeerConnection pc = await _createPeer();

    await pc.setRemoteDescription(remoteSDP!);
    localSDP = await pc.createAnswer();
    await pc.setLocalDescription(localSDP!);

    signaller.send({
      "janus": "message",
      "transaction": signaller.transaction,
      "session_id": signaller.sessionId,
      "handle_id": handleId,
      "body": {"request": "accept"},
      "jsep": {
        "sdp": localSDP!.sdp,
        "type": localSDP!.type,
      }
    });
  }

  void hangup() {
    if (peer == null && remoteSDP == null) return;

    localStream?.getTracks().forEach((track) {
      track.stop();
      localStream?.removeTrack(track);
    });
    remoteStream?.getTracks().forEach((track) {
      track.stop();
      remoteStream?.removeTrack(track);
    });
    peer?.close();

    peer = null;
    localStream = null;
    remoteStream = null;
    localSDP = null;
    remoteSDP = null;
    stats.reset();
    statsUpdateTimer?.cancel();

    _send({"request": "hangup"});
    onHangup?.call();
  }

  void _send(Map body) {
    signaller.send({
      "janus": "message",
      "transaction": signaller.transaction,
      "session_id": signaller.sessionId,
      "handle_id": handleId,
      "body": body,
    });
  }

  void setAudio(bool value) {
    _send({"request": "set", "audio": value});
  }

  void setVideo(bool value) {
    _send({"request": "set", "video": value});
  }

  Future<MediaStream> _openUserMedia() async {
    return await navigator.mediaDevices
        .getUserMedia({'video': true, 'audio': true});
  }

  void updateStats() async {
    if (peer == null) return;

    var statsReport = await peer!.getStats();

    int lastIncomingBytes = stats.lastIncomingBytes;
    int lastOutgoingBytes = stats.lastOutgoingBytes;
    DateTime? lastUpdated = stats.lastUpdated;
    DateTime currentTime = DateTime.now();

    for (StatsReport report in statsReport) {
      switch (report.type) {
        case 'inbound-rtp':
          if (report.values['mediaType'] == 'video') {
            if (report.values['bytesReceived'] != null && lastUpdated != null) {
              int bytesReceived = report.values['bytesReceived'];
              int dt = currentTime.difference(lastUpdated).inMilliseconds;
              stats.incomingKbps = (bytesReceived - lastIncomingBytes) * 8 ~/ dt;
            }
            stats.incomingVideoResolution.width  = report.values['frameWidth'];
            stats.incomingVideoResolution.height = report.values['frameHeight'];
            stats.lastIncomingBytes = report.values['bytesReceived'];
          }
          break;
        case 'outbound-rtp':
          if (report.values['mediaType'] == 'video') {
            if (report.values['bytesSent'] != null && lastUpdated != null) {
              int bytesSent = report.values['bytesSent'];
              int dt = currentTime.difference(lastUpdated).inMilliseconds;
              stats.outgoingKbps = (bytesSent - lastOutgoingBytes) * 8 ~/ dt;
            }
            stats.outgoingVideoResolution.width  = report.values['frameWidth'];
            stats.outgoingVideoResolution.height = report.values['frameHeight'];
            stats.lastOutgoingBytes = report.values['bytesSent'];
          }
          break;
      }
    }

    stats.lastUpdated = currentTime;
    onStatsUpdated?.call();
  }

  Future<RTCPeerConnection> _createPeer() async {
    RTCPeerConnection pc = await signaller.createPeer();
    peer = pc;

    statsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      updateStats();
    });

    localStream = await _openUserMedia();
    localStream!.getTracks().forEach((track) {
      pc.addTrack(track, localStream!);
    });
    onLocalStream!.call(localStream!);

    pc.onAddStream = (MediaStream stream) {
      logger.debug("onAddStream: ${stream.getTracks().length} tracks.");
      remoteStream = stream;
      onRemoteStream?.call(stream);
    };

    pc.onTrack = (RTCTrackEvent event) {
      logger.debug('Got remote track: ${event.track}');
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      logger.debug('onIceCandidate: ${candidate.toMap()}');
      signaller.send({
        "janus": "trickle",
        "transaction": signaller.transaction,
        "session_id": signaller.sessionId,
        "handle_id": handleId,
        "candidate": {
          "candidate": candidate.candidate,
          "sdpMid": candidate.sdpMid,
          "sdpMLineIndex": candidate.sdpMLineIndex,
        },
      });
    };

    return pc;
  }

  void _handleEvent(Map message) {
    if (!message.containsKey('plugindata')) return;

    Map<String, dynamic> data = message['plugindata']['data'];
    if (!data.containsKey('result')) {
      return;
    }
    switch (data['result']['event']) {
      case "registered":
        onRegistered?.call();
        break;
      case "incomingcall":
        callerName = data['result']['username'];
        dynamic jsep = message['jsep'];
        remoteSDP = RTCSessionDescription(jsep['sdp'], jsep['type']);
        onIncomingCall?.call(callerName);
        break;
      case "accepted":
        if (peer != null) {
          if (message.containsKey('jsep')) {
            dynamic jsep = message['jsep'];
            remoteSDP = RTCSessionDescription(jsep['sdp'], jsep['type']);
            peer!.setRemoteDescription(remoteSDP!);
          }
          onCallStart?.call();
        }
        break;
      case "calling":
        onCalling?.call();
        break;
      case "set":
      case "hangup":
        logger.debug("video call: ${data['result']['event']}.");
        break;
      default:
        assert(false, "unreachable");
    }
  }
}
