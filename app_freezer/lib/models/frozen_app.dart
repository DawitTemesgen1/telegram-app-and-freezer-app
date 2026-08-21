import 'dart:convert';

class FrozenApp {
  final String packageName;
  final String appName;
  final DateTime unfreezeTime;

  FrozenApp({
    required this.packageName,
    required this.appName,
    required this.unfreezeTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'unfreezeTime': unfreezeTime.toIso8601String(),
    };
  }

  factory FrozenApp.fromMap(Map<String, dynamic> map) {
    return FrozenApp(
      packageName: map['packageName'],
      appName: map['appName'],
      unfreezeTime: DateTime.parse(map['unfreezeTime']),
    );
  }

  String toJson() => json.encode(toMap());

  factory FrozenApp.fromJson(String source) => FrozenApp.fromMap(json.decode(source));
}
