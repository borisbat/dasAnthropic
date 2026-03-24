options gen2
options no_unused_block_arguments = false
options no_unused_function_arguments = false
options indenting = 4

require dastest/testing_boost public
require daslib/json_boost
require anthropic/anthropic
require daslib/fio

// ============================================================================
// Unit tests — SSE line parser
// ============================================================================

[test]
def test_parse_sse_simple(t : T?) {
    t |> run("single event") <| @(t : T?) {
        var buf = "event: message_start\ndata: \{\"type\":\"message_start\"}\n\n"
        var events : array<tuple<string; string>>
        parse_sse_lines(buf) <| $(event_type, data : string) {
            events |> push(event_type => data)
        }
        t |> equal(length(events), 1)
        t |> equal(events[0]._0, "message_start")
        t |> equal(events[0]._1, "\{\"type\":\"message_start\"}")
        t |> equal(buf, "")
    }
    t |> run("multiple events") <| @(t : T?) {
        var buf = "event: ping\ndata: \{\"type\":\"ping\"}\n\nevent: content_block_delta\ndata: \{\"type\":\"content_block_delta\"}\n\n"
        var events : array<tuple<string; string>>
        parse_sse_lines(buf) <| $(event_type, data : string) {
            events |> push(event_type => data)
        }
        t |> equal(length(events), 2)
        t |> equal(events[0]._0, "ping")
        t |> equal(events[1]._0, "content_block_delta")
        t |> equal(buf, "")
    }
    t |> run("partial event stays in buffer") <| @(t : T?) {
        var buf = "event: ping\ndata: \{\"type\":\"ping\"}"
        var events : array<tuple<string; string>>
        parse_sse_lines(buf) <| $(event_type, data : string) {
            events |> push(event_type => data)
        }
        t |> equal(length(events), 0)
        t |> success(!empty(buf))
    }
    t |> run("incremental accumulation") <| @(t : T?) {
        var buf = "event: ping\n"
        var events : array<tuple<string; string>>
        parse_sse_lines(buf) <| $(event_type, data : string) {
            events |> push(event_type => data)
        }
        t |> equal(length(events), 0)
        buf = "{buf}data: \{\"type\":\"ping\"}\n\n"
        parse_sse_lines(buf) <| $(event_type, data : string) {
            events |> push(event_type => data)
        }
        t |> equal(length(events), 1)
        t |> equal(events[0]._0, "ping")
    }
    t |> run("data-only event (no event: line)") <| @(t : T?) {
        var buf = "data: \{\"type\":\"ping\"}\n\n"
        var events : array<tuple<string; string>>
        parse_sse_lines(buf) <| $(event_type, data : string) {
            events |> push(event_type => data)
        }
        t |> equal(length(events), 1)
        t |> equal(events[0]._0, "")
        t |> equal(events[0]._1, "\{\"type\":\"ping\"}")
    }
}

// ============================================================================
// Integration tests — require ANTHROPIC_API_KEY env var
// ============================================================================

def has_api_key() : bool {
    return has_env_variable("ANTHROPIC_API_KEY")
}

[test]
def test_ask_stream(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    var config <- claude_config_from_env()
    t |> run("ask_stream returns text and invokes callback") <| @(t : T?) {
        var error : string
        var fragments : array<string>
        let text = ask_stream(config, "Reply with exactly: streaming works", $(fragment : string) {
            fragments |> push(clone_string(fragment))
        }, error)
        t |> success(empty(error), "no error: {error}")
        t |> success(!empty(text), "got text")
        t |> success(length(fragments) > 0, "got fragments")
        // fragments should concatenate to the full text
        var accumulated = ""
        for (f in fragments) {
            accumulated = "{accumulated}{f}"
        }
        t |> equal(accumulated, text)
    }
}

[test]
def test_create_message_stream_events(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    var config <- claude_config_from_env()
    t |> run("stream receives expected event sequence") <| @(t : T?) {
        var params : MessageCreateParams
        params.messages |> emplace(user_message("Reply with exactly: ok"))
        var error : string
        var got_message_start = false
        var got_content_block_start = false
        var got_content_block_delta = false
        var got_content_block_stop = false
        var got_message_delta = false
        var got_message_stop = false
        var got_ping = false
        create_message_stream(config, params, $(event : StreamEvent) {
            if (event is _message_start) {
                got_message_start = true
            } elif (event is _content_block_start) {
                got_content_block_start = true
            } elif (event is _content_block_delta) {
                got_content_block_delta = true
            } elif (event is _content_block_stop) {
                got_content_block_stop = true
            } elif (event is _message_delta) {
                got_message_delta = true
            } elif (event is _message_stop) {
                got_message_stop = true
            } elif (event is _ping) {
                got_ping = true
            }
        }, error)
        t |> success(empty(error), "no error: {error}")
        t |> success(got_message_start, "got message_start")
        t |> success(got_content_block_start, "got content_block_start")
        t |> success(got_content_block_delta, "got content_block_delta")
        t |> success(got_content_block_stop, "got content_block_stop")
        t |> success(got_message_delta, "got message_delta")
        t |> success(got_message_stop, "got message_stop")
    }
}

[test]
def test_stream_bad_api_key(t : T?) {
    t |> run("streaming with bad key returns error") <| @(t : T?) {
        var config <- claude_config("sk-ant-invalid-key-for-testing")
        var params : MessageCreateParams
        params.messages |> emplace(user_message("hello"))
        var error : string
        var event_count = 0
        create_message_stream(config, params, $(event : StreamEvent) {
            event_count++
        }, error)
        t |> success(!empty(error), "got error")
        t |> equal(event_count, 0)
    }
}

[test]
def test_run_tool_loop_stream(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    var config <- claude_config_from_env()
    t |> run("streaming tool loop calls handler and streams events") <| @(t : T?) {
        var params : MessageCreateParams
        var req_arr : array<JsonValue?>
        req_arr |> push(JV("city"))
        var schema = write_json(JV({
            "type" => JV("object"),
            "properties" => JV({ "city" => JV({ "type" => JV("string") }) }),
            "required" => JV(req_arr)
        }))
        params.tools |> emplace(Tool(
            name = "get_weather",
            description = "Get the weather for a city",
            input_schema = schema
        ))
        params.messages |> emplace(user_message("What is the weather in Paris? Use the get_weather tool."))
        var error : string
        var event_count = 0
        var tool_called = false
        var msg = run_tool_loop_stream(config, params, $(tc : ToolUseBlock) : string {
            tool_called = true
            return write_json(JV({ "temperature" => JV(22), "condition" => JV("sunny") }))
        }, $(event : StreamEvent) {
            event_count++
        }, error)
        t |> success(empty(error), "no error: {error}")
        t |> success(tool_called, "tool was called")
        t |> success(event_count > 0, "received stream events")
        let text = get_text(msg)
        t |> success(!empty(text), "got final text: {text}")
    }
}
