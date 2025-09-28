# Implementation Plan: Realtime API GA Spec Alignment

## 1. Executive Summary

This document outlines the implementation plan to bring the `openai_core` library's Realtime API client into full compliance with the official General Availability (GA) specification. The plan addresses several critical discrepancies between the current implementation and the `openai_spec_realtime.yaml` document.

The core of this effort involves a significant refactoring of the `RealtimeResponse` data model to correctly distinguish between response creation parameters and the actual server response object. We will also introduce missing models for transcription sessions, dedicated usage statistics, and various server-sent events. Finally, we will correct event handling logic for cancellations and polymorphic session updates, and fix several minor bugs. The result will be a robust, spec-compliant client for the Realtime GA API.

## 2. Development Branch Name

**Rationale:** Using a consistent and descriptive branch naming convention is crucial for team collaboration and repository clarity. The following name is recommended based on standard industry practices (e.g., `type/short-description`).

**Recommended Branch Name:**

```sh
feature/realtime-ga-spec-alignment
```

## 3. Guiding Principles: The Code Quality Manifesto

All development for this feature must adhere to the following principles. These are non-negotiable requirements for creating a production-grade, maintainable, and robust codebase. The ultimate goal is to produce software that is not just functional, but exemplary in its craftsmanship and ready for long-term evolution.

- **SOLID Principles:** The code must strictly adhere to the five SOLID principles of design.
  - **S - Single Responsibility Principle (SRP):** Every module, class, or function must have one, and only one, reason to change.
  - **O - Open/Closed Principle:** Entities should be open for extension but closed for modification.
  - **L - Liskov Substitution Principle:** Subtypes must be substitutable for their base types without altering the correctness of the program.
  - **I - Interface Segregation Principle:** Clients should not be forced to depend on interfaces they do not use.
  - **D - Dependency Inversion Principle:** High-level modules should not depend on low-level modules. Both should depend on abstractions.
- **DRY (Don't Repeat Yourself):** Avoid redundancy. Every piece of logic and configuration should have a single, unambiguous, authoritative representation.
- **KISS (Keep It Simple, Stupid):** Prioritize clarity and simplicity over unnecessary complexity. The most straightforward solution is almost always the best.
- **Defensive Programming & Robustness:** Code must be resilient. Assume invalid inputs and potential failures. Implement rigorous server-side validation, handle errors gracefully, and provide clear, contextual logging.
- **Readability & Maintainability:** Write clean, self-documenting code with consistent and descriptive naming. The codebase should be as intuitive as possible for a new developer.
- **Security by Design:** Security is a foundational requirement, not an afterthought. Proactively address vulnerabilities through input sanitization, parameterized queries, secure secret management, and adherence to security best practices.
- **Idiomatic Code:** Write code that is natural to the ecosystem. Effectively use the features, conventions, and standard libraries of the chosen language and framework.
- **Testability:** Code must be structured for easy testing. Use techniques like dependency injection and pure functions to ensure components are decoupled and can be tested in isolation.

## 4. Key Architectural Decisions

This section outlines the high-level strategic decisions made, their rationale, and how they were informed by our conversation.

- **Decision 1: Adopt a Strict "Parameters vs. Response" Model**
  - **Rationale:** The current `RealtimeResponse` class ambiguously mixes creation parameters with response fields. We will refactor this into two distinct classes: `RealtimeResponseOptions` (for client-side request configuration) and a new `RealtimeResponse` (for the server's actual response). This aligns directly with the OpenAPI specification, improves type safety, and makes the API's intent much clearer.
- **Decision 2: Leverage Polymorphism for Session and Usage Types**
  - **Rationale:** The API uses `type` discriminator fields for session configurations (`realtime`, `transcription`) and usage objects (`tokens`, `duration`). We will use abstract base classes (`BaseRealtimeSession`, `TranscriptionUsage`) and factory constructors to handle this polymorphism cleanly, ensuring the correct data model is instantiated based on the `type` field during JSON deserialization. This avoids complex conditional logic and adheres to the Open/Closed Principle.

## 5. Potential Risks & Mitigations

An analysis of potential challenges and a plan to address them.

| Risk                                        | Likelihood | Mitigation Strategy                                                                                                                                                                                                                                                       |
| ------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cascading changes from refactoring**      | Medium     | The plan is structured to handle the core `RealtimeResponse` refactoring first. Each task explicitly lists the dependent files. A full-project search will be conducted post-refactor to catch any remaining instances of the old class name and its usages.              |
| **Breaking changes to legacy Beta API**     | Low        | The plan leverages the existing `BaseRealtimeSession` and introduces new, separate classes for GA features. No modifications will be made to beta-specific files. Care will be taken to ensure changes in shared files are additive and do not alter existing beta logic. |
| **Forgetting to update `fromJson` factory** | Medium     | Each task that introduces a new event or data model includes an explicit instruction to update the corresponding `fromJson` factory. This will be a key item on the code review checklist for each task.                                                                  |

## 6. Phases & Tasks

---

### **Phase 1 [✅ DONE]: Foundational Data Model Corrections**

_This phase corrects the core data models to align with the GA specification, addressing the most critical structural issues before building upon them._

#### **Task 1.1 [✅ DONE]: Rename `RealtimeResponse` to `RealtimeResponseOptions`**

- **Description:** Rename the existing `RealtimeResponse` class to `RealtimeResponseOptions` to accurately reflect its purpose as a parameter object for creating a response, as defined by the `RealtimeResponseCreateParams` schema.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Perform a project-wide find-and-replace for the class name. This will cause temporary compilation errors that will be resolved in subsequent tasks.
- **Depends On:** `None`

#### **Task 1.2 [✅ DONE]: Refactor `RealtimeResponseOptions` Structure**

- **Description:** Modify the newly renamed `RealtimeResponseOptions` to precisely match the `RealtimeResponseCreateParams` schema from the spec.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Create two new helper classes: `ResponseAudioOptions` and `ResponseAudioOutputOptions`.
  - Remove the incorrect top-level properties: `temperature`, `voice`, and `outputAudioFormat`.
  - Add a new property: `ResponseAudioOptions? audio`. `ResponseAudioOptions` should contain `ResponseAudioOutputOptions? output`, which in turn contains `AudioFormat? format` and `SpeechVoice? voice`.
  - Rename the `modalities` field to `outputModalities` to match the spec (`output_modalities`).
  - Add the missing `prompt` property, reusing the `Prompt` class from `responses.dart`.
- **Depends On:** `Task 1.1`

#### **Task 1.3 [✅ DONE]: Create New `RealtimeResponse` Class**

- **Description:** Create a new class named `RealtimeResponse` that accurately models the server's response object as defined in the `RealtimeResponse` schema.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - The class should include all properties from the spec: `id`, `object`, `status`, `status_details`, `output` (as `List<RealtimeConversationItem>`), `metadata`, `audio`, `usage`, `conversation_id`, `output_modalities`, and `max_output_tokens`.
  - The `usage` field will be typed with a new `RealtimeResponseUsage` class, which will be created in Phase 2. For now we could use the `Usage` class from `common.dart`.
- **Depends On:** `Task 1.1`

#### **Task 1.4 [✅ DONE]: Update Events to Use the New `RealtimeResponse`**

- **Description:** Update all event classes that carry a response object to use the new, correct `RealtimeResponse` model.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Modify `RealtimeResponseCreatedEvent` to use `RealtimeResponse response`.
  - Modify `RealtimeResponseDoneEvent` to use `RealtimeResponse response`.
  - Ensure their `fromJson` factories correctly instantiate the new `RealtimeResponse` class.
- **Depends On:** `Task 1.2`, `Task 1.3`

#### **Task 1.5 [✅ DONE]: Fix `RealtimeTruncation` `toJson` Methods**

- **Description:** Correct the bugs in the `toJson` methods of the `RealtimeTruncationDisabled` and `RealtimeTruncationRatio` classes.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - In `RealtimeTruncationDisabled`, change `toJson()` to return `"disabled"`.
  - In `RealtimeTruncationRatio`, change `toJson()` to return `{'type': 'retention_ratio', 'retention_ratio': ratio}`.
- **Depends On:** `None`

---

### **Phase 2 [✅ DONE]: Session and Event Model Enhancements**

_This phase adds the missing data models and enhances existing ones to fully support the GA API's features._

#### **Task 2.1 [✅ DONE]: Enhance `RealtimeSession` Model**

- **Description:** Add the missing `truncation` and `prompt` properties to the `RealtimeSession` class.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Add the field `RealtimeTruncation? truncation`.
  - Add the field `Prompt? prompt` (reusing the class from `responses.dart`).
  - Update the `RealtimeSession.fromJson` factory and `toJson` method to handle these new fields.
- **Depends On:** `Task 1.5`

#### **Task 2.2 [✅ DONE]: Create `TranscriptionUsage` Model Hierarchy**

- **Description:** Create a new set of classes to accurately model the polymorphic `usage` object for transcription events.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Create a new abstract class `TranscriptionUsage`.
  - Create `TranscriptionUsageTokens` and `TranscriptionUsageDuration` classes that extend it.
  - Implement a `fromJson` factory on the base class that uses the `type` field to decide which concrete class to instantiate.
  - The `TranscriptionUsageTokens` class should include a nested class `InputTokenDetails` to handle the `input_token_details` object.
- **Depends On:** `None`

#### **Task 2.3 [✅ DONE]: Update Transcription Completion Event with Correct Usage Model**

- **Description:** Add the new `TranscriptionUsage` model to the `ConversationItemInputAudioTranscriptionCompletedEvent`.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Add a final field `TranscriptionUsage? usage` to the `ConversationItemInputAudioTranscriptionCompletedEvent` class.
  - Update its `fromJson` factory to use the new `TranscriptionUsage.fromJson` factory.
- **Depends On:** `Task 2.2`

#### **Task 2.4 [✅ DONE]: Create `RealtimeTranscriptionSession` Class**

- **Description:** Implement the `RealtimeTranscriptionSession` class to support transcription-only sessions.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - The new class must extend `BaseRealtimeSession`.
  - It should model the `RealtimeTranscriptionSessionCreateResponseGA` schema, including properties like `type` (hardcoded to `'transcription'`), `audio`, and `include`.
- **Depends On:** `None`

#### **Task 2.5 [✅ DONE]: Create `RealtimeResponseUsage` Model**

- **Description:** Create a new class hierarchy to accurately model the `usage` object within the `RealtimeResponse`.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Create a new class `RealtimeResponseUsage`.
  - This class must include all fields from the spec's `usage` object: `total_tokens`, `input_tokens`, `output_tokens`.
  - It must also include the nested objects `input_token_details` and `output_token_details`, which should be modeled with their own dedicated classes (`InputTokenDetails`, `OutputTokenDetails`).
- **Depends On:** `Task 1.3`

---

### **Phase 3: Event Handling and Polymorphism**

_This phase implements the logic for handling new events, corrects existing event definitions, and enables polymorphic session updates._

#### **Task 3.1 [✅ DONE]: Create `InputAudioBufferTimeoutTriggeredEvent`**

- **Description:** Add a new event class to handle the `input_audio_buffer.timeout_triggered` server event.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - The class must extend `RealtimeEvent` and contain `event_id`, `audio_start_ms`, `audio_end_ms`, and `item_id` fields.
  - Add a new case `'input_audio_buffer.timeout_triggered'` to the `RealtimeEvent.fromJson` factory to instantiate this new class.
- **Depends On:** `None`

#### **Task 3.2: Create `ConversationItemInputAudioTranscriptionSegmentEvent`**

- **Description:** Add a new event class to handle the `conversation.item.input_audio_transcription.segment` server event.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - The class must extend `RealtimeEvent` and contain all fields from the spec, including `item_id`, `text`, `speaker`, `start`, and `end`.
  - Add a new case `'conversation.item.input_audio_transcription.segment'` to the `RealtimeEvent.fromJson` factory.
- **Depends On:** `None`

#### **Task 3.3: Create `RealtimeResponseCancelEvent`**

- **Description:** Create a new client-side event class to allow developers to cancel an in-progress response.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - The class must extend `RealtimeEvent`.
  - The `type` should be hardcoded to `'response.cancel'`.
  - It should include an optional `String? response_id` property.
- **Depends On:** `None`

#### **Task 3.4: Remove Incorrect `RealtimeResponseCancelledEvent`**

- **Description:** Remove the non-existent server-side `response.cancelled` event handling logic.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Delete the entire `RealtimeResponseCancelledEvent` class definition.
  - Remove the `'response.cancelled'` case from the `RealtimeEvent.fromJson` factory.
- **Depends On:** `None`

#### **Task 3.5: Correct `ConversationItemAddedEvent` Type**

- **Description:** Fix the bug in the `ConversationItemAddedEvent` where the wrong event type string is used.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - In the constructor for `ConversationItemAddedEvent`, change the `super` call from `super('conversation.item.created')` to `super('conversation.item.added')`.
- **Depends On:** `None`

#### **Task 3.6: Update `SessionUpdateEvent` for Polymorphism**

- **Description:** Refactor the `SessionUpdateEvent` to support updating both `RealtimeSession` and `RealtimeTranscriptionSession`.
- **Files to Create/Modify:**
  - `lib/realtime.dart` (Modify)
- **Key Considerations & Instructions:**
  - Change the type of the `session` property from `RealtimeSession` to `BaseRealtimeSession`.
  - In the `SessionUpdateEvent.fromJson` factory, inspect the `type` field of the incoming `session` JSON object.
  - Based on the `type`, call the appropriate factory (`RealtimeSession.fromJson` or `RealtimeTranscriptionSession.fromJson`).
- **Depends On:** `Task 2.4`

## 7. Post-Implementation Checklist

- [ ] Run all unit and integration tests.
- [ ] Perform a final code review of all changes in `realtime.dart` and any other affected files.
- [ ] Update the `README.md` and any relevant documentation to reflect the new models and event handlers, particularly the correct way to handle cancellations via `response.done`.
- [ ] Verify that all configuration and secrets are correctly handled in a production-like environment.
