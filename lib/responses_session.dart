import 'dart:async';
import 'dart:convert';
import 'common.dart';
import 'exceptions.dart';
import 'openai_client.dart';
import 'responses.dart';

class MissingResponseCompletedException extends OpenAIException {
  MissingResponseCompletedException() : super(message: "stream did not return a response completed event");
}

class MissingToolException extends OpenAIException {
  MissingToolException(String name)
      : name = name,
        super(message: "a tool was missing: $name");

  final String name;
}

class ResponsesSessionController {
  ResponsesSessionController(
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
      this.stream = true}) {
    if (tools != null) {
      this.addTools(tools);
    }
  }

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

  final List<ToolHandler> _tools = [];
  Iterable<ToolHandler> get tools {
    return _tools;
  }

  Future<void> addTools(List<ToolHandler> tools) async {
    for (final tool in tools) {
      if (this._tools.any((t) => t.metadata.matches(tool.metadata))) {
        throw new ArgumentError("tool ${tool.metadata} is already added");
      }
    }

    for (final tool in tools) {
      this._tools.add(tool);
    }
  }

  Future<void> removeTools(List<ToolHandler> tools) async {
    for (final tool in tools) {
      if (!this._tools.any((t) => t.metadata.matches(tool.metadata))) {
        throw new ArgumentError("tool ${tool.metadata} cannot be removed because it was not found");
      }
    }

    for (final tool in tools) {
      this._tools.remove(tool);
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
        for (final tool in this._tools) {
          final e = tool.getHandler(event);
          if (e != null) {
            await _handle(event, e);
          }
        }

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
          final events = [
            ResponseOutputItemAdded(item: output, outputIndex: index, sequenceNumber: _sequenceNumber++),
            ResponseOutputItemDone(item: output, outputIndex: index, sequenceNumber: _sequenceNumber++),
            ResponseCompleted(response: response, sequenceNumber: _sequenceNumber++)
          ];

          for (final evt in events) {
            for (final tool in this._tools) {
              final e = tool.getHandler(evt);
              if (e != null) {
                await _handle(evt, e);
              }
            }

            serverEventsController.add(evt);
          }
          index++;
        }
        return response;
      } on OpenAIRequestException catch (e) {
        final response = Response(error: ResponseError(code: e.code ?? "", message: e.message, param: e.param));
        serverEventsController.add(ResponseFailed(response: response, sequenceNumber: _sequenceNumber++));
        rethrow;
      }
    }
  }

  void didBeginHandling(ResponseEvent item) {}
  void didEndHandling(ResponseEvent item) {}

  void didCompleteClientTurn(Response response) {
    if (store == true) {
      previousResponseId = response.id;
      this.input = ResponseInputItems([..._pendingOutputs.values.whereType<ResponseItem>()]);
    } else {
      if (input is ResponseInputItems) {
        this.input = ResponseInputItems([
          ...(input as ResponseInputItems).items,
          if (response.output != null) ...response.output!,
          ..._pendingOutputs.values.whereType<ResponseItem>()
        ]);
      } else if (input is ResponseInputText) {
        final text = input as ResponseInputText;
        this.input = ResponseInputItems([
          InputText(role: "user", text: text.text),
          if (response.output != null) ...response.output!,
          ..._pendingOutputs.values.whereType<ResponseItem>()
        ]);
      } else {
        throw ArgumentError("There was no input or input was unexpected");
      }
    }

    _pendingOutputs.clear();
  }

  Future<void> _handle(ResponseEvent input, Future<ResponseItem?> Function(ResponsesSessionController) handler) async {
    _registerPendingOutput(input);

    didBeginHandling(input);

    final output = await handler(this);
    if (output != null) {
      _addLocalOutput(input, output);
    } else {
      _pendingOutputs.remove(input);
    }

    didEndHandling(input);

    for (final entry in _pendingOutputs.entries) {
      if (entry.value == null) {
        return;
      }
    }
  }

  void _addLocalOutput(ResponseEvent input, ResponseItem output) {
    if (_pendingOutputs[input] == null) {
      _pendingOutputs[input] = output;
    } else {
      throw ArgumentError("The output was already sent for $input");
    }
  }

  void _registerPendingOutput(ResponseEvent input) {
    _pendingOutputs[input] = null;
  }

  final Map<ResponseEvent, ResponseItem?> _pendingOutputs = {};

  Future<Response> _takeTurn() async {
    Response lastResponse = await _createResponse();

    didCompleteClientTurn(lastResponse);

    final error = lastResponse.error;
    if (error != null) {
      throw OpenAIRequestException(
          message: error.message, code: error.code, param: error.param, statusCode: -1); // TODO: need to pull status code from response?
    }

    return lastResponse;
  }

  Future<Response> nextResponse([bool autoIterate = true]) async {
    Response response;
    do {
      response = await _takeTurn();

      if (response.error != null) {
        return response;
      }
      if (response.outputText != null) {
        return response;
      }
    } while (autoIterate);

    return response;
  }
}

abstract class ToolHandler<TMeta extends Tool> {
  ToolHandler({required this.metadata});

  final TMeta metadata;

  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event);
}

abstract class ToolCallHandler<TMeta extends Tool, TInput extends ResponseItem, TOutput extends ResponseItem> extends ToolHandler<TMeta> {
  ToolCallHandler({required super.metadata});

  Future<TOutput> call(ResponsesSessionController controller, TInput call);
}

abstract class FunctionToolHandler extends ToolCallHandler<FunctionTool, FunctionCall, FunctionCallOutput> {
  FunctionToolHandler({required super.metadata});

  Future<String> execute(ResponsesSessionController controller, Map<String, dynamic> arguments);

  String translateError(Object error) {
    return "The function call failed with the following error: $error";
  }

  @override
  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event) {
    if (event is ResponseOutputItemDone && event.item is FunctionCall && (event.item as FunctionCall).name == metadata.name) {
      return (controller) => call(controller, event.item as FunctionCall);
    }

    return null;
  }

  @override
  Future<FunctionCallOutput> call(ResponsesSessionController controller, FunctionCall call) async {
    try {
      final result = await execute(controller, jsonDecode(call.arguments));
      return call.output(result);
    } catch (e) {
      return call.output(translateError(e));
    }
  }
}

abstract class FileSearchToolHandler extends ToolHandler<FileSearchTool> {
  FileSearchToolHandler({required super.metadata});

  @override
  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event) {
    if (event is ResponseFileSearchCallEvent) {
      return (controller) async {
        onFileSearch(controller, event);
        return null;
      };
    }
    return null;
  }

  Future<void> onFileSearch(ResponsesSessionController controller, ResponseFileSearchCallEvent e);
}

abstract class WebSearchToolHandler extends ToolHandler<WebSearchPreviewTool> {
  WebSearchToolHandler({required super.metadata});

  @override
  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event) {
    if (event is ResponseWebSearchCallEvent) {
      return (controller) async {
        onWebSearch(controller, event);
        return null;
      };
    }
    return null;
  }

  Future<void> onWebSearch(ResponsesSessionController controller, ResponseWebSearchCallEvent e);
}

abstract class McpToolHandler extends ToolHandler<McpTool> {
  McpToolHandler({required super.metadata});

  @override
  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event) {
    if (event is ResponseMcpCallEvent) {
      return (controller) async {
        onMcpCall(controller, event);
        return null;
      };
    }
    return null;
  }

  Future<void> onMcpCall(ResponsesSessionController controller, ResponseMcpCallEvent e);
}

abstract class CodeInterpreterToolHandler extends ToolHandler<CodeInterpreterTool> {
  CodeInterpreterToolHandler({required super.metadata});

  @override
  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event) {
    if (event is ResponseCodeInterpreterCallEvent) {
      return (controller) async {
        onCodeInterpreterCall(controller, event);
        return null;
      };
    }
    return null;
  }

  Future<void> onCodeInterpreterCall(ResponsesSessionController controller, ResponseCodeInterpreterCallEvent e);
}

abstract class ImageGenerationToolHandler extends ToolHandler {
  ImageGenerationToolHandler({required super.metadata});

  @override
  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event) {
    if (event is ResponseImageGenerationCallEvent) {
      return (controller) async {
        onImageGenerationCall(controller, event);
        return null;
      };
    }
    return null;
  }

  Future<void> onImageGenerationCall(ResponsesSessionController controller, ResponseImageGenerationCallEvent e);
}

abstract class LocalShellToolHandler extends ToolCallHandler<LocalShellTool, LocalShellCall, LocalShellCallOutput> {
  LocalShellToolHandler({required super.metadata});

  @override
  Future<ResponseItem?> Function(ResponsesSessionController)? getHandler(ResponseEvent event) {
    if (event is LocalShellCall) {
      return (controller) async {
        onLocalShellToolCall(controller, event as LocalShellCall);
        return null;
      };
    }
    return null;
  }

  Future<LocalShellCallOutput> onLocalShellToolCall(ResponsesSessionController controller, LocalShellCall e);
}

abstract class ComputerUsePreviewToolHandler extends ToolCallHandler<ComputerUsePreviewTool, ComputerCall, ComputerCallOutput> {
  ComputerUsePreviewToolHandler({required super.metadata});
}
