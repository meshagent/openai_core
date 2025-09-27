import 'dart:async';
import 'dart:convert';

import 'images.dart';

import 'common.dart';
import 'exceptions.dart';
import 'openai_client.dart';
import 'sse_client.dart';

extension ResponsesAPI on OpenAIClient {
  Future<Response> createResponse({
    bool? background,
    List<String>? include,
    Input? input,
    String? instructions,
    int? maxOutputTokens,
    Map<String, dynamic>? metadata,
    ChatModel? model,
    bool? parallelToolCalls,
    String? previousResponseId,
    ReasoningOptions? reasoning,
    bool? store,
    num? temperature,
    TextFormat? text,
    ToolChoice? toolChoice,
    List<Tool>? tools,
    num? topP,
    Truncation? truncation,
    String? user,
  }) async {
    final resp = await postJson("/responses", {
      if (background != null) 'background': background,
      if (include != null) 'include': include,
      if (input != null) 'input': input.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
      if (metadata != null) 'metadata': metadata,
      if (model != null) 'model': model.toJson(),
      if (parallelToolCalls != null) 'parallel_tool_calls': parallelToolCalls,
      if (previousResponseId != null) 'previous_response_id': previousResponseId,
      if (reasoning != null) 'reasoning': reasoning.toJson(),
      if (store != null) 'store': store,
      if (temperature != null) 'temperature': temperature,
      if (text != null) 'text': text.toJson(),
      if (toolChoice != null) 'tool_choice': toolChoice.toJson(),
      if (tools != null) 'tools': tools.map((t) => t.toJson()).toList(),
      if (topP != null) 'top_p': topP,
      if (truncation != null) 'truncation': truncation.toJson(),
      if (user != null) 'user': user,
    });

    if (resp.statusCode == 200) {
      return Response.fromJson(jsonDecode(resp.body));
    } else {
      throw OpenAIRequestException.fromHttpResponse(resp);
    }
  }

  Future<ResponseStream> streamResponse({
    bool? background,
    List<String>? include,
    Input? input,
    String? instructions,
    int? maxOutputTokens,
    Map<String, dynamic>? metadata,
    ChatModel? model,
    bool? parallelToolCalls,
    String? previousResponseId,
    ReasoningOptions? reasoning,
    bool? store,
    num? temperature,
    TextFormat? text,
    ToolChoice? toolChoice,
    List<Tool>? tools,
    num? topP,
    Truncation? truncation,
    String? user,
  }) async {
    final sse = streamJson("/responses", {
      "stream": true,
      if (background != null) 'background': background,
      if (include != null) 'include': include,
      if (input != null) 'input': input.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
      if (metadata != null) 'metadata': metadata,
      if (model != null) 'model': model.toJson(),
      if (parallelToolCalls != null) 'parallel_tool_calls': parallelToolCalls,
      if (previousResponseId != null) 'previous_response_id': previousResponseId,
      if (reasoning != null) 'reasoning': reasoning.toJson(),
      if (store != null) 'store': store,
      if (temperature != null) 'temperature': temperature,
      if (text != null) 'text': text.toJson(),
      if (toolChoice != null) 'tool_choice': toolChoice.toJson(),
      if (tools != null) 'tools': tools.map((t) => t.toJson()).toList(),
      if (topP != null) 'top_p': topP,
      if (truncation != null) 'truncation': truncation.toJson(),
      if (user != null) 'user': user,
    });

    return ResponseStream(sse);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status enums
// ─────────────────────────────────────────────────────────────────────────────

class FunctionToolCallStatus extends JsonEnum {
  static const inProgress = FunctionToolCallStatus('in_progress');
  static const completed = FunctionToolCallStatus('completed');
  static const incomplete = FunctionToolCallStatus('incomplete');

  const FunctionToolCallStatus(super.value);

  static FunctionToolCallStatus fromJson(String raw) => FunctionToolCallStatus(raw);
}

class ReasoningOutputStatus extends JsonEnum {
  static const inProgress = ReasoningOutputStatus('in_progress');
  static const completed = ReasoningOutputStatus('completed');
  static const incomplete = ReasoningOutputStatus('incomplete');

  const ReasoningOutputStatus(super.value);

  static ReasoningOutputStatus fromJson(String raw) => ReasoningOutputStatus(raw);
}

class ImageGenerationCallStatus extends JsonEnum {
  static const inProgress = ImageGenerationCallStatus('in_progress');
  static const generating = ImageGenerationCallStatus('generating');
  static const completed = ImageGenerationCallStatus('completed');
  static const failed = ImageGenerationCallStatus('failed');
  static const incomplete = ImageGenerationCallStatus('incomplete');

  const ImageGenerationCallStatus(super.value);

  static ImageGenerationCallStatus fromJson(String raw) => ImageGenerationCallStatus(raw);
}

class CodeInterpreterToolCallStatus extends JsonEnum {
  static const inProgress = CodeInterpreterToolCallStatus('in_progress');
  static const running = CodeInterpreterToolCallStatus('running');
  static const completed = CodeInterpreterToolCallStatus('completed');
  static const failed = CodeInterpreterToolCallStatus('failed');
  static const incomplete = CodeInterpreterToolCallStatus('incomplete');

  const CodeInterpreterToolCallStatus(super.value);

  static CodeInterpreterToolCallStatus fromJson(String raw) => CodeInterpreterToolCallStatus(raw);
}

class LocalShellCallStatus extends JsonEnum {
  static const inProgress = LocalShellCallStatus('in_progress');
  static const running = LocalShellCallStatus('running');
  static const completed = LocalShellCallStatus('completed');
  static const failed = LocalShellCallStatus('failed');
  static const incomplete = LocalShellCallStatus('incomplete');

  const LocalShellCallStatus(super.value);

  static LocalShellCallStatus fromJson(String raw) => LocalShellCallStatus(raw);
}

class ImageGenerationBackground extends JsonEnum {
  static const transparent = ImageGenerationBackground('transparent');
  static const opaque = ImageGenerationBackground('opaque');
  static const auto = ImageGenerationBackground('auto');

  const ImageGenerationBackground(super.value);

  static ImageGenerationBackground fromJson(String raw) => ImageGenerationBackground(raw);
}

class Truncation extends JsonEnum {
  static const auto = Truncation('auto');
  static const disabled = Truncation('disabled');

  const Truncation(super.value);

  static Truncation fromJson(String raw) => Truncation(raw);
}

class ImageOutputFormat extends JsonEnum {
  static const png = ImageOutputFormat('png');
  static const webp = ImageOutputFormat('webp');
  static const jpeg = ImageOutputFormat('jpeg');

  const ImageOutputFormat(super.value);

  static ImageOutputFormat fromJson(String raw) => ImageOutputFormat(raw);
}

class ImageOutputQuality extends JsonEnum {
  static const low = ImageOutputQuality('low');
  static const medium = ImageOutputQuality('medium');
  static const high = ImageOutputQuality('high');
  static const auto = ImageOutputQuality('auto');

  const ImageOutputQuality(super.value);

  static ImageOutputQuality fromJson(String raw) => ImageOutputQuality(raw);
}

class ImageOutputSize extends JsonEnum {
  static const auto = ImageOutputSize('auto');
  // ── Square sizes (all models) ──────────────────────────────────────────
  static const square256 = ImageOutputSize('256x256'); // DALL·E-2
  static const square512 = ImageOutputSize('512x512'); // DALL·E-2
  static const square1024 = ImageOutputSize('1024x1024'); // all models

  // ── Landscape (width > height) ─────────────────────────────────────────
  static const landscape1536x1024 = ImageOutputSize('1536x1024'); // gpt-image-1
  static const landscape1792x1024 = ImageOutputSize('1792x1024'); // DALL·E-3

  // ── Portrait (height > width) ─────────────────────────────────────────
  static const portrait1024x1536 = ImageOutputSize('1024x1536'); // gpt-image-1
  static const portrait1024x1792 = ImageOutputSize('1024x1792'); // DALL·E-3

  const ImageOutputSize(super.value);

  static ImageOutputSize fromJson(String raw) => ImageOutputSize(raw);
}

class ServiceTier extends JsonEnum {
  static const auto = ServiceTier('auto');
  static const defaultTier = ServiceTier('default');
  static const flex = ServiceTier('flex');
  static const other = ServiceTier('other');

  const ServiceTier(super.value);

  static ServiceTier fromJson(String raw) => ServiceTier(raw);
}

class ReasoningDetail extends JsonEnum {
  static const auto = ReasoningDetail('auto');
  static const concise = ReasoningDetail('concise');
  static const detailed = ReasoningDetail('detailed');
  static const other = ReasoningDetail('other');

  const ReasoningDetail(super.value);

  static ReasoningDetail fromJson(String raw) => ReasoningDetail(raw);
}

class ReasoningEffort extends JsonEnum {
  static const low = ReasoningEffort('low');
  static const medium = ReasoningEffort('medium');
  static const high = ReasoningEffort('high');

  const ReasoningEffort(super.value);

  static ReasoningEffort fromJson(String raw) => ReasoningEffort(raw);
}

class ReasoningOptions {
  const ReasoningOptions({
    this.effort,
    this.summary,
  });

  factory ReasoningOptions.fromJson(Map<String, dynamic> json) => ReasoningOptions(
        effort: json['effort'] == null ? null : ReasoningEffort.fromJson(json["effort"]),
        summary: json['summary'] == null ? null : ReasoningDetail.fromJson(json['summary'] as String),
      );

  final ReasoningEffort? effort;
  final ReasoningDetail? summary;

  Map<String, dynamic> toJson() => {
        if (effort != null) 'effort': effort,
        if (summary != null) 'summary': summary!.toJson(),
      };
}

abstract class TextFormat {
  const TextFormat();

  Map<String, dynamic> toJson();

  factory TextFormat.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'text':
        return const TextFormatText();
      case 'json_object':
        return const TextFormatJsonObject();
      case 'json_schema':
        return TextFormatJsonSchema(
          name: json['name'] as String,
          schema: json['schema'],
          description: json['description'] as String?,
          strict: json['strict'] as bool?,
        );
      default:
        return TextFormatOther(json);
    }
  }
}

class TextFormatText extends TextFormat {
  const TextFormatText();
  @override
  Map<String, dynamic> toJson() => {
        'format': {'type': 'text'}
      };
}

class TextFormatJsonObject extends TextFormat {
  const TextFormatJsonObject();
  @override
  Map<String, dynamic> toJson() => {
        'format': {'type': 'json_object'}
      };
}

class TextFormatJsonSchema extends TextFormat {
  const TextFormatJsonSchema({
    required this.name,
    required this.schema,
    this.description,
    this.strict,
  });

  final String name;
  final Map<String, dynamic> schema;
  final String? description;
  final bool? strict;

  @override
  Map<String, dynamic> toJson() => {
        "format": {
          'type': 'json_schema',
          'name': name,
          'schema': schema,
          if (description != null) 'description': description,
          if (strict != null) 'strict': strict,
        }
      };
}

class TextFormatOther extends TextFormat {
  const TextFormatOther(this.raw);
  final Map<String, dynamic> raw;
  @override
  Map<String, dynamic> toJson() => raw;
}

class LogProbs {
  const LogProbs(this.entries);

  factory LogProbs.fromJson(List<dynamic> raw) => LogProbs(raw.cast<Map<String, dynamic>>().map(LogProb.fromJson).toList());

  final List<LogProb> entries;

  List<Map<String, dynamic>> toJson() => entries.map((e) => e.toJson()).toList();
}

abstract class ResponseItem {
  const ResponseItem();

  Map<String, dynamic> toJson();

  // Factory parses *all* 17 shapes defined by the REST spec
  factory ResponseItem.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      // ───────── Tool outputs / calls ─────────
      case 'computer_call_output':
        return ComputerCallOutput(
          callId: json['call_id'],
          output: ComputerScreenshotOutput.fromJson(json['output'] as Map<String, dynamic>),
          acknowledgedSafetyChecks:
              (json['acknowledged_safety_checks'] as List?)?.cast<Map<String, dynamic>>().map(ComputerSafetyCheck.fromJson).toList(),
          id: json['id'],
          status: json['status'] == null ? null : ComputerResultStatus.fromJson(json['status']),
        );
      case 'file_search_call':
        return FileSearchCall(
          id: json['id'],
          queries: List<String>.from(json['queries']),
          status: FileSearchToolCallStatus.fromJson(json['status']),
          results: (json['results'] as List?)?.cast<Map<String, dynamic>>().map(FileSearchToolCallResult.fromJson).toList(),
        );
      case 'web_search_call':
        return WebSearchCall(
          id: json['id'],
          status: WebSearchToolCallStatus.fromJson(json['status']),
        );
      case 'local_shell_call':
        return LocalShellCall(
          id: json['id'],
          callId: json['call_id'],
          action: LocalShellAction.fromJson(json["action"]),
          status: LocalShellCallStatus.fromJson(json['status']),
        );
      case 'local_shell_call_output':
        return LocalShellCallOutput(
          callId: json['id'], // REST names the field "id"
          output: json['output'],
          status: json['status'] == null ? null : LocalShellCallStatus.fromJson(json['status']),
        );
      case 'mcp_call':
        return McpCall(
          id: json['id'],
          name: json['name'],
          argumentsJson: json['arguments'],
          serverLabel: json['server_label'],
          error: json['error'],
          output: json['output'],
        );
      case 'mcp_list_tools':
        return McpListTools(
          id: json['id'],
          serverLabel: json['server_label'],
          tools: (json['tools'] as List).cast<Map<String, dynamic>>().map(MCPListToolItem.fromJson).toList(),
          error: json['error'],
        );
      case 'mcp_approval_request':
        return McpApprovalRequest(
          id: json['id'],
          arguments: json['arguments'],
          name: json['name'],
          serverLabel: json['server_label'],
        );
      case 'mcp_approval_response':
        return McpApprovalResponse(
          approvalRequestId: json['approval_request_id'],
          approve: json['approve'],
          id: json['id'],
          reason: json['reason'],
        );
      case 'function_call_output':
        return FunctionCallOutput(
          callId: json['call_id'],
          output: json['output'],
          status: json['status'] == null ? null : FunctionToolCallStatus.fromJson(json['status']),
          id: json['id'],
        );
      case 'function_call':
        return FunctionCall(
          arguments: json['arguments'],
          callId: json['call_id'],
          name: json['name'],
          id: json['id'],
          status: json['status'] == null ? null : FunctionToolCallStatus.fromJson(json['status']),
        );
      case 'image_generation_call':
        return ImageGenerationCall(
          id: json['id'],
          status: ImageGenerationCallStatus.fromJson(json['status']),
          resultBase64: json['result'],
        );

      case 'code_interpreter_call':
        return CodeInterpreterCall(
          id: json['id'],
          code: json['code'],
          results: json['results'] == null
              ? null
              : (json['results'] as List).cast<Map<String, dynamic>>().map(CodeInterpreterResult.fromJson).toList(),
          status: CodeInterpreterToolCallStatus.fromJson(json['status']),
          containerId: json['container_id'],
        );
      case 'reasoning':
        return Reasoning(
          id: json['id'],
          summary: (json['summary'] as List).map((a) => ReasoningSummary.fromJson(a)).toList(),
          encryptedContent: json['encrypted_content'],
          status: json['status'] == null ? null : ReasoningOutputStatus.fromJson(json['status']),
        );
      case 'item_reference':
        return ItemReference(id: json['id']);

      case 'computer_call':
        return ComputerCall(
          id: json['id'],
          callId: json['call_id'],
          action: ComputerAction.fromJson(json['action'] as Map<String, dynamic>),
          pendingSafetyChecks:
              (json['pending_safety_checks'] as List).cast<Map<String, dynamic>>().map(ComputerSafetyCheck.fromJson).toList(),
          status: json['status'] == null ? null : ComputerResultStatus.fromJson(json['status']),
        );
      // ───────── Messages (three shapes) ─────────
      case 'message':
        final content = json['content'];
        if (content is String) {
          return InputText(role: json['role'], text: content);
        }
        if (json.containsKey('id') && json.containsKey('status')) {
          return OutputMessage(
            role: json['role'],
            content: (content as List).cast<Map<String, dynamic>>().map(ResponseContent.fromJson).toList(),
            id: json['id'],
            status: json['status'],
          );
        }
        return InputMessage(
          role: json['role'],
          content: (content as List).cast<Map<String, dynamic>>().map(ResponseContent.fromJson).toList(),
        );
      default:
        return OtherResponseItem(json);
    }
  }
}

class ReasoningSummary {
  const ReasoningSummary({required this.text});

  /// Human-readable short summary of the model’s reasoning.
  final String text;

  /* ––––– JSON helpers ––––– */

  factory ReasoningSummary.fromJson(Map<String, dynamic> j) => ReasoningSummary(text: j['text'] as String);

  Map<String, dynamic> toJson() => {'type': 'summary_text', 'text': text};

  @override
  String toString() => 'ReasoningSummaryItem("$text")';
}

/* ────────────────────────────────────────────────────────────────────────── */
/* Computer-use tool call                                                    */
/* ────────────────────────────────────────────────────────────────────────── */

/// Base-class for every computer-action payload.
abstract class ComputerAction {
  const ComputerAction();

  /// `"click"`, `"double_click"`, …
  String get type;

  Map<String, dynamic> toJson();

  /* ––– dynamic factory ––– */
  static ComputerAction fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'click':
        return ComputerActionClick(
          x: j['x'],
          y: j['y'],
          button: j['button'],
        );
      case 'double_click':
        return ComputerActionDoubleClick(x: j['x'], y: j['y']);
      case 'drag':
        return ComputerActionDrag(
          path: (j['path'] as List).cast<Map<String, dynamic>>().map((p) => Point(x: p['x'], y: p['y'])).toList(),
        );
      case 'keypress':
        return ComputerActionKeyPress(keys: List<String>.from(j['keys']));
      case 'move':
        return ComputerActionMove(x: j['x'], y: j['y']);
      case 'screenshot':
        return const ComputerActionScreenshot();
      case 'scroll':
        return ComputerActionScroll(
          x: j['x'],
          y: j['y'],
          scrollX: j['scroll_x'],
          scrollY: j['scroll_y'],
        );
      case 'type':
        return ComputerActionType(text: j['text']);
      case 'wait':
        return const ComputerActionWait();
      default:
        return OtherComputerAction(j);
    }
  }
}

class OtherComputerAction extends ComputerAction {
  OtherComputerAction(this.json);

  Map<String, dynamic> json;

  @override
  String get type => 'click';

  @override
  Map<String, dynamic> toJson() => json;
}

class Point {
  const Point({required this.x, required this.y});
  final int x;
  final int y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class ComputerActionClick extends ComputerAction {
  const ComputerActionClick({required this.x, required this.y, required this.button});
  final int x, y;
  final String button; // left, right, wheel, back, forward

  @override
  String get type => 'click';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'x': x, 'y': y, 'button': button};
}

class ComputerActionDoubleClick extends ComputerAction {
  const ComputerActionDoubleClick({required this.x, required this.y});
  final int x, y;

  @override
  String get type => 'double_click';
  @override
  Map<String, dynamic> toJson() => {'type': type, 'x': x, 'y': y};
}

class ComputerActionDrag extends ComputerAction {
  const ComputerActionDrag({required this.path});
  final List<Point> path;

  @override
  String get type => 'drag';
  @override
  Map<String, dynamic> toJson() => {'type': type, 'path': path.map((p) => p.toJson()).toList()};
}

class ComputerActionKeyPress extends ComputerAction {
  const ComputerActionKeyPress({required this.keys});
  final List<String> keys;

  @override
  String get type => 'keypress';
  @override
  Map<String, dynamic> toJson() => {'type': type, 'keys': keys};
}

class ComputerActionMove extends ComputerAction {
  const ComputerActionMove({required this.x, required this.y});
  final int x, y;

  @override
  String get type => 'move';
  @override
  Map<String, dynamic> toJson() => {'type': type, 'x': x, 'y': y};
}

class ComputerActionScreenshot extends ComputerAction {
  const ComputerActionScreenshot();
  @override
  String get type => 'screenshot';
  @override
  Map<String, dynamic> toJson() => {'type': type};
}

class ComputerActionScroll extends ComputerAction {
  const ComputerActionScroll({required this.x, required this.y, required this.scrollX, required this.scrollY});
  final int x, y;
  final int scrollX, scrollY;

  @override
  String get type => 'scroll';
  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'x': x,
        'y': y,
        'scroll_x': scrollX,
        'scroll_y': scrollY,
      };
}

class ComputerActionType extends ComputerAction {
  const ComputerActionType({required this.text});
  final String text;

  @override
  String get type => 'type';
  @override
  Map<String, dynamic> toJson() => {'type': type, 'text': text};
}

class ComputerActionWait extends ComputerAction {
  const ComputerActionWait();
  @override
  String get type => 'wait';
  @override
  Map<String, dynamic> toJson() => {'type': type};
}

class ComputerCall extends ResponseItem {
  const ComputerCall({
    required this.id,
    required this.callId,
    required this.action,
    required this.pendingSafetyChecks,
    this.status,
  });

  final String id;
  final String callId;
  final ComputerAction action;
  final List<ComputerSafetyCheck> pendingSafetyChecks;
  final ComputerResultStatus? status; // in_progress | completed | incomplete

  ComputerCallOutput output(ComputerScreenshotOutput output,
      {List<ComputerSafetyCheck>? acknowledgedSafetyChecks, ComputerResultStatus? status, String? id}) {
    return ComputerCallOutput(callId: callId, output: output, status: status, id: id, acknowledgedSafetyChecks: acknowledgedSafetyChecks);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'computer_call',
        'id': id,
        'call_id': callId,
        'action': action.toJson(),
        'pending_safety_checks': pendingSafetyChecks.map((c) => c.toJson()).toList(),
        if (status != null) 'status': status!.toJson(),
      };
}

class ComputerCallOutput extends ResponseItem {
  const ComputerCallOutput({
    required this.callId,
    required this.output,
    this.acknowledgedSafetyChecks,
    this.id,
    this.status,
  });

  final String callId;
  final ComputerScreenshotOutput output;
  final List<ComputerSafetyCheck>? acknowledgedSafetyChecks;
  final String? id;
  final ComputerResultStatus? status;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'computer_call_output',
        'call_id': callId,
        'output': output.toJson(),
        if (acknowledgedSafetyChecks != null) 'acknowledged_safety_checks': acknowledgedSafetyChecks!.map((e) => e.toJson()).toList(),
        if (id != null) 'id': id,
        if (status != null) 'status': status!.toJson(),
      };
}

class FileSearchCall extends ResponseItem {
  const FileSearchCall({
    required this.id,
    required this.queries,
    required this.status,
    this.results,
  });

  final String id;
  final List<String> queries;
  final FileSearchToolCallStatus status;
  final List<FileSearchToolCallResult>? results;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'file_search_call',
        'id': id,
        'queries': queries,
        'status': status.toJson(),
        if (results != null) 'results': results!.map((e) => e.toJson()).toList(),
      };
}

class WebSearchCall extends ResponseItem {
  const WebSearchCall({
    required this.id,
    required this.status,
  });

  final String id;
  final WebSearchToolCallStatus status;

  @override
  Map<String, dynamic> toJson() => {'type': 'web_search_call', 'id': id, 'status': status.toJson()};
}

class LocalShellCall extends ResponseItem {
  const LocalShellCall({
    required this.id,
    required this.callId,
    required this.action,
    required this.status,
  });

  final String id;
  final String callId;
  final LocalShellAction action;
  final LocalShellCallStatus status;

  LocalShellCallOutput output(String output, {LocalShellCallStatus? status, String? id}) {
    return LocalShellCallOutput(callId: callId, output: output, status: status);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'local_shell_call',
        'id': id,
        'call_id': callId,
        'action': action.toJson(),
        'status': status.toJson(),
      };
}

class LocalShellCallOutput extends ResponseItem {
  const LocalShellCallOutput({
    required this.callId,
    required this.output,
    this.status,
  });

  final String callId;
  final String output;
  final LocalShellCallStatus? status;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'local_shell_call_output',
        'call_id': callId,
        'output': output,
        if (status != null) 'status': status!.toJson(),
      };
}

class McpCall extends ResponseItem {
  const McpCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
    required this.serverLabel,
    this.error,
    this.output,
  });

  final String id;
  final String name;
  final String argumentsJson;
  final String serverLabel;
  final String? error;
  final String? output;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'mcp_call',
        'id': id,
        'name': name,
        'arguments': argumentsJson,
        'server_label': serverLabel,
        if (error != null) 'error': error,
        if (output != null) 'output': output,
      };
}

class McpListTools extends ResponseItem {
  const McpListTools({
    required this.id,
    required this.serverLabel,
    required this.tools,
    this.error,
  });

  final String id;
  final String serverLabel;
  final List<MCPListToolItem> tools;
  final String? error;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'mcp_list_tools',
        'id': id,
        'server_label': serverLabel,
        'tools': tools.map((t) => t.toJson()).toList(),
        if (error != null) 'error': error,
      };
}

class McpApprovalRequest extends ResponseItem {
  const McpApprovalRequest({
    required this.id,
    required this.arguments,
    required this.name,
    required this.serverLabel,
  });

  final String id;
  final String arguments;
  final String name;
  final String serverLabel;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'mcp_approval_request',
        'id': id,
        'arguments': arguments,
        'name': name,
        'server_label': serverLabel,
      };
}

class McpApprovalResponse extends ResponseItem {
  const McpApprovalResponse({
    required this.approvalRequestId,
    required this.approve,
    this.id,
    this.reason,
  });

  final String approvalRequestId;
  final bool approve;
  final String? id;
  final String? reason;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'mcp_approval_response',
        'approval_request_id': approvalRequestId,
        'approve': approve,
        if (id != null) 'id': id,
        if (reason != null) 'reason': reason,
      };
}

class FunctionCallOutput extends ResponseItem {
  const FunctionCallOutput({
    required this.callId,
    required this.output,
    this.status,
    this.id,
  });

  const FunctionCallOutput.text({
    required this.callId,
    required String output,
    this.status,
    this.id,
  }) : output = output;

  FunctionCallOutput.image({
    required this.callId,
    required InputImageContent output,
    this.status,
    this.id,
  }) : output = [output];

  FunctionCallOutput.file({
    required this.callId,
    required InputFileContent output,
    this.status,
    this.id,
  }) : output = [output];

  FunctionCallOutput.list({
    required this.callId,
    required List<ResponseContent> output,
    this.status,
    this.id,
  }) : output = output;

  final String callId;
  final dynamic output;
  final FunctionToolCallStatus? status;
  final String? id;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'function_call_output',
        'call_id': callId,
        'output': output,
        if (id != null) 'id': id,
        if (status != null) 'status': status!.toJson(),
      };
}

class FunctionCall extends ResponseItem {
  const FunctionCall({
    required this.arguments,
    required this.callId,
    required this.name,
    this.id,
    this.status,
  });

  final String arguments;
  final String callId;
  final String name;
  final String? id;
  final FunctionToolCallStatus? status;

  Map<String, dynamic> decodeArguments() {
    return jsonDecode(arguments);
  }

  FunctionCallOutput output(String output, {FunctionToolCallStatus? status, String? id}) {
    return FunctionCallOutput(callId: callId, output: output, status: status, id: id);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'function_call',
        'arguments': arguments,
        'call_id': callId,
        'name': name,
        if (id != null) 'id': id,
        if (status != null) 'status': status!.toJson(),
      };
}

class ImageGenerationCall extends ResponseItem {
  const ImageGenerationCall({
    required this.id,
    required this.status,
    this.resultBase64,
  });

  final String id;
  final ImageGenerationCallStatus status;
  final String? resultBase64;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'image_generation_call',
        'id': id,
        'status': status.toJson(),
        if (resultBase64 != null) 'result': resultBase64,
      };
}

class CodeInterpreterCall extends ResponseItem {
  const CodeInterpreterCall({
    required this.id,
    required this.code,
    this.results,
    required this.status,
    this.containerId,
  });

  final String id;
  final String code;
  final List<CodeInterpreterResult>? results;
  final CodeInterpreterToolCallStatus status;
  final String? containerId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'code_interpreter_call',
        'id': id,
        'code': code,
        if (results != null) 'results': results?.map((e) => e.toJson()).toList(),
        'status': status.toJson(),
        if (containerId != null) 'container_id': containerId,
      };
}

class Reasoning extends ResponseItem {
  const Reasoning({
    required this.id,
    required this.summary,
    this.encryptedContent,
    this.status,
  });

  final String id;
  final List<ReasoningSummary> summary;
  final String? encryptedContent;
  final ReasoningOutputStatus? status;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'reasoning',
        'id': id,
        'summary': summary,
        if (encryptedContent != null) 'encrypted_content': encryptedContent,
        if (status != null) 'status': status!.toJson(),
      };
}

class ItemReference extends ResponseItem {
  const ItemReference({required this.id});
  final String id;
  @override
  Map<String, dynamic> toJson() => {'type': 'item_reference', 'id': id};
}

// Three “message” shapes
class InputText extends ResponseItem {
  const InputText({required this.role, required this.text});
  final String role;
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'message', 'role': role, 'content': text};
}

class InputMessage extends ResponseItem {
  const InputMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final List<ResponseContent> content;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'message',
        'role': role,
        'content': content.map((e) => e.toJson()).toList(),
      };
}

class OutputMessage extends ResponseItem {
  const OutputMessage({
    required this.role,
    required this.content,
    required this.id,
    required this.status,
  });

  final String role;
  final List<ResponseContent> content;
  final String id;
  final String status;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'message',
        'role': role,
        'content': content.map((e) => e.toJson()).toList(),
        'id': id,
        'status': status,
      };
}

// Fallback / unknown
class OtherResponseItem extends ResponseItem {
  const OtherResponseItem(this.raw);
  final Map<String, dynamic> raw;

  @override
  Map<String, dynamic> toJson() => raw;
}

/// Top-level result object returned by the API.
class Response {
  // ── Core metadata ──────────────────────────────────────────────────────────
  final bool? background;
  final int? createdAt; // Unix epoch-seconds
  final ResponseError? error;
  final String? id;
  final IncompleteDetails? incompleteDetails;

  /// Either a single instruction string or an array of message objects.
  final dynamic instructions;

  final Input? input;
  final int? maxOutputTokens;
  final Map<String, dynamic>? metadata;
  final ChatModel? model;
  final bool? parallelToolCalls;
  final String? previousResponseId;
  final Map<String, dynamic>? prompt;
  final ReasoningOptions? reasoning;
  final ServiceTier? serviceTier;

  /// completed / failed / in_progress / cancelled / queued / incomplete
  final String? status;

  final num? temperature;
  final TextFormat? text;
  final ToolChoice? toolChoice;
  final List<Tool>? tools;
  final num? topP;
  final Truncation? truncation;
  final Usage? usage;
  final String? user;

  // ── Model output ───────────────────────────────────────────────────────────
  final List<ResponseItem>? output;
  String? get outputText {
    StringBuffer buf = StringBuffer();

    if (output != null) {
      for (final o in output!) {
        if (o is OutputMessage) {
          for (final content in o.content.whereType<OutputTextContent>()) {
            buf.write(content.text);
          }
        }
      }
    }
    if (buf.isEmpty) {
      return null;
    }
    return buf.toString();
  }

  const Response(
      {this.background,
      this.createdAt,
      this.error,
      this.id,
      this.incompleteDetails,
      this.instructions,
      this.input,
      this.maxOutputTokens,
      this.metadata,
      this.model,
      this.parallelToolCalls,
      this.previousResponseId,
      this.prompt,
      this.reasoning,
      this.serviceTier,
      this.status,
      this.temperature,
      this.text,
      this.toolChoice,
      this.tools,
      this.topP,
      this.truncation,
      this.usage,
      this.user,
      this.output});

  // ── Serialisation helpers ──────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'object': 'response',
        if (background != null) 'background': background,
        if (createdAt != null) 'created_at': createdAt,
        if (error != null) 'error': error!.toJson(),
        if (id != null) 'id': id,
        if (incompleteDetails != null) 'incomplete_details': incompleteDetails!.toJson(),
        if (instructions != null) 'instructions': instructions,
        if (input != null) 'input': input!.toJson(),
        if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
        if (metadata != null) 'metadata': metadata,
        if (model != null) 'model': model?.toJson(),
        if (parallelToolCalls != null) 'parallel_tool_calls': parallelToolCalls,
        if (previousResponseId != null) 'previous_response_id': previousResponseId,
        if (prompt != null) 'prompt': prompt,
        if (reasoning != null) 'reasoning': reasoning!.toJson(),
        if (serviceTier != null) 'service_tier': serviceTier!.toJson(),
        if (status != null) 'status': status,
        if (temperature != null) 'temperature': temperature,
        if (text != null) 'text': text!.toJson(),
        if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
        if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
        if (topP != null) 'top_p': topP,
        if (truncation != null) 'truncation': truncation!.toJson(),
        if (usage != null) 'usage': usage!.toJson(),
        if (user != null) 'user': user,
        if (output != null) 'output': output!.map((e) => e.toJson()).toList(),
      };

  factory Response.fromJson(Map<String, dynamic> json) => Response(
        background: json['background'] as bool?,
        createdAt: json['created_at'] as int?,
        error: json['error'] == null ? null : ResponseError.fromJson(json['error'] as Map<String, dynamic>),
        id: json['id'] as String?,
        incompleteDetails:
            json['incomplete_details'] == null ? null : IncompleteDetails.fromJson(json['incomplete_details'] as Map<String, dynamic>),
        instructions: json['instructions'],
        input: json['input'] == null ? null : Input.fromJson(json['input'] as Map<String, dynamic>),
        maxOutputTokens: json['max_output_tokens'] as int?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        model: json['model'] != null ? ChatModel.fromJson(json['model']) : null,
        parallelToolCalls: json['parallel_tool_calls'] as bool?,
        previousResponseId: json['previous_response_id'] as String?,
        prompt: json['prompt'] as Map<String, dynamic>?,
        reasoning: json['reasoning'] == null ? null : ReasoningOptions.fromJson(json['reasoning'] as Map<String, dynamic>),
        serviceTier: json['service_tier'] == null ? null : ServiceTier.fromJson(json['service_tier'] as String),
        status: json['status'] as String?,
        temperature: (json['temperature'] as num?),
        text: json['text'] == null ? null : TextFormat.fromJson(json['text'] as Map<String, dynamic>),
        toolChoice: json['tool_choice'] == null ? null : ToolChoice.fromJson(json['tool_choice']),
        tools: (json['tools'] as List?)?.map((e) => Tool.fromJson(e as Map<String, dynamic>)).toList(),
        topP: (json['top_p'] as num?),
        truncation: json['truncation'] == null ? null : Truncation.fromJson(json['truncation']),
        usage: json['usage'] == null ? null : Usage.fromJson(json['usage'] as Map<String, dynamic>),
        user: json['user'] as String?,
        output: (json['output'] as List?)?.map((e) => ResponseItem.fromJson(e as Map<String, dynamic>)).toList(),
      );

  @override
  String toString() => 'Response(id: $id, status: $status, model: $model, error: $error)';
}

/// Error information returned when the model fails to generate a response.
class ResponseError {
  /// A short machine-readable code, e.g. `"rate_limit_exceeded"`.
  final String? code;

  /// Human-readable explanation of the failure.
  final String message;

  /// Optional parameter name that caused the error, if applicable.
  final String? param;

  const ResponseError({
    required this.code,
    required this.message,
    this.param,
  });

  /// JSON-serialization helper.
  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (param != null) 'param': param,
      };

  /// JSON-deserialization helper.
  factory ResponseError.fromJson(Map<String, dynamic> json) => ResponseError(
        code: json['code'] as String?,
        message: json['message'] as String,
        param: json['param'] as String?,
      );

  @override
  String toString() => 'ResponseError(code: $code, message: $message, param: $param)';
}

/// Explains why the response is **incomplete**.
class IncompleteDetails {
  /// A short machine-readable reason for the incomplete result.
  final String reason;

  const IncompleteDetails({
    required this.reason,
  });

  /// Serialise to JSON.
  Map<String, dynamic> toJson() => {'reason': reason};

  /// Deserialise from JSON.
  factory IncompleteDetails.fromJson(Map<String, dynamic> json) => IncompleteDetails(reason: json['reason'] as String);

  @override
  String toString() => 'IncompleteDetails(reason: $reason)';
}

class WebSearchToolCallStatus extends JsonEnum {
  static const inProgress = WebSearchToolCallStatus('in_progress');
  static const searching = WebSearchToolCallStatus('searching');
  static const completed = WebSearchToolCallStatus('completed');
  static const incomplete = WebSearchToolCallStatus('incomplete');
  static const failed = WebSearchToolCallStatus('failed'); // fallback for unexpected values

  const WebSearchToolCallStatus(super.value);

  /// Parse from raw JSON.
  static WebSearchToolCallStatus fromJson(String raw) => WebSearchToolCallStatus(raw);
}

class ImageDetail extends JsonEnum {
  static const low = ImageDetail('low');
  static const auto = ImageDetail('auto');
  static const high = ImageDetail('high');

  const ImageDetail(super.value);

  static ImageDetail fromJson(String raw) => ImageDetail(raw);
}

class FileSearchToolCallStatus extends JsonEnum {
  static const inProgress = FileSearchToolCallStatus('in_progress');
  static const searching = FileSearchToolCallStatus('searching');
  static const incomplete = FileSearchToolCallStatus('incomplete');
  static const failed = FileSearchToolCallStatus('failed');
  static const completed = FileSearchToolCallStatus('completed');

  const FileSearchToolCallStatus(super.value);

  static FileSearchToolCallStatus fromJson(String raw) => FileSearchToolCallStatus(raw);
}

class ComputerSafetyCheckStatus extends JsonEnum {
  static const inProgress = ComputerSafetyCheckStatus('in_progress');
  static const completed = ComputerSafetyCheckStatus('completed');
  static const incomplete = ComputerSafetyCheckStatus('incomplete');

  const ComputerSafetyCheckStatus(super.value);

  static ComputerSafetyCheckStatus fromJson(String raw) => ComputerSafetyCheckStatus(raw);
}

abstract class Input {
  const Input();

  /// Serialise to the wire shape (string or array of ResponseItem JSON).
  dynamic toJson();

  /// Parse a raw value (string or list) coming back from the server.
  factory Input.fromJson(dynamic raw) {
    if (raw is String) return ResponseInputText(raw);
    if (raw is List) {
      return ResponseInputItems(
        raw.map((e) => e is ResponseItem ? e : ResponseItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
    }
    throw ArgumentError("Unexpected data return from responses call");
  }
}

/// Holds a single instruction / prompt string.
class ResponseInputText extends Input {
  const ResponseInputText(this.text);

  final String text;

  @override
  String toJson() => text;

  @override
  String toString() => 'ResponseInputText("$text")';
}

/// Holds a list of structured input items.
class ResponseInputItems extends Input {
  const ResponseInputItems(this.items);

  final List<ResponseItem> items;

  @override
  List<Map<String, dynamic>> toJson() => items.map((e) => e.toJson()).toList();

  @override
  String toString() => 'ResponseInputItems(len=${items.length})';
}

class ComputerResultStatus extends JsonEnum {
  static const inProgress = ComputerResultStatus('in_progress');
  static const completed = ComputerResultStatus('completed');
  static const incomplete = ComputerResultStatus('incomplete');

  const ComputerResultStatus(super.value);

  static ComputerResultStatus fromJson(String raw) => ComputerResultStatus(raw);
}

abstract class ResponseContent {
  const ResponseContent();

  Map<String, dynamic> toJson();

  factory ResponseContent.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'input_text':
        return InputTextContent(text: json['text'] as String);
      case 'input_image':
        return InputImageContent(
          detail: ImageDetail.fromJson(json['detail'] as String),
          imageUrl: json['image_url'] as String?,
          fileId: json['file_id'] as String?,
        );
      case 'input_file':
        return InputFileContent(
          fileId: json['file_id'] as String?,
          fileData: json['file_data'] as String?,
          filename: json['filename'] as String?,
        );
      case 'output_text':
        return OutputTextContent(
          text: json['text'] as String,
          annotations: (json['annotations'] as List).cast<Map<String, dynamic>>().map(Annotation.fromJson).toList(),
          logProbs: (json['log_probs'] as List?)?.cast<Map<String, dynamic>>().map(LogProb.fromJson).toList(),
        );
      case 'refusal':
        return RefusalContent(refusal: json['refusal'] as String);
      default:
        return OtherResponseContent(json);
    }
  }
}

/// Simple wrapper for unexpected shapes.
class OtherResponseContent extends ResponseContent {
  const OtherResponseContent(this.raw);
  final Map<String, dynamic> raw;

  @override
  Map<String, dynamic> toJson() => raw;
}

/// `input_text`
class InputTextContent extends ResponseContent {
  const InputTextContent({required this.text});
  final String text;
  @override
  Map<String, dynamic> toJson() => {'type': 'input_text', 'text': text};
}

/// `input_image` (by URL **or** by file-ID)
class InputImageContent extends ResponseContent {
  const InputImageContent({
    required this.detail,
    this.imageUrl,
    this.fileId,
  });
  final ImageDetail detail;
  final String? imageUrl;
  final String? fileId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'input_image',
        'detail': detail.toJson(),
        if (imageUrl != null) 'image_url': imageUrl,
        if (fileId != null) 'file_id': fileId,
      };
}

/// `input_file` (inline or by ID)
class InputFileContent extends ResponseContent {
  const InputFileContent({
    this.fileId,
    this.fileData,
    this.filename,
  });
  final String? fileId;
  final String? fileData;
  final String? filename;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'input_file',
        if (fileId != null) 'file_id': fileId,
        if (fileData != null) 'file_data': fileData,
        if (filename != null) 'filename': filename,
      };
}

/// `output_text`
class OutputTextContent extends ResponseContent {
  const OutputTextContent({
    required this.annotations,
    required this.text,
    this.logProbs,
  });

  final List<Annotation> annotations;
  final String text;
  final List<LogProb>? logProbs;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'output_text',
        'text': text,
        'annotations': annotations.map((e) => e.toJson()).toList(),
        if (logProbs != null) 'log_probs': logProbs!.map((e) => e.toJson()).toList(),
      };
}

/// `refusal`
class RefusalContent extends ResponseContent {
  const RefusalContent({required this.refusal});
  final String refusal;
  @override
  Map<String, dynamic> toJson() => {'type': 'refusal', 'refusal': refusal};
}

class FileSearchToolCallResult {
  const FileSearchToolCallResult({
    this.attributes,
    this.fileId,
    this.filename,
    this.score,
    this.text,
  });

  factory FileSearchToolCallResult.fromJson(Map<String, dynamic> json) => FileSearchToolCallResult(
        attributes: json['attributes'] as Map<String, dynamic>?,
        fileId: json['file_id'] as String?,
        filename: json['filename'] as String?,
        score: (json['score'] as num?),
        text: json['text'] as String?,
      );

  final Map<String, dynamic>? attributes;
  final String? fileId;
  final String? filename;
  final num? score;
  final String? text;

  Map<String, dynamic> toJson() => {
        if (attributes != null) 'attributes': attributes,
        if (fileId != null) 'file_id': fileId,
        if (filename != null) 'filename': filename,
        if (score != null) 'score': score,
        if (text != null) 'text': text,
      };
}

class ComputerSafetyCheck {
  const ComputerSafetyCheck({
    required this.code,
    required this.id,
    required this.message,
    required this.status,
  });

  factory ComputerSafetyCheck.fromJson(Map<String, dynamic> json) => ComputerSafetyCheck(
        code: json['code'] as String,
        id: json['id'] as String,
        message: json['message'] as String,
        status: ComputerSafetyCheckStatus.fromJson(json['status'] as String),
      );

  final String code;
  final String id;
  final String message;
  final ComputerSafetyCheckStatus status;

  Map<String, dynamic> toJson() => {
        'code': code,
        'id': id,
        'message': message,
        'status': status.toJson(),
      };
}

class ComputerScreenshotOutput {
  const ComputerScreenshotOutput({this.fileId, this.imageUrl});

  factory ComputerScreenshotOutput.fromJson(Map<String, dynamic> json) => ComputerScreenshotOutput(
        fileId: json['file_id'] as String?,
        imageUrl: json['image_url'] as String?,
      );

  final String? fileId;
  final String? imageUrl;

  Map<String, dynamic> toJson() => {
        'type': 'computer_screenshot',
        if (fileId != null) 'file_id': fileId,
        if (imageUrl != null) 'image_url': imageUrl,
      };
}

class CodeInterpreterResultFile {
  const CodeInterpreterResultFile({this.id, this.fileId, this.filename});

  factory CodeInterpreterResultFile.fromJson(Map<String, dynamic> json) => CodeInterpreterResultFile(
        id: json['id'] as String?,
        fileId: json['file_id'] as String?,
        filename: json['filename'] as String?,
      );

  final String? id;
  final String? fileId;
  final String? filename;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (fileId != null) 'file_id': fileId,
        if (filename != null) 'filename': filename,
      };
}

abstract class CodeInterpreterResult {
  const CodeInterpreterResult();

  Map<String, dynamic> toJson();

  factory CodeInterpreterResult.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'logs':
        return CodeInterpreterLogs(json['logs'] as String);
      case 'files':
        return CodeInterpreterFiles(
          (json['files'] as List).cast<Map<String, dynamic>>().map(CodeInterpreterResultFile.fromJson).toList(),
        );
      default:
        return CodeInterpreterResultOther(json);
    }
  }
}

class CodeInterpreterLogs extends CodeInterpreterResult {
  const CodeInterpreterLogs(this.logs);
  final String logs;
  @override
  Map<String, dynamic> toJson() => {'type': 'logs', 'logs': logs};
}

class CodeInterpreterFiles extends CodeInterpreterResult {
  const CodeInterpreterFiles(this.files);
  final List<CodeInterpreterResultFile> files;
  @override
  Map<String, dynamic> toJson() => {'type': 'files', 'files': files.map((e) => e.toJson()).toList()};
}

class CodeInterpreterResultOther extends CodeInterpreterResult {
  const CodeInterpreterResultOther(this.raw);
  final Map<String, dynamic> raw;
  @override
  Map<String, dynamic> toJson() => raw;
}

abstract class Annotation {
  const Annotation();

  Map<String, dynamic> toJson();

  factory Annotation.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'file_citation':
        return FileCitation(
          fileId: json['file_id'] as String,
          index: json['index'] as int,
        );
      case 'url_citation':
        return UrlCitation(
          startIndex: json['start_index'] as int,
          endIndex: json['end_index'] as int,
          title: json['title'] as String,
          url: json['url'] as String,
        );
      case 'container_file_citation':
        return ContainerFileCitation(
          containerId: json['container_id'] as String,
          fileId: json['file_id'] as String,
          startIndex: json['start_index'] as int,
          endIndex: json['end_index'] as int,
        );
      case 'file_path':
        return FilePath(
          fileId: json['file_id'] as String,
          index: json['index'] as int,
        );
      default:
        return OtherAnnotation(json);
    }
  }
}

class FileCitation extends Annotation {
  const FileCitation({
    required this.fileId,
    required this.index,
  });
  final String fileId;
  final int index;

  @override
  Map<String, dynamic> toJson() => {'type': 'file_citation', 'file_id': fileId, 'index': index};
}

class UrlCitation extends Annotation {
  const UrlCitation({
    required this.startIndex,
    required this.endIndex,
    required this.title,
    required this.url,
  });

  final int startIndex;
  final int endIndex;
  final String title;
  final String url;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'url_citation',
        'start_index': startIndex,
        'end_index': endIndex,
        'title': title,
        'url': url,
      };
}

class ContainerFileCitation extends Annotation {
  const ContainerFileCitation({
    required this.containerId,
    required this.fileId,
    required this.startIndex,
    required this.endIndex,
  });

  final String containerId;
  final String fileId;
  final int startIndex;
  final int endIndex;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'container_file_citation',
        'container_id': containerId,
        'file_id': fileId,
        'start_index': startIndex,
        'end_index': endIndex,
      };
}

class FilePath extends Annotation {
  const FilePath({
    required this.fileId,
    required this.index,
  });

  final String fileId;
  final int index;

  @override
  Map<String, dynamic> toJson() => {'type': 'file_path', 'file_id': fileId, 'index': index};
}

class OtherAnnotation extends Annotation {
  const OtherAnnotation(this.raw);
  final Map<String, dynamic> raw;
  @override
  Map<String, dynamic> toJson() => raw;
}

class LocalShellAction {
  const LocalShellAction({
    required this.command,
    required this.env,
    this.timeoutMs,
    this.user,
    this.workingDirectory,
  });

  factory LocalShellAction.fromJson(Map<String, dynamic> json) => LocalShellAction(
        command: List<String>.from(json['command'] as List),
        env: Map<String, String>.from(json['env'] as Map),
        timeoutMs: json['timeout_ms'] as int?,
        user: json['user'] as String?,
        workingDirectory: json['working_directory'] as String?,
      );

  final List<String> command;
  final Map<String, String> env;
  final int? timeoutMs;
  final String? user;
  final String? workingDirectory;

  Map<String, dynamic> toJson() => {
        'type': 'exec',
        'command': command,
        'env': env,
        if (timeoutMs != null) 'timeout_ms': timeoutMs,
        if (user != null) 'user': user,
        if (workingDirectory != null) 'working_directory': workingDirectory,
      };
}

class SearchContextSize extends JsonEnum {
  static const low = SearchContextSize('low');
  static const medium = SearchContextSize('medium');
  static const high = SearchContextSize('high');
  static const other = SearchContextSize('other');

  const SearchContextSize(super.value);

  static SearchContextSize fromJson(String raw) => SearchContextSize(raw);
}

class UserLocation {
  const UserLocation({
    this.city,
    this.country,
    this.region,
    this.timezone,
  });

  factory UserLocation.fromJson(Map<String, dynamic> json) => UserLocation(
        city: json['city'] as String?,
        country: json['country'] as String?,
        region: json['region'] as String?,
        timezone: json['timezone'] as String?,
      );

  final String? city;
  final String? country;
  final String? region;
  final String? timezone;

  Map<String, dynamic> toJson() => {
        'type': 'approximate',
        if (city != null) 'city': city,
        if (country != null) 'country': country,
        if (region != null) 'region': region,
        if (timezone != null) 'timezone': timezone,
      };
}

class RankingOptions {
  const RankingOptions({this.ranker, this.scoreThreshold});

  factory RankingOptions.fromJson(Map<String, dynamic> json) => RankingOptions(
        ranker: json['ranker'] as String?,
        scoreThreshold: (json['score_threshold'] as num?),
      );

  final String? ranker;
  final num? scoreThreshold;

  Map<String, dynamic> toJson() => {
        if (ranker != null) 'ranker': ranker,
        if (scoreThreshold != null) 'score_threshold': scoreThreshold,
      };
}

abstract class InputImageMask {
  const InputImageMask();

  factory InputImageMask.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('image_url')) {
      return InputImageMaskUrl(json['image_url'] as String);
    }
    return InputImageMaskFile(json['file_id'] as String);
  }

  Map<String, dynamic> toJson();
}

class InputImageMaskUrl extends InputImageMask {
  const InputImageMaskUrl(this.imageUrl);
  final String imageUrl;

  @override
  Map<String, dynamic> toJson() => {'image_url': imageUrl};
}

class InputImageMaskFile extends InputImageMask {
  const InputImageMaskFile(this.fileId);
  final String fileId;

  @override
  Map<String, dynamic> toJson() => {'file_id': fileId};
}

abstract class CodeInterpreterContainer {
  const CodeInterpreterContainer();

  factory CodeInterpreterContainer.fromJson(dynamic raw) {
    if (raw is String) return CodeInterpreterContainerId(raw);
    // expect {"type":"auto", "file_ids":[...]}
    return CodeInterpreterContainerAuto(
      fileIds: List<String>.from((raw as Map)['file_ids'] ?? const []),
    );
  }

  dynamic toJson();
}

class CodeInterpreterContainerId extends CodeInterpreterContainer {
  const CodeInterpreterContainerId(this.containerId);
  final String containerId;

  @override
  dynamic toJson() => containerId;
}

class CodeInterpreterContainerAuto extends CodeInterpreterContainer {
  const CodeInterpreterContainerAuto({this.fileIds});
  final List<String>? fileIds;

  @override
  Map<String, dynamic> toJson() => {'type': 'auto', if (fileIds != null) 'file_ids': fileIds};
}

class MCPListToolItem {
  const MCPListToolItem({
    required this.inputSchema,
    required this.name,
    this.annotations,
    this.description,
  });

  /// Factory to parse the wire shape.
  factory MCPListToolItem.fromJson(Map<String, dynamic> json) => MCPListToolItem(
        inputSchema: Map<String, dynamic>.from(json['input_schema'] as Map),
        name: json['name'] as String,
        annotations: (json['annotations'] as Map?)?.cast<String, dynamic>(),
        description: json['description'] as String?,
      );

  /// JSON Schema for the tool’s `arguments` payload.
  final Map<String, dynamic> inputSchema;

  /// Tool identifier used when calling it.
  final String name;

  /// Optional free-form annotations.
  final Map<String, dynamic>? annotations;

  /// Optional human-readable description.
  final String? description;

  Map<String, dynamic> toJson() => {
        'input_schema': inputSchema,
        'name': name,
        if (annotations != null) 'annotations': annotations,
        if (description != null) 'description': description,
      };

  @override
  String toString() => 'MCPListToolItem(name: $name)';
}

abstract class MCPToolApproval {
  const MCPToolApproval();

  factory MCPToolApproval.fromJson(dynamic raw) {
    if (raw == 'always') return const MCPToolApprovalAlways();
    if (raw == 'never') return const MCPToolApprovalNever();
    final map = raw as Map<String, dynamic>;
    return MCPToolApprovalList(
      always: (map['always'] as List?)?.cast<String>(),
      never: (map['never'] as List?)?.cast<String>(),
    );
  }

  dynamic toJson();
}

class MCPToolApprovalAlways extends MCPToolApproval {
  const MCPToolApprovalAlways();
  @override
  String toJson() => 'always';
}

class MCPToolApprovalNever extends MCPToolApproval {
  const MCPToolApprovalNever();
  @override
  String toJson() => 'never';
}

class MCPToolApprovalList extends MCPToolApproval {
  const MCPToolApprovalList({this.always, this.never});
  final List<String>? always;
  final List<String>? never;

  @override
  Map<String, dynamic> toJson() => {'always': always, 'never': never}..removeWhere((k, v) => v == null);
}

abstract class FileSearchFilter {
  const FileSearchFilter();

  factory FileSearchFilter.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    if (type == 'and' || type == 'or') {
      final filters = (json['filters'] as List).cast<Map<String, dynamic>>().map(FileSearchFilter.fromJson).toList();
      return type == 'and' ? FileSearchFilterAnd(filters) : FileSearchFilterOr(filters);
    }
    return _SimpleFileSearchFilter(
      op: type,
      key: json['key'] as String,
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson();
}

class _SimpleFileSearchFilter extends FileSearchFilter {
  const _SimpleFileSearchFilter({
    required this.op,
    required this.key,
    required this.value,
  });

  final String op; // eq, ne, gt, gte, lt, lte
  final String key;
  final dynamic value;

  @override
  Map<String, dynamic> toJson() => {'type': op, 'key': key, 'value': value};
}

class FileSearchFilterAnd extends FileSearchFilter {
  const FileSearchFilterAnd(this.filters);
  final List<FileSearchFilter> filters;

  @override
  Map<String, dynamic> toJson() => {'type': 'and', 'filters': filters.map((f) => f.toJson()).toList()};
}

class FileSearchFilterOr extends FileSearchFilter {
  const FileSearchFilterOr(this.filters);
  final List<FileSearchFilter> filters;

  @override
  Map<String, dynamic> toJson() => {'type': 'or', 'filters': filters.map((f) => f.toJson()).toList()};
}

abstract class ToolChoice {
  const ToolChoice();

  dynamic toJson();

  factory ToolChoice.fromJson(dynamic raw) {
    if (raw is String) {
      switch (raw) {
        case 'auto':
          return const ToolChoiceAuto();
        case 'none':
          return const ToolChoiceNone();
        case 'required':
          return const ToolChoiceRequired();
      }
    }
    final map = raw as Map<String, dynamic>;
    switch (map['type']) {
      case 'file_search':
        return const ToolChoiceFileSearch();
      case 'web_search_preview':
        return const ToolChoiceWebSearchPreview();
      case 'computer_use_preview':
        return const ToolChoiceComputerUsePreview();
      case 'code_interpreter':
        return const ToolChoiceCodeInterpreter();
      case 'mcp':
        return const ToolChoiceMcp();
      case 'image_generation':
        return const ToolChoiceImageGeneration();
      case 'function_tool':
        return ToolChoiceFunction(name: map['name'] as String);
      default:
        return ToolChoiceOther(raw);
    }
  }
}

class ToolChoiceAuto extends ToolChoice {
  const ToolChoiceAuto();
  @override
  String toJson() => 'auto';
}

class ToolChoiceNone extends ToolChoice {
  const ToolChoiceNone();
  @override
  String toJson() => 'none';
}

class ToolChoiceRequired extends ToolChoice {
  const ToolChoiceRequired();
  @override
  String toJson() => 'required';
}

class ToolChoiceFileSearch extends ToolChoice {
  const ToolChoiceFileSearch();
  @override
  Map<String, dynamic> toJson() => {'type': 'file_search'};
}

class ToolChoiceWebSearchPreview extends ToolChoice {
  const ToolChoiceWebSearchPreview();
  @override
  Map<String, dynamic> toJson() => {'type': 'web_search_preview'};
}

class ToolChoiceComputerUsePreview extends ToolChoice {
  const ToolChoiceComputerUsePreview();
  @override
  Map<String, dynamic> toJson() => {'type': 'computer_use_preview'};
}

class ToolChoiceCodeInterpreter extends ToolChoice {
  const ToolChoiceCodeInterpreter();
  @override
  Map<String, dynamic> toJson() => {'type': 'code_interpreter'};
}

class ToolChoiceMcp extends ToolChoice {
  const ToolChoiceMcp();
  @override
  Map<String, dynamic> toJson() => {'type': 'mcp'};
}

class ToolChoiceImageGeneration extends ToolChoice {
  const ToolChoiceImageGeneration();
  @override
  Map<String, dynamic> toJson() => {'type': 'image_generation'};
}

class ToolChoiceFunction extends ToolChoice {
  const ToolChoiceFunction({required this.name});
  final String name;
  @override
  Map<String, dynamic> toJson() => {'type': 'function', 'name': name};
}

class ToolChoiceOther extends ToolChoice {
  const ToolChoiceOther(this.raw);
  final dynamic raw;
  @override
  dynamic toJson() => raw;
}

abstract class Tool {
  const Tool();

  /// Whether the tool matches this one, if a tool matches another tool will be considered a duplicate
  bool matches(Tool tool) {
    return tool.runtimeType == this.runtimeType;
  }

  Map<String, dynamic> toJson();

  factory Tool.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'function_tool':
        return FunctionTool(
          name: json['name'] as String,
          parameters: Map<String, dynamic>.from(json['parameters'] as Map),
          strict: json['strict'] as bool?,
          description: json['description'] as String?,
        );
      case 'file_search':
        return FileSearchTool(
          vectorStoreIds: (json['vector_store_ids'] as List?)?.cast<String>() ?? const [],
          filters: (json['filters'] as List?)?.cast<Map<String, dynamic>>().map(FileSearchFilter.fromJson).toList(),
          maxNumResults: json['max_num_results'] as int?,
          rankingOptions: json['ranking_options'] == null ? null : RankingOptions.fromJson(json['ranking_options'] as Map<String, dynamic>),
        );
      case 'web_search_preview':
        return WebSearchPreviewTool(
          searchContextSize: json['search_context_size'] == null ? null : SearchContextSize.fromJson(json['search_context_size'] as String),
          userLocation: json['user_location'] == null ? null : UserLocation.fromJson(json['user_location'] as Map<String, dynamic>),
        );
      case 'computer_use_preview':
        return ComputerUsePreviewTool(
          displayHeight: json['display_height'] as int,
          displayWidth: json['display_width'] as int,
          environment: json['environment'] as String,
        );
      case 'mcp':
        return McpTool(
          serverLabel: json['server_label'] as String,
          serverUrl: json['server_url'] as String,
          allowedTools: (json['allowed_tools'] as List?)?.cast<String>(),
          headers: (json['headers'] as Map?)?.cast<String, String>(),
          requireApproval: json['require_approval'] == null ? null : MCPToolApproval.fromJson(json['require_approval']),
        );
      case 'code_interpreter':
        return CodeInterpreterTool(
          container: CodeInterpreterContainer.fromJson(json['container']),
        );
      case 'image_generation':
        return ImageGenerationTool(
          background: json['background'] == null ? null : ImageGenerationBackground.fromJson(json['background'] as String),
          inputImageMask:
              json['input_image_mask'] == null ? null : InputImageMask.fromJson(json['input_image_mask'] as Map<String, dynamic>),
          model: json['model'] as String?,
          moderation: json['moderation'] == null ? null : ImageModeration.fromJson(json['moderation'] as String),
          outputCompression: json['output_compression'] as int?,
          imageOutputFormat: json['output_format'] == null ? null : ImageOutputFormat.fromJson(json['output_format'] as String),
          partialImages: json['partial_images'] as int?,
          quality: json['quality'] == null ? null : ImageOutputQuality.fromJson(json['quality'] as String),
          imageOutputSize: json['size'] == null ? null : ImageOutputSize.fromJson(json['size'] as String),
        );
      case 'local_shell':
        return const LocalShellTool();
      default:
        return OtherTool(json);
    }
  }
}

/// — function_tool
class FunctionTool extends Tool {
  const FunctionTool({
    required this.name,
    required this.parameters,
    this.strict,
    this.description,
  });

  @override
  bool matches(Tool tool) {
    return tool is FunctionTool && tool.name == this.name;
  }

  final String name;
  final Map<String, dynamic> parameters;
  final bool? strict;
  final String? description;

  Future<FunctionCallOutput> call(FunctionCall call) {
    throw UnimplementedError();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'function',
        'name': name,
        'parameters': parameters,
        if (strict != null) 'strict': strict,
        if (description != null) 'description': description,
      };
}

/// — file_search
class FileSearchTool extends Tool {
  const FileSearchTool({
    required this.vectorStoreIds,
    this.filters,
    this.maxNumResults,
    this.rankingOptions,
  });

  final List<String> vectorStoreIds;
  final List<FileSearchFilter>? filters;
  final int? maxNumResults;
  final RankingOptions? rankingOptions;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'file_search',
        'vector_store_ids': vectorStoreIds,
        if (filters != null) 'filters': filters!.map((e) => e.toJson()).toList(),
        if (rankingOptions != null) 'ranking_options': rankingOptions!.toJson(),
        if (maxNumResults != null) 'max_num_results': maxNumResults,
      };
}

/// — web_search_preview
class WebSearchPreviewTool extends Tool {
  const WebSearchPreviewTool({this.searchContextSize, this.userLocation});
  final SearchContextSize? searchContextSize;
  final UserLocation? userLocation;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'web_search_preview',
        if (searchContextSize != null) 'search_context_size': searchContextSize!.toJson(),
        if (userLocation != null) 'user_location': userLocation!.toJson(),
      };
}

/// — computer_use_preview
class ComputerUsePreviewTool<T> extends Tool {
  const ComputerUsePreviewTool({
    required this.displayHeight,
    required this.displayWidth,
    required this.environment,
  });

  final int displayHeight;
  final int displayWidth;
  final String environment;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'computer_use_preview',
        'display_height': displayHeight,
        'display_width': displayWidth,
        'environment': environment,
      };
}

/// — mcp
class McpTool extends Tool {
  const McpTool({
    required this.serverLabel,
    required this.serverUrl,
    this.allowedTools,
    this.headers,
    this.requireApproval,
  });

  final String serverLabel;
  final String serverUrl;
  final List<String>? allowedTools;
  final Map<String, String>? headers;
  final MCPToolApproval? requireApproval;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'mcp',
        'server_label': serverLabel,
        'server_url': serverUrl,
        if (headers != null) 'headers': headers,
        if (allowedTools != null) 'allowed_tools': allowedTools,
        if (requireApproval != null) 'require_approval': requireApproval!.toJson(),
      };
}

/// — code_interpreter
class CodeInterpreterTool extends Tool {
  const CodeInterpreterTool({required this.container});
  final CodeInterpreterContainer container;

  @override
  Map<String, dynamic> toJson() => {'type': 'code_interpreter', 'container': container.toJson()};
}

/// — image_generation
class ImageGenerationTool extends Tool {
  const ImageGenerationTool({
    this.background,
    this.inputImageMask,
    this.model,
    this.moderation,
    this.outputCompression,
    this.imageOutputFormat,
    this.partialImages,
    this.quality,
    this.imageOutputSize,
  });

  final ImageGenerationBackground? background;
  final InputImageMask? inputImageMask;
  final String? model;
  final ImageModeration? moderation;
  final int? outputCompression;
  final ImageOutputFormat? imageOutputFormat;
  final int? partialImages;
  final ImageOutputQuality? quality;
  final ImageOutputSize? imageOutputSize;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'image_generation',
        if (background != null) 'background': background!.toJson(),
        if (inputImageMask != null) 'input_image_mask': inputImageMask!.toJson(),
        if (model != null) 'model': model,
        if (moderation != null) 'moderation': moderation!.toJson(),
        if (outputCompression != null) 'output_compression': outputCompression,
        if (imageOutputFormat != null) 'output_format': imageOutputFormat!.toJson(),
        if (partialImages != null) 'partial_images': partialImages,
        if (quality != null) 'quality': quality!.toJson(),
        if (imageOutputSize != null) 'size': imageOutputSize!.toJson(),
      };
}

/// — local_shell
class LocalShellTool extends Tool {
  const LocalShellTool();
  @override
  Map<String, dynamic> toJson() => {'type': 'local_shell'};
}

/// Fallback for bespoke tool types.
class OtherTool extends Tool {
  const OtherTool(this.raw);
  final Map<String, dynamic> raw;
  @override
  Map<String, dynamic> toJson() => raw;
}

class ResponseStream {
  ResponseStream(SseClient client) : _client = client {
    events = _client.stream.map((i) => ResponseEvent.fromJson(jsonDecode(i.data)));

    _client.stream.where((x) => x is ResponseCompleted).map((_) async => await close());
  }

  late Stream<ResponseEvent> events;

  SseClient _client;

  Future<void> close() async {
    await _client.close();
  }
}

abstract class ResponseEvent {
  const ResponseEvent(this.type);

  final String type;

  Map<String, dynamic> toJson();

  static ResponseEvent fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null) {
      throw ArgumentError('Event JSON is missing a "type" field.');
    }

    switch (type) {
      // ────────── Core response lifecycle ──────────
      case 'response.created':
        return ResponseCreated.fromJson(json);
      case 'response.in_progress':
        return ResponseInProgress.fromJson(json);
      case 'response.completed':
        return ResponseCompleted.fromJson(json);
      case 'response.failed':
        return ResponseFailed.fromJson(json);
      case 'response.incomplete':
        return ResponseIncomplete.fromJson(json);
      case 'response.queued':
        return ResponseQueued.fromJson(json);

      // ────────── Output-item level ──────────
      case 'response.output_item.added':
        return ResponseOutputItemAdded.fromJson(json);
      case 'response.output_item.done':
        return ResponseOutputItemDone.fromJson(json);

      // ────────── Content-part level ──────────
      case 'response.content_part.added':
        return ResponseContentPartAdded.fromJson(json);
      case 'response.content_part.done':
        return ResponseContentPartDone.fromJson(json);

      // ────────── Text streaming ──────────
      case 'response.output_text.delta':
        return ResponseOutputTextDelta.fromJson(json);
      case 'response.output_text.done':
        return ResponseOutputTextDone.fromJson(json);

      // ────────── Refusal streaming ──────────
      case 'response.refusal.delta':
        return ResponseRefusalDelta.fromJson(json);
      case 'response.refusal.done':
        return ResponseRefusalDone.fromJson(json);

      // ────────── Function-call arguments streaming ──────────
      case 'response.function_call_arguments.delta':
        return ResponseFunctionCallArgumentsDelta.fromJson(json);
      case 'response.function_call_arguments.done':
        return ResponeFunctionCallArgumentsDone.fromJson(json);

      // ────────── File-search lifecycle ──────────
      case 'response.file_search_call.in_progress':
        return ResponseFileSearchCallInProgress.fromJson(json);
      case 'response.file_search_call.searching':
        return ResponseFileSearchCallSearching.fromJson(json);
      case 'response.file_search_call.completed':
        return ResponseFileSearchCallCompleted.fromJson(json);

      // ────────── Web-search lifecycle ──────────
      case 'response.web_search_call.in_progress':
        return ResponseWebSearchCallInProgress.fromJson(json);
      case 'response.web_search_call.searching':
        return ResponseWebSearchCallSearching.fromJson(json);
      case 'response.web_search_call.completed':
        return ResponseWebSearchCallCompleted.fromJson(json);

      // ────────── Image-generation lifecycle ──────────
      case 'response.image_generation_call.in_progress':
        return ResponseImageGenerationCallInProgress.fromJson(json);
      case 'response.image_generation_call.generating':
        return ResponseImageGenerationCallGenerating.fromJson(json);
      case 'response.image_generation_call.completed':
        return ResponseImageGenerationCallCompleted.fromJson(json);
      case 'response.image_generation_call.partial_image':
        return ResponseImageGenerationCallPartialImage.fromJson(json);

      // ────────── Reasoning summary parts & text ──────────
      case 'response.reasoning_summary_part.added':
        return ResponseReasoningSummaryPartAdded.fromJson(json);
      case 'response.reasoning_summary_part.done':
        return ResponseReasoningSummaryPartDone.fromJson(json);
      case 'response.reasoning_summary_text.delta':
        return ResponseReasoningSummaryTextDelta.fromJson(json);
      case 'response.reasoning_summary_text.done':
        return ResponseReasoningSummaryTextDone.fromJson(json);

      // ────────── Reasoning content streaming ──────────
      case 'response.reasoning.delta':
        return ResponseReasoningDelta.fromJson(json);
      case 'response.reasoning.done':
        return ResponseReasoningDone.fromJson(json);
      case 'response.reasoning_summary.delta':
        return ResponseReasoningSummaryDelta.fromJson(json);
      case 'response.reasoning_summary.done':
        return ResponseReasoningSummaryDone.fromJson(json);

      // ────────── Output-text annotations ──────────
      case 'response.output_text.annotation.added':
        return ResponseTextAnnotationAdded.fromJson(json);

      // ────────── MCP tool-call lifecycle & arg streaming ──────────
      case 'response.mcp_call_arguments.delta':
        return ResponseMcpCallArgumentsDelta.fromJson(json);
      case 'response.mcp_call_arguments.done':
        return ResponseMcpCallArgumentsDone.fromJson(json);
      case 'response.mcp_call.in_progress':
        return ResponseMcpCallInProgress.fromJson(json);
      case 'response.mcp_call.completed':
        return ResponseMcpCallCompleted.fromJson(json);
      case 'response.mcp_call.failed':
        return ResponseMcpCallFailed.fromJson(json);

      // ────────── MCP list-tools lifecycle ──────────
      case 'response.mcp_list_tools.in_progress':
        return ResponseMcpListToolsInProgress.fromJson(json);
      case 'response.mcp_list_tools.completed':
        return ResponseMcpListToolsCompleted.fromJson(json);
      case 'response.mcp_list_tools.failed':
        return ResponseMcpListToolsFailed.fromJson(json);

      // ────────── Code-interpreter code streaming ──────────
      case 'response.code_interpreter_call_code.delta':
        return ResponseCodeInterpreterCallCodeDelta.fromJson(json);
      case 'response.code_interpreter_call_code.done':
        return ResponseCodeInterpreterCallCodeDone.fromJson(json);

      // ────────── Code-interpreter call lifecycle ──────────
      case 'response.code_interpreter_call.interpreting':
        return ResponseCodeInterpreterCallInterpreting.fromJson(json);
      case 'response.code_interpreter_call.in_progress':
        return ResponseCodeInterpreterCallInProgress.fromJson(json);
      case 'response.code_interpreter_call.completed':
        return ResponseCodeInterpreterCallCompleted.fromJson(json);

      // ────────── Generic stream-level error ──────────
      case 'error':
        return ErrorEvent.fromJson(json["error"]);

      // ────────── Unknown type ──────────
      default:
        return OtherResponseEvent(json);
    }
  }
}

/// Fallback wrapper for unseen summary part types.
class OtherResponseEvent extends ResponseEvent {
  OtherResponseEvent(this.raw) : super(raw["type"]);

  final Map<String, dynamic> raw;

  @override
  Map<String, dynamic> toJson() => raw;
}

/* ────────────────────────────────────────────────────────────────────────── */
/* Code-Interpreter tool events                                              */
/* ────────────────────────────────────────────────────────────────────────── */

abstract class ResponseCodeInterpreterCallEvent extends ResponseEvent {
  const ResponseCodeInterpreterCallEvent(
    super.type, {
    required this.itemId,
    required this.outputIndex,
    required this.sequenceNumber,
  });

  final String itemId;
  final int outputIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };
}

/* ── Code streaming ─────────────────────────────────────────────────────── */

class ResponseCodeInterpreterCallCodeDelta extends ResponseCodeInterpreterCallEvent {
  const ResponseCodeInterpreterCallCodeDelta({
    required super.itemId,
    required super.outputIndex,
    required super.sequenceNumber,
    required this.delta,
  }) : super('response.code_interpreter_call_code.delta');

  factory ResponseCodeInterpreterCallCodeDelta.fromJson(Map<String, dynamic> j) => ResponseCodeInterpreterCallCodeDelta(
        itemId: j['item_id'],
        outputIndex: j['output_index'],
        sequenceNumber: j['sequence_number'],
        delta: j['delta'],
      );

  final String delta;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'delta': delta};
}

class ResponseCodeInterpreterCallCodeDone extends ResponseCodeInterpreterCallEvent {
  const ResponseCodeInterpreterCallCodeDone({
    required super.itemId,
    required super.outputIndex,
    required super.sequenceNumber,
    required this.code,
  }) : super('response.code_interpreter_call_code.done');

  factory ResponseCodeInterpreterCallCodeDone.fromJson(Map<String, dynamic> j) => ResponseCodeInterpreterCallCodeDone(
        itemId: j['item_id'],
        outputIndex: j['output_index'],
        sequenceNumber: j['sequence_number'],
        code: j['code'],
      );

  final String code;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'code': code};
}

/* ── CI call lifecycle notifications ────────────────────────────────────── */

class ResponseCodeInterpreterCallInterpreting extends ResponseCodeInterpreterCallEvent {
  ResponseCodeInterpreterCallInterpreting(Map<String, dynamic> j)
      : super(
          'response.code_interpreter_call.interpreting',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  static ResponseCodeInterpreterCallInterpreting fromJson(Map<String, dynamic> j) => ResponseCodeInterpreterCallInterpreting(j);
}

class ResponseCodeInterpreterCallInProgress extends ResponseCodeInterpreterCallEvent {
  ResponseCodeInterpreterCallInProgress(Map<String, dynamic> j)
      : super(
          'response.code_interpreter_call.in_progress',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  static ResponseCodeInterpreterCallInProgress fromJson(Map<String, dynamic> j) => ResponseCodeInterpreterCallInProgress(j);
}

class ResponseCodeInterpreterCallCompleted extends ResponseCodeInterpreterCallEvent {
  ResponseCodeInterpreterCallCompleted(Map<String, dynamic> j)
      : super(
          'response.code_interpreter_call.completed',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  static ResponseCodeInterpreterCallCompleted fromJson(Map<String, dynamic> j) => ResponseCodeInterpreterCallCompleted(j);
}

/// Emitted whenever a new `Response` object is created.
class ResponseCreated extends ResponseEvent {
  const ResponseCreated({
    required this.response,
    required this.sequenceNumber,
  }) : super('response.created');

  factory ResponseCreated.fromJson(Map<String, dynamic> json) => ResponseCreated(
        response: Response.fromJson(json['response'] as Map<String, dynamic>),
        sequenceNumber: json['sequence_number'] as int,
      );

  /// The freshly created response.
  final Response response;

  /// Monotonic ordering number for this stream / session.
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // always "response.created"
        'response': response.toJson(),
        'sequence_number': sequenceNumber,
      };

  @override
  String toString() => 'ResponseEventCreated(seq=$sequenceNumber, id=${response.id})';
}

/// Emitted while a `Response` is still being generated (streaming).
class ResponseInProgress extends ResponseEvent {
  const ResponseInProgress({
    required this.response,
    required this.sequenceNumber,
  }) : super('response.in_progress');

  factory ResponseInProgress.fromJson(Map<String, dynamic> json) => ResponseInProgress(
        response: Response.fromJson(json['response'] as Map<String, dynamic>),
        sequenceNumber: json['sequence_number'] as int,
      );

  final Response response;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // always "response.in_progress"
        'response': response.toJson(),
        'sequence_number': sequenceNumber,
      };
}

/// Emitted once the model has fully finished generating a response.
class ResponseCompleted extends ResponseEvent {
  const ResponseCompleted({
    required this.response,
    required this.sequenceNumber,
  }) : super('response.completed');

  /// Parse from JSON.
  factory ResponseCompleted.fromJson(Map<String, dynamic> json) => ResponseCompleted(
        response: Response.fromJson(json['response'] as Map<String, dynamic>),
        sequenceNumber: json['sequence_number'] as int,
      );

  /// The fully materialised response object.
  final Response response;

  /// Monotonically increasing event index.
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // always "response.completed"
        'response': response.toJson(),
        'sequence_number': sequenceNumber,
      };

  @override
  String toString() => 'ResponseEventCompleted(seq=$sequenceNumber, id=${response.id})';
}

/// Emitted when the model fails to generate a response.
class ResponseFailed extends ResponseEvent {
  const ResponseFailed({
    required this.response,
    required this.sequenceNumber,
  }) : super('response.failed');

  /// Parse from the wire‐format JSON.
  factory ResponseFailed.fromJson(Map<String, dynamic> json) => ResponseFailed(
        response: Response.fromJson(json['response'] as Map<String, dynamic>),
        sequenceNumber: json['sequence_number'] as int,
      );

  /// The failed response object (usually contains an `error` field).
  final Response response;

  /// Monotonic ordering index for the event stream.
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // always "response.failed"
        'response': response.toJson(),
        'sequence_number': sequenceNumber,
      };

  @override
  String toString() => 'ResponseEventFailed(seq=$sequenceNumber, id=${response.id})';
}

/// Emitted when the model finishes but the response is *incomplete*.
class ResponseIncomplete extends ResponseEvent {
  const ResponseIncomplete({
    required this.response,
    required this.sequenceNumber,
  }) : super('response.incomplete');

  factory ResponseIncomplete.fromJson(Map<String, dynamic> json) => ResponseIncomplete(
        response: Response.fromJson(json['response'] as Map<String, dynamic>),
        sequenceNumber: json['sequence_number'] as int,
      );

  final Response response;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // always "response.incomplete"
        'response': response.toJson(),
        'sequence_number': sequenceNumber,
      };

  @override
  String toString() => 'ResponseEventIncomplete(seq=$sequenceNumber, id=${response.id})';
}

/// Emitted each time a new entry is appended to the `Response.output` array.
class ResponseOutputItemAdded extends ResponseEvent {
  const ResponseOutputItemAdded({
    required this.item,
    required this.outputIndex,
    required this.sequenceNumber,
  }) : super('response.output_item.added');

  /// Parse the wire-format JSON.
  factory ResponseOutputItemAdded.fromJson(Map<String, dynamic> json) => ResponseOutputItemAdded(
        item: ResponseItem.fromJson(json['item'] as Map<String, dynamic>),
        outputIndex: json['output_index'] as int,
        sequenceNumber: json['sequence_number'] as int,
      );

  /// The item just appended to the response’s `output` list.
  final ResponseItem item;

  /// Index of the item within `response.output`.
  final int outputIndex;

  /// Monotonic event number in this stream.
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // always "response.output_item.added"
        'item': item.toJson(),
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };

  @override
  String toString() => 'ResponseEventOutputItemAdded(seq=$sequenceNumber, idx=$outputIndex)';
}

class ResponseOutputItemDone extends ResponseEvent {
  const ResponseOutputItemDone({
    required this.item,
    required this.outputIndex,
    required this.sequenceNumber,
  }) : super('response.output_item.done');

  factory ResponseOutputItemDone.fromJson(Map<String, dynamic> json) => ResponseOutputItemDone(
        item: ResponseItem.fromJson(json['item'] as Map<String, dynamic>),
        outputIndex: json['output_index'] as int,
        sequenceNumber: json['sequence_number'] as int,
      );

  final ResponseItem item;
  final int outputIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item': item.toJson(),
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };
}

class ResponseContentPartAdded extends ResponseEvent {
  const ResponseContentPartAdded({
    required this.part,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.sequenceNumber,
  }) : super('response.content_part.added');

  factory ResponseContentPartAdded.fromJson(Map<String, dynamic> json) => ResponseContentPartAdded(
        part: ResponseContent.fromJson(json['part'] as Map<String, dynamic>),
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        contentIndex: json['content_index'] as int,
        sequenceNumber: json['sequence_number'] as int,
      );

  final ResponseContent part;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'part': part.toJson(),
        'sequence_number': sequenceNumber,
      };
}

class ResponseContentPartDone extends ResponseEvent {
  const ResponseContentPartDone({
    required this.part,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.sequenceNumber,
  }) : super('response.content_part.done');

  factory ResponseContentPartDone.fromJson(Map<String, dynamic> json) => ResponseContentPartDone(
        part: ResponseContent.fromJson(json['part'] as Map<String, dynamic>),
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        contentIndex: json['content_index'] as int,
        sequenceNumber: json['sequence_number'] as int,
      );

  final ResponseContent part;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'part': part.toJson(),
        'sequence_number': sequenceNumber,
      };
}

class ResponseOutputTextDelta extends ResponseEvent {
  const ResponseOutputTextDelta({
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
    required this.sequenceNumber,
  }) : super('response.output_text.delta');

  factory ResponseOutputTextDelta.fromJson(Map<String, dynamic> json) => ResponseOutputTextDelta(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        contentIndex: json['content_index'] as int,
        delta: json['delta'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String delta;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'delta': delta,
        'sequence_number': sequenceNumber,
      };
}

class ResponseOutputTextDone extends ResponseEvent {
  const ResponseOutputTextDone({
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.text,
    required this.sequenceNumber,
  }) : super('response.output_text.done');

  factory ResponseOutputTextDone.fromJson(Map<String, dynamic> json) => ResponseOutputTextDone(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        contentIndex: json['content_index'] as int,
        text: json['text'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String text;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'text': text,
        'sequence_number': sequenceNumber,
      };
}

/// Emitted as partial refusal text streams in.
class ResponseRefusalDelta extends ResponseEvent {
  const ResponseRefusalDelta({
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
    required this.sequenceNumber,
  }) : super('response.refusal.delta');

  factory ResponseRefusalDelta.fromJson(Map<String, dynamic> json) => ResponseRefusalDelta(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        contentIndex: json['content_index'] as int,
        delta: json['delta'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String delta;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "response.refusal.delta"
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'delta': delta,
        'sequence_number': sequenceNumber,
      };
}

/// Emitted once refusal text is finalised.
class ResponseRefusalDone extends ResponseEvent {
  const ResponseRefusalDone({
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.refusal,
    required this.sequenceNumber,
  }) : super('response.refusal.done');

  factory ResponseRefusalDone.fromJson(Map<String, dynamic> json) => ResponseRefusalDone(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        contentIndex: json['content_index'] as int,
        refusal: json['refusal'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String refusal;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "response.refusal.done"
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'refusal': refusal,
        'sequence_number': sequenceNumber,
      };
}

class ResponseFunctionCallArgumentsDelta extends ResponseEvent {
  const ResponseFunctionCallArgumentsDelta({
    required this.itemId,
    required this.outputIndex,
    required this.delta,
    required this.sequenceNumber,
  }) : super('response.function_call_arguments.delta');

  factory ResponseFunctionCallArgumentsDelta.fromJson(Map<String, dynamic> json) => ResponseFunctionCallArgumentsDelta(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        delta: json['delta'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final String delta;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'delta': delta,
        'sequence_number': sequenceNumber,
      };
}

class ResponeFunctionCallArgumentsDone extends ResponseEvent {
  const ResponeFunctionCallArgumentsDone({
    required this.itemId,
    required this.outputIndex,
    required this.arguments,
    required this.sequenceNumber,
  }) : super('response.function_call_arguments.done');

  factory ResponeFunctionCallArgumentsDone.fromJson(Map<String, dynamic> json) => ResponeFunctionCallArgumentsDone(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        arguments: json['arguments'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final String arguments;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'arguments': arguments,
        'sequence_number': sequenceNumber,
      };
}

abstract class ResponseFileSearchCallEvent extends ResponseEvent {
  const ResponseFileSearchCallEvent(
    super.type, {
    required this.itemId,
    required this.outputIndex,
    required this.sequenceNumber,
  });

  final String itemId;
  final int outputIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };
}

// Concrete subclasses ----------------------------------------------

class ResponseFileSearchCallInProgress extends ResponseFileSearchCallEvent {
  ResponseFileSearchCallInProgress(Map<String, dynamic> j)
      : super(
          'response.file_search_call.in_progress',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  static ResponseFileSearchCallInProgress fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'response.file_search_call.in_progress':
        return ResponseFileSearchCallInProgress(json);
      default:
        throw ArgumentError('Unknown file-search event type "${json['type']}".');
    }
  }
}

class ResponseFileSearchCallSearching extends ResponseFileSearchCallEvent {
  ResponseFileSearchCallSearching(Map<String, dynamic> j)
      : super(
          'response.file_search_call.searching',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  static ResponseFileSearchCallSearching fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'response.file_search_call.searching':
        return ResponseFileSearchCallSearching(json);
      default:
        throw ArgumentError('Unknown file-search event type "${json['type']}".');
    }
  }
}

class ResponseFileSearchCallCompleted extends ResponseFileSearchCallEvent {
  ResponseFileSearchCallCompleted(Map<String, dynamic> j)
      : super(
          'response.file_search_call.completed',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  static ResponseFileSearchCallCompleted fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      default:
        throw ArgumentError('Unknown file-search event type "${json['type']}".');
    }
  }
}

abstract class ResponseWebSearchCallEvent extends ResponseEvent {
  const ResponseWebSearchCallEvent(
    super.type, {
    required this.itemId,
    required this.outputIndex,
    required this.sequenceNumber,
  });

  final String itemId;
  final int outputIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };
}

class ResponseWebSearchCallInProgress extends ResponseWebSearchCallEvent {
  ResponseWebSearchCallInProgress(Map<String, dynamic> j)
      : super(
          'response.web_search_call.in_progress',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  /// Switch-based factory that dispatches to the correct subclass.
  static ResponseWebSearchCallInProgress fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'response.web_search_call.in_progress':
        return ResponseWebSearchCallInProgress(json);
      default:
        throw ArgumentError(
          'Unknown web-search event type "${json['type']}".',
        );
    }
  }
}

class ResponseWebSearchCallSearching extends ResponseWebSearchCallEvent {
  ResponseWebSearchCallSearching(Map<String, dynamic> j)
      : super(
          'response.web_search_call.searching',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  /// Switch-based factory that dispatches to the correct subclass.
  static ResponseWebSearchCallSearching fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'response.web_search_call.searching':
        return ResponseWebSearchCallSearching(json);
      default:
        throw ArgumentError(
          'Unknown web-search event type "${json['type']}".',
        );
    }
  }
}

class ResponseWebSearchCallCompleted extends ResponseWebSearchCallEvent {
  ResponseWebSearchCallCompleted(Map<String, dynamic> j)
      : super(
          'response.web_search_call.completed',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  /// Switch-based factory that dispatches to the correct subclass.
  static ResponseWebSearchCallCompleted fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'response.web_search_call.completed':
        return ResponseWebSearchCallCompleted(json);
      default:
        throw ArgumentError(
          'Unknown web-search event type "${json['type']}".',
        );
    }
  }
}

abstract class ReasoningSummaryPart {
  const ReasoningSummaryPart();

  factory ReasoningSummaryPart.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'summary_text':
        return ReasoningSummaryTextPart(text: json['text'] as String);
      default:
        return ReasoningSummaryPartOther(json);
    }
  }

  Map<String, dynamic> toJson();
}

/// The common “summary_text” variant.
class ReasoningSummaryTextPart extends ReasoningSummaryPart {
  const ReasoningSummaryTextPart({required this.text});
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'summary_text', 'text': text};
}

/// Fallback wrapper for unseen summary part types.
class ReasoningSummaryPartOther extends ReasoningSummaryPart {
  const ReasoningSummaryPartOther(this.raw);
  final Map<String, dynamic> raw;

  @override
  Map<String, dynamic> toJson() => raw;
}

class ResponseReasoningSummaryPartAdded extends ResponseEvent {
  const ResponseReasoningSummaryPartAdded({
    required this.itemId,
    required this.outputIndex,
    required this.summaryIndex,
    required this.part,
    required this.sequenceNumber,
  }) : super('response.reasoning_summary_part.added');

  factory ResponseReasoningSummaryPartAdded.fromJson(Map<String, dynamic> json) => ResponseReasoningSummaryPartAdded(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        summaryIndex: json['summary_index'] as int,
        part: ReasoningSummaryPart.fromJson(json['part'] as Map<String, dynamic>),
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int summaryIndex;
  final ReasoningSummaryPart part;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'summary_index': summaryIndex,
        'part': part.toJson(),
        'sequence_number': sequenceNumber,
      };
}

class ResponseReasoningSummaryPartDone extends ResponseEvent {
  const ResponseReasoningSummaryPartDone({
    required this.itemId,
    required this.outputIndex,
    required this.summaryIndex,
    required this.part,
    required this.sequenceNumber,
  }) : super('response.reasoning_summary_part.done');

  factory ResponseReasoningSummaryPartDone.fromJson(Map<String, dynamic> json) => ResponseReasoningSummaryPartDone(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        summaryIndex: json['summary_index'] as int,
        part: ReasoningSummaryPart.fromJson(json['part'] as Map<String, dynamic>),
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int summaryIndex;
  final ReasoningSummaryPart part;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'summary_index': summaryIndex,
        'part': part.toJson(),
        'sequence_number': sequenceNumber,
      };
}

class ResponseReasoningSummaryTextDelta extends ResponseEvent {
  const ResponseReasoningSummaryTextDelta({
    required this.itemId,
    required this.outputIndex,
    required this.summaryIndex,
    required this.delta,
    required this.sequenceNumber,
  }) : super('response.reasoning_summary_text.delta');

  factory ResponseReasoningSummaryTextDelta.fromJson(Map<String, dynamic> json) => ResponseReasoningSummaryTextDelta(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        summaryIndex: json['summary_index'] as int,
        delta: json['delta'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int summaryIndex;
  final String delta;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'summary_index': summaryIndex,
        'delta': delta,
        'sequence_number': sequenceNumber,
      };
}

class ResponseReasoningSummaryTextDone extends ResponseEvent {
  const ResponseReasoningSummaryTextDone({
    required this.itemId,
    required this.outputIndex,
    required this.summaryIndex,
    required this.text,
    required this.sequenceNumber,
  }) : super('response.reasoning_summary_text.done');

  factory ResponseReasoningSummaryTextDone.fromJson(Map<String, dynamic> json) => ResponseReasoningSummaryTextDone(
        itemId: json['item_id'] as String,
        outputIndex: json['output_index'] as int,
        summaryIndex: json['summary_index'] as int,
        text: json['text'] as String,
        sequenceNumber: json['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int summaryIndex;
  final String text;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'summary_index': summaryIndex,
        'text': text,
        'sequence_number': sequenceNumber,
      };
}

abstract class ResponseImageGenerationCallEvent extends ResponseEvent {
  const ResponseImageGenerationCallEvent(
    super.type, {
    required this.itemId,
    required this.outputIndex,
    required this.sequenceNumber,
  });

  final String itemId;
  final int outputIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };
}

class ResponseImageGenerationCallInProgress extends ResponseImageGenerationCallEvent {
  /// Direct constructor.
  const ResponseImageGenerationCallInProgress({
    required String itemId,
    required int outputIndex,
    required int sequenceNumber,
  }) : super(
          'response.image_generation_call.in_progress',
          itemId: itemId,
          outputIndex: outputIndex,
          sequenceNumber: sequenceNumber,
        );

  /// JSON factory.
  factory ResponseImageGenerationCallInProgress.fromJson(Map<String, dynamic> j) => ResponseImageGenerationCallInProgress(
        itemId: j['item_id'],
        outputIndex: j['output_index'],
        sequenceNumber: j['sequence_number'],
      );
}

class ResponseImageGenerationCallGenerating extends ResponseImageGenerationCallEvent {
  const ResponseImageGenerationCallGenerating({
    required String itemId,
    required int outputIndex,
    required int sequenceNumber,
  }) : super(
          'response.image_generation_call.generating',
          itemId: itemId,
          outputIndex: outputIndex,
          sequenceNumber: sequenceNumber,
        );

  factory ResponseImageGenerationCallGenerating.fromJson(Map<String, dynamic> j) => ResponseImageGenerationCallGenerating(
        itemId: j['item_id'],
        outputIndex: j['output_index'],
        sequenceNumber: j['sequence_number'],
      );
}

class ResponseImageGenerationCallCompleted extends ResponseImageGenerationCallEvent {
  const ResponseImageGenerationCallCompleted({
    required String itemId,
    required int outputIndex,
    required int sequenceNumber,
  }) : super(
          'response.image_generation_call.completed',
          itemId: itemId,
          outputIndex: outputIndex,
          sequenceNumber: sequenceNumber,
        );

  factory ResponseImageGenerationCallCompleted.fromJson(Map<String, dynamic> j) => ResponseImageGenerationCallCompleted(
        itemId: j['item_id'],
        outputIndex: j['output_index'],
        sequenceNumber: j['sequence_number'],
      );
}

class ResponseImageGenerationCallPartialImage extends ResponseImageGenerationCallEvent {
  const ResponseImageGenerationCallPartialImage({
    required String itemId,
    required int outputIndex,
    required int sequenceNumber,
    required this.partialImageB64,
    required this.partialImageIndex,
  }) : super(
          'response.image_generation_call.partial_image',
          itemId: itemId,
          outputIndex: outputIndex,
          sequenceNumber: sequenceNumber,
        );

  factory ResponseImageGenerationCallPartialImage.fromJson(Map<String, dynamic> j) => ResponseImageGenerationCallPartialImage(
        itemId: j['item_id'],
        outputIndex: j['output_index'],
        sequenceNumber: j['sequence_number'],
        partialImageB64: j['partial_image_b64'],
        partialImageIndex: j['partial_image_index'],
      );

  final String partialImageB64;
  final int partialImageIndex;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'partial_image_b64': partialImageB64,
        'partial_image_index': partialImageIndex,
      };
}

abstract class ResponseMcpCallArgumentsEvent extends ResponseMcpCallEvent {
  const ResponseMcpCallArgumentsEvent(
    super.type, {
    required this.itemId,
    required this.outputIndex,
    required this.sequenceNumber,
  });

  final String itemId;
  final int outputIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };
}

/// `response.mcp_call_arguments.delta`
class ResponseMcpCallArgumentsDelta extends ResponseMcpCallArgumentsEvent {
  ResponseMcpCallArgumentsDelta(Map<String, dynamic> j)
      : delta = j['delta'] as String,
        super(
          'response.mcp_call_arguments.delta',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  final String delta;

  static ResponseMcpCallArgumentsDelta fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_call_arguments.delta':
        return ResponseMcpCallArgumentsDelta(j);
      default:
        throw ArgumentError('Unknown MCP-call event ${j['type']}.');
    }
  }

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'delta': delta};
}

/// `response.mcp_call_arguments.done`
class ResponseMcpCallArgumentsDone extends ResponseMcpCallArgumentsEvent {
  ResponseMcpCallArgumentsDone(Map<String, dynamic> j)
      : arguments = j['arguments'] as String,
        super(
          'response.mcp_call_arguments.done',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          sequenceNumber: j['sequence_number'],
        );

  final String arguments;

  static ResponseMcpCallArgumentsDone fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_call_arguments.done':
        return ResponseMcpCallArgumentsDone(j);
      default:
        throw ArgumentError('Unknown MCP-call event ${j['type']}.');
    }
  }

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'arguments': arguments};
}

abstract class ResponseMcpCallEvent extends ResponseEvent {
  const ResponseMcpCallEvent(super.type);
}

/// Thin wrappers for the simple lifecycle notifications.
class ResponseMcpCallInProgress extends ResponseMcpCallEvent {
  ResponseMcpCallInProgress(Map<String, dynamic> j)
      : itemId = j['item_id'],
        outputIndex = j['output_index'],
        sequenceNumber = j['sequence_number'],
        super('response.mcp_call.in_progress');

  final String itemId;
  final int outputIndex;
  final int sequenceNumber;

  static ResponseMcpCallInProgress fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_call.in_progress':
        return ResponseMcpCallInProgress(j);
      default:
        throw ArgumentError('Unknown MCP-call event ${j['type']}.');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'sequence_number': sequenceNumber,
      };
}

class ResponseMcpCallCompleted extends ResponseMcpCallEvent {
  ResponseMcpCallCompleted(Map<String, dynamic> j)
      : sequenceNumber = j['sequence_number'],
        super('response.mcp_call.completed');

  final int sequenceNumber;

  static ResponseMcpCallCompleted fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_call.completed':
        return ResponseMcpCallCompleted(j);
      default:
        throw ArgumentError('Unknown MCP-call event ${j['type']}.');
    }
  }

  @override
  Map<String, dynamic> toJson() => {'type': type, 'sequence_number': sequenceNumber};
}

class ResponseMcpCallFailed extends ResponseMcpCallEvent {
  ResponseMcpCallFailed(Map<String, dynamic> j)
      : sequenceNumber = j['sequence_number'],
        super('response.mcp_call.failed');

  static ResponseMcpCallFailed fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_call.failed':
        return ResponseMcpCallFailed(j);
      default:
        throw ArgumentError('Unknown MCP-call event ${j['type']}.');
    }
  }

  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {'type': type, 'sequence_number': sequenceNumber};
}

abstract class ResponseMcpListToolsEvent extends ResponseEvent {
  const ResponseMcpListToolsEvent(super.type, {required this.sequenceNumber});
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {'type': type, 'sequence_number': sequenceNumber};
}

class ResponseMcpListToolsInProgress extends ResponseMcpListToolsEvent {
  ResponseMcpListToolsInProgress(Map<String, dynamic> j)
      : super('response.mcp_list_tools.in_progress', sequenceNumber: j['sequence_number']);

  static ResponseMcpListToolsInProgress fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_list_tools.in_progress':
        return ResponseMcpListToolsInProgress(j);
      default:
        throw ArgumentError('Unknown list-tools event ${j['type']}.');
    }
  }
}

class ResponseMcpListToolsCompleted extends ResponseMcpListToolsEvent {
  ResponseMcpListToolsCompleted(Map<String, dynamic> j) : super('response.mcp_list_tools.completed', sequenceNumber: j['sequence_number']);

  static ResponseMcpListToolsCompleted fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_list_tools.completed':
        return ResponseMcpListToolsCompleted(j);
      default:
        throw ArgumentError('Unknown list-tools event ${j['type']}.');
    }
  }
}

class ResponseMcpListToolsFailed extends ResponseMcpListToolsEvent {
  ResponseMcpListToolsFailed(Map<String, dynamic> j) : super('response.mcp_list_tools.failed', sequenceNumber: j['sequence_number']);

  static ResponseMcpListToolsFailed fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'response.mcp_list_tools.failed':
        return ResponseMcpListToolsFailed(j);
      default:
        throw ArgumentError('Unknown list-tools event ${j['type']}.');
    }
  }
}

class ResponseTextAnnotationAdded extends ResponseEvent {
  const ResponseTextAnnotationAdded({
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.annotationIndex,
    required this.annotation,
    required this.sequenceNumber,
  }) : super('response.output_text.annotation.added');

  factory ResponseTextAnnotationAdded.fromJson(Map<String, dynamic> j) => ResponseTextAnnotationAdded(
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        annotationIndex: j['annotation_index'] as int,
        annotation: Annotation.fromJson(j['annotation'] as Map<String, dynamic>),
        sequenceNumber: j['sequence_number'] as int,
      );

  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final int annotationIndex;
  final Annotation annotation;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'annotation_index': annotationIndex,
        'annotation': annotation.toJson(),
        'sequence_number': sequenceNumber,
      };
}

class ResponseQueued extends ResponseEvent {
  const ResponseQueued({
    required this.response,
    required this.sequenceNumber,
  }) : super('response.queued');

  factory ResponseQueued.fromJson(Map<String, dynamic> j) => ResponseQueued(
        response: Response.fromJson(j['response'] as Map<String, dynamic>),
        sequenceNumber: j['sequence_number'] as int,
      );

  final Response response;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'response': response.toJson(),
        'sequence_number': sequenceNumber,
      };
}

abstract class ReasoningEvent extends ResponseEvent {
  const ReasoningEvent(
    super.type, {
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.sequenceNumber,
  });

  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'sequence_number': sequenceNumber,
      };
}

class ResponseReasoningDelta extends ReasoningEvent {
  ResponseReasoningDelta.fromJson(Map<String, dynamic> j)
      : delta = Map<String, dynamic>.from(j['delta'] as Map),
        super(
          'response.reasoning.delta',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          contentIndex: j['content_index'],
          sequenceNumber: j['sequence_number'],
        );

  final Map<String, dynamic> delta;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'delta': delta};
}

class ResponseReasoningDone extends ReasoningEvent {
  ResponseReasoningDone.fromJson(Map<String, dynamic> j)
      : text = j['text'] as String,
        super(
          'response.reasoning.done',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          contentIndex: j['content_index'],
          sequenceNumber: j['sequence_number'],
        );

  final String text;
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'text': text};
}

abstract class ReasoningSummaryEvent extends ResponseEvent {
  const ReasoningSummaryEvent(
    super.type, {
    required this.itemId,
    required this.outputIndex,
    required this.summaryIndex,
    required this.sequenceNumber,
  });

  final String itemId;
  final int outputIndex;
  final int summaryIndex;
  final int sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'item_id': itemId,
        'output_index': outputIndex,
        'summary_index': summaryIndex,
        'sequence_number': sequenceNumber,
      };
}

class ResponseReasoningSummaryDelta extends ReasoningSummaryEvent {
  ResponseReasoningSummaryDelta.fromJson(Map<String, dynamic> j)
      : delta = Map<String, dynamic>.from(j['delta'] as Map),
        super(
          'response.reasoning_summary.delta',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          summaryIndex: j['summary_index'],
          sequenceNumber: j['sequence_number'],
        );

  final Map<String, dynamic> delta;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'delta': delta};
}

class ResponseReasoningSummaryDone extends ReasoningSummaryEvent {
  ResponseReasoningSummaryDone.fromJson(Map<String, dynamic> j)
      : text = j['text'] as String,
        super(
          'response.reasoning_summary.done',
          itemId: j['item_id'],
          outputIndex: j['output_index'],
          summaryIndex: j['summary_index'],
          sequenceNumber: j['sequence_number'],
        );

  final String text;
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'text': text};
}

class ErrorEvent extends ResponseEvent {
  const ErrorEvent({
    required this.code,
    required this.message,
    this.param,
    required this.sequenceNumber,
  }) : super('error');

  factory ErrorEvent.fromJson(Map<String, dynamic> j) {
    return ErrorEvent(
      code: j['code'] as String?,
      message: j['message'] as String,
      param: j['param'] as String?,
      sequenceNumber: j['sequence_number'] as int?,
    );
  }

  final String? code;
  final String message;
  final String? param;
  final int? sequenceNumber;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "error"
        if (code != null) 'code': code,
        'message': message,
        if (param != null) 'param': param,
        if (sequenceNumber != null) 'sequence_number': sequenceNumber,
      };
}
