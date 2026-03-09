options gen2
options no_unused_block_arguments = false
options no_unused_function_arguments = false
options indenting = 4

require dastest/testing_boost public
require daslib/json_boost
require anthropic/anthropic

// ============================================================================
// Helpers
// ============================================================================

def json_has_key(jv : JsonValue?; key : string) : bool {
    if (jv == null || !(jv.value is _object)) {
        return false
    }
    let found = (jv.value as _object)?[key] ?? default<JsonValue?>
    return found != null
}

def json_string(jv : JsonValue?; key : string) : string {
    if (jv == null || !(jv.value is _object)) {
        return ""
    }
    let fv = (jv.value as _object)?[key] ?? default<JsonValue?>
    if (fv == null || !(fv.value is _string)) {
        return ""
    }
    return fv.value as _string
}

def json_int(jv : JsonValue?; key : string) : int {
    if (jv == null || !(jv.value is _object)) {
        return 0
    }
    let fv = (jv.value as _object)?[key] ?? default<JsonValue?>
    if (fv == null) {
        return 0
    }
    if (fv.value is _longint) {
        return int(fv.value as _longint)
    } elif (fv.value is _number) {
        return int(fv.value as _number)
    }
    return 0
}

def json_array_length(jv : JsonValue?; key : string) : int {
    if (jv == null || !(jv.value is _object)) {
        return 0
    }
    let fv = (jv.value as _object)?[key] ?? default<JsonValue?>
    if (fv == null || !(fv.value is _array)) {
        return 0
    }
    return length(fv.value as _array)
}

// ============================================================================
// ContentBlockParam JV tests
// ============================================================================

[test]
def test_text_param_jv(t : T?) {
    t |> run("text block serializes with type field") @(t : T?) {
        var blk = text_param("hello")
        var jv = JV(blk)
        t |> equal(json_string(jv, "type"), "text")
        t |> equal(json_string(jv, "text"), "hello")
    }
}

[test]
def test_tool_result_param_jv(t : T?) {
    t |> run("tool_result block serializes correctly") @(t : T?) {
        var blk = tool_result_param("toolu_123", "result text")
        var jv = JV(blk)
        t |> equal(json_string(jv, "type"), "tool_result")
        t |> equal(json_string(jv, "tool_use_id"), "toolu_123")
        t |> equal(json_string(jv, "content"), "result text")
        t |> success(!json_has_key(jv, "is_error"), "is_error omitted when false")
    }
    t |> run("tool_result with is_error=true") @(t : T?) {
        var blk = tool_result_param("toolu_456", "error msg", [is_error = true])
        var jv = JV(blk)
        t |> equal(json_string(jv, "type"), "tool_result")
        t |> success(json_has_key(jv, "is_error"), "is_error present when true")
    }
}

[test]
def test_tool_use_param_jv(t : T?) {
    t |> run("tool_use block serializes with input") @(t : T?) {
        var inp = JV("test")
        var blk = tool_use_param("toolu_abc", "get_weather", inp)
        var jv = JV(blk)
        t |> equal(json_string(jv, "type"), "tool_use")
        t |> equal(json_string(jv, "id"), "toolu_abc")
        t |> equal(json_string(jv, "name"), "get_weather")
        t |> success(json_has_key(jv, "input"), "input field present")
    }
}

// ============================================================================
// ContentBlock from_JV tests
// ============================================================================

[test]
def test_content_block_from_jv(t : T?) {
    t |> run("parse text content block") @(t : T?) {
        var errors : string
        var jv = read_json("\{ \"type\":\"text\",\"text\":\"hello world\" \}", errors)
        t |> success(empty(errors), "parse ok")
        var blk = from_JV(jv, default<ContentBlock>)
        t |> success(blk is _text, "is text block")
        unsafe {
            t |> equal((blk as _text).text, "hello world")
        }
    }
    t |> run("parse tool_use content block") @(t : T?) {
        var errors : string
        var jv = read_json("\{ \"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"calc\",\"input\":\{\"x\":42\} \}", errors)
        t |> success(empty(errors), "parse ok")
        var blk = from_JV(jv, default<ContentBlock>)
        t |> success(blk is _tool_use, "is tool_use block")
        unsafe {
            t |> equal((blk as _tool_use).id, "toolu_1")
            t |> equal((blk as _tool_use).name, "calc")
            t |> success((blk as _tool_use).input != null, "input is not null")
        }
    }
    t |> run("parse thinking content block") @(t : T?) {
        var errors : string
        var jv = read_json("\{ \"type\":\"thinking\",\"thinking\":\"Let me think...\",\"signature\":\"sig123\" \}", errors)
        t |> success(empty(errors), "parse ok")
        var blk = from_JV(jv, default<ContentBlock>)
        t |> success(blk is _thinking, "is thinking block")
        unsafe {
            t |> equal((blk as _thinking).thinking, "Let me think...")
            t |> equal((blk as _thinking).signature, "sig123")
        }
    }
}

// ============================================================================
// ToolChoiceParam JV/from_JV tests
// ============================================================================

[test]
def test_tool_choice_jv(t : T?) {
    t |> run("auto tool choice") @(t : T?) {
        var tc : ToolChoiceParam
        unsafe {
            tc._auto = ToolChoiceAuto()
        }
        var jv = JV(tc)
        t |> equal(json_string(jv, "type"), "auto")
        t |> success(!json_has_key(jv, "disable_parallel_tool_use"), "no disable flag when false")
    }
    t |> run("tool choice with specific tool") @(t : T?) {
        var tc : ToolChoiceParam
        unsafe {
            set_variant_index(tc, 3)
            tc._tool = ToolChoiceTool(name = "get_weather")
        }
        var jv = JV(tc)
        t |> equal(json_string(jv, "type"), "tool")
        t |> equal(json_string(jv, "name"), "get_weather")
    }
    t |> run("tool choice roundtrip") @(t : T?) {
        var errors : string
        var jv = read_json("\{ \"type\":\"any\",\"disable_parallel_tool_use\":true \}", errors)
        t |> success(empty(errors), "parse ok")
        var tc = from_JV(jv, default<ToolChoiceParam>)
        t |> success(tc is _any, "is any")
        unsafe {
            t |> success((tc as _any).disable_parallel_tool_use, "disable flag preserved")
        }
    }
}

// ============================================================================
// MessageCreateParams JV (request building) tests
// ============================================================================

[test]
def test_build_request_json(t : T?) {
    t |> run("minimal request") @(t : T?) {
        var msgs : array<MessageParam>
        msgs |> emplace(user_message("Hello"))
        var req = MessageCreateParams(
            model = "claude-sonnet-4-20250514",
            max_tokens = 1024,
            messages <- msgs
        )
        var json_str = build_request_json(req)
        var errors : string
        var jv = read_json(json_str, errors)
        t |> success(empty(errors), "valid json output")
        t |> equal(json_string(jv, "model"), "claude-sonnet-4-20250514")
        t |> equal(json_int(jv, "max_tokens"), 1024)
        t |> equal(json_array_length(jv, "messages"), 1)
    }
    t |> run("optional fields omitted when default") @(t : T?) {
        var msgs : array<MessageParam>
        msgs |> emplace(user_message("Hi"))
        var req = MessageCreateParams(
            model = "claude-sonnet-4-20250514",
            max_tokens = 100,
            messages <- msgs
        )
        var json_str = build_request_json(req)
        var errors : string
        var jv = read_json(json_str, errors)
        t |> success(!json_has_key(jv, "system"), "system omitted")
        t |> success(!json_has_key(jv, "temperature"), "temperature omitted")
        t |> success(!json_has_key(jv, "top_p"), "top_p omitted")
        t |> success(!json_has_key(jv, "top_k"), "top_k omitted")
        t |> success(!json_has_key(jv, "stop_sequences"), "stop_sequences omitted")
        t |> success(!json_has_key(jv, "tools"), "tools omitted")
        t |> success(!json_has_key(jv, "stream"), "stream omitted")
    }
    t |> run("optional fields present when set") @(t : T?) {
        var msgs : array<MessageParam>
        msgs |> emplace(user_message("Hi"))
        var req = MessageCreateParams(
            model = "claude-sonnet-4-20250514",
            max_tokens = 100,
            messages <- msgs,
            system = "You are helpful.",
            temperature = 0.7
        )
        var json_str = build_request_json(req)
        var errors : string
        var jv = read_json(json_str, errors)
        t |> equal(json_string(jv, "system"), "You are helpful.")
        t |> success(json_has_key(jv, "temperature"), "temperature present")
    }
}

// ============================================================================
// Message from_JV (response parsing) tests
// ============================================================================

[test]
def test_parse_response(t : T?) {
    t |> run("parse simple text response") @(t : T?) {
        let json_str = "\{\"id\":\"msg_01\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[\{\"type\":\"text\",\"text\":\"Hello!\"\}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"end_turn\",\"usage\":\{\"input_tokens\":10,\"output_tokens\":5\}\}"
        var errors : string
        var msg = parse_response(json_str, errors)
        t |> success(empty(errors), "parse ok")
        t |> equal(msg.id, "msg_01")
        t |> equal(msg._type, "message")
        t |> equal(msg.role, "assistant")
        t |> equal(msg.stop_reason, "end_turn")
        t |> equal(msg.model, "claude-sonnet-4-20250514")
        t |> equal(msg.usage.input_tokens, 10)
        t |> equal(msg.usage.output_tokens, 5)
        t |> equal(get_text(msg), "Hello!")
    }
    t |> run("parse tool use response") @(t : T?) {
        let json_str = "\{\"id\":\"msg_02\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[\{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_weather\",\"input\":\{\"location\":\"SF\"\}\}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"tool_use\",\"usage\":\{\"input_tokens\":20,\"output_tokens\":15\}\}"
        var errors : string
        var msg = parse_response(json_str, errors)
        t |> success(empty(errors), "parse ok")
        t |> equal(msg.stop_reason, "tool_use")
        t |> success(has_tool_use(msg), "has tool use")
        var calls = get_tool_calls(msg)
        t |> equal(length(calls), 1)
        t |> equal(calls[0].name, "get_weather")
        t |> equal(calls[0].id, "toolu_1")
        t |> success(calls[0].input != null, "input not null")
    }
    t |> run("parse response with cache usage") @(t : T?) {
        let json_str = "\{\"id\":\"msg_03\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[\{\"type\":\"text\",\"text\":\"cached\"\}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"end_turn\",\"usage\":\{\"input_tokens\":10,\"output_tokens\":5,\"cache_creation_input_tokens\":100,\"cache_read_input_tokens\":50\}\}"
        var errors : string
        var msg = parse_response(json_str, errors)
        t |> success(empty(errors), "parse ok")
        t |> equal(msg.usage.cache_creation_input_tokens, 100)
        t |> equal(msg.usage.cache_read_input_tokens, 50)
    }
}

// ============================================================================
// Message constructors tests
// ============================================================================

[test]
def test_message_constructors(t : T?) {
    t |> run("user_message from string") @(t : T?) {
        var msg = user_message("Hi")
        t |> equal(msg.role, "user")
        t |> equal(length(msg.content), 1)
        t |> success(msg.content[0] is _text, "is text block")
    }
    t |> run("assistant_message from string") @(t : T?) {
        var msg = assistant_message("Hello")
        t |> equal(msg.role, "assistant")
        t |> equal(length(msg.content), 1)
    }
}

// ============================================================================
// Variant roundtrip tests
// ============================================================================

[test]
def test_content_block_roundtrip(t : T?) {
    t |> run("text block roundtrip") @(t : T?) {
        var blk = text_param("roundtrip test")
        var jv = JV(blk)
        var json_str = write_json(jv)
        var errors : string
        var jv2 = read_json(json_str, errors)
        t |> success(empty(errors), "re-parse ok")
        var blk2 = from_JV(jv2, default<ContentBlockParam>)
        t |> success(blk2 is _text, "still text after roundtrip")
        unsafe {
            t |> equal((blk2 as _text).text, "roundtrip test")
        }
    }
}

// ============================================================================
// Tool definition JV test
// ============================================================================

[test]
def test_tool_definition_jv(t : T?) {
    t |> run("tool with embedded input_schema") @(t : T?) {
        var tools : array<Tool>
        tools |> emplace(Tool(
            name = "get_weather",
            description = "Get the weather",
            input_schema = "\{\"type\":\"object\",\"properties\":\{\"location\":\{\"type\":\"string\"\}\},\"required\":[\"location\"]\}"
        ))
        var msgs : array<MessageParam>
        msgs |> emplace(user_message("weather?"))
        var req = MessageCreateParams(
            model = "claude-sonnet-4-20250514",
            max_tokens = 1024,
            messages <- msgs,
            tools <- tools
        )
        var json_str = build_request_json(req)
        var errors : string
        var jv = read_json(json_str, errors)
        t |> success(empty(errors), "valid json")
        t |> equal(json_array_length(jv, "tools"), 1)
    }
}

// ============================================================================
// Stream event from_JV tests
// ============================================================================

[test]
def test_stream_events(t : T?) {
    t |> run("parse message_start event") @(t : T?) {
        let json_str = "\{\"type\":\"message_start\",\"message\":\{\"id\":\"msg_s1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"\",\"usage\":\{\"input_tokens\":25,\"output_tokens\":0\}\}\}"
        var errors : string
        var ev = parse_stream_event(json_str, errors)
        t |> success(empty(errors), "parse ok")
        t |> success(ev is _message_start, "is message_start")
        unsafe {
            t |> equal((ev as _message_start).message.id, "msg_s1")
        }
    }
    t |> run("parse content_block_delta text event") @(t : T?) {
        let json_str = "\{\"type\":\"content_block_delta\",\"index\":0,\"delta\":\{\"type\":\"text_delta\",\"text\":\"Hello\"\}\}"
        var errors : string
        var ev = parse_stream_event(json_str, errors)
        t |> success(empty(errors), "parse ok")
        t |> success(ev is _content_block_delta, "is content_block_delta")
        unsafe {
            let cbd & = ev as _content_block_delta
            t |> equal(cbd.index, 0)
            t |> success(cbd.delta is _text_delta, "delta is text_delta")
            t |> equal((cbd.delta as _text_delta).text, "Hello")
        }
    }
    t |> run("parse ping event") @(t : T?) {
        let json_str = "\{\"type\":\"ping\"\}"
        var errors : string
        var ev = parse_stream_event(json_str, errors)
        t |> success(empty(errors), "parse ok")
        t |> success(ev is _ping, "is ping")
    }
}
