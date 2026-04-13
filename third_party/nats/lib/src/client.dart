import 'package:nats/src/transformers/message_transformer.dart';

import 'services/protocol_handler.dart';
import 'model/connection_options.dart';
import 'package:logging/logging.dart';
import 'model/nats_message.dart';
import 'model/subscription.dart';
import 'model/server_info.dart';
import 'model/tcp_client.dart';
import 'constants.dart';
import "dart:convert";
import 'dart:async';

class NatsClient {
  // Private attributes
  final String _currentHost;
  final int _currentPort;
  final List<Subscription> _subscriptions;
  final StreamController<NatsMessage> _messagesController;
  ServerInfo? _serverInfo;
  ProtocolHandler? _protocolHandler;
  // Public attributes
  final Logger log = Logger("NatsClient");
  TcpClient tcpClient;

  // Getters & setters
  String get currentHost => _currentHost;
  int get currentPort => _currentPort;

  NatsClient(
    this._currentHost,
    this._currentPort, {
    Level logLevel = Level.INFO,
  })  : this._messagesController = new StreamController.broadcast(),
        this._subscriptions = [],
        this.tcpClient = TcpClient(host: _currentHost, port: _currentPort) {
    this._initLogger(logLevel);
  }

  void _initLogger(Level level) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    });
  }

  /// Connects to the given NATS url
  ///
  /// ```dart
  /// var client = NatsClient("localhost", 4222);
  /// var options = ConnectionOptions()
  /// options
  ///  ..verbose = true
  ///  ..pedantic = false
  ///  ..tlsRequired = false
  /// await client.connect(connectionOptions: options);
  /// ```
  Future<void> connect({
    ConnectionOptions? connectionOptions,
    void onClusterupdate(ServerInfo? info)?,
  }) async {
    final _socket = await this.tcpClient.connect();

    this._protocolHandler = ProtocolHandler(socket: _socket, log: log);

    utf8.decoder.bind(_socket).transform(createMessagesTransformer()).listen(
      (String data) {
        if (data.startsWith(INFO)) {
          _setServerInfo(data, connectionOptions);
          if (onClusterupdate != null) onClusterupdate(_serverInfo);
          return;
        }
        _serverPushString(data);
      },
      onDone: () {
        log.info("Host down. Switching to next available host in cluster");
        _removeCurrentHostFromServerInfo(_currentHost, _currentPort);
        _reconnectToNextAvailableInCluster(
            opts: connectionOptions, onClusterupdate: onClusterupdate);
      },
    );
  }

  /// Publishes the [message] to the [subject] with an optional [replyTo] set to receive the response
  /// ```dart
  /// var client = NatsClient("localhost", 4222);
  /// await client.connect();
  /// client.publish("Hello World", "foo-topic");
  /// client.publish("Hello World", "foo-topic", replyTo: "reply-topic");
  /// ```
  void publish(
    String message,
    String subject, {
    String? replyTo,
  }) {
    if (this._protocolHandler == null)
      throw new Exception("Client not connected yet, operation not allowed");
    _protocolHandler!.publish(message, subject, replyTo: replyTo);
  }

  NatsMessage _convertToMessage(String serverPushString) {
    final int headerEnd = serverPushString.indexOf(CR_LF);
    if (headerEnd == -1) {
      throw Exception('Invalid NATS message: missing header terminator');
    }

    final String header =
        serverPushString.substring(0, headerEnd).replaceFirst(MSG, EMPTY).trim();
    List<String> firstLineParts = header.split(RegExp(r'\s+'));
    bool replySubjectPresent = firstLineParts.length == 4;
    final subject = firstLineParts[0];
    final sid = firstLineParts[1];
    final length = replySubjectPresent
        ? int.parse(firstLineParts[3])
        : int.parse(firstLineParts[2]);
    final replyTo = replySubjectPresent ? firstLineParts[2] : null;
    final int payloadStart = headerEnd + CR_LF.length;
    final int payloadEnd = payloadStart + length;
    if (serverPushString.length < payloadEnd) {
      throw Exception('Invalid NATS message: payload shorter than advertised');
    }
    final payload = serverPushString.substring(payloadStart, payloadEnd);

    return NatsMessage(
        payload: payload,
        subject: subject,
        sid: sid,
        length: length,
        replyTo: replyTo);
  }

  /// Subscribes to the [subject] with a given [subscriberId] and an optional [queueGroup] set to group the responses
  /// ```dart
  /// var client = NatsClient("localhost", 4222);
  /// await client.connect();
  /// var messageStream = client.subscribe("sub-1", "foo-topic"); // No [queueGroup] set
  /// var messageStream = client.subscribe("sub-1", "foo-topic", queueGroup: "group-1")
  ///
  /// messageStream.listen((message) {
  ///   // Do something awesome
  /// });
  /// ```
  Stream<NatsMessage> subscribe(
    String subscriberId,
    String subject, {
    String? queueGroup,
  }) =>
      _doSubscribe(false, subscriberId, subject);

  Stream<NatsMessage> _doSubscribe(
    bool isReconnect,
    String subscriptionId,
    String subject, {
    String queueGroup = "",
  }) {
    subject = subject.trim();
    queueGroup = queueGroup.trim();
    if (subject.contains(' ')) throw Exception("Subject cannot contain spaces");
    try {
      _protocolHandler!.subscribe(
        subscriptionId,
        subject,
        queueGroup: queueGroup,
      );
      if (!isReconnect) {
        _subscriptions.add(Subscription(
            subscriptionId: subscriptionId,
            subject: subject,
            queueGroup: queueGroup));
      } else {
        log.fine("Carrying over subscription [${subject}]");
      }
    } catch (err) {
      log.severe(err);
    }
    return _messagesController.stream
        .where((incomingMsg) => matchesRegex(subject, incomingMsg.subject));
  }

  bool matchesRegex(String listeningSubject, String incomingSubject) {
    final expression = listeningSubject
        .replaceAll(RegExp(r'\.'), "\\.")
        .replaceAll(
            RegExp(r'(?<=\\\.)(\*)(?=\\\.)|(?<=\\\.)(\*$)|(^\*)(?=\\\.)'),
            "[^.]+")
        .replaceAll(RegExp(r'(?<=\\\.)(>$)'), ".+");
    final regexp = RegExp("^$expression\$");
    return regexp.hasMatch(incomingSubject.trim());
  }

  void unsubscribe(String subscriberId, {int? waitUntilMessageCount}) {
    if (this._protocolHandler == null)
      throw new Exception("Client not connected yet, operation not allowed");
    try {
      _protocolHandler!.unsubscribe(
        subscriberId,
        waitUntilMessageCount: waitUntilMessageCount,
      );
      _subscriptions.removeWhere(
          (subscription) => subscription.subscriptionId == subscriberId);
    } catch (err) {}
  }

  void _setServerInfo(
    String serverInfoString,
    ConnectionOptions? connectionOptions,
  ) {
    final data =
        serverInfoString.replaceFirst(INFO, EMPTY).replaceAll(OK, EMPTY).trim();
    try {
      Map<String, dynamic> map = json.decode(data);

      _serverInfo = ServerInfo(
        serverId: map["server_id"],
        version: map["version"],
        protocolVersion: map["proto"],
        goVersion: map["go"],
        host: map["host"],
        port: map["port"],
        maxPayload: map["max_payload"],
        clientId: map["client_id"],
      );
      if (map["connect_urls"] != null) {
        _serverInfo?.serverUrls = map["connect_urls"].cast<String>();
      }
      _sendConnectionPacket(connectionOptions);
    } catch (ex) {
      log.severe(ex.toString());
    }
  }

  void _sendConnectionPacket(ConnectionOptions? opts) {
    _protocolHandler!.connect(opts: opts);
    _protocolHandler!.sendPing();
  }

  void _removeCurrentHostFromServerInfo(String host, int port) =>
      _serverInfo?.serverUrls!.removeWhere((url) => url == "$host:$port");

  void _reconnectToNextAvailableInCluster({
    ConnectionOptions? opts,
    void onClusterupdate(ServerInfo? info)?,
  }) async {
    final urls = _serverInfo?.serverUrls;
    bool isIPv6Address(String url) => url.contains("[") && url.contains("]");
    if (urls != null) {
      for (var url in urls) {
        tcpClient = _createTcpClient(url, isIPv6Address);
        try {
          await connect(
            connectionOptions: opts,
            onClusterupdate: onClusterupdate,
          );
          log.info("Successfully switched client to $url now");
          _carryOverSubscriptions();
          break;
        } catch (ex) {
          log.fine("Tried connecting to $url but failed. Moving on");
        }
      }
    }
  }

  /// Returns a [TcpClient] from the given [url]
  TcpClient _createTcpClient(String url, bool checker(String url)) {
    log.fine("Trying to connect to $url now");
    int port = int.parse(url.split(":")[url.split(":").length - 1]);
    String host = checker(url)
        ? url.substring(url.indexOf("[") + 1, url.indexOf("]"))
        : url.substring(0, url.indexOf(":"));
    return TcpClient(host: host, port: port);
  }

  /// Carries over [Subscription] objects from one host to another during cluster rearrangement
  void _carryOverSubscriptions() {
    _subscriptions.forEach((subscription) {
      _doSubscribe(true, subscription.subscriptionId, subscription.subject);
    });
  }

  void _serverPushString(String serverPushString) {
    if (serverPushString.startsWith(MSG)) {
      NatsMessage msg = _convertToMessage(serverPushString);
      _messagesController.add(msg);
    } else if (serverPushString.startsWith(PING)) {
      _protocolHandler!.sendPong();
    } else if (serverPushString.startsWith(OK)) {
      log.fine("Received server OK");
    }
  }
}
