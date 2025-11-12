import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart';

class SignallingService {
  // instance of Socket
  Socket? socket;

  SignallingService._();
  static final instance = SignallingService._();

  init({required String websocketUrl, required String selfCallerID}) {
    // init Socket
    socket = io(websocketUrl, {
      "transports": ['websocket'],
      "query": {"callerId": selfCallerID},
    });

    // listen onConnect event
    socket!.onConnect((data) {
      log("Socket connected !!");
    });

    // listen onConnectError event
    socket!.onConnectError((data) {
      log("Connect Error $data");
    });

    // connect socket
    socket!.connect();
  }

  static Future<void> sendVoiceToServer(
    List<double> samples,
    String partnerId,
    Socket socket,
  ) async {
    try {
      final Uint8List pcmBytes = _floatListToPcm16(samples);
      final String base64Audio = base64Encode(pcmBytes);

      // ---------------------------------------------------------------
      // c) Build the payload (exactly what your Node.js expects)
      // ---------------------------------------------------------------
      final Map<String, dynamic> payload = {
        'to': partnerId, // the recipient socket.id
        'voice': base64Audio,
        "format": "LINEAR16",
      };

      // ---------------------------------------------------------------
      // d) Emit via Socket.IO
      // ---------------------------------------------------------------
      socket.emit('voice', payload);

      debugPrint('✅ Sent voice to server');
    } catch (e, st) {
      debugPrint('❌ Failed to send audio: $e\n$st');
    }
  }

  static Future<void> sendAudioToServer(
    List<double> samples,
    String language,
    String partnerId,
    Socket socket,
  ) async {
    try {
      // ---------------------------------------------------------------
      // a) Convert List<double> (normalized -1..1) → Int16 PCM
      // ---------------------------------------------------------------
      const int sampleRate = 16000; // <-- match your VAD config!
      const int channels = 1; // mono

      final Uint8List pcmBytes = _floatListToPcm16(samples);

      // ---------------------------------------------------------------
      // b) Base64 encode
      // ---------------------------------------------------------------
      final String base64Audio = base64Encode(pcmBytes);

      // ---------------------------------------------------------------
      // c) Build the payload (exactly what your Node.js expects)
      // ---------------------------------------------------------------
      final Map<String, dynamic> payload = {
        'language': language, // e.g. "my-MM" or "en-US"
        'to': partnerId, // the recipient socket.id
        'audio': base64Audio,
        "format": "LINEAR16",
      };

      // ---------------------------------------------------------------
      // d) Emit via Socket.IO
      // ---------------------------------------------------------------
      socket.emit('audioRecording', payload);

      debugPrint('✅ Sent audio (${pcmBytes.length} bytes) to server');
    } catch (e, st) {
      debugPrint('❌ Failed to send audio: $e\n$st');
    }
  }

  /// -------------------------------------------------------------------
  /// 3. Convert normalized floats (-1..1) → 16-bit PCM (little-endian)
  /// -------------------------------------------------------------------
  static Uint8List _floatListToPcm16(List<double> floats) {
    final ByteData byteData = ByteData(floats.length * 2);
    int offset = 0;

    for (final double sample in floats) {
      // Clamp to -1..1
      final double clamped = sample.clamp(-1.0, 1.0);
      // Scale to -32768..32767
      final int intSample = (clamped * 32767).round();
      byteData.setInt16(offset, intSample, Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }
}
