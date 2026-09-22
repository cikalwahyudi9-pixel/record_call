import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

  // Mendengarkan perintah dari Firebase Realtime Database
  void listenToCloudCommands() {
    final dbRef = FirebaseDatabase.instance.ref('remote_control/command');
    dbRef.onValue.listen((event) {
      final data = event.snapshot.value as String?;
      if (data == 'START' && !_isRecording) {
        startRecording(isRemote: true);
        dbRef.set('RECORDING');
      } else if (data == 'STOP' && _isRecording) {
        stopRecording(isRemote: true);
        dbRef.set('IDLE');
      }
    });
  }

  Future<bool> startRecording({bool isRemote = false}) async {
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
        
        if (!isRemote) {
          FirebaseDatabase.instance.ref('remote_control/command').set('RECORDING');
        }

        _startTimer();
        return true;
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
    return false;
  }

  Future<bool> stopRecording({String notes = '', bool isRemote = false}) async {
    if (!_isRecording) return false;

    _timer?.cancel();
    final path = await _audioRecorder.stop();
    
    _isRecording = false;
    notifyListeners();

    if (path != null) {
      if (!isRemote) {
        FirebaseDatabase.instance.ref('remote_control/command').set('IDLE');
      }
      await _saveRecord(path, notes);
      await _uploadToFirebase(path, notes);
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

  Future<void> _uploadToFirebase(String filePath, String notes) async {
    try {
      final file = File(filePath);
      final fileName = filePath.split('/').last;
      
      // Upload ke Firebase Storage
      final storageRef = FirebaseStorage.instance.ref().child('records/$fileName');
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      
      // Simpan metadata ke Firebase Realtime Database
      final dbRef = FirebaseDatabase.instance.ref('records').push();
      await dbRef.set({
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'timestamp': DateTime.now().toIso8601String(),
        'duration': _recordDuration,
        'notes': notes,
      });
    } catch (e) {
      debugPrint('Firebase Upload Error: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      _recordDuration++;
      notifyListeners();
    });
  }
}
