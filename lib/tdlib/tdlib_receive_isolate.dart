import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui';

import 'package:tdlib/src/tdclient/platform_interfaces/td_native_plugin_real.dart'
    as native;
import 'package:tdlib/src/tdclient/platform_interfaces/td_plugin.dart';

/// Survives Flutter hot restart so we can stop the previous receive loop.
const tdlibReceiveControlName = 'tg_focus_tdlib_receive_ctrl';

/// Entry point for the TDLib receive isolate.
/// Flutter plugin registration does not run here, so we open libtdjson ourselves.
@pragma('vm:entry-point')
void tdlibReceiveIsolateMain(List<dynamic> args) {
  final sendPort = args[0] as SendPort;
  final tdlibPath = args[1] as String?;

  try {
    final lib = (tdlibPath == null || tdlibPath.isEmpty)
        ? DynamicLibrary.process()
        : DynamicLibrary.open(tdlibPath);
    TdPlugin.instance = native.TdNativePlugin(lib);

    final control = ReceivePort();
    IsolateNameServer.removePortNameMapping(tdlibReceiveControlName);
    IsolateNameServer.registerPortWithName(
      control.sendPort,
      tdlibReceiveControlName,
    );

    var running = true;
    control.listen((message) {
      if (message == 'stop') {
        running = false;
      }
    });

    while (running) {
      final raw = TdPlugin.instance.tdReceive(0.4);
      if (raw != null) {
        sendPort.send(raw);
      }
    }

    control.close();
    IsolateNameServer.removePortNameMapping(tdlibReceiveControlName);
  } catch (e) {
    try {
      IsolateNameServer.removePortNameMapping(tdlibReceiveControlName);
    } catch (_) {}
    sendPort.send({'error': e.toString()});
  }
}

/// Ask any previous receive isolate (e.g. after hot restart) to exit.
Future<void> stopExistingTdlibReceiveIsolate() async {
  final existing = IsolateNameServer.lookupPortByName(tdlibReceiveControlName);
  if (existing == null) return;
  try {
    existing.send('stop');
  } catch (_) {}
  // Wait longer than tdReceive timeout so the loop can exit cleanly.
  await Future<void>.delayed(const Duration(milliseconds: 600));
  IsolateNameServer.removePortNameMapping(tdlibReceiveControlName);
}
