import 'dart:convert';
import 'dart:math';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vad_example/pages/vad_manager.dart';

import '../signalling.dart';

enum Language { en, my }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? liveKitToken;
  Language _selectedLanguage = Language.en;
  final String selfCallerID =
      Random().nextInt(999999).toString().padLeft(6, '0');
  final remoteCallerIdTextEditingController = TextEditingController();

  String? livekitToken;
  String livekitUrl = "wss://p2p-test-omq0i7wx.livekit.cloud";
  String websocketUrl =
      "https://p2p-live-translate-backend-39445099784.europe-west1.run.app"; /* "http://192.168.1.33:8080"; */
  String tokenUrl =
      "https://p2p-live-translate-backend-39445099784.europe-west1.run.app/getToken";

  Future<String?> fetchToken(String identity) async {
    final response = await http.post(
      Uri.parse(
        tokenUrl,
      ),
      body: jsonEncode({"identity": identity, "roomName": "roomName"}),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode == 200) {
      debugPrint("🔥. TOKEN received for room");
      return jsonDecode(response.body)["token"];
    } else {
      debugPrint("❌ Failed to fetch token: ${response.body}");
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    fetchToken(selfCallerID).then((v) {
      if (mounted) {
        setState(() {
          liveKitToken = v;
        });
      }
    });
    SignallingService.instance.init(
      websocketUrl: websocketUrl,
      selfCallerID: selfCallerID,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.center,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Video Call Icon and Title
                    const Column(
                      children: [
                        Icon(
                          Icons.videocam_outlined,
                          color: Colors.blue,
                          size: 48,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Live Translation',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: DropdownButtonFormField<Language>(
                        value: _selectedLanguage,
                        decoration: InputDecoration(
                          labelText: "Your Native Language",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: Language.en,
                            child: Text("🇬🇧  English"),
                          ),
                          DropdownMenuItem(
                            value: Language.my,
                            child: Text("🇲🇲  Myanmar"),
                          ),
                        ],
                        onChanged: (Language? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedLanguage = newValue;
                            });
                          }
                        },
                      ),
                    ),

                    const SizedBox(height: 10),

                    const SizedBox(height: 12),
                    TextField(
                      readOnly: true,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: "Your ID",
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: selfCallerID,
                        hintStyle: const TextStyle(color: Colors.white),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: remoteCallerIdTextEditingController,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: "Enter  Partner ID",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Start Meeting Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        "Start Meeting Now",
                        style: TextStyle(fontSize: 16),
                      ),
                      onPressed: () async {
                        final roomName =
                            remoteCallerIdTextEditingController.text.trim();
                        if (liveKitToken?.isEmpty == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Livekit token error..."),
                            ),
                          );
                          return;
                        }
                        if (roomName.isEmpty) {
                          // Show error/snackbar
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please enter a Partner ID."),
                            ),
                          );
                          return;
                        }

                        // Fetch token for the dynamic room
                        /*  final token = await fetchToken(
                          selfCallerID,
                          roomName,
                        ); */

                        /* if (token != null && mounted) {
                          // Join the LiveKit room
                          _joinCall(
                            context: context,
                            roomName: roomName,
                            selectedLanguage: _selectedLanguage,
                            token: token,
                          );
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Failed to get LiveKit token."),
                            ),
                          );
                        } */
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => VadManager(
                                    liveKitToken: liveKitToken ?? "",
                                    partnerId:
                                        remoteCallerIdTextEditingController
                                            .text,
                                    language: _selectedLanguage == Language.en
                                        ? "en-US"
                                        : "my-MM",
                                  )),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
