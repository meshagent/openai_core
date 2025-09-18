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
      for (final tool in initialTools) {
        tool.didAttach(this);
      }
    }

    _ready.future.then((_) {
      if (initialTools != null) {
        send(SessionUpdateEvent(session: RealtimeSessionUpdate(tools: [...initialTools.map((t) => t.metadata)])));
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
      tool.didAttach(this);
    }
    updateSession(RealtimeSessionUpdate(tools: [...this._tools.values.map((t) => t.metadata)]));
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
      tool.didDetach(this);
    }

    updateSession(RealtimeSessionUpdate(tools: [...this._tools.values.map((t) => t.metadata)]));
  }

  void updateSession(RealtimeSessionUpdate session) async {
    final event = SessionUpdateEvent(session: session);
    send(event);
  }

  void dispose() {
    _sub.cancel();
    serverEventsController.close();
    for (final tool in tools) {
      tool.didDetach(this);
    }
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

abstract class RealtimeFunctionToolHandler {
  RealtimeFunctionToolHandler({required this.metadata});

  final RealtimeFunctionTool metadata;

  Future<RealtimeFunctionCallOutput> call(RealtimeFunctionCall call);

  Map<RealtimeSessionController, StreamSubscription> _attachedTo = {};

  void didAttach(RealtimeSessionController controller) {
    if (!_attachedTo.containsKey(controller)) {
      _attachedTo[controller] = controller.serverEvents.listen((e) async {
        switch (e) {
          case RealtimeResponseOutputItemDoneEvent(item: RealtimeFunctionCall()):
            final item = e.item as RealtimeFunctionCall;
            if (item.name == metadata.name) {
              final output = await call(item);
              controller.send(RealtimeConversationItemCreateEvent(item: output, previousItemId: item.id));
              controller.send(RealtimeResponseCreateEvent(response: RealtimeResponse()));
            }
        }
      });
    } else {
      throw ArgumentError("Already listening to controller");
    }
  }

  void didDetach(RealtimeSessionController controller) {
    final sub = _attachedTo.remove(controller);
    sub!.cancel();
  }
}

typedef RealtimeFunctionToolDelegateCallback = Future<String> Function(Map<String, dynamic> arguments);

class RealtimeFunctionToolDelegate extends RealtimeFunctionToolHandler {
  RealtimeFunctionToolDelegate({
    required super.metadata,
    required this.handler,
  });

  RealtimeFunctionToolDelegateCallback handler;

  @override
  Future<RealtimeFunctionCallOutput> call(RealtimeFunctionCall call) async {
    final result = await handler(jsonDecode(call.arguments));
    return call.output(result);
  }
}
