library motion_detection;

import 'dart:developer';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:easy_isolate/easy_isolate.dart';
import 'package:image/image.dart';
import 'package:motion_detection/utils/converters.dart';

class PayloadWithCameraImage {
  final Image? prev;
  final CameraImage current;

  PayloadWithCameraImage(
    this.current, [
    this.prev,
  ]);
}

class PayloadWithImages {
  final Image? prev;
  final Image current;
  final List<int>? bytes;
  final DetectionData? detectionData;

  PayloadWithImages(
    this.current, [
    this.prev,
    this.bytes,
    this.detectionData,
  ]);
}

class DetectionData {
  final Image diffImage;
  final int pixCount;
  final int whiteCount;

  DetectionData(this.diffImage, this.pixCount, this.whiteCount);
}

class MotionDetector {
  final worker = Worker();

  int resetCounter = 0;

  Image? lastImage;

  bool _processing = false;

  Function(Uint8List bytes)? _onSet;

  Future<void> init() async {
    await worker.init(
      _inMain,
      _inIsolate,
      errorHandler: print,
    );
  }

  static DetectionData _detect(Image image, Image lastImage) {
    final threshold = 10;
    final currentImage = grayscale(image);
    lastImage = grayscale(lastImage);

    Image diffImage = Image(currentImage.width, currentImage.height);
    int count = 0;
    int whiteCount = 0;
    for (var x = 0; x < currentImage.width; x++) {
      for (var y = 0; y < currentImage.height; y++) {
        count++;
        final currentImagePixel = currentImage.getPixel(x, y);
        final lastImagePixel = lastImage.getPixel(x, y);

        final a = 255;
        final b = getBlue(currentImagePixel) - getBlue(lastImagePixel);
        final g = getGreen(currentImagePixel) - getGreen(lastImagePixel);
        final r = getRed(currentImagePixel) - getRed(lastImagePixel);

        final lum = getLuminance(Color.fromRgba(r.abs(), g.abs(), b.abs(), a));
        if (lum > threshold) {
          diffImage.setPixel(x, y, 0xFFFFFFFF);
          whiteCount++;
        } else {
          diffImage.setPixel(x, y, 0xFF000000);
        }
      }
    }

    return DetectionData(copyRotate(diffImage, 90), count, whiteCount);
  }

  void onGettingDiff(Function(Uint8List bytes) onSet) {
    _onSet = onSet;
  }

  void _inMain(dynamic data, SendPort senderPort) {
    if (data is PayloadWithImages) {
      _processing = false;
      if (lastImage == null) {
        lastImage = data.current;
        return;
      }

      resetCounter++;

      if (_onSet != null && data.bytes != null) {
        if (data.detectionData != null) {
          print(
              "${(data.detectionData!.whiteCount / data.detectionData!.pixCount) * 100} %");
          log("""
          white: ${data.detectionData!.whiteCount}
          black: ${data.detectionData!.pixCount - data.detectionData!.whiteCount}
          total: ${data.detectionData!.pixCount}
          \n
          """);
        }
        _onSet!(data.bytes as Uint8List);
      }
    }

    if (lastImage != null) {
      lastImage = null;
      resetCounter = 0;
    }
  }

  static _inIsolate(
      dynamic data, SendPort recieverPort, SendErrorFunction sendError) async {
    if (data is PayloadWithCameraImage) {
      final image = ImageUtils.convertCameraImage(data.current);

      if (data.prev == null) {
        recieverPort.send(PayloadWithImages(image!));
        return;
      }

      final processed = _detect(image!, data.prev!);

      final png = PngEncoder().encodeImage(processed.diffImage);

      recieverPort.send(
          PayloadWithImages(processed.diffImage, data.prev!, png, processed));
    }
  }

  onLatestImageAvailable(CameraImage cameraImage) async {
    if (_processing) return;
    _processing = true;
    worker.sendMessage(PayloadWithCameraImage(cameraImage, lastImage));
  }

  dispose() {
    worker.dispose();
  }
}
