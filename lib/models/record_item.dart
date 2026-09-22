class RecordItem {
  final String id;
  final String filePath;
  final String timestamp;
  final String notes;
  final int durationInSeconds;

  RecordItem({
    required this.id,
    required this.filePath,
    required this.timestamp,
    required this.notes,
    required this.durationInSeconds,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'timestamp': timestamp,
      'notes': notes,
      'durationInSeconds': durationInSeconds,
    };
  }

  factory RecordItem.fromMap(Map<String, dynamic> map) {
    return RecordItem(
      id: map['id'],
      filePath: map['filePath'],
      timestamp: map['timestamp'],
      notes: map['notes'] ?? '',
      durationInSeconds: map['durationInSeconds'] ?? 0,
    );
  }
}
