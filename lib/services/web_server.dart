import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/record_item.dart';
import 'record_service.dart';
import 'package:mime/mime.dart';

class LocalWebServer extends ChangeNotifier {
  static final LocalWebServer _instance = LocalWebServer._internal();
  factory LocalWebServer() => _instance;
  LocalWebServer._internal();

  HttpServer? _server;
  String _serverIp = '';
  String get serverIp => _serverIp;
  bool get isRunning => _server != null;

  Future<void> startServer() async {
    if (_server != null) return;

    final app = Router();

    // CORS Headers
    final corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type',
    };

    Middleware corsMiddleware() {
      return (Handler innerHandler) {
        return (Request request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: corsHeaders);
          }
          final response = await innerHandler(request);
          return response.change(headers: corsHeaders);
        };
      };
    }

    // Serve HTML Dashboard
    app.get('/', (Request request) {
      const html = '''
      <!DOCTYPE html>
      <html lang="en">
      <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Call Recorder Dashboard</title>
          <style>
              body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #121212; color: #fff; margin: 0; padding: 20px; }
              .container { max-width: 800px; margin: auto; }
              h1 { text-align: center; color: #4fa3e3; }
              .card { background-color: #1e1e1e; padding: 20px; border-radius: 12px; margin-bottom: 20px; }
              .btn { padding: 12px 24px; font-size: 16px; border: none; border-radius: 8px; cursor: pointer; font-weight: bold; width: 100%; transition: 0.3s; }
              .btn-start { background-color: #e74c3c; color: white; }
              .btn-start:hover { background-color: #c0392b; }
              .btn-stop { background-color: #fff; color: #e74c3c; }
              .record-item { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #333; padding: 15px 0; }
              .record-item:last-child { border-bottom: none; }
              .record-title { font-size: 16px; font-weight: bold; }
              .record-meta { font-size: 12px; color: #aaa; margin-top: 5px; }
              audio { width: 100%; margin-top: 10px; }
          </style>
      </head>
      <body>
          <div class="container">
              <h1>Call Recorder Remote</h1>
              <div class="card">
                  <h3 id="status-text">Status: Loading...</h3>
                  <button id="record-btn" class="btn btn-start" onclick="toggleRecord()">MULAI REKAMAN</button>
              </div>
              <div class="card">
                  <h3>Daftar Rekaman</h3>
                  <div id="records-list">Memuat...</div>
              </div>
          </div>

          <script>
              let isRecording = false;

              async function fetchStatus() {
                  const res = await fetch('/api/status');
                  const data = await res.json();
                  isRecording = data.isRecording;
                  updateUI();
              }

              async function toggleRecord() {
                  if (isRecording) {
                      await fetch('/api/stop', { method: 'POST' });
                  } else {
                      await fetch('/api/start', { method: 'POST' });
                  }
                  await fetchStatus();
                  await fetchRecords();
              }

              function updateUI() {
                  const btn = document.getElementById('record-btn');
                  const status = document.getElementById('status-text');
                  if (isRecording) {
                      btn.textContent = 'HENTIKAN REKAMAN';
                      btn.className = 'btn btn-stop';
                      status.textContent = 'Status: Sedang Merekam...';
                  } else {
                      btn.textContent = 'MULAI REKAMAN';
                      btn.className = 'btn btn-start';
                      status.textContent = 'Status: Siap Merekam';
                  }
              }

              async function fetchRecords() {
                  const res = await fetch('/api/records');
                  const records = await res.json();
                  const list = document.getElementById('records-list');
                  list.innerHTML = '';
                  if(records.length === 0) list.innerHTML = 'Belum ada rekaman.';
                  records.forEach(r => {
                      const div = document.createElement('div');
                      div.className = 'record-item';
                      
                      const date = new Date(r.timestamp).toLocaleString();
                      const min = Math.floor(r.durationInSeconds / 60).toString().padStart(2, '0');
                      const sec = (r.durationInSeconds % 60).toString().padStart(2, '0');
                      
                      div.innerHTML = `
                          <div style="flex:1">
                              <div class="record-title">\${date} - \${min}:\${sec}</div>
                              <div class="record-meta">\${r.notes || 'Tidak ada catatan'}</div>
                              <audio controls src="/api/play?path=\${encodeURIComponent(r.filePath)}"></audio>
                          </div>
                      `;
                      list.appendChild(div);
                  });
              }

              fetchStatus();
              fetchRecords();
              setInterval(fetchStatus, 3000); // Polling status
          </script>
      </body>
      </html>
      ''';
      return Response.ok(html, headers: {'Content-Type': 'text/html'});
    });

    // API Status
    app.get('/api/status', (Request request) {
      return Response.ok(
        jsonEncode({
          'isRecording': RecordService().isRecording,
          'durationInSeconds': RecordService().recordDuration,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // API Start
    app.post('/api/start', (Request request) async {
      await RecordService().startRecording();
      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
    });

    // API Stop
    app.post('/api/stop', (Request request) async {
      await RecordService().stopRecording(notes: 'Direkam dari Web');
      return Response.ok(jsonEncode({'success': true}), headers: {'Content-Type': 'application/json'});
    });

    // API Records
    app.get('/api/records', (Request request) async {
      final prefs = await SharedPreferences.getInstance();
      final String? recordsJson = prefs.getString('call_records');
      
      List<RecordItem> records = [];
      if (recordsJson != null) {
        final List<dynamic> decoded = jsonDecode(recordsJson);
        records = decoded.map((e) => RecordItem.fromMap(e)).toList();
        records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      return Response.ok(jsonEncode(records.map((e) => e.toMap()).toList()), headers: {'Content-Type': 'application/json'});
    });

    // API Play Audio
    app.get('/api/play', (Request request) async {
      final filePath = request.url.queryParameters['path'];
      if (filePath == null) return Response.notFound('File path required');

      final file = File(filePath);
      if (!await file.exists()) return Response.notFound('File not found');

      final mimeType = lookupMimeType(filePath) ?? 'audio/mp4';
      
      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': mimeType,
          'Content-Length': (await file.length()).toString(),
          'Accept-Ranges': 'bytes',
        },
      );
    });

    final handler = const Pipeline().addMiddleware(corsMiddleware()).addHandler(app.call);
    
    // Bind to all interfaces (0.0.0.0) so it's accessible externally
    _server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
    
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();
    
    _serverIp = wifiIP ?? 'localhost';
    notifyListeners();
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    notifyListeners();
  }
}
