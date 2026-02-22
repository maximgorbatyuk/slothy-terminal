import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ProviderStreamParser")
struct ProviderStreamParserTests {

  // MARK: - Anthropic: Text

  @Test("Anthropic text_delta produces textDelta event")
  func anthropicTextDelta() {
    let event = SSEEvent(
      event: "content_block_delta",
      data: """
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .textDelta(let text) = events[0] {
      #expect(text == "Hello")
    } else {
      Issue.record("Expected textDelta, got \(events[0])")
    }
  }

  // MARK: - Anthropic: Thinking

  @Test("Anthropic thinking_delta produces thinkingDelta event")
  func anthropicThinkingDelta() {
    let event = SSEEvent(
      event: "content_block_delta",
      data: """
        {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me think..."}}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .thinkingDelta(let text) = events[0] {
      #expect(text == "Let me think...")
    } else {
      Issue.record("Expected thinkingDelta")
    }
  }

  // MARK: - Anthropic: Tool Use

  @Test("Anthropic content_block_start with tool_use produces toolCallStart")
  func anthropicToolCallStart() {
    let event = SSEEvent(
      event: "content_block_start",
      data: """
        {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_123","name":"bash"}}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .toolCallStart(let id, let name) = events[0] {
      #expect(id == "toolu_123")
      #expect(name == "bash")
    } else {
      Issue.record("Expected toolCallStart")
    }
  }

  @Test("Anthropic input_json_delta produces toolCallDelta")
  func anthropicToolCallDelta() {
    let event = SSEEvent(
      event: "content_block_delta",
      data: """
        {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\":"}}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .toolCallDelta(_, let delta) = events[0] {
      #expect(delta.contains("command"))
    } else {
      Issue.record("Expected toolCallDelta")
    }
  }

  @Test("Anthropic content_block_stop produces toolCallEnd")
  func anthropicContentBlockStop() {
    let event = SSEEvent(
      event: "content_block_stop",
      data: """
        {"type":"content_block_stop","index":1}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .toolCallEnd(let id) = events[0] {
      #expect(id == "1")
    } else {
      Issue.record("Expected toolCallEnd")
    }
  }

  // MARK: - Anthropic: Message lifecycle

  @Test("Anthropic message_start extracts input tokens")
  func anthropicMessageStart() {
    let event = SSEEvent(
      event: "message_start",
      data: """
        {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":150}}}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .usage(let input, let output) = events[0] {
      #expect(input == 150)
      #expect(output == 0)
    } else {
      Issue.record("Expected usage")
    }
  }

  @Test("Anthropic message_delta extracts stop reason and output tokens")
  func anthropicMessageDelta() {
    let event = SSEEvent(
      event: "message_delta",
      data: """
        {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":250}}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 2)

    let hasComplete = events.contains { event in
      if case .messageComplete(let reason) = event {
        return reason == "end_turn"
      }
      return false
    }
    #expect(hasComplete)

    let hasUsage = events.contains { event in
      if case .usage(_, let output) = event {
        return output == 250
      }
      return false
    }
    #expect(hasUsage)
  }

  @Test("Anthropic message_stop produces messageComplete")
  func anthropicMessageStop() {
    let event = SSEEvent(
      event: "message_stop",
      data: """
        {"type":"message_stop"}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .messageComplete(let reason) = events[0] {
      #expect(reason == nil)
    } else {
      Issue.record("Expected messageComplete")
    }
  }

  @Test("Anthropic error event produces error")
  func anthropicError() {
    let event = SSEEvent(
      event: "error",
      data: """
        {"type":"error","error":{"type":"overloaded_error","message":"Server overloaded"}}
        """
    )

    let events = ProviderStreamParser.parseAnthropic(event: event)

    #expect(events.count == 1)
    if case .error(let msg) = events[0] {
      #expect(msg == "Server overloaded")
    } else {
      Issue.record("Expected error")
    }
  }

  // MARK: - OpenAI: Text

  @Test("OpenAI content delta produces textDelta")
  func openAITextDelta() {
    let event = SSEEvent(
      event: nil,
      data: """
        {"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
        """
    )

    let events = ProviderStreamParser.parseOpenAI(event: event)

    #expect(events.count == 1)
    if case .textDelta(let text) = events[0] {
      #expect(text == "Hello")
    } else {
      Issue.record("Expected textDelta, got \(events[0])")
    }
  }

  // MARK: - OpenAI: Reasoning

  @Test("OpenAI reasoning_content produces thinkingDelta")
  func openAIReasoningDelta() {
    let event = SSEEvent(
      event: nil,
      data: """
        {"choices":[{"index":0,"delta":{"reasoning_content":"Thinking..."},"finish_reason":null}]}
        """
    )

    let events = ProviderStreamParser.parseOpenAI(event: event)

    #expect(events.count == 1)
    if case .thinkingDelta(let text) = events[0] {
      #expect(text == "Thinking...")
    } else {
      Issue.record("Expected thinkingDelta")
    }
  }

  // MARK: - OpenAI: Tool Calls

  @Test("OpenAI tool_calls with id produces toolCallStart")
  func openAIToolCallStart() {
    let event = SSEEvent(
      event: nil,
      data: """
        {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc","function":{"name":"bash","arguments":""}}]},"finish_reason":null}]}
        """
    )

    let events = ProviderStreamParser.parseOpenAI(event: event)

    let hasStart = events.contains { e in
      if case .toolCallStart(let id, let name) = e {
        return id == "call_abc" && name == "bash"
      }
      return false
    }
    #expect(hasStart)
  }

  @Test("OpenAI tool_calls arguments delta produces toolCallDelta")
  func openAIToolCallDelta() {
    let event = SSEEvent(
      event: nil,
      data: """
        {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"command\\":\\"ls\\"}"}}]},"finish_reason":null}]}
        """
    )

    let events = ProviderStreamParser.parseOpenAI(event: event)

    let hasDelta = events.contains { e in
      if case .toolCallDelta(_, let delta) = e {
        return delta.contains("command")
      }
      return false
    }
    #expect(hasDelta)
  }

  // MARK: - OpenAI: Finish

  @Test("OpenAI finish_reason produces messageComplete")
  func openAIFinishReason() {
    let event = SSEEvent(
      event: nil,
      data: """
        {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
        """
    )

    let events = ProviderStreamParser.parseOpenAI(event: event)

    let hasComplete = events.contains { e in
      if case .messageComplete(let reason) = e {
        return reason == "stop"
      }
      return false
    }
    #expect(hasComplete)
  }

  @Test("OpenAI usage in final chunk produces usage event")
  func openAIUsage() {
    let event = SSEEvent(
      event: nil,
      data: """
        {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":200}}
        """
    )

    let events = ProviderStreamParser.parseOpenAI(event: event)

    let hasUsage = events.contains { e in
      if case .usage(let input, let output) = e {
        return input == 100 && output == 200
      }
      return false
    }
    #expect(hasUsage)
  }

  @Test("OpenAI error response produces error event")
  func openAIError() {
    let event = SSEEvent(
      event: nil,
      data: """
        {"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}
        """
    )

    let events = ProviderStreamParser.parseOpenAI(event: event)

    #expect(events.count == 1)
    if case .error(let msg) = events[0] {
      #expect(msg == "Rate limit exceeded")
    } else {
      Issue.record("Expected error")
    }
  }

  // MARK: - Edge cases

  @Test("Invalid JSON data produces no events")
  func invalidJSON() {
    let event = SSEEvent(event: nil, data: "not json")

    let anthropic = ProviderStreamParser.parseAnthropic(event: event)
    let openai = ProviderStreamParser.parseOpenAI(event: event)

    #expect(anthropic.isEmpty)
    #expect(openai.isEmpty)
  }

  @Test("Empty choices array produces no events")
  func emptyChoices() {
    let event = SSEEvent(event: nil, data: "{\"choices\":[]}")
    let events = ProviderStreamParser.parseOpenAI(event: event)
    #expect(events.isEmpty)
  }
}
