options gen2
options no_unused_block_arguments = false
options no_unused_function_arguments = false
options indenting = 4

require dastest/testing_boost public
require daslib/json_boost
require anthropic/anthropic
require daslib/fio

// ============================================================================
// Integration tests — require ANTHROPIC_API_KEY env var
// ============================================================================

def has_api_key() : bool {
    return has_env_variable("ANTHROPIC_API_KEY")
}

[test]
def test_ask(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    var config <- claude_config_from_env()
    t |> run("simple ask returns text") <| @(t : T?) {
        var error : string
        let text = ask(config, "Reply with exactly: hello world", error)
        t |> success(empty(error))
        t |> success(!empty(text))
    }
}

[test]
def test_create_message(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    var config <- claude_config_from_env()
    t |> run("create_message returns valid Message") <| @(t : T?) {
        var params : MessageCreateParams
        params.messages |> emplace(user_message("Reply with exactly: test"))
        var error : string
        var msg = create_message(config, params, error)
        t |> success(empty(error))
        t |> equal(msg.role, "assistant")
        t |> success(!empty(msg.id))
        t |> success(!empty(msg.model))
        t |> success(msg.usage.input_tokens > 0)
        t |> success(msg.usage.output_tokens > 0)
        t |> success(length(msg.content) > 0)
    }
}

[test]
def test_create_message_with_system(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    var config <- claude_config_from_env()
    t |> run("system prompt is respected") <| @(t : T?) {
        var params : MessageCreateParams
        params.system = "You are a calculator. Only output numbers."
        params.messages |> emplace(user_message("What is 2+2?"))
        var error : string
        var msg = create_message(config, params, error)
        t |> success(empty(error))
        let text = get_text(msg)
        t |> success(!empty(text))
    }
}

[test]
def test_tool_use(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    var config <- claude_config_from_env()
    t |> run("tool use loop calls handler and returns final response") <| @(t : T?) {
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
        var msg = run_tool_loop(config, params, $(tc : ToolUseBlock) : string {
            t |> equal(tc.name, "get_weather")
            return write_json(JV({ "temperature" => JV(22), "condition" => JV("sunny") }))
        }, error)
        t |> success(empty(error))
        let text = get_text(msg)
        t |> success(!empty(text))
    }
}

[test]
def test_api_error(t : T?) {
    if (!has_api_key()) {
        t |> run("skipped — ANTHROPIC_API_KEY not set") <| @(t : T?) {}
        return
    }
    t |> run("invalid model returns error") <| @(t : T?) {
        var config <- claude_config_from_env([model = "nonexistent-model-xyz"])
        var params : MessageCreateParams
        params.messages |> emplace(user_message("hello"))
        var error : string
        var msg = create_message(config, params, error)
        t |> success(!empty(error))
    }
}

[test]
def test_bad_api_key(t : T?) {
    t |> run("bad API key returns HTTP error") <| @(t : T?) {
        var config <- claude_config("sk-ant-invalid-key-for-testing")
        var params : MessageCreateParams
        params.messages |> emplace(user_message("hello"))
        var error : string
        var msg = create_message(config, params, error)
        t |> success(!empty(error))
    }
}
