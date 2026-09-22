import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import '../models/record_item.dart';
import 'recorder_screen.dart';
import '../services/web_server.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RecordItem> _records = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingId;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
    
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (state == PlayerState.completed) {
          _currentlyPlayingId = null;
        }
      });
    });
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString('call_records');
    if (recordsJson != null) {
      final List<dynamic> decoded = jsonDecode(recordsJson);
      setState(() {
        _records = decoded.map((e) => RecordItem.fromMap(e)).toList();
        // Urutkan dari yang terbaru
        _records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    }
  }

  Future<void> _deleteRecord(RecordItem item) async {
    // Hapus file fisik
    final file = File(item.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    
    // Update state & simpan
    setState(() {
      _records.removeWhere((r) => r.id == item.id);
    });
    
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = jsonEncode(_records.map((e) => e.toMap()).toList());
    await prefs.setString('call_records', recordsJson);
  }

  void _playRecord(RecordItem item) async {
    if (_currentlyPlayingId == item.id && _isPlaying) {
      await _audioPlayer.pause();
      return;
    }
    
    await _audioPlayer.play(DeviceFileSource(item.filePath));
    setState(() {
      _currentlyPlayingId = item.id;
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showNotesDialog(RecordItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Catatan Panggilan'),
        content: SingleChildScrollView(
          child: Text(item.notes.isEmpty ? 'Tidak ada catatan.' : item.notes),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rekaman Saya', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Banner IP Address
          ListenableBuilder(
            listenable: LocalWebServer(),
            builder: (context, _) {
              final ip = LocalWebServer().serverIp;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.blueAccent.withOpacity(0.2),
                child: Column(
                  children: [
                    const Text('Akses Remote Web:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      ip.isEmpty ? 'Memuat...' : 'http://$ip:8080',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: _records.isEmpty
                ? const Center(
                    child: Text(
                      'Belum ada rekaman.\nTekan tombol rekam di bawah\natau melalui Remote Web.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                final item = _records[index];
                final isPlaying = _currentlyPlayingId == item.id && _isPlaying;
                final date = DateTime.parse(item.timestamp);
                final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formattedDate,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              _formatDuration(item.durationInSeconds),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                size: 40,
                                color: Theme.of(context).primaryColor,
                              ),
                              onPressed: () => _playRecord(item),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showNotesDialog(item),
                                icon: const Icon(Icons.notes, size: 18),
                                label: const Text('Catatan'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2C2C2C),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Hapus Rekaman?'),
                                    content: const Text('Rekaman ini akan dihapus permanen.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Batal'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteRecord(item);
                                        },
                                        child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RecorderScreen()),
          );
          _loadRecords(); // Refresh list when coming back
        },
        icon: const Icon(Icons.mic),
        label: const Text('Rekam Sesi'),
        backgroundColor: Colors.blueAccent,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
