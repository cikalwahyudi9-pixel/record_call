import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/record_item.dart';
import '../services/record_service.dart';

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _notesController = TextEditingController();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    await RecordService().startRecording();
  }

  Future<void> _stopRecording() async {
    await RecordService().stopRecording(notes: _notesController.text);
    if (mounted) {
      Navigator.pop(context); // Kembali ke halaman utama
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RecordService(),
      builder: (context, _) {
        final isRecording = RecordService().isRecording;
        final duration = RecordService().recordDuration;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Sedang Merekam...'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                if (isRecording) {
                  RecordService().stopRecording();
                }
                Navigator.pop(context);
              },
            ),
          ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Animasi visualizer sederhana (berkedip)
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isRecording 
                          ? Colors.red.withValues(alpha: 0.3 + (_animationController.value * 0.4))
                          : Colors.grey.withValues(alpha: 0.2),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.mic,
                        size: 80,
                        color: isRecording ? Colors.redAccent : Colors.grey,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 40),
              // Area Catatan
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _notesController,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Tulis catatan Anda di sini selama panggilan berlangsung...',
                      hintStyle: TextStyle(color: Colors.white38),
                    ),
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              // Tombol Rekam / Stop
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: isRecording ? _stopRecording : _startRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecording ? Colors.white : Colors.redAccent,
                    foregroundColor: isRecording ? Colors.red : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    isRecording ? 'HENTIKAN REKAMAN' : 'MULAI REKAMAN',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }
}
