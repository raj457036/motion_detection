import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:motion_detection/motion_detection.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  cameras = await availableCameras();
  runApp(CameraApp());
}

class CameraApp extends StatefulWidget {
  @override
  _CameraAppState createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> with WidgetsBindingObserver {
  CameraController? controller;
  final MotionDetector detector = MotionDetector();

  double threshold = 0.1;

  void _callback() {
    print('call back function was called');
  }

  @override
  void initState() {
    super.initState();
    _ambiguate(WidgetsBinding.instance)?.addObserver(this);
    controller = CameraController(cameras[0], ResolutionPreset.low);
    controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
      detector.init(_callback).then((_) {
        controller?.startImageStream(
            (image) => detector.onLatestImageAvailable(image, threshold));
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed before we got the chance to initialize.
    if (controller == null || !(controller?.value.isInitialized ?? false)) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (controller != null) {
        onNewCameraSelected(controller!.description);
      }
    }
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller!.dispose();
    }

    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.low,
      enableAudio: true,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) setState(() {});
      if (cameraController.value.hasError) {
        print('Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();
    } on CameraException catch (e) {
      print(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ambiguate(WidgetsBinding.instance)?.removeObserver(this);
    controller?.dispose();
    detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!(controller?.value.isInitialized ?? false) || controller == null) {
      return Container();
    }
    return MaterialApp(
      home: Stack(
        children: [
          Positioned.fill(
            child: CameraPreview(controller!),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              margin: const EdgeInsets.all(15.0),
              width: 240,
              height: 360,
              child: DetectorPreview(detector: detector),
            ),
          ),
          // comment this line only for testing for increasing threshold
          Positioned(
            bottom: 20,
            right: 20,
            child: GestureDetector(
              onTap: () {
                threshold += 0.1;
              },
              child: Container(
                width: 100,
                height: 100,
                color: Colors.black,
              ),
            ),
          ),
          // till here
        ],
      ),
    );
  }
}

class DetectorPreview extends StatefulWidget {
  final MotionDetector detector;
  const DetectorPreview({Key? key, required this.detector}) : super(key: key);

  @override
  _DetectorPreviewState createState() => _DetectorPreviewState();
}

class _DetectorPreviewState extends State<DetectorPreview> {
  Uint8List? _bytes;
  double _detected = 0;

  @override
  void initState() {
    super.initState();

    widget.detector.onGettingDiff(updateImage);
  }

  updateImage(Uint8List bytes, double detected) {
    setState(() {
      _bytes = bytes;
      _detected = detected;
    });

    // print(_detected);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null)
      return Material(
        child: Stack(
          children: [
            Positioned.fill(
                child: Image.memory(
              _bytes!,
              gaplessPlayback: true,
            )),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Text(
                "Motion $_detected",
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 18.0,
                ),
                textAlign: TextAlign.center,
              ),
            )
          ],
        ),
      );
    return Container();
  }
}

T? _ambiguate<T>(T? value) => value;
