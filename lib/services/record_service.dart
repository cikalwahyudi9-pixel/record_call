import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/record_item.dart';

class RecordService extends ChangeNotifier {
  static final RecordService _instance = RecordService._internal();
  factory RecordService() => _instance;
  RecordService._internal();

  final AudioRecorder _audioRecorder = AudioRecorder();
  
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  int _recordDuration = 0;
  int get recordDuration => _recordDuration;

  Timer? _timer;

  Future<bool> startRecording() async {
    if (_isRecording) return false;

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) return false;

    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/record_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000);
        await _audioRecorder.start(config, path: filePath);

        _isRecording = true;
        _recordDuration = 0;
        notifyListeners();

        _startTimer();
        return true;
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
    return false;
  }

  Future<bool> stopRecording({String notes = ''}) async {
    if (!_isRecording) return false;

    _timer?.cancel();
    final path = await _audioRecorder.stop();
    
    _isRecording = false;
    notifyListeners();

    if (path != null) {
      await _saveRecord(path, notes);
      return true;
    }
    return false;
  }

  Future<void> _saveRecord(String filePath, String notes) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString('call_records');
    
    List<RecordItem> records = [];
    if (recordsJson != null) {
      final List<dynamic> decoded = jsonDecode(recordsJson);
      records = decoded.map((e) => RecordItem.fromMap(e)).toList();
    }

    final newItem = RecordItem(
      id: const Uuid().v4(),
      filePath: filePath,
      timestamp: DateTime.now().toIso8601String(),
      notes: notes,
      durationInSeconds: _recordDuration,
    );

    records.add(newItem);
    await prefs.setString('call_records', jsonEncode(records.map((e) => e.toMap()).toList()));
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      _recordDuration++;
      notifyListeners();
    });
  }
}
