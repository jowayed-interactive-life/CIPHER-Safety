import 'package:nats/nats.dart';

void main() async {
  var client = NatsClient("demo.nats.io", 4222);

  final client2 = NatsClient("demo.nats.io", 4222);

  await client.connect(
      connectionOptions: ConnectionOptions(protocol: 1),
      onClusterupdate: (serverInfo) {
        print("Got new update: ${serverInfo!.serverId}");
      });

  client.subscribe("sub-1", "tata.>").listen((msg) {
    print("Got message: ${msg.payload}");
  });

  client.publish("Hello, World", "tata.papa.tata.adios");
}
