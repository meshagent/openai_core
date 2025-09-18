import 'dart:async';

import 'package:openai/common.dart';
import 'package:openai/exceptions.dart';
import 'package:openai/openai_client.dart';
import 'package:openai/responses.dart';

class MissingResponseCompletedException extends OpenAIException {
  MissingResponseCompletedException() : super(message: "stream did not return a response completed event");
}

class MissingToolException extends OpenAIException {
  MissingToolException(String name)
      : name = name,
        super(message: "a tool was missing: $name");

  final String name;
}

class EventLoop {
  EventLoop(
      {required this.client,
      this.background,
      this.input,
      this.include,
      this.instructions,
      this.maxOutputTokens,
      this.metadata,
      this.model,
      this.parallelToolCalls,
      this.previousResponseId,
      this.reasoning,
      this.store,
      this.temperature,
      this.text,
      this.toolChoice,
      List<ToolHandler>? tools,
      this.topP,
      this.truncation,
      this.user,
      this.stream = true})
      : this._tools = tools ?? const [];

  final OpenAIClient client;

  bool stream;
  bool? background;
  List<String>? include;
  Input? input;
  String? instructions;
  int? maxOutputTokens;
  Map<String, dynamic>? metadata;
  ChatModel? model;
  bool? parallelToolCalls;
  String? previousResponseId;
  ReasoningOptions? reasoning;
  bool? store;
  num? temperature;
  TextFormat? text;
  ToolChoice? toolChoice;

  num? topP;
  Truncation? truncation;
  String? user;

  final serverEventsController = StreamController<ResponseEvent>();

  Stream<ResponseEvent> get serverEvents {
    return serverEventsController.stream;
  }

  final List<ToolHandler> _tools;
  Iterable<ToolHandler> get tools {
    return _tools;
  }

  Future<void> addTools(List<ToolHandler> tools) async {
    for (final tool in tools) {
      if (this._tools.any((t) => t.metadata.matches(tool.metadata))) {
        throw new ArgumentError("tool ${tool.metadata} cannot be added is already attached");
      }
    }

    for (final tool in tools) {
      this._tools.add(tool);
      tool.didAttach(this);
    }
  }

  Future<void> removeTools(List<ToolHandler> tools) async {
    for (final tool in tools) {
      if (!this._tools.any((t) => t.metadata.matches(tool.metadata))) {
        throw new ArgumentError("tool ${tool.metadata} cannot be removed because it is not attached");
      }
    }

    for (final tool in tools) {
      this._tools.remove(tool);
      tool.didDetach(this);
    }
  }

  int _sequenceNumber = 0;

  Future<Response> _createResponse() async {
    if (stream) {
      final responseStream = await client.streamResponse(
        background: background,
        include: include,
        input: input,
        instructions: instructions,
        maxOutputTokens: maxOutputTokens,
        metadata: metadata,
        model: model,
        parallelToolCalls: parallelToolCalls,
        previousResponseId: previousResponseId,
        reasoning: reasoning,
        store: store,
        temperature: temperature,
        text: text,
        toolChoice: toolChoice,
        tools: tools.map((t) => t.metadata).toList(),
        topP: topP,
        truncation: truncation,
        user: user,
      );

      await for (final event in responseStream.events) {
        serverEventsController.sink.add(event);
        switch (event) {
          case ResponseCompleted():
            return event.response;
        }
      }
      throw MissingResponseCompletedException();
    } else {
      try {
        final response = await client.createResponse(
          background: background,
          include: include,
          input: input,
          instructions: instructions,
          maxOutputTokens: maxOutputTokens,
          metadata: metadata,
          model: model,
          parallelToolCalls: parallelToolCalls,
          previousResponseId: previousResponseId,
          reasoning: reasoning,
          store: store,
          temperature: temperature,
          text: text,
          toolChoice: toolChoice,
          tools: tools.map((t) => t.metadata).toList(),
          topP: topP,
          truncation: truncation,
          user: user,
        );
        int index = 0;
        for (final output in response.output ?? []) {
          serverEventsController.add(ResponseOutputItemAdded(item: output, outputIndex: index, sequenceNumber: _sequenceNumber++));
          serverEventsController.add(ResponseOutputItemDone(item: output, outputIndex: index, sequenceNumber: _sequenceNumber++));
          index++;
        }
        serverEventsController.add(ResponseCompleted(response: response, sequenceNumber: _sequenceNumber++));
        return response;
      } on OpenAIRequestException catch (e) {
        final response = Response(error: ResponseError(code: e.code ?? "", message: e.message, param: e.param));
        serverEventsController.add(ResponseFailed(response: response, sequenceNumber: _sequenceNumber++));
        rethrow;
      }
    }
  }

  void didBeginHandling(ResponseItem item) {}
  void didEndHandling(ResponseItem item) {}

  void didCompleteClientTurn() {
    if (store == true) {
      this.input = ResponseInputItems([..._pendingOutputs.values.whereType<ResponseItem>()]);
    } else {
      if (input is ResponseInputItems) {
        this.input = ResponseInputItems([...(input as ResponseInputItems).items, ..._pendingOutputs.values.whereType<ResponseItem>()]);
      } else if (input is ResponseInputText) {
        final text = input as ResponseInputText;
        this.input = ResponseInputItems([InputText(role: "user", text: text.text), ..._pendingOutputs.values.whereType<ResponseItem>()]);
      } else {
        throw ArgumentError("There was no input");
      }
    }
    // TODO: notify user

    _pendingOutputs.clear();
  }

  void handle(ResponseItem input, Future<ResponseItem> Function(ResponseItem) handler) async {
    _registerPendingOutput(input);

    didBeginHandling(input);

    _addLocalOutput(input, await handler(input));

    didEndHandling(input);

    for (final entry in _pendingOutputs.entries) {
      if (entry.value == null) {
        return;
      }
    }

    // TODO: what if response is still in progress? need to wait for server turn to complete first.
    didCompleteClientTurn();
  }

  void _addLocalOutput(ResponseItem input, ResponseItem output) {
    if (_pendingOutputs[input] == null) {
      _pendingOutputs[input] = output;
    } else {
      throw ArgumentError("The output was already sent for $input");
    }
  }

  void _registerPendingOutput(ResponseItem input) {
    _pendingOutputs[input] = null;
  }

  final Map<ResponseItem, ResponseItem?> _pendingOutputs = {};

  Future<Response> tick() async {
    Response lastResponse = await _createResponse();

    final error = lastResponse.error;
    if (error != null) {
      throw OpenAIRequestException(
          message: error.message, code: error.code, param: error.param, statusCode: 200); // TODO: need to pull status code from response?
    }
    if (store == true) {
      previousResponseId = lastResponse.id;
    } else {
      this.input = ResponseInputItems([...(input as ResponseInputItems).items, ...lastResponse.output ?? []]);
    }
    return lastResponse;
  }
}
