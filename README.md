# das-claude

Typed daslang bindings for the [Anthropic Claude Messages API](https://docs.anthropic.com/en/api/messages).

## Install

```bash
daspkg install das-claude
```

Or from a local checkout:

```bash
daspkg install D:\DASPKG\das-claude
```

## Quick start

```das
options gen2

require anthropic/anthropic

[export]
def main() {
    var config <- claude_config_from_env()  // reads ANTHROPIC_API_KEY
    var error : string
    let reply = ask(config, "What is daslang?", error)
    if (!empty(error)) {
        print("error: {error}\n")
        return
    }
    print("{reply}\n")
}
```

## Features

### One-shot question

```das
let reply = ask(config, "Hello!", error)
```

### Full message control

```das
var params : MessageCreateParams
params.system = "You are a helpful assistant."
params.messages |> emplace(user_message("What is 2+2?"))
var msg = create_message(config, params, error)
print("{get_text(msg)}\n")
```

### Tool use

```das
var params : MessageCreateParams
params.tools |> emplace(Tool(
    name = "get_weather",
    description = "Get weather for a city",
    input_schema = write_json(JV({
        "type" => JV("object"),
        "properties" => JV({ "city" => JV({ "type" => JV("string") }) }),
        "required" => JV(req_arr)
    }))
))
params.messages |> emplace(user_message("What's the weather in Paris?"))

var msg = run_tool_loop(config, params, $(tc : ToolUseBlock) : string {
    // handle tool call, return result as string
    return "{\"temperature\": 22, \"condition\": \"sunny\"}"
}, error)
```

## API

### Configuration

| Function | Description |
|---|---|
| `claude_config(api_key)` | Create config with explicit API key |
| `claude_config_from_env()` | Create config from `ANTHROPIC_API_KEY` env var |

Both accept optional named arguments: `model`, `max_tokens`, `base_url`.

### HTTP client

| Function | Description |
|---|---|
| `create_message(config, params, error)` | Send a Messages API request |
| `ask(config, prompt, error)` | One-shot text question |
| `run_tool_loop(config, params, handler, error)` | Multi-turn tool use loop |

### Request builders

| Function | Description |
|---|---|
| `user_message(text)` | Single-text user message |
| `user_message(blocks)` | Multi-block user message |
| `assistant_message(text)` | Single-text assistant message |
| `text_param(text)` | Text content block |
| `tool_result_param(id, content)` | Tool result content block |

### Response helpers

| Function | Description |
|---|---|
| `get_text(msg)` | Extract concatenated text from response |
| `get_tool_calls(msg)` | Extract tool use blocks |
| `has_tool_use(msg)` | Check if response contains tool calls |

### Serialization

| Function | Description |
|---|---|
| `build_request_json(params)` | Serialize request to JSON string |
| `parse_response(json, error)` | Parse JSON response into `Message` |
| `parse_stream_event(json, error)` | Parse SSE event JSON into `StreamEvent` |

## Types

All types match the [Claude Messages API](https://docs.anthropic.com/en/api/messages) schema:

- **Request:** `MessageCreateParams`, `MessageParam`, `ContentBlockParam` (variant), `Tool`, `ToolChoiceParam` (variant)
- **Response:** `Message`, `ContentBlock` (variant: text/tool_use/thinking), `Usage`
- **Streaming:** `StreamEvent` (variant), `ContentBlockDelta` (variant)

## Dependencies

Built-in daScript modules only — no external packages required:

- `daslib/json_boost` — JSON serialization
- `dashv/dashv_boost` — HTTP client
- `fio` — environment variables

## Tests

```bash
# Serialization tests (no API key needed)
daslang.exe dastest/dastest.das -- --test D:\DASPKG\das-claude\test_anthropic.das

# Integration tests (requires ANTHROPIC_API_KEY)
daslang.exe dastest/dastest.das -- --test D:\DASPKG\das-claude\test_client.das
```

## License

MIT
