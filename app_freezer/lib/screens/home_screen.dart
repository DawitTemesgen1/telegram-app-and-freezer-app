import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/frozen_app.dart';
import '../services/freeze_service.dart';
import '../services/frozen_apps_manager.dart';
import 'app_selection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<FrozenApp> _frozenApps = [];
  Timer? _timer;
  bool _isDeviceOwner = false;
  String _adbCommand =
      'adb shell dpm set-device-owner com.example.app_freezer/.DeviceAdminReceiver';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
      _loadApps();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final owner = await FreezeService.isDeviceOwner();
    final cmd = await FreezeService.getSetupAdbCommand();
    final apps = await FrozenAppsManager.getFrozenApps();
    if (!mounted) return;
    setState(() {
      _isDeviceOwner = owner;
      _adbCommand = cmd;
      _frozenApps = apps;
      _loading = false;
    });
  }

  Future<void> _loadApps() async {
    final apps = await FrozenAppsManager.getFrozenApps();
    if (!mounted) return;
    setState(() => _frozenApps = apps);
  }

  String _formatRemainingTime(DateTime unfreezeTime) {
    final now = DateTime.now();
    if (unfreezeTime.isAfter(now.add(const Duration(days: 365 * 40)))) {
      return 'Frozen indefinitely';
    }
    if (unfreezeTime.isBefore(now)) return 'Expired — refreshing…';
    final diff = unfreezeTime.difference(now);
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m remaining';
    }
    if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m remaining';
    }
    return '${diff.inSeconds}s remaining';
  }

  Future<void> _unfreezeApp(FrozenApp app) async {
    try {
      await FrozenAppsManager.unfreezeApp(app.packageName);
      await _loadApps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${app.appName} unfrozen'),
            duration: const Duration(milliseconds: 1400),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('NOT_DEVICE_OWNER')
          ? 'Not Device Owner — finish ADB setup first.'
          : 'Failed to unfreeze.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _copyAdb() async {
    await Clipboard.setData(ClipboardData(text: _adbCommand));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ADB command copied'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'App Freezer',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!_isDeviceOwner)
                  _DeviceOwnerBanner(
                    command: _adbCommand,
                    onCopy: _copyAdb,
                  ),
                Expanded(
                  child: _frozenApps.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.ac_unit,
                                size: 80,
                                color: Colors.cyan.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No frozen apps',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade300,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isDeviceOwner
                                    ? 'Tap + to freeze an app'
                                    : 'Complete Device Owner setup first',
                                style:
                                    TextStyle(color: Colors.blueGrey.shade400),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _frozenApps.length,
                          itemBuilder: (context, index) {
                            final app = _frozenApps[index];
                            return Card(
                              color: const Color(0xFF1E293B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: Colors.cyan.withValues(alpha: 0.2),
                                ),
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.cyan.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.ac_unit,
                                    color: Colors.cyanAccent,
                                  ),
                                ),
                                title: Text(
                                  app.appName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _formatRemainingTime(app.unfreezeTime),
                                    style:
                                        TextStyle(color: Colors.cyan.shade100),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.greenAccent,
                                  ),
                                  tooltip: 'Unfreeze now',
                                  onPressed: () => _unfreezeApp(app),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor:
            _isDeviceOwner ? Colors.cyan.shade600 : Colors.blueGrey.shade700,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Freeze App',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () async {
          if (!_isDeviceOwner) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Set Device Owner with ADB first'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
          );
          _loadApps();
        },
      ),
    );
  }
}

class _DeviceOwnerBanner extends StatelessWidget {
  const _DeviceOwnerBanner({
    required this.command,
    required this.onCopy,
  });

  final String command;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF422006),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'One-time setup required',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Personal use only. Remove Google accounts from this user (or use a clean user), install the app, then run:',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 8),
            SelectableText(
              command,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy command'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
