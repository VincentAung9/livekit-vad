import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:socket_io_client/socket_io_client.dart';
import 'package:vad/vad.dart';
import 'package:vad_example/ui/call_control.dart';

import '../custom_audio_stream_provider.dart';
import '../recording.dart';
import '../signalling.dart';
import '../vad_settings_dialog.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

class VadManager extends StatefulWidget {
  final String liveKitToken;
  final String language;
  final String partnerId;
  const VadManager({
    super.key,
    required this.liveKitToken,
    required this.language,
    required this.partnerId,
  });

  @override
  State<VadManager> createState() => _VadManagerState();
}

class _VadManagerState extends State<VadManager> {
  final ScrollController _scrollController = ScrollController();
  final Socket _socket = SignallingService.instance.socket!;
  //--livekit--
  String livekitUrl = "wss://p2p-test-omq0i7wx.livekit.cloud";
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool isCloseVideo = false;
  bool isMuteVoice = false;
  Timer? _timer;
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  MediaStream? onLocalStream;
  MediaStream? onRemoteStream;
  ConnectionState? connectionState;
  //--livekit-end-
  List<Recording> recordings = [];
  List<String> translations = [];
  late VadHandler _vadHandler;
  bool isListening = false;
  bool isSpeaking = false;
  bool isPaused = false;
  late VadSettings settings;
  int _chunkCounter = 0;

  // Custom audio stream provider
  CustomAudioStreamProvider? _customAudioProvider;
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  @override
  void initState() {
    super.initState();
    settings = VadSettings();
    _initializeVad();
    initializeLivekit();
    socketInit();
    _mPlayer!.openPlayer().then((value) {
      debugPrint("🔥 Flutter sound player is initialized");
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  socketInit() {
    _socket.on("playVoice", (data) async {
      debugPrint("✅ Voice received");
      final Uint8List pcmBytes = base64Decode(data["voice"]);
      await _mPlayer?.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 16000,
        interleaved: true,
        bufferSize: 1024,
        onBufferUnderlow: () => debugPrint("🔥 Buffer underflow!"),
      );
      _mPlayer?.uint8ListSink?.add(pcmBytes);
    });
    _socket.on("sttResult", (data) {
      if (mounted) {
        setState(() {
          translations.add(data["translated"]);
        });
      }
      _scrollToBottom();
    });
  }

  //-------------LIVEKIT----------------
  Future<void> initializeLivekit() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await connect(url: livekitUrl, token: widget.liveKitToken);
  }

  Future<void> disposeLivekit() async {
    await _listener?.dispose();
    await _room?.disconnect();
    localRenderer.dispose();
    remoteRenderer.dispose();
  }

  //-------------LIVEKIT-END----------
  Future<void> connect({required String url, required String token}) async {
    final room = Room();
    await room.connect(
      url,
      token,
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    _room = room;
    _listener = _room!.createListener();

    // Publish Local Tracks
    await _room!.localParticipant?.setMicrophoneEnabled(false);
    await _room!.localParticipant?.setCameraEnabled(true);

    //  For Local Tracks, binding MediaStream is often sufficient.
    for (final pub in _room!.localParticipant!.trackPublications.values) {
      if (pub.track is LocalVideoTrack) {
        final track = pub.track as LocalVideoTrack;
        localRenderer.srcObject = track.mediaStream;
        onLocalStream = track.mediaStream;
        break;
      }
    }

    // This runs immediately after connecting to find tracks already in the room.
    for (final participant in _room!.remoteParticipants.values) {
      for (final trackPublication in participant.trackPublications.values) {
        if (trackPublication.track is RemoteVideoTrack) {
          final track = trackPublication.track as RemoteVideoTrack;

          remoteRenderer.srcObject = track.mediaStream;
          onRemoteStream = track.mediaStream;
          return;
        }
      }
    }
    // ----------------------------------------------------------------------
    //for future participants joining the room.
    _listener!.on<TrackSubscribedEvent>((event) {
      if (event.track is RemoteVideoTrack) {
        final track = event.track as RemoteVideoTrack;
        remoteRenderer.srcObject = track.mediaStream;
        onRemoteStream = track.mediaStream;
      }
    });

    // Connection state
    _listener!.on<ParticipantDisconnectedEvent>((event) {
      debugPrint(
        'Remote Participant Disconnected: ${event.participant.identity}',
      );

      remoteRenderer.srcObject = null;
      connectionState = ConnectionState.disconnected;
    });

    _listener!.on<RoomDisconnectedEvent>((event) {
      connectionState = _room!.connectionState;
    });
    if (mounted) {
      setState(() {});
    }
  }

  //-----------------VAD--------------
  void _initializeVad() {
    _vadHandler = VadHandler.create(isDebug: true);
    _setupVadHandler();
  }

  void startListening() async {
    _chunkCounter = 0; // Reset chunk counter for new session

    // Initialize and start custom audio provider if needed
    Stream<Uint8List>? customAudioStream;
    if (settings.useCustomAudioStream) {
      try {
        _customAudioProvider = CustomAudioStreamProvider();
        await _customAudioProvider!.initialize();
        await _customAudioProvider!.startRecording();
        customAudioStream = _customAudioProvider!.audioStream;
      } catch (e) {
        // Fall back to built-in recorder
        customAudioStream = null;
      }
    }

    await _vadHandler.startListening(
      frameSamples: settings.frameSamples,
      minSpeechFrames: settings.minSpeechFrames,
      preSpeechPadFrames: settings.preSpeechPadFrames,
      redemptionFrames: settings.redemptionFrames,
      endSpeechPadFrames: settings.endSpeechPadFrames,
      positiveSpeechThreshold: settings.positiveSpeechThreshold,
      negativeSpeechThreshold: settings.negativeSpeechThreshold,
      submitUserSpeechOnPause: settings.submitUserSpeechOnPause,
      model: settings.modelString,
      numFramesToEmit:
          settings.enableChunkEmission ? settings.numFramesToEmit : 0,
      audioStream: customAudioStream, // Pass custom stream if available
      recordConfig: RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        bitRate: 16,
        numChannels: 1,
        echoCancel: true,
        autoGain: true,
        noiseSuppress: true,
        androidConfig: const AndroidRecordConfig(
          speakerphone: true,
          audioSource: AndroidAudioSource.voiceCommunication,
          audioManagerMode: AudioManagerMode.modeInCommunication,
        ),
        iosConfig: IosRecordConfig(
          categoryOptions: const [
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetooth,
            IosAudioCategoryOption.allowBluetoothA2DP,
          ],
          // When using custom audio stream, that provider manages the session
          manageAudioSession: customAudioStream == null,
        ),
      ),
      // baseAssetPath: '/assets/', // Alternative to using the CDN (see README.md)
      // onnxWASMBasePath: '/assets/', // Alternative to using the CDN (see README.md)
    );
    if (mounted) {
      setState(() {
        isListening = true;
        isPaused = false;
      });
    }
  }

  Future<void> _stopListening() async {
    await _vadHandler.stopListening();

    // Clean up custom audio provider if it was used
    if (_customAudioProvider != null) {
      await _customAudioProvider!.dispose();
      _customAudioProvider = null;
    }

    if (mounted) {
      setState(() {
        isListening = false;
        isPaused = false;
      });
    }
  }

  void _setupVadHandler() {
    _vadHandler.onSpeechStart.listen((_) async {
      if (mounted) {
        setState(() {
          isSpeaking = true;
          recordings.add(Recording(
            samples: [],
            type: RecordingType.speechStart,
          ));
        });
      }
      debugPrint('🔥 Speech detected: ${recordings.length}');
    });

    _vadHandler.onRealSpeechStart.listen((_) {
      if (mounted) {
        setState(() {
          recordings.add(Recording(
            samples: [],
            type: RecordingType.realSpeechStart,
          ));
        });
      }
      debugPrint('🔥 Real speech start detected: ${recordings.length}');
    });

    _vadHandler.onSpeechEnd.listen((List<double> samples) async {
      if (mounted) {
        isSpeaking = false;
        setState(() {
          recordings.add(Recording(
            samples: samples,
            type: RecordingType.speechEnd,
          ));
        });
      }
      if (!isMuteVoice) {
        SignallingService.sendVoiceToServer(samples, widget.partnerId, _socket);
        SignallingService.sendAudioToServer(
            samples, widget.language, widget.partnerId, _socket);
      }

      debugPrint('🔥 Speech ended, recording added. ${samples.length} samples');
    });

    _vadHandler.onFrameProcessed.listen((frameData) {
      // final isSpeech = frameData.isSpeech;
      // final notSpeech = frameData.notSpeech;
      // final firstFiveSamples = frameData.frame.length >= 5
      //     ? frameData.frame.sublist(0, 5)
      //     : frameData.frame;

      // debugPrint(
      //     'Frame processed - isSpeech: $isSpeech, notSpeech: $notSpeech');
      // debugPrint('First few audio samples: $firstFiveSamples');
    });

    _vadHandler.onVADMisfire.listen((_) {
      if (mounted) {
        setState(() {
          isSpeaking = false;
          recordings.add(Recording(type: RecordingType.misfire));
        });
      }
      debugPrint('🔥 VAD misfire detected.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Voice error, speak gain!"),
        ),
      );
    });

    _vadHandler.onError.listen((String message) {
      if (mounted) {
        setState(() {
          isSpeaking = false;
          recordings.add(Recording(type: RecordingType.error));
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Voice error, speak gain!"),
          ),
        );
      }
      debugPrint('🔥 Error: $message');
    });

    _vadHandler.onEmitChunk.listen((chunkData) {
      if (settings.enableChunkEmission) {
        if (mounted) {
          setState(() {
            isSpeaking = false;
            recordings.add(Recording(
              samples: chunkData.samples,
              type: RecordingType.chunk,
              chunkIndex: _chunkCounter++,
              isFinal: chunkData.isFinal,
            ));
          });
        }
        debugPrint(
            '🔥 Audio chunk emitted #$_chunkCounter (${chunkData.samples.length} samples)${chunkData.isFinal ? ' [FINAL]' : ''}');
      }
    });
    startSpeechDetecting();
  }

  Future<void> startSpeechDetecting() async {
    startListening();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!isSpeaking) {
        debugPrint("🔥Stop->Start again...");
        _stopListening().then((_) => startListening());
      } else {
        debugPrint("🔥Timer finished...");
      }
    });
  }

  //-----------------VAD-END-------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top half: Video section
            Expanded(
              flex: 1,
              child: Container(
                color: Colors.black,
                child: Row(
                  children: [
                    // Remote video
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Builder(
                          builder: (context) {
                            if (remoteRenderer.srcObject == null) {
                              return _infoText("Waiting for participant...");
                            } else {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: RTCVideoView(
                                  remoteRenderer,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                    // Local video
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Builder(
                            builder: (context) {
                              final videoTrack = localRenderer.srcObject
                                  ?.getVideoTracks()
                                  .first;

                              if (localRenderer.srcObject == null) {
                                return _infoText("Waiting for participant...");
                              } else if (videoTrack == null ||
                                  !videoTrack.enabled) {
                                return _infoText("Camera is off 🚫");
                              } else {
                                return RTCVideoView(
                                  localRenderer,
                                  mirror: true,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Subtitles history
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: translations.length,
                itemBuilder: (_, index) {
                  final messageNumber = index + 1;
                  final message = translations[index];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Number badge
                        Container(
                          margin: const EdgeInsets.only(
                            right: 8,
                            top: 2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$messageNumber',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Chat bubble
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(
                                16,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.03,
                                  ),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              message,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CallControls(
                isMuteVoice: isMuteVoice,
                onPressedVoice: () {
                  if (mounted) {
                    setState(() {
                      isMuteVoice = !isMuteVoice;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _socket.emit("stopSTT");
    _timer?.cancel();
    if (isListening) {
      _vadHandler.stopListening();
    }
    _vadHandler.dispose();
    _customAudioProvider?.dispose();
    disposeLivekit();
    stopPlayer();
    _mPlayer!.closePlayer();
    _mPlayer = null;
    super.dispose();
  }

  Future<void> stopPlayer() async {
    if (_mPlayer != null) {
      await _mPlayer!.stopPlayer();
    }
  }

  Widget _infoText(String text) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Colors.black,
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
