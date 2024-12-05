import 'dart:async';
import 'dart:developer';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:reko_mqtt_helper/reko_mqtt_helper.dart';

/// A helper class for working with MQTT connections and events.
///
/// This class provides a convenient way to manage MQTT connections, subscriptions, and events. It also provides streams for listening to connection changes, raw events, and parsed events.
class MqttHelper {
  /// The underlying MQTT configuration.
  ///
  /// This configuration object holds the necessary settings for connecting to an MQTT broker, such as the server URL, port, and credentials.
  late MqttConfig _config;

  /// Whether the MQTT helper has been initialized.
  ///
  /// This flag indicates whether the `initialize` method has been called and the MQTT helper is ready for use.
  bool _initialized = false;

  /// The callback functions for MQTT events.
  ///
  /// These callback functions are called when specific MQTT events occur, such as connection, disconnection, subscription, and unsubscription.
  MqttCallbacks? _callbacks;

  /// The underlying MQTT client.
  ///
  /// This is the actual MQTT client that connects to the MQTT broker and handles the communication.
  MqttClient? _client;

  /// The MQTT helper client.
  ///
  /// This is a wrapper around the underlying MQTT client that provides additional functionality and convenience methods.
  MqttHelperClient? _helperClient;

  /// The list of topics to subscribe to.
  ///
  /// This list of topics is used when auto-subscribing to topics during initialization.
  late List<String> _topics;

  /// The callback function for subscribed topics.
  ///
  /// This callback function is called when the subscription to topics is successful.
  void Function(List<String>)? _subscribedTopicsCallback;

  /// The list of subscribed topics.
  ///
  /// This list keeps track of the topics that the MQTT helper is currently subscribed to.
  List<String> subscribedTopics = [];

  /// Whether to auto-subscribe to topics.
  ///
  /// If set to true, the MQTT helper will automatically subscribe to the specified topics during initialization.
  bool _autoSubscribe = false;

  /// A stream controller for raw events.
  ///
  /// This stream controller is used to broadcast raw MQTT events to listeners.
  late StreamController<MqttHelperPayload?> _rawEventStream;

  /// A stream controller for parsed events.
  ///
  /// This stream controller is used to broadcast parsed MQTT events to listeners.
  late StreamController<EventModel> _eventStream;

  /// A stream controller for connection changes.
  ///
  /// This stream controller is used to broadcast connection changes (e.g., connected, disconnected) to listeners.
  late StreamController<bool> _connectionStream;

  /// A stream for listening to parsed events.
  ///
  /// This stream allows listeners to receive parsed MQTT events of type [EventModel]
  StreamSubscription<EventModel> onEvent(
    Function(EventModel) event,
  ) =>
      _eventStream.stream.listen(event);

  /// A stream for listening to raw events.
  ///
  /// This stream allows listeners to receive raw MQTT events.
  StreamSubscription<MqttHelperPayload?> onRawEvent(
    Function(MqttHelperPayload?) event,
  ) =>
      _rawEventStream.stream.listen(event);

  /// A stream for listening to connection changes.
  ///
  /// This stream allows listeners to receive connection change events (e.g., connected, disconnected).
  StreamSubscription<bool> onConnectionChange(
    Function(bool) change,
  ) =>
      _connectionStream.stream.listen(change);

  /// Initializes the MQTT helper with the provided configuration.
  ///
  /// This method sets up the underlying MQTT client and configures it with the provided configuration. It also sets up the streams for listening to events and connection changes.
  ///
  /// Parameters:
  ///   - `config`: The MQTT configuration.
  ///   - `callbacks`: The callback functions for MQTT events.
  ///   - `autoSubscribe`: Whether to auto-subscribe to topics.
  ///   - `topics`: The list of topics to subscribe to.
  ///   - `subscribedTopicsCallback`: The callback function for subscribed topics.
  Future<void> initialize(
    MqttConfig config, {
    MqttCallbacks? callbacks,
    bool autoSubscribe = false,
    List<String>? topics,
    void Function(List<String>)? subscribedTopicsCallback,
  }) async {
    if (autoSubscribe) {
      if (topics == null || topics.isEmpty) {
        throw Exception(
          'You must specify at least one topic when auto-subscribing',
        );
      }
    }

    _rawEventStream = StreamController<MqttHelperPayload>.broadcast();
    _eventStream = StreamController<EventModel>.broadcast();
    _connectionStream = StreamController<bool>.broadcast();

    _initialized = true;
    _config = config;
    _callbacks = callbacks;
    _topics = topics ?? [];
    _autoSubscribe = autoSubscribe;
    _subscribedTopicsCallback = subscribedTopicsCallback;
    await _initializeClient();
    await _connectClient();
  }

  /// Initializes the underlying MQTT client.
  ///
  /// This method sets up the underlying MQTT client with the provided configuration and sets up the necessary callbacks.
  Future<void> _initializeClient() async {
    if (!_initialized) {
      throw Exception(
        'MqttConfig is not initialized. Initialize it by calling initialize(config)',
      );
    }

    _helperClient = MqttHelperClient();
    var userIdentifier = _config.projectConfig.userIdentifier;
    var deviceId = _config.projectConfig.deviceId;
    var identifier = '$userIdentifier$deviceId';

    _client = _helperClient?.setup(_config);

    _client?.port = _config.serverConfig.port;
    _client?.keepAlivePeriod = 60;
    _client?.onDisconnected = _onDisconnected;
    _client?.onUnsubscribed = _onUnSubscribed;
    _client?.onSubscribeFail = _onSubscribeFailed;
    _client?.logging(on: _config.enableLogging);
    _client?.autoReconnect = true;
    _client?.pongCallback = _pong;
    _client?.setProtocolV311();
    _client?.websocketProtocols = _config.webSocketConfig?.websocketProtocols ?? [];

    /// Add the successful connection callback
    _client?.onConnected = _onConnected;
    _client?.onSubscribed = _onSubscribed;

    _client?.connectionMessage = MqttConnectMessage().withClientIdentifier(identifier).startClean();
  }

  /// Connects the underlying MQTT client to the MQTT broker.
  ///
  /// This method attempts to connect the underlying MQTT client to the MQTT broker using the provided configuration.
  Future<void> _connectClient() async {
    try {
      var res = await _client?.connect(
        _config.projectConfig.username.isNotEmpty ? _config.projectConfig.username : null,
        _config.projectConfig.password.isNotEmpty ? _config.projectConfig.password : null,
      );
      if (res?.state == MqttConnectionState.connected) {
        _connectionStream.add(true);
        if (_autoSubscribe) {
          subscribedTopics.clear();
          subscribeTopics(_topics);
        }
      }
    } on NoConnectionException catch (e, st) {
      disconnect();
      log('[MQTTHelper] - $e', stackTrace: st);
    } catch (e, st) {
      disconnect();
      log('[MQTTHelper] - $e', stackTrace: st);
    }
  }

  /// Subscribes to a single topic.
  ///
  /// This method subscribes to a single topic on the MQTT broker.
  ///
  /// Parameters:
  ///   - `topic`: The topic to subscribe to.
  void subscribeTopic(String topic) {
    if (!_initialized) {
      throw Exception(
        'MqttConfig is not initialized. Initialize it by calling initialize(config)',
      );
    }

    _client?.subscribe(topic, MqttQos.atMostOnce);
    subscribedTopics.add(topic);
  }

  /// Subscribes to multiple topics.
  ///
  /// This method subscribes to multiple topics on the MQTT broker.
  ///
  /// Parameters:
  ///   - `topics`: The list of topics to subscribe to.
  void subscribeTopics(List<String> topics) {
    if (!_initialized) {
      throw Exception(
        'MqttConfig is not initialized. Initialize it by calling initialize(config)',
      );
    }
    for (var topic in topics) {
      subscribeTopic(topic);
    }
    _subscribedTopicsCallback?.call(subscribedTopics);
  }

  /// Unsubscribes from a single topic.
  ///
  /// This method unsubscribes from a single topic on the MQTT broker.
  ///
  /// Parameters:
  ///   - `topic`: The topic to unsubscribe from.
  void unsubscribeTopic(String topic) {
    _client?.unsubscribe(topic);
  }

  /// Unsubscribes from multiple topics.
  ///
  /// This method unsubscribes from multiple topics on the MQTT broker.
  ///
  /// Parameters:
  ///   - `topics`: The list of topics to unsubscribe from.
  void unsubscribeTopics(List<String> topics) {
    for (var topic in topics) {
      unsubscribeTopic(topic);
    }
  }

  /// Disconnects the MQTT client from the MQTT broker.
  ///
  /// This method disconnects the MQTT client from the MQTT broker and stops the auto-reconnect feature.
  void disconnect() {
    _client?.autoReconnect = false;
    _client?.disconnect();
  }

  /// A callback function for when the MQTT client receives a PONG response.
  ///
  /// This function is called when the MQTT client receives a PONG response from the MQTT broker.
  void _pong() {
    _callbacks?.pongCallback?.call();
  }

  /// A callback function for when the MQTT client is disconnected.
  ///
  /// This function is called when the MQTT client is disconnected from the MQTT broker.
  void _onDisconnected() {
    _connectionStream.add(false);
    _callbacks?.onDisconnected?.call();
  }

  /// A callback function for when the MQTT client subscribes to a topic.
  ///
  /// This function is called when the MQTT client subscribes to a topic on the MQTT broker.
  void _onSubscribed(String topic) {
    _callbacks?.onSubscribed?.call(topic);

    /// print data from MqttEventModel
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) async {
      _rawEventStream.add(c);
      final recMess = c?.first.payload as MqttPublishMessage;
      final topic = c?.first.topic;

      final payloadMessageString =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      print('Received message :${payloadMessageString} from topic:$topic');

      // var payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      // _eventStream.add(
      //   EventModel(
      //     topic: topic ?? '',
      //     payload: payload,
      //   ),
      // );
    });
  }

  /// A callback function for when the MQTT client unsubscribes from a topic.
  ///
  /// This function is called when the MQTT client unsubscribes from a topic on the MQTT broker.
  void _onUnSubscribed(String? topic) {
    _callbacks?.onUnsubscribed?.call(topic);
  }

  /// A callback function for when the MQTT client fails to subscribe to a topic.
  ///
  /// This function is called when the MQTT client fails to subscribe to a topic on the MQTT broker.
  void _onSubscribeFailed(String topic) {
    _callbacks?.onSubscribeFail?.call(topic);
  }

  /// A callback function for when the MQTT client connects to the MQTT broker.
  ///
  /// This function is called when the MQTT client connects to the MQTT broker.
  void _onConnected() {
    _callbacks?.onConnected?.call();
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) async {
      _rawEventStream.add(c);
      final recMess = c?.first.payload as MqttPublishMessage;
      final topic = c?.first.topic;

      //print message
      var payloadPrint = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      print('Received message:${recMess.payload.message} from topic:$topic');

      // var payload = jsonDecode(
      //   MqttPublishPayload.bytesToStringAsString(recMess.payload.message),
      // ) as Map<String, dynamic>;

      // _eventStream.add(
      //   EventModel(
      //     topic: topic ?? '',
      //     payload: payload,
      //   ),
      // );
    });
  }

  /// Publishes a message to an MQTT topic.
  ///
  /// This method publishes a message to an MQTT topic on the MQTT broker.
  ///
  /// Parameters:
  ///   - `message`: The message to publish.
  ///   - `pubTopic`: The topic to publish to.
  ///   - `retain`: Whether to retain the message on the MQTT broker.
  int? publishMessage({
    required String message,
    required String pubTopic,
    bool retain = false,
  }) {
    if (message.isEmpty || pubTopic.isEmpty) {
      throw ArgumentError('Message and topic cannot be empty');
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      throw Exception('Client is not connected');
    }

    return _client?.publishMessage(
      pubTopic,
      //qos 0
      MqttQos.values[0],
      builder.payload!,
      retain: retain,
    );
  }
}
