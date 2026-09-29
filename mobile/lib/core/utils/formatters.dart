import 'package:intl/intl.dart';

/// `75` -> `1:15`, `3600` -> `1:00:00`.
String formatClock(Duration duration) {
  final totalSeconds = duration.inSeconds.abs();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// `45` -> `45s`, `90` -> `1m 30s`, `120` -> `2 min`.
String formatDurationShort(int? seconds) {
  if (seconds == null || seconds <= 0) return '--';
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m min' : '${m}m ${s}s';
}

String formatDate(DateTime? date) {
  if (date == null) return '';
  return DateFormat.yMMMd().format(date.toLocal());
}

String formatDateTime(DateTime? date) {
  if (date == null) return '';
  return DateFormat.yMMMd().add_jm().format(date.toLocal());
}

String formatTime(DateTime? date) {
  if (date == null) return '';
  return DateFormat.jm().format(date.toLocal());
}

/// Formats a byte count as e.g. `12.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
