import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math';

class FaceEmbeddingExtractor {
  final FaceDetector _faceDetector;

  FaceEmbeddingExtractor() : _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableContours: true,
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
    ),
  );

  Future<List<double>?> extractEmbedding(InputImage inputImage) async {
    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) return null;
      return _createFeatureVector(faces.first);
    } catch (e) {
      print('Error getting embeddings: $e');
      return null;
    }
  }

  List<double> _normalizeVector(List<double> vector) {
    final norm = sqrt(vector.map((x) => x * x).reduce((a, b) => a + b));
    return norm > 0 ? vector.map((x) => x / norm).toList() : vector;
  }

  List<double> _createFeatureVector(Face face) {
    // Basic face measurements
    final faceWidth = face.boundingBox.width.toDouble();
    final faceHeight = face.boundingBox.height.toDouble();
    final faceDiagonal = sqrt(pow(faceWidth, 2) + pow(faceHeight, 2));

    // Get all supported landmarks (using Point<int> from dart:math)
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
    final leftCheek = face.landmarks[FaceLandmarkType.leftCheek]?.position;
    final rightCheek = face.landmarks[FaceLandmarkType.rightCheek]?.position;
    final leftEar = face.landmarks[FaceLandmarkType.leftEar]?.position;
    final rightEar = face.landmarks[FaceLandmarkType.rightEar]?.position;

    // Initialize feature vector
    final vector = <double>[
      // Head orientation
      (face.headEulerAngleY ?? 0.0) / 180.0,
      (face.headEulerAngleZ ?? 0.0) / 180.0,
      
      // Eye states
      face.leftEyeOpenProbability ?? 0.0,
      face.rightEyeOpenProbability ?? 0.0,
      
      // Facial expression
      face.smilingProbability ?? 0.0,
    ];

    // Helper to add Point<int> landmark positions
    void _addLandmarkPosition(Point<int>? position) {
      if (position != null) {
        vector.add((position.x - face.boundingBox.left) / faceWidth);
        vector.add((position.y - face.boundingBox.top) / faceHeight);
      } else {
        vector.addAll([0.0, 0.0]);
      }
    }

    // Add landmark positions
    _addLandmarkPosition(leftEye);
    _addLandmarkPosition(rightEye);
    _addLandmarkPosition(noseBase);
    _addLandmarkPosition(leftMouth);
    _addLandmarkPosition(rightMouth);
    _addLandmarkPosition(leftCheek);
    _addLandmarkPosition(rightCheek);
    _addLandmarkPosition(leftEar);
    _addLandmarkPosition(rightEar);

    // Helper to calculate distances between points
    double _calculateNormalizedDistance(Point<int>? a, Point<int>? b) {
      if (a == null || b == null) return 0.0;
      return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)) / faceDiagonal;
    }

    // Add normalized distances
    vector.add(_calculateNormalizedDistance(leftEye, rightEye));
    vector.add(_calculateNormalizedDistance(leftEye, noseBase));
    vector.add(_calculateNormalizedDistance(rightEye, noseBase));
    vector.add(_calculateNormalizedDistance(noseBase, leftMouth));
    vector.add(_calculateNormalizedDistance(leftEye, leftMouth));
    vector.add(_calculateNormalizedDistance(leftCheek, rightCheek));
    vector.add(_calculateNormalizedDistance(leftEar, leftEye));

    // Add symmetry features
    if (leftEye != null && rightEye != null) {
      vector.add((leftEye.y - rightEye.y).abs() / faceHeight); // Vertical alignment
    } else {
      vector.add(0.0);
    }

    if (noseBase != null && leftMouth != null && rightMouth != null) {
      final leftDist = noseBase.x - leftMouth.x;
      final rightDist = rightMouth.x - noseBase.x;
      vector.add((leftDist - rightDist).abs() / faceWidth); // Horizontal alignment
    } else {
      vector.add(0.0);
    }

    return _normalizeVector(vector);
  }

  void dispose() {
    _faceDetector.close();
  }
}