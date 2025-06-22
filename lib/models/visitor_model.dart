class Visitor {
  final String id;
  final String faceId;
  final String listType;
  final String timestamp;
  final List<double> embedding;
  final DateTime? lastSeen;
  final double confidence;

  const Visitor({
    required this.id,
    required this.faceId,
    required this.listType,
    required this.timestamp,
    required this.embedding,
    this.lastSeen,
    this.confidence = 1.0,
  });

  factory Visitor.fromMap(Map<String, dynamic> map, String id) {
    return Visitor(
      id: id,
      faceId: map['faceId'] ?? '',  
      listType: map['listType'],
      timestamp: map['timestamp'],
      embedding: List<double>.from(map['embedding']),
      lastSeen: map['lastSeen']?.toDate(),
      confidence: map['confidence'] ?? 1.0, // Added confidence parsing
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'faceId': faceId,
      'listType': listType,
      'timestamp': timestamp,
      'embedding': embedding,
      'lastSeen': lastSeen,
      'confidence': confidence, // Added confidence to map
    };
  }

  Visitor copyWith({
    String? id,
    String? faceId,
    String? listType,
    String? timestamp,
    List<double>? embedding,
    DateTime? lastSeen,
    double? confidence,
  }) {
    return Visitor(
      id: id ?? this.id,
      faceId: faceId ?? this.faceId,
      listType: listType ?? this.listType,
      timestamp: timestamp ?? this.timestamp,
      embedding: embedding ?? this.embedding,
      lastSeen: lastSeen ?? this.lastSeen,
      confidence: confidence ?? this.confidence,
    );
  }
}