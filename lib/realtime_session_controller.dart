import 'dart:async';
import 'dart:convert';

import 'realtime.dart';

class RealtimeSessionException implements Exception {
  RealtimeSessionException(this.error);

  final RealtimeErrorInfo error;

  @override
  String toString() {
    return error.message;
  }
}

abstract class RealtimeSessionController {
  RealtimeSessionController({RealtimeSession? session, List<RealtimeFunctionToolHandler>? initialTools}) : _session = session {
    _sub = serverEvents.listen(_handleSessionEvents);
    if (initialTools != null) {
      for (final tool in initialTools) {
        if (_tools.containsKey(tool.metadata.name)) {
          throw new ArgumentError("duplicate tool ${tool.metadata.name}");
        }
        _tools[tool.metadata.name] = tool;
      }
    }

    _ready.future.then((_) {
      if (initialTools != null) {
        send(SessionUpdateEvent(session: RealtimeSession(tools: [...initialTools.map((t) => t.metadata)])));
      }
    });
  }

  final Completer _ready = Completer();

  late final StreamSubscription _sub;

  void _handleSessionEvents(RealtimeEvent event) {
    if (event is SessionUpdatedEvent) {
      _session = event.session;
    } else if (event is SessionCreatedEvent) {
      _session = event.session;
      _ready.complete();
    }

    for (final handler in tools) {
      final h = handler.getHandler(event);
      if (h != null) {
        // Handle events async
        h(this);
      }
    }
  }

  RealtimeSession? _session;
  RealtimeSession? get session {
    return _session;
  }

  final Map<String, RealtimeFunctionToolHandler> _tools = {};
  Iterable<RealtimeFunctionToolHandler> get tools {
    return _tools.values;
  }

  Future<void> addTools(List<RealtimeFunctionToolHandler> tools) async {
    await _ready;

    for (final tool in tools) {
      if (this._tools.containsKey(tool.metadata.name)) {
        throw new ArgumentError("tool ${tool.metadata.name} cannot be added is already attached");
      }
    }

    for (final tool in tools) {
      this._tools[tool.metadata.name] = tool;
    }
    updateSession(RealtimeSession(tools: [...this._tools.values.map((t) => t.metadata)]));
  }

  Future<void> removeTools(List<RealtimeFunctionToolHandler> tools) async {
    await _ready;

    for (final tool in tools) {
      if (!this._tools.containsKey(tool.metadata.name)) {
        throw new ArgumentError("tool ${tool.metadata.name} cannot be removed because it is not attached");
      }
    }

    for (final tool in tools) {
      this._tools.remove(tool.metadata.name);
    }

    updateSession(RealtimeSession(tools: [...this._tools.values.map((t) => t.metadata)]));
  }

  void updateSession(RealtimeSession session) async {
    final event = SessionUpdateEvent(session: session);
    send(event);
  }

  void dispose() {
    _sub.cancel();
    serverEventsController.close();
  }

  final clientEventsController = StreamController<RealtimeEvent>.broadcast();
  final serverEventsController = StreamController<RealtimeEvent>.broadcast();

  Stream<RealtimeEvent> get clientEvents {
    return clientEventsController.stream;
  }

  Stream<RealtimeEvent> get serverEvents {
    return serverEventsController.stream;
  }

  void send(RealtimeEvent event) async {
    clientEventsController.sink.add(event);
  }
}

abstract class RealtimeToolHandler<TMetadata> {
  RealtimeToolHandler({required this.metadata});

  final TMetadata metadata;

  Future<void> Function(RealtimeSessionController controller)? getHandler(RealtimeEvent e);
}

abstract class RealtimeFunctionToolHandler extends RealtimeToolHandler<RealtimeFunctionTool> {
  RealtimeFunctionToolHandler({required super.metadata});

  @override
  Future<void> Function(RealtimeSessionController controller)? getHandler(RealtimeEvent e) {
    switch (e) {
      case RealtimeResponseOutputItemDoneEvent(item: RealtimeFunctionCall()):
        return (controller) async {
          final item = e.item as RealtimeFunctionCall;
          if (item.name == metadata.name) {
            try {
              final output = await _doCall(controller, item);
              controller.send(RealtimeConversationItemCreateEvent(item: output, previousItemId: item.id));
              controller.send(RealtimeResponseCreateEvent(response: RealtimeResponseOptions()));
            } catch (err) {
              controller.send(RealtimeConversationItemCreateEvent(
                  item: RealtimeFunctionCallOutput(callId: item.callId, output: "Error: ${err}", status: "failed"),
                  previousItemId: item.id));
              controller.send(RealtimeResponseCreateEvent(response: RealtimeResponseOptions()));
            }
          }
        };
      default:
        return null;
    }
  }

  Future<RealtimeFunctionCallOutput> _doCall(RealtimeSessionController controller, RealtimeFunctionCall call) async {
    final result = await execute(controller, jsonDecode(call.arguments));
    return call.output(result);
  }

  Future<String> execute(RealtimeSessionController controller, Map<String, dynamic> arguments);
}
