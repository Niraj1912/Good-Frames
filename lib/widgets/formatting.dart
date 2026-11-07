/// "1 photo", "5 photos", "10,020 photos".
String photoCount(int count) =>
    count == 1 ? '1 photo' : '${formatCount(count)} photos';

/// A whole number with thousands separators: 10020 becomes "10,020".
String formatCount(int number) {
  final digits = number.abs().toString();
  final out = StringBuffer(number < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A file size the way people say it: "830 KB", "4.2 MB".
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// How long a stretch of time is, roughly, to follow "within": "a second",
/// "40 seconds",
/// "1 minute", "7 minutes".
String formatSpan(Duration span) {
  if (span.inSeconds < 1) return 'a second';
  if (span.inSeconds < 60) {
    final seconds = span.inSeconds;
    return seconds == 1 ? '1 second' : '$seconds seconds';
  }
  final minutes = span.inMinutes;
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}

/// "March 2024".
String formatMonth(DateTime month) =>
    '${_monthNames[month.month - 1]} ${month.year}';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "2026-10-31 23:59".
String formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
