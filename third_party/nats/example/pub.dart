import 'package:nats/nats.dart';

void main() async {
  var client = NatsClient("demo.nats.io", 4222);

  await client.connect();

  client.publish("Hello world", "tata.papa");
}
