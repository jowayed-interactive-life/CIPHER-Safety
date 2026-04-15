import 'parsed_alert_payload.dart';

class ReceivedAlert {
  const ReceivedAlert({
    required this.subject,
    required this.payload,
    required this.parsed,
    required this.receivedAt,
  });

  final String subject;
  final String payload;
  final ParsedAlertPayload parsed;
  final DateTime receivedAt;

  String get uniqueKey => '$subject|${receivedAt.microsecondsSinceEpoch}';
}
