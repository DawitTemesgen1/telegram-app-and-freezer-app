import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/freeze_service.dart';
import '../services/frozen_apps_manager.dart';

class AppSelectionScreen extends StatefulWidget {
  const AppSelectionScreen({super.key});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  List<Map<String, dynamic>> _apps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _includeSystemApps = false;

  final Set<String> _selectedPackages = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    final apps = await FreezeService.getInstalledApps(
      includeSystemApps: _includeSystemApps,
    );
    apps.sort(
      (a, b) => (a['appName'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['appName'] ?? '').toString().toLowerCase()),
    );
    setState(() {
      _apps = apps;
      _filterApps(_searchQuery);
      _isLoading = false;
    });
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      _filteredApps = _apps
          .where(
            (app) => (app['appName'] ?? '')
                .toString()
                .toLowerCase()
                .contains(query.toLowerCase()),
          )
          .toList();
    });
  }

  void _toggleSelection(String packageName) {
    setState(() {
      if (_selectedPackages.contains(packageName)) {
        _selectedPackages.remove(packageName);
        if (_selectedPackages.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPackages.add(packageName);
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _onAppSelected(Map<String, dynamic> app) async {
    if (_isSelectionMode) {
      _toggleSelection(app['packageName'] as String);
    } else {
      _selectedPackages.add(app['packageName'] as String);
      final duration = await _showDurationBottomSheet();
      if (duration != null && mounted) {
        await _freezeSelectedApps(duration);
      } else {
        _selectedPackages.remove(app['packageName']);
      }
    }
  }

  Future<void> _onBatchFreezePressed() async {
    final duration = await _showDurationBottomSheet();
    if (duration != null && mounted) {
      await _freezeSelectedApps(duration);
    }
  }

  Future<void> _freezeSelectedApps(Duration? duration) async {
    final freezeDuration = duration ?? const Duration(days: 36500);

    try {
      for (final pkg in _selectedPackages) {
        final app = _apps.firstWhere((a) => a['packageName'] == pkg);
        final appName = app['appName']?.toString() ?? 'Unknown App';
        await FrozenAppsManager.freezeApp(pkg, appName, freezeDuration);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedPackages.length} app(s) frozen'),
            duration: const Duration(milliseconds: 1400),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('NOT_DEVICE_OWNER')
          ? 'Not Device Owner — finish ADB setup first.'
          : 'Failed to freeze app(s).';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<Duration?> _showDurationBottomSheet() async {
    return showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Freeze Duration',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              _durationTile(
                Icons.timer_10,
                '15 Minutes',
                const Duration(minutes: 15),
              ),
              _durationTile(
                Icons.timer,
                '1 Hour',
                const Duration(hours: 1),
              ),
              _durationTile(
                Icons.timer_3_select,
                '3 Hours',
                const Duration(hours: 3),
              ),
              _durationTile(
                Icons.today,
                '24 Hours',
                const Duration(hours: 24),
              ),
              _durationTile(
                Icons.all_inclusive,
                'Indefinitely',
                const Duration(days: 36500),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _durationTile(IconData icon, String title, Duration duration) {
    return ListTile(
      leading: Icon(icon, color: Colors.cyanAccent),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () => Navigator.pop(context, duration),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          _isSelectionMode
              ? '${_selectedPackages.length} Selected'
              : 'Select App to Freeze',
        ),
        actions: [
          Row(
            children: [
              const Text('System', style: TextStyle(fontSize: 12)),
              Switch(
                value: _includeSystemApps,
                onChanged: (val) {
                  setState(() {
                    _includeSystemApps = val;
                    _loadApps();
                  });
                },
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search apps…',
                hintStyle: TextStyle(color: Colors.blueGrey.shade300),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: const Color(0xFF1E293B),
              ),
              onChanged: _filterApps,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _filteredApps.length,
              itemBuilder: (context, index) {
                final app = _filteredApps[index];
                final packageName = app['packageName'] as String;
                final isSelected = _selectedPackages.contains(packageName);
                final isSystemApp = app['isSystemApp'] == true;

                Widget iconWidget = const Icon(Icons.android, size: 40);
                if (app['icon'] != null) {
                  iconWidget = Image.memory(
                    app['icon'] as Uint8List,
                    width: 40,
                    height: 40,
                    errorBuilder: (ctx, err, stack) =>
                        const Icon(Icons.android, size: 40),
                  );
                }

                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Colors.cyan.withValues(alpha: 0.15),
                  leading: iconWidget,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          app['appName']?.toString() ?? 'Unknown App',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (isSystemApp)
                        const Icon(
                          Icons.warning,
                          size: 16,
                          color: Colors.orange,
                        ),
                    ],
                  ),
                  subtitle: Text(
                    packageName,
                    style: TextStyle(color: Colors.blueGrey.shade300),
                  ),
                  onTap: () => _onAppSelected(app),
                  onLongPress: () => _toggleSelection(packageName),
                  trailing: _isSelectionMode
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection(packageName),
                        )
                      : null,
                );
              },
            ),
      floatingActionButton: _isSelectionMode
          ? FloatingActionButton.extended(
              onPressed: _onBatchFreezePressed,
              icon: const Icon(Icons.ac_unit),
              label: const Text('Freeze Selected'),
              backgroundColor: Colors.cyan.shade600,
            )
          : null,
    );
  }
}
