String _compactDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes <= 0) {
    return '<1m';
  }

  final days = totalMinutes ~/ (24 * 60);
  final hours = (totalMinutes % (24 * 60)) ~/ 60;
  final minutes = totalMinutes % 60;

  if (days > 0) {
    if (hours > 0) {
      return '${days}d ${hours}h';
    }
    return '${days}d';
  }

  if (hours > 0) {
    if (minutes > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${hours}h';
  }

  return '${minutes}m';
}

String buildExpiryRelativeLabel(
  DateTime expiresAt, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  if (expiresAt.isAfter(reference)) {
    return 'Ends in ${_compactDuration(expiresAt.difference(reference))}';
  }
  return 'Expired ${_compactDuration(reference.difference(expiresAt))} ago';
}
