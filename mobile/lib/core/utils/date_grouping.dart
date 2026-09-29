enum DateGroup {
  today('Today'),
  yesterday('Yesterday'),
  last7Days('Last 7 Days'),
  lastMonth('Last Month'),
  older('Older');

  const DateGroup(this.label);

  final String label;
}

/// Buckets [date] relative to [now] using calendar days (DST-safe).
DateGroup dateGroupFor(DateTime date, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toLocal();
  final local = date.toLocal();
  final today = DateTime.utc(current.year, current.month, current.day);
  final day = DateTime.utc(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return DateGroup.today;
  if (diff == 1) return DateGroup.yesterday;
  if (diff < 7) return DateGroup.last7Days;
  if (diff <= 30) return DateGroup.lastMonth;
  return DateGroup.older;
}

/// Groups [items] by [dateOf], preserving item order within each group and
/// returning groups in chronological-bucket order (Today first).
Map<DateGroup, List<T>> groupByDate<T>(
  Iterable<T> items,
  DateTime? Function(T item) dateOf, {
  DateTime? now,
}) {
  final buckets = <DateGroup, List<T>>{};
  for (final item in items) {
    final date = dateOf(item);
    final group = date == null ? DateGroup.older : dateGroupFor(date, now: now);
    buckets.putIfAbsent(group, () => <T>[]).add(item);
  }
  return {
    for (final group in DateGroup.values)
      if (buckets[group] != null) group: buckets[group]!,
  };
}
