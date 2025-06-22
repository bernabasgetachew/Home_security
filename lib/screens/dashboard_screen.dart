import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:integrated_home/models/visitor_model.dart';
import 'package:integrated_home/services/database_service.dart';
import 'package:integrated_home/services/notification_handler.dart';  
import 'package:integrated_home/services/face_detector.dart';
import 'package:integrated_home/services/face_embedding_extractor.dart';
import 'package:integrated_home/services/notification_service.dart';
import 'package:flutter/foundation.dart';  // Add this line
import 'package:integrated_home/utils/image_utils.dart';
import 'package:integrated_home/widgets/navbar.dart';
import 'package:integrated_home/widgets/sidebar.dart';
import 'package:integrated_home/widgets/settings_sidebar.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:logging/logging.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';  
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';




class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FaceDetectorService _faceDetector = FaceDetectorService();
  final FaceEmbeddingExtractor _embeddingExtractor = FaceEmbeddingExtractor();
  
  bool _isModelLoading = false;
  final _uuid = Uuid();
  final _processingLock = Lock();
  bool _isProcessing = false;
  //bool _cameraInitialized = false;
  bool _detectorReady = true;
  bool _irSensorActive = false;
  bool _reedSensorActive = false;
  StreamSubscription? _irSensorSub;
  StreamSubscription? _reedSensorSub;
  final List<String> _processedFaceIds = [];
  DateTime _lastNotificationTime = DateTime.now();
  List<Face> _detectedFaces = [];
  bool _showStream = true;
  bool _doorState = false;
  
  DateTime? _lastProcessed;
  //StreamSubscription<CameraImage>? _cameraSubscription;
  final _logger = Logger('Dashboard');
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  //CameraController? _cameraController;
  final _frameSkipCounter = ValueNotifier<int>(0);
  static const _frameSkipRate = 2;
  bool _isDialogShowing = false;
  final Set<String> _processedFaces = {};
  late DatabaseService _dbService;
  InputImage? _currentInputImage;
  List<double>? _currentNormalizedEmbedding;
  Uint8List? _currentImage;
  String? _currentImageId;
  bool _imageLoading = false;
  // Add these constants at the top
 
 static const _kDoorOpenDuration = Duration(seconds: 5);
  
  @override
  void initState() {
    super.initState();
    _setupLogging();
    //_initializeCamera();
    _setupSensorListeners();
    NotificationHandler.setupFirestoreListeners();
    _initializeNotifications();
    _setupFirestoreListener();
  }

  void _setupFirestoreListener() {
  FirebaseFirestore.instance
      .collection('triggers')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .listen((snapshot) {
    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        _processNewTrigger(change.doc);
      }
    }
  });
}

  Future<void> _initializeNotifications() async {
  await NotificationService.initialize();
  
  // Android-specific initialization
  if (Platform.isAndroid) {
    // Set high priority for Android notifications
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,  // Show heads-up notification
      badge: true,  // Show badge
      sound: true,  // Play sound
    );
  }

  // Handle all messages (works for both Android/iOS)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      NotificationService.showNotification(
        message.notification!.title ?? 'Motion Alert',
        message.notification!.body ?? 'Visitor detected at your door',
      );
    }
  });

  // Handle background/terminated messages
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    // Optional: Navigate to specific screen when notification is tapped
    // _handleNotificationTap(message);
  });

  // Get initial message if app was terminated
  RemoteMessage? initialMessage = 
      await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    NotificationService.showNotification(
      initialMessage.notification?.title ?? 'Motion Alert',
      initialMessage.notification?.body ?? 'Visitor detected earlier',
    );
  }
}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dbService = Provider.of<DatabaseService>(context, listen: false);
  }

  void _setupSensorListeners() {
  final dbService = Provider.of<DatabaseService>(context, listen: false);

  _irSensorSub = dbService.getSensorStream('ir').listen(
    (data) {
      if (mounted) {
        setState(() => _irSensorActive = data['is_active']);
        if (data['is_active']) {
          NotificationService.showSensorNotification('ir', true);
        }
      }
    },
    onError: (error) => _logger.severe('IR sensor error', error)
  );

  _reedSensorSub = dbService.getSensorStream('reed').listen(
    (data) {
      if (mounted) {
        setState(() => _reedSensorActive = data['is_active']);
        NotificationService.showSensorNotification('reed', data['is_active']);
      }
    },
    onError: (error) => _logger.severe('Reed sensor error', error)
  );
}
  void _setupLogging() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      print('${record.level.name}: ${record.time}: ${record.message}');
      if (record.error != null) print('Error: ${record.error}');
      if (record.stackTrace != null) print('Stack: ${record.stackTrace}');
    });
  }

  
  Rect _transformBoundingBox(Rect boundingBox, Size imageSize, Size widgetSize) {
    final scaleX = widgetSize.width / imageSize.width;
    final scaleY = widgetSize.height / imageSize.height;
    final scale = min(scaleX, scaleY);

    final offsetX = (widgetSize.width - imageSize.width * scale) / 2;
    final offsetY = (widgetSize.height - imageSize.height * scale) / 2;

    return Rect.fromLTRB(
      boundingBox.left * scale + offsetX,
      boundingBox.top * scale + offsetY,
      boundingBox.right * scale + offsetX,
      boundingBox.bottom * scale + offsetY,
    );
  }

  Future<void> _processNewTrigger(DocumentSnapshot doc) async {
  if (_isProcessing || _imageLoading) return;

  setState(() => _imageLoading = true);

  try {
    final data = doc.data() as Map<String, dynamic>;
    final imageId = doc.id;
    final base64Image = (data['image'] as String?)?.replaceAll(RegExp(r'\s'), '');

    // Validate image before processing
    if (base64Image == null || imageId == _currentImageId || !base64Image.startsWith('/9j/')) {
      setState(() => _imageLoading = false);
      return;
    }

    final bytes = base64.decode(base64Image);
    
    // Update UI immediately with JPEG
    setState(() {
      _currentImage = bytes;
      _imageLoading = false;
      _currentImageId = imageId;
    });

    await _processingLock.synchronized(() async {
      _isProcessing = true;
      
      try {
        // Convert in isolate for better performance
        final nv21Bytes = await compute(
          (List<dynamic> params) => ImageUtils.convertJpegToNV21(
          params[0] as Uint8List, 
          params[1] as int, 
          params[2] as int
      ),
      [bytes, 640, 480]
  );

        final inputImage = InputImage.fromBytes(
          bytes: nv21Bytes,
          metadata: InputImageMetadata(
            size: const Size(640, 480),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: 640,
          ),
        );

        final faces = await _faceDetector.detectFacesFromImage(inputImage);
        if (!mounted) return;

        // Filter valid faces
        final validFaces = faces.where((face) {
          final box = face.boundingBox;
          return box.width > 100 && box.height > 100; // Minimum face size
        }).toList();

        setState(() => _detectedFaces = validFaces);

        if (validFaces.isNotEmpty) {
          final face = validFaces.first; 
          final embedding = await _embeddingExtractor.extractEmbedding(inputImage);

          if (embedding != null && embedding.isNotEmpty) {
            final normalized = _normalizeVector(embedding);
            final visitor = await _dbService.findSimilarVisitor(normalized);
            
            visitor != null 
                ? _handleKnownVisitor(visitor)
                : _handleNewVisitor(normalized);
          }
        }
      } catch (e) {
        _logger.severe('Face processing error', e);
      }
    });
  } catch (e, stack) {
    _logger.severe('Processing error', e, stack);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processing failed: ${e.toString().substring(0, 50)}'))
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _imageLoading = false;
      });
    }
  }
}
  void _handleKnownVisitor(Visitor visitor) async {
  if (!mounted || visitor.confidence < 0.7) return; // Confidence threshold

  final shouldOpen = visitor.listType == 'green';
  final dbService = Provider.of<DatabaseService>(context, listen: false);

  // Update visitor last seen
  await dbService.updateVisitorLastSeen(visitor.id!);

  // Show feedback immediately
  _showVisitorFeedback(
    isWelcome: shouldOpen,
    confidence: visitor.confidence,
  );

  if (shouldOpen) {
    await dbService.updateSensorState('reed', true);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) dbService.updateSensorState('reed', false);
    });
  }

  // Update UI state
  if (mounted) {
    setState(() {
      _doorState = shouldOpen;
      _showStream = visitor.listType != 'black';
    });
  }
}

  void _showVisitorFeedback({required bool isWelcome, required double confidence}) {
    final message = isWelcome
        ? 'Welcome back! (${(confidence * 100).toStringAsFixed(1)}% match)'
        : 'Restricted: Blacklisted visitor';

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(isWelcome ? Icons.verified : Icons.block, color: Colors.white),
          const SizedBox(width: 8),
          Text(message),
        ],
      ),
      backgroundColor: isWelcome ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _handleNewVisitor(List<double> embedding) async {
  if (!mounted || embedding.isEmpty) return;

  // Prevent multiple dialogs
  if (_isDialogShowing) return;
  _isDialogShowing = true;

  try {
    final listType = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Unrecognized Visitor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(_currentImage!, height: 150),
            const SizedBox(height: 20),
            const Text('How would you like to classify this visitor?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'black'),
            child: const Text('Block', style: TextStyle(color: Colors.red)),),
          TextButton(
            onPressed: () => Navigator.pop(context, 'green'),
            child: const Text('Allow', style: TextStyle(color: Colors.green)),),
        ],
      ),
    );

    if (listType == null || !mounted) return;

    final visitor = Visitor(
      id: 'visitor_${DateTime.now().millisecondsSinceEpoch}',
      faceId: 'face_${Uuid().v4()}',
      listType: listType,
      timestamp: DateTime.now().toIso8601String(),
      embedding: embedding,
      confidence: 1.0,
      
    );

    await _dbService.addVisitor(visitor);
    
    // Immediate feedback
    _showVisitorFeedback(
      isWelcome: listType == 'green',
      confidence: 1.0,
    );

    // Update door state if allowed
    if (listType == 'green') {
      await _dbService.updateSensorState('reed', true);
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _dbService.updateSensorState('reed', false);
      });
    }
  } finally {
    _isDialogShowing = false;
  }
}

  List<double> _normalizeVector(List<double> vector) {
    final norm = sqrt(vector.map((x) => x * x).reduce((a, b) => a + b));
    return norm > 0 ? vector.map((x) => x / norm).toList() : vector;
  }

  

Future<bool> _showVerificationDialog(Visitor visitor) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Verify Visitor (${(visitor.confidence * 100).toStringAsFixed(1)}% match)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Is this ${visitor.listType == 'green' ? 'an approved' : 'a restricted'} visitor?'),
          SizedBox(height: 20),
          if (visitor.timestamp != null) 
            Text('Last seen: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(visitor.timestamp!))}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('NO'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(visitor.listType == 'green' ? 'CONFIRM' : 'OVERRIDE'),
        ),
      ],
    ),
  ) ?? false;
}

  @override
  @mustCallSuper
  void dispose() {
    _isProcessing = true;
    _isDialogShowing = false;
    
    _faceDetector.dispose();
    _embeddingExtractor.dispose();
    _frameSkipCounter.dispose();
    _irSensorSub?.cancel();
    _reedSensorSub?.cancel();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewSize = MediaQuery.of(context).size;

    return Scaffold(
      key: _scaffoldKey,
      appBar: Navbar(scaffoldKey: _scaffoldKey),
      drawer: const Sidebar(),
      endDrawer: const SettingsSidebar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Smart Door System',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: _buildCameraView(previewSize),
          ),
          _buildControlPanel(),
        ],
      ),
    );
  }

 Widget _buildCameraView(Size previewSize) {
  if (_imageLoading) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Loading security feed...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  return Stack(
    fit: StackFit.expand,
    children: [
      if (_currentImage != null)
        Image.memory(_currentImage!, 
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      if (_currentImage == null && !_imageLoading)
        Center(
          child: Text(
            'Waiting for security feed...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ..._buildDetectionBoxes(),
      _buildProcessingIndicator(),
    ],
  );
}

  List<Widget> _buildDetectionBoxes() {
    if (_detectedFaces.isEmpty) return [];

    final imageSize = Size(640, 480); 
    final widgetSize = MediaQuery.of(context).size;
    return _detectedFaces.take(5).map((face) {
      final transformedBox = _transformBoundingBox(
        face.boundingBox,
        imageSize,
        widgetSize,
      );

      return Positioned(
        left: transformedBox.left,
        top: transformedBox.top,
        width: transformedBox.width,
        height: transformedBox.height,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(
              '${(face.headEulerAngleY?.toStringAsFixed(1) ?? '0')}°',
              style: const TextStyle(
                color: Colors.white,
                backgroundColor: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildProcessingIndicator() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              'Faces: ${_detectedFaces.length}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

 Widget _buildControlPanel() {
  final dbService = Provider.of<DatabaseService>(context, listen: false);
  
  return Padding(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      children: [
        // Sensor Status Indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // IR Sensor Status
            Column(
              children: [
                const Icon(Icons.motion_photos_on, size: 30),
                const Text('Motion Sensor'),
                StreamBuilder<Map<String, dynamic>>(
                  stream: dbService.getSensorStream('ir'),
                  builder: (context, snapshot) {
                    final is_active = snapshot.data?['is_active'] ?? false;
                    return Text(
                      is_active ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(
                        color: is_active ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ],
            ),
            // Door Sensor Status
            Column(
              children: [
                const Icon(Icons.door_sliding, size: 30),
                const Text('Door Sensor'),
                StreamBuilder<Map<String, dynamic>>(
                  stream: dbService.getSensorStream('reed'),
                  builder: (context, snapshot) {
                    final is_active = snapshot.data?['is_active'] ?? false;
                    return Text(
                      is_active ? 'OPEN' : 'CLOSED',
                      style: TextStyle(
                        color: is_active ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Door Control Button
        ElevatedButton(
          onPressed: () async {
            final newState = !_doorState;
            setState(() => _doorState = newState);
            await dbService.updateSensorState('reed', newState);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(newState ? 'Door unlocked' : 'Door locked')),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _doorState ? Colors.green : Colors.orange,
            minimumSize: const Size(double.infinity, 50),
          ),
          child: Text(
            _doorState ? 'LOCK DOOR' : 'UNLOCK DOOR',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 20),
        
        // Manual Testing Controls
        const Text(
          'Manual Testing Controls', 
          style: TextStyle(fontWeight: FontWeight.bold)
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => dbService.updateSensorState('ir', true),
              child: const Text('Trigger IR'),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => dbService.updateSensorState('ir', false),
              child: const Text('Reset IR'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => dbService.updateSensorState('reed', true),
              child: const Text('Open Door'),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => dbService.updateSensorState('reed', false),
              child: const Text('Close Door'),
            ),
          ],
        ),
      ],
    ),
  );
}
}