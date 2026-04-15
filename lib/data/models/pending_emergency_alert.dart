class PendingEmergencyAlert {
  const PendingEmergencyAlert({
    required this.subject,
    required this.payload,
    required this.receivedAt,
  });

  final String subject;
  final String payload;
  final DateTime receivedAt;
}
