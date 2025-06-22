import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false,
      enableClassification: false,
      enableTracking: true,
      minFaceSize: 0.2,
    ),
  );

  Future<List<Face>> detectFacesFromImage(InputImage image) async {
    try {
      return await _faceDetector.processImage(image);
    } catch (e) {
      print('Face detection error: $e');
      return [];
    }
  }

  void dispose() => _faceDetector.close();
}