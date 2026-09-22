import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';
import 'services/record_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  
  // Inisialisasi Firebase
  await Firebase.initializeApp();
  
  // Mulai mendengarkan perintah dari Firebase Cloud
  RecordService().listenToCloudCommands();
  
  runApp(const CallRecorderApp());
}

class CallRecorderApp extends StatelessWidget {
  const CallRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Recorder & Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        cardColor: const Color(0xFF1E1E1E),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
