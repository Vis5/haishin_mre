import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:haishin_kit/audio_settings.dart';
import 'package:haishin_kit/audio_source.dart';
import 'package:haishin_kit/net_stream_drawable_texture.dart';
import 'package:haishin_kit/rtmp_connection.dart';
import 'package:haishin_kit/rtmp_stream.dart';
import 'package:haishin_kit/video_settings.dart';
import 'package:haishin_kit/video_source.dart';
import 'package:haishin_mre/server_settings.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({
    Key? key,
  }) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  RtmpConnection? _connection;
  RtmpStream? _stream;
  CameraPosition currentPosition = CameraPosition.back;

  DateTime? _lastButtonPress;
  String _liveDuration = "00:00:00";
  bool flashLight = false;
  bool muteStatus = false;
  Timer? _ticker;
  bool _showStartButton = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      askPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Stack(
          children: <Widget>[
            if (_stream != null)
              GestureDetector(
                onTapDown: (_) => {},
                child: Container(
                  color: kDebugMode ? Colors.purple : Colors.black,
                  height: MediaQuery.of(context).size.height,
                  width: MediaQuery.of(context).size.width,
                  child: Transform.scale(
                    // scaleX: currentPosition == CameraPosition.front ? -1 : 1,
                    scaleX: 1,
                    child: NetStreamDrawableTexture(_stream),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.only(
                top: 48.0,
                left: 16.0,
                right: 16.0,
                bottom: 16.0,
              ),
              child: Wrap(
                children: <Widget>[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFff6c00),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(5.0),
                            bottomLeft: Radius.circular(5.0),
                          ),
                        ),
                        child: Text(
                          _liveDuration,
                        ),
                      ),
                      Expanded(
                        child: Container(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.switch_camera),
                        color: Colors.white,
                        onPressed: () async {
                          if (currentPosition == CameraPosition.front) {
                            currentPosition = CameraPosition.back;
                          } else {
                            currentPosition = CameraPosition.front;
                          }
                          _stream?.attachVideo(
                            VideoSource(position: currentPosition),
                          );
                          Future.delayed(
                            const Duration(milliseconds: 500),
                            () {
                              setState(() {});
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        onPressed: () async {
                          await _endLive();
                          dispose();
                        },
                      )
                    ],
                  ),
                ],
              ),
            ),
            if (_showStartButton)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: ButtonBar(
                    alignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: 200,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: _streamPublish,
                            child: const Text(
                              "Start",
                              style: TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // ),
      ),
    );
  }

  @override
  void dispose() {
    if (_ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
    // _stream?.dispose();
    // _connection?.dispose();
    super.dispose();
  }

  void askPermission() async {
    print("asking perm");
    await Permission.camera.request();
    PermissionStatus status = await Permission.camera.status;
    print("got camera perm $status");
    if (await Permission.camera.isPermanentlyDenied) {
      await openAppSettings();
      status = await Permission.camera.status;
    }
    if (status == PermissionStatus.denied) {
      await Permission.microphone.request();
      status = await Permission.camera.status;
    }
    if (status == PermissionStatus.denied) {
      Navigator.of(context).pop();
    }
    print("asking mic perm");
    await Permission.microphone.request();
    status = await Permission.microphone.status;
    print("got mic perm $status");
    if (await Permission.microphone.isPermanentlyDenied) {
      await openAppSettings();
      status = await Permission.microphone.status;
    }
    if (status == PermissionStatus.denied) {}
    initializePublisher();
  }

  Future<void> _startLive() async {
    if (_stream == null || _connection == null) {
      await initializePublisher();
    }
    print("starting controller");
    _connection?.connect(ServerSettings.mediaServerRTMP);
  }

  Future<void> initializePublisher() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth,
    ));

    // int _physWidth = window.physicalSize.width.round();
    // int _physHeight = window.physicalSize.height.round();
    RtmpConnection connection = await RtmpConnection.create();
    connection.eventChannel.receiveBroadcastStream().listen((event) {
      if (event["data"] != null) {
        print("Event code ${event['data']['code']}");
        switch (event["data"]["code"]) {
          case 'NetConnection.Connect.Success':
            break;
          case 'NetConnection.Connect.NetworkChange':
            break;
          case 'NetConnection.Connect.Closed':
            Future.wait([_endLive()]);
            break;
          default:
            break;
        }
      }
    });

    RtmpStream stream = await RtmpStream.create(connection);
    stream.audioSettings = AudioSettings(bitrate: 8 * 1000);
    int width = MediaQuery.of(context).size.width.toInt();
    int height = MediaQuery.of(context).size.height.toInt();
    int bitrate = 800000;
    if (Platform.isAndroid) {
      print("IS AND");
      width = MediaQuery.of(context).size.height * 13 ~/ 16;
      // bitrate = 320000;
      // bitrate = 6291456;
    }
    stream.videoSettings = VideoSettings(
      width: width,
      height: height,
      // height: 1080,
      bitrate: bitrate,
    );
    if (!muteStatus) {
      stream.attachAudio(AudioSource());
    }
    stream.attachVideo(VideoSource(position: currentPosition));

    stream.eventChannel.receiveBroadcastStream().listen((event) {
      print("to true $event");
      switch (event["data"]["code"]) {
        case "Exception 1":
          print("Setting camera exception to true");
          break;
      }
    });

    if (!mounted) return;

    setState(() {
      _connection = connection;
      _stream = stream;
    });
    // _startCountDown();
    _startLive();
  }

  void _streamPublish() {
    String? streamKey = "test";
    print("publishing with $streamKey");
    _stream?.publish(streamKey ?? "test");
    setState(() {
      _showStartButton = false;
    });
    _lastButtonPress = DateTime.now();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTimer(),
    );
    print("started");
  }

  void _updateTimer() {
    final duration =
        DateTime.now().difference(_lastButtonPress ?? DateTime.now());
    final newDuration = _formatDuration(duration);
    setState(() {
      _liveDuration = newDuration;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) {
      if (n >= 10) return "$n";
      return "0$n";
    }

    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _endLive() async {
    if (_ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
    print("disposing 1");
    await Future.wait([
      _stream!.attachAudio(null),
      _stream!.attachVideo(null),
    ]);
    print("disposing 2");
    await _stream?.close();
    // print("disposing 3");
    // await _stream?.dispose();
    print("disposing 4");
    _connection?.close();
    // print("disposing 5");
    // _connection?.dispose();
    print("disposing 6");
    _stream = null;
    _connection = null;
    Future.microtask(() {
      pop();
    });
    //}
  }

  void pop() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
