import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageUtils {
  static Uint8List convertJpegToNV21(Uint8List jpegBytes, int width, int height) {
    try {
      // Decode JPEG
      final image = img.decodeImage(jpegBytes)!;
      
      // Resize if needed (match your camera resolution)
      final resized = img.copyResize(image, width: width, height: height);
      
      // Convert to NV21
      final nv21 = Uint8List(width * height * 3 ~/ 2);
      int yIndex = 0;
      int uvIndex = width * height;
      
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = resized.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();
          
          // Convert RGB to YUV
          final yValue = (0.299 * r + 0.587 * g + 0.114 * b).clamp(0, 255).toInt();
          final uValue = (-0.169 * r - 0.331 * g + 0.5 * b + 128).clamp(0, 255).toInt();
          final vValue = (0.5 * r - 0.419 * g - 0.081 * b + 128).clamp(0, 255).toInt();
          
          // Fill Y plane
          nv21[yIndex++] = yValue;
          
          // Fill UV plane (NV21 = Y + VU interleaved)
          if (y % 2 == 0 && x % 2 == 0) {
            nv21[uvIndex++] = vValue;
            nv21[uvIndex++] = uValue;
          }
        }
      }
      return nv21;
    } catch (e) {
      throw Exception('JPEG to NV21 conversion failed: ${e.toString()}');
    }
  }
}