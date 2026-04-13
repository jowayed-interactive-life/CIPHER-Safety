class Subscription {
  String subscriptionId;
  String subject;
  String? queueGroup;

  Subscription(
      {required this.subscriptionId, required this.subject, this.queueGroup});
}
