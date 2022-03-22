library motion_detection;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:easy_isolate/easy_isolate.dart';
import 'package:image/image.dart';
import 'package:motion_detection/utils/converters.dart';

class PayloadWithCameraImage {
  final Image? prev;
  final CameraImage current;
  final double threshold;

  PayloadWithCameraImage(
    this.current,
    this.threshold, [
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
  final Image morphImage;
  final int pixCount;
  final int whiteCount;

  DetectionData(
      this.diffImage, this.morphImage, this.pixCount, this.whiteCount);
}

class MotionDetector {
  final worker = Worker();

  Image? lastImage;

  bool _processing = false;

  Function(Uint8List bytes, double detected)? _onSet;

  late void Function() _callBackFunction;

  bool _isMotionIsActive = false;

  Future<void> init(void Function() _callBackFunction) async {
    this._callBackFunction = _callBackFunction;
    await worker.init(
      _inMain,
      _inIsolate,
      errorHandler: print,
    );
  }

  static DetectionData _detect(
      Image currentImage, Image lastImage, double threshold) {
    print('threshold value: ' + threshold.toString());
    Image diffImage = Image(currentImage.width, currentImage.height);
    // Image morphBg = Image(currentImage.width, currentImage.height);
    int count = 0;
    int whiteCount = 0;
    for (var x = 0; x < currentImage.width; x++) {
      for (var y = 0; y < currentImage.height; y++) {
        count++;
        final currentImagePixel = currentImage.getPixel(x, y);
        final lastImagePixel = lastImage.getPixel(x, y);
        final b = getBlue(currentImagePixel) - getBlue(lastImagePixel);
        final g = getGreen(currentImagePixel) - getGreen(lastImagePixel);
        final r = getRed(currentImagePixel) - getRed(lastImagePixel);

        final lum = getLuminanceRgb(r, g, b) / 255;
        if (lum > threshold) {
          diffImage.setPixel(x, y, 0xFFFFFFFF);
          whiteCount++;
        } else {
          diffImage.setPixel(x, y, 0xFF000000);
        }

        // final morphColor = 0.75 * lastImagePixel + 0.25 * currentImagePixel;
        // final morphColor = currentImagePixel;

        // morphBg.setPixel(x, y, morphColor.toInt());
      }
    }

    return DetectionData(
        copyRotate(diffImage, 90), currentImage, count, whiteCount);
  }

  void onGettingDiff(Function(Uint8List bytes, double detected) onSet) {
    _onSet = onSet;
  }

  void _inMain(dynamic data, SendPort senderPort) {
    if (data is PayloadWithImages) {
      _processing = false;
      if (lastImage == null) {
        lastImage = data.current;
        return;
      }

      if (_onSet != null && data.bytes != null) {
        double detected = 0;

        if (data.detectionData != null) {
          // log("white : ${data.detectionData!.whiteCount}");
          // log("total : ${data.detectionData!.pixCount}");
          detected =
              (data.detectionData!.whiteCount / data.detectionData!.pixCount) *
                  1000;
        }

        final motionDetectedValue = detected.roundToDouble();

        _onSet!(data.bytes as Uint8List, motionDetectedValue);

        if (motionDetectedValue > 20 && !_isMotionIsActive) {
          _callBackFunction();
          _isMotionIsActive = true;
        } else if (motionDetectedValue == 0 && _isMotionIsActive) {
          _isMotionIsActive = false;
        }
      }

      lastImage = data.prev;
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

      final processed = _detect(image!, data.prev!, data.threshold);

      final png = PngEncoder().encodeImage(processed.diffImage);

      recieverPort.send(PayloadWithImages(
          processed.diffImage, processed.morphImage, png, processed));
    }
  }

  onLatestImageAvailable(CameraImage cameraImage, double? threshold) async {
    if (_processing) return;
    if (threshold == null) threshold = 0.1;
    _processing = true;
    worker
        .sendMessage(PayloadWithCameraImage(cameraImage, threshold, lastImage));
  }

  dispose() {
    worker.dispose();
  }
}
