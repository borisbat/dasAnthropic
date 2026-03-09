options gen2
options no_unused_block_arguments = false
options no_unused_function_arguments = false
options indenting = 4
options rtti

module anthropic shared private

//! Typed bindings for the Anthropic Claude Messages API.
//!
//! Provides variant-based types matching the Claude API, custom JV/from_JV
//! overloads for JSON serialization with "type" field discriminator, and
//! convenience helpers for building requests and parsing responses.

require strings
require fio
require dashv/dashv_boost
require daslib/json_boost

// ============================================================================
// Response content blocks
// ============================================================================

struct public TextBlock {
    //! Text content block in a response.
    text : string //! generated text
}

struct public ToolUseBlock {
    //! Tool use content block in a response — Claude wants to call a tool.
    id : string       //! unique ID for this tool invocation
    name : string     //! name of the tool to call
    input : JsonValue? //! tool input arguments as raw JSON
}

struct public ThinkingBlock {
    //! Extended thinking content block in a response.
    thinking : string  //! model's chain-of-thought reasoning
    signature : string //! server-side signature for verification
}

// ============================================================================
// Request content blocks
// ============================================================================

struct public TextBlockParam {
    //! Text content block for a request message.
    text : string //! text to send
}

struct public ToolUseBlockParam {
    //! Tool use content block for a request message (assistant turn replay).
    id : string       //! tool invocation ID from the response
    name : string     //! tool name
    input : JsonValue? //! tool input arguments
}

struct public ToolResultBlockParam {
    //! Tool result content block for a request message — returns tool output to Claude.
    tool_use_id : string //! ID of the tool_use block this result corresponds to
    content : string     //! tool execution result as text
    is_error : bool      //! true if the tool execution failed
}

// ============================================================================
// Variant types — discriminated by "type" JSON field
// ============================================================================

variant public ContentBlock {
    //! Response content block, discriminated by "type" in JSON.
    _text : TextBlock
    _tool_use : ToolUseBlock
    _thinking : ThinkingBlock
}

variant public ContentBlockParam {
    //! Request content block, discriminated by "type" in JSON.
    _text : TextBlockParam
    _tool_use : ToolUseBlockParam
    _tool_result : ToolResultBlockParam
}

// ============================================================================
// Tool choice
// ============================================================================

struct public ToolChoiceAuto {
    //! Let Claude decide whether to use tools.
    @optional disable_parallel_tool_use : bool //! prevent multiple tool calls in one turn
}

struct public ToolChoiceAny {
    //! Force Claude to use at least one tool.
    @optional disable_parallel_tool_use : bool //! prevent multiple tool calls in one turn
}

struct public ToolChoiceNone {
    //! Prevent Claude from using any tools.
    _dummy : bool
}

struct public ToolChoiceTool {
    //! Force Claude to use a specific tool.
    name : string //! name of the required tool
    @optional disable_parallel_tool_use : bool //! prevent multiple tool calls in one turn
}

variant public ToolChoiceParam {
    //! Tool choice strategy, discriminated by "type" in JSON.
    _auto : ToolChoiceAuto
    _any : ToolChoiceAny
    _none : ToolChoiceNone
    _tool : ToolChoiceTool
}

// ============================================================================
// Tool definition
// ============================================================================

struct public Tool {
    //! Custom tool definition for function calling.
    name : string                  //! tool name (must match regex [a-zA-Z0-9_-]+)
    @optional description : string //! human-readable description of what the tool does
    @embed input_schema : string   //! JSON Schema for the tool's input parameters
}

// ============================================================================
// Request metadata
// ============================================================================

struct public RequestMetadata {
    //! Optional metadata for the request.
    @optional @rename = "user_id" user_id : string //! external user ID for abuse detection
}

// ============================================================================
// Message params
// ============================================================================

struct public MessageParam {
    //! A single message in the conversation.
    role : string                       //! "user" or "assistant"
    content : array<ContentBlockParam>  //! message content blocks
}

struct public MessageCreateParams {
    //! Request body for the Messages API (POST /v1/messages).
    model : string                              //! model ID, e.g. "claude-sonnet-4-20250514"
    max_tokens : int                            //! maximum tokens to generate
    messages : array<MessageParam>              //! conversation history
    @optional system : string                   //! system prompt
    @optional temperature : float               //! sampling temperature (0.0–1.0)
    @optional top_p : float                     //! nucleus sampling threshold
    @optional top_k : int                       //! top-k sampling
    @optional stop_sequences : array<string>    //! custom stop sequences
    @optional tools : array<Tool>               //! available tools
    @optional tool_choice : ToolChoiceParam     //! tool use strategy
    @optional stream : bool                     //! enable server-sent events streaming
    @optional metadata : RequestMetadata        //! request metadata
}

// ============================================================================
// Response types
// ============================================================================

struct public Usage {
    //! Token usage counts for the request/response.
    input_tokens : int                              //! tokens in the input
    output_tokens : int                             //! tokens in the output
    @optional cache_creation_input_tokens : int     //! tokens written to prompt cache
    @optional cache_read_input_tokens : int         //! tokens read from prompt cache
}

struct public Message {
    //! Response from the Messages API.
    id : string                    //! unique message ID (e.g. "msg_...")
    @rename = "type" _type : string //! always "message"
    role : string                  //! always "assistant"
    content : array<ContentBlock>  //! response content blocks
    model : string                 //! model that generated the response
    stop_reason : string           //! "end_turn", "max_tokens", "stop_sequence", or "tool_use"
    usage : Usage                  //! token usage counts
}

// ============================================================================
// Streaming event types
// ============================================================================

struct public MessageDelta {
    //! Final message metadata sent in a message_delta event.
    @optional stop_reason : string   //! why generation stopped
    @optional stop_sequence : string //! which stop sequence was hit, if any
}

struct public MessageDeltaUsage {
    //! Incremental usage in a message_delta event.
    output_tokens : int //! total output tokens so far
}

struct public TextDelta {
    //! Incremental text in a content_block_delta event.
    text : string //! text fragment
}

struct public InputJsonDelta {
    //! Incremental tool input JSON in a content_block_delta event.
    partial_json : string //! partial JSON fragment
}

struct public ThinkingDelta {
    //! Incremental thinking text in a content_block_delta event.
    thinking : string //! thinking fragment
}

variant public ContentBlockDelta {
    //! Delta payload for a content_block_delta event.
    _text_delta : TextDelta
    _input_json_delta : InputJsonDelta
    _thinking_delta : ThinkingDelta
}

struct public MessageStartEvent {
    //! Sent when the message begins streaming.
    message : Message //! initial message object (content will be empty)
}

struct public MessageDeltaEvent {
    //! Sent at the end of streaming with final metadata.
    delta : MessageDelta        //! final stop reason and sequence
    usage : MessageDeltaUsage   //! final token counts
}

struct public MessageStopEvent {
    //! Sent when the message stream ends.
    _dummy : bool
}

struct public ContentBlockStartEvent {
    //! Sent when a new content block begins streaming.
    index : int                //! index of this block in the content array
    content_block : ContentBlock //! initial block (text will be empty)
}

struct public ContentBlockDeltaEvent {
    //! Sent for each incremental update to a content block.
    index : int               //! index of the block being updated
    delta : ContentBlockDelta //! incremental content
}

struct public ContentBlockStopEvent {
    //! Sent when a content block finishes streaming.
    index : int //! index of the completed block
}

struct public PingEvent {
    //! Keepalive event sent periodically during streaming.
    _dummy : bool
}

variant public StreamEvent {
    //! Server-sent event from the streaming Messages API.
    _message_start : MessageStartEvent
    _message_delta : MessageDeltaEvent
    _message_stop : MessageStopEvent
    _content_block_start : ContentBlockStartEvent
    _content_block_delta : ContentBlockDeltaEvent
    _content_block_stop : ContentBlockStopEvent
    _ping : PingEvent
}

// ============================================================================
// Variant name <-> "type" string mapping
// ============================================================================

let private CONTENT_BLOCK_TYPES = fixed_array("text", "tool_use", "thinking")
let private CONTENT_BLOCK_PARAM_TYPES = fixed_array("text", "tool_use", "tool_result")
let private TOOL_CHOICE_TYPES = fixed_array("auto", "any", "none", "tool")
let private CONTENT_BLOCK_DELTA_TYPES = fixed_array("text_delta", "input_json_delta", "thinking_delta")
let private STREAM_EVENT_TYPES = fixed_array(
    "message_start", "message_delta", "message_stop",
    "content_block_start", "content_block_delta", "content_block_stop",
    "ping"
)

// ============================================================================
// Helpers
// ============================================================================

def private get_type_string(v : JsonValue const?) : string {
    if (v == null || !(v.value is _object)) {
        return ""
    }
    let tv = (v.value as _object)?["type"] ?? default<JsonValue?>
    if (tv == null || !(tv.value is _string)) {
        return ""
    }
    return tv.value as _string
}

def private lookup_type_index(types : auto; s : string) : int {
    for (i in range(length(types))) {
        if (types[i] == s) {
            return i
        }
    }
    return -1
}

def private deconst(v : JsonValue const?) : JsonValue? {
    unsafe {
        return reinterpret<JsonValue?>(v)
    }
}

def private get_field(v : JsonValue const?; key : string) : JsonValue? {
    if (v == null || !(v.value is _object)) {
        return null
    }
    return deconst((v.value as _object)?[key] ?? default<JsonValue?>)
}

def private get_string_field(v : JsonValue const?; key : string) : string {
    let fv = get_field(v, key)
    if (fv == null || !(fv.value is _string)) {
        return ""
    }
    return fv.value as _string
}

def private get_int_field(v : JsonValue const?; key : string) : int {
    let fv = get_field(v, key)
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

def private get_bool_field(v : JsonValue const?; key : string) : bool {
    let fv = get_field(v, key)
    if (fv == null || !(fv.value is _bool)) {
        return false
    }
    return fv.value as _bool
}

// ============================================================================
// Custom JV overloads — variant → JSON with "type" discriminator
// ============================================================================

def public JV(value : ContentBlock) : JsonValue? {
    var map : table<string; JsonValue?>
    if (value is _text) {
        map |> insert("type", JV("text"))
        map |> insert("text", JV((value as _text).text))
    } elif (value is _tool_use) {
        let blk & = unsafe(value as _tool_use)
        map |> insert("type", JV("tool_use"))
        map |> insert("id", JV(blk.id))
        map |> insert("name", JV(blk.name))
        if (blk.input != null) {
            map |> insert("input", deconst(blk.input))
        }
    } elif (value is _thinking) {
        let blk & = unsafe(value as _thinking)
        map |> insert("type", JV("thinking"))
        map |> insert("thinking", JV(blk.thinking))
        map |> insert("signature", JV(blk.signature))
    }
    return JV(map)
}

def public JV(value : ContentBlockParam) : JsonValue? {
    var map : table<string; JsonValue?>
    if (value is _text) {
        map |> insert("type", JV("text"))
        map |> insert("text", JV((value as _text).text))
    } elif (value is _tool_use) {
        let blk & = unsafe(value as _tool_use)
        map |> insert("type", JV("tool_use"))
        map |> insert("id", JV(blk.id))
        map |> insert("name", JV(blk.name))
        if (blk.input != null) {
            map |> insert("input", deconst(blk.input))
        }
    } elif (value is _tool_result) {
        let blk & = unsafe(value as _tool_result)
        map |> insert("type", JV("tool_result"))
        map |> insert("tool_use_id", JV(blk.tool_use_id))
        map |> insert("content", JV(blk.content))
        if (blk.is_error) {
            map |> insert("is_error", JV(true))
        }
    }
    return JV(map)
}

def public JV(value : ToolChoiceParam) : JsonValue? {
    var map : table<string; JsonValue?>
    if (value is _auto) {
        map |> insert("type", JV("auto"))
        if ((value as _auto).disable_parallel_tool_use) {
            map |> insert("disable_parallel_tool_use", JV(true))
        }
    } elif (value is _any) {
        map |> insert("type", JV("any"))
        if ((value as _any).disable_parallel_tool_use) {
            map |> insert("disable_parallel_tool_use", JV(true))
        }
    } elif (value is _none) {
        map |> insert("type", JV("none"))
    } elif (value is _tool) {
        let blk & = unsafe(value as _tool)
        map |> insert("type", JV("tool"))
        map |> insert("name", JV(blk.name))
        if (blk.disable_parallel_tool_use) {
            map |> insert("disable_parallel_tool_use", JV(true))
        }
    }
    return JV(map)
}

def public JV(value : ContentBlockDelta) : JsonValue? {
    var map : table<string; JsonValue?>
    if (value is _text_delta) {
        map |> insert("type", JV("text_delta"))
        map |> insert("text", JV((value as _text_delta).text))
    } elif (value is _input_json_delta) {
        map |> insert("type", JV("input_json_delta"))
        map |> insert("partial_json", JV((value as _input_json_delta).partial_json))
    } elif (value is _thinking_delta) {
        map |> insert("type", JV("thinking_delta"))
        map |> insert("thinking", JV((value as _thinking_delta).thinking))
    }
    return JV(map)
}

def public JV(value : StreamEvent) : JsonValue? {
    var map : table<string; JsonValue?>
    if (value is _message_start) {
        map |> insert("type", JV("message_start"))
        map |> insert("message", JV((value as _message_start).message))
    } elif (value is _message_delta) {
        let ev & = unsafe(value as _message_delta)
        map |> insert("type", JV("message_delta"))
        map |> insert("delta", JV(ev.delta))
        map |> insert("usage", JV(ev.usage))
    } elif (value is _message_stop) {
        map |> insert("type", JV("message_stop"))
    } elif (value is _content_block_start) {
        let ev & = unsafe(value as _content_block_start)
        map |> insert("type", JV("content_block_start"))
        map |> insert("index", JV(ev.index))
        map |> insert("content_block", JV(ev.content_block))
    } elif (value is _content_block_delta) {
        let ev & = unsafe(value as _content_block_delta)
        map |> insert("type", JV("content_block_delta"))
        map |> insert("index", JV(ev.index))
        map |> insert("delta", JV(ev.delta))
    } elif (value is _content_block_stop) {
        map |> insert("type", JV("content_block_stop"))
        map |> insert("index", JV((value as _content_block_stop).index))
    } elif (value is _ping) {
        map |> insert("type", JV("ping"))
    }
    return JV(map)
}

// ============================================================================
// Custom from_JV overloads — JSON with "type" discriminator → variant
// ============================================================================

def public from_JV(v : JsonValue const explicit?; ent : ContentBlock) : ContentBlock {
    let t = get_type_string(v)
    let idx = lookup_type_index(CONTENT_BLOCK_TYPES, t)
    if (idx == 0) {
        return <- ContentBlock(_text = TextBlock(text = get_string_field(v, "text")))
    } elif (idx == 1) {
        return <- ContentBlock(_tool_use = ToolUseBlock(
            id = get_string_field(v, "id"),
            name = get_string_field(v, "name"),
            input = get_field(v, "input")
        ))
    } elif (idx == 2) {
        return <- ContentBlock(_thinking = ThinkingBlock(
            thinking = get_string_field(v, "thinking"),
            signature = get_string_field(v, "signature")
        ))
    }
    return <- ContentBlock(_text = TextBlock())
}

def public from_JV(v : JsonValue const explicit?; ent : ContentBlockParam) : ContentBlockParam {
    let t = get_type_string(v)
    let idx = lookup_type_index(CONTENT_BLOCK_PARAM_TYPES, t)
    if (idx == 0) {
        return <- ContentBlockParam(_text = TextBlockParam(text = get_string_field(v, "text")))
    } elif (idx == 1) {
        return <- ContentBlockParam(_tool_use = ToolUseBlockParam(
            id = get_string_field(v, "id"),
            name = get_string_field(v, "name"),
            input = get_field(v, "input")
        ))
    } elif (idx == 2) {
        return <- ContentBlockParam(_tool_result = ToolResultBlockParam(
            tool_use_id = get_string_field(v, "tool_use_id"),
            content = get_string_field(v, "content"),
            is_error = get_bool_field(v, "is_error")
        ))
    }
    return <- ContentBlockParam(_text = TextBlockParam())
}

def public from_JV(v : JsonValue const explicit?; ent : ToolChoiceParam) : ToolChoiceParam {
    let t = get_type_string(v)
    let idx = lookup_type_index(TOOL_CHOICE_TYPES, t)
    if (idx == 0) {
        return <- ToolChoiceParam(_auto = ToolChoiceAuto(
            disable_parallel_tool_use = get_bool_field(v, "disable_parallel_tool_use")
        ))
    } elif (idx == 1) {
        return <- ToolChoiceParam(_any = ToolChoiceAny(
            disable_parallel_tool_use = get_bool_field(v, "disable_parallel_tool_use")
        ))
    } elif (idx == 2) {
        return <- ToolChoiceParam(_none = ToolChoiceNone())
    } elif (idx == 3) {
        return <- ToolChoiceParam(_tool = ToolChoiceTool(
            name = get_string_field(v, "name"),
            disable_parallel_tool_use = get_bool_field(v, "disable_parallel_tool_use")
        ))
    }
    return <- ToolChoiceParam(_auto = ToolChoiceAuto())
}

def public from_JV(v : JsonValue const explicit?; ent : ContentBlockDelta) : ContentBlockDelta {
    let t = get_type_string(v)
    let idx = lookup_type_index(CONTENT_BLOCK_DELTA_TYPES, t)
    if (idx == 0) {
        return <- ContentBlockDelta(_text_delta = TextDelta(text = get_string_field(v, "text")))
    } elif (idx == 1) {
        return <- ContentBlockDelta(_input_json_delta = InputJsonDelta(
            partial_json = get_string_field(v, "partial_json")
        ))
    } elif (idx == 2) {
        return <- ContentBlockDelta(_thinking_delta = ThinkingDelta(
            thinking = get_string_field(v, "thinking")
        ))
    }
    return <- ContentBlockDelta(_text_delta = TextDelta())
}

def public from_JV(v : JsonValue const explicit?; ent : StreamEvent) : StreamEvent {
    let t = get_type_string(v)
    let idx = lookup_type_index(STREAM_EVENT_TYPES, t)
    if (idx == 0) {
        return <- StreamEvent(_message_start = MessageStartEvent(
            message = from_JV(get_field(v, "message"), default<Message>)
        ))
    } elif (idx == 1) {
        return <- StreamEvent(_message_delta = MessageDeltaEvent(
            delta = from_JV(get_field(v, "delta"), default<MessageDelta>),
            usage = from_JV(get_field(v, "usage"), default<MessageDeltaUsage>)
        ))
    } elif (idx == 2) {
        return <- StreamEvent(_message_stop = MessageStopEvent())
    } elif (idx == 3) {
        return <- StreamEvent(_content_block_start = ContentBlockStartEvent(
            index = get_int_field(v, "index"),
            content_block = from_JV(get_field(v, "content_block"), default<ContentBlock>)
        ))
    } elif (idx == 4) {
        return <- StreamEvent(_content_block_delta = ContentBlockDeltaEvent(
            index = get_int_field(v, "index"),
            delta = from_JV(get_field(v, "delta"), default<ContentBlockDelta>)
        ))
    } elif (idx == 5) {
        return <- StreamEvent(_content_block_stop = ContentBlockStopEvent(
            index = get_int_field(v, "index")
        ))
    } elif (idx == 6) {
        return <- StreamEvent(_ping = PingEvent())
    }
    return <- StreamEvent(_message_start = MessageStartEvent())
}

// ============================================================================
// Public API — request building
// ============================================================================

def public build_request_json(req : MessageCreateParams) : string {
    //! Serialize a MessageCreateParams to a JSON string for the Messages API.
    var jv = JV(req)
    return write_json(jv)
}

// ============================================================================
// Public API — response parsing
// ============================================================================

def public parse_response(json_str : string; var error : string&) : Message {
    //! Parse a Messages API JSON response into a Message struct.
    var jv = read_json(json_str, error)
    if (jv == null) {
        return default<Message>
    }
    return from_JV(jv, default<Message>)
}

def public parse_stream_event(json_str : string; var error : string&) : StreamEvent {
    //! Parse a streaming SSE JSON payload into a StreamEvent variant.
    var jv = read_json(json_str, error)
    if (jv == null) {
        return default<StreamEvent>
    }
    return from_JV(jv, default<StreamEvent>)
}

// ============================================================================
// Public API — content block param constructors
// ============================================================================

def public text_param(text : string) : ContentBlockParam {
    //! Create a text content block param.
    return <- ContentBlockParam(_text = TextBlockParam(text = text))
}

def public tool_use_param(id, name : string; var input : JsonValue?) : ContentBlockParam {
    //! Create a tool_use content block param (for replaying assistant tool calls).
    return <- ContentBlockParam(_tool_use = ToolUseBlockParam(id = id, name = name, input <- input))
}

def public tool_result_param(tool_use_id, content : string; is_error : bool = false) : ContentBlockParam {
    //! Create a tool_result content block param with the tool's output.
    return <- ContentBlockParam(_tool_result = ToolResultBlockParam(
        tool_use_id = tool_use_id, content = content, is_error = is_error
    ))
}

// ============================================================================
// Public API — message param constructors
// ============================================================================

def public user_message(text : string) : MessageParam {
    //! Create a user message with a single text block.
    var blocks : array<ContentBlockParam>
    blocks |> emplace(text_param(text))
    return <- MessageParam(role = "user", content <- blocks)
}

def public user_message(var blocks : array<ContentBlockParam>) : MessageParam {
    //! Create a user message with multiple content blocks.
    return <- MessageParam(role = "user", content <- blocks)
}

def public assistant_message(text : string) : MessageParam {
    //! Create an assistant message with a single text block.
    var blocks : array<ContentBlockParam>
    blocks |> emplace(text_param(text))
    return <- MessageParam(role = "assistant", content <- blocks)
}

def public assistant_message(var blocks : array<ContentBlockParam>) : MessageParam {
    //! Create an assistant message with multiple content blocks.
    return <- MessageParam(role = "assistant", content <- blocks)
}

// ============================================================================
// Public API — response inspection
// ============================================================================

def public get_text(msg : Message) : string {
    //! Extract concatenated text from all text content blocks in a response.
    return build_string() $(var writer) {
        for (blk in msg.content) {
            if (blk is _text) {
                writer |> write((blk as _text).text)
            }
        }
    }
}

def public get_tool_calls(msg : Message) : array<ToolUseBlock> {
    //! Extract all tool_use blocks from a response.
    var result : array<ToolUseBlock>
    for (blk in msg.content) {
        if (blk is _tool_use) {
            let tc & = unsafe(blk as _tool_use)  // reference binding requires unsafe
            var inp = deconst(tc.input)
            result |> emplace(ToolUseBlock(id = tc.id, name = tc.name, input <- inp))
        }
    }
    return <- result
}

def public has_tool_use(msg : Message) : bool {
    //! Return true if the response contains any tool_use blocks.
    for (blk in msg.content) {
        if (blk is _tool_use) {
            return true
        }
    }
    return false
}

// ============================================================================
// v1 — Configuration
// ============================================================================

let public CLAUDE_DEFAULT_BASE_URL = "https://api.anthropic.com"
let public CLAUDE_DEFAULT_MODEL = "claude-sonnet-4-20250514"
let public CLAUDE_DEFAULT_MAX_TOKENS = 4096
let private ANTHROPIC_VERSION = "2023-06-01"

struct public ClaudeConfig {
    //! Configuration for Claude API calls.
    api_key : string       //! Anthropic API key (sk-ant-...)
    model : string         //! model ID (default: claude-sonnet-4-20250514)
    max_tokens : int       //! default max tokens for responses
    base_url : string      //! API base URL (default: https://api.anthropic.com)
}

def public claude_config(api_key : string;
                         model : string = CLAUDE_DEFAULT_MODEL;
                         max_tokens : int = CLAUDE_DEFAULT_MAX_TOKENS;
                         base_url : string = CLAUDE_DEFAULT_BASE_URL) : ClaudeConfig {
    //! Create a ClaudeConfig with an explicit API key.
    return <- ClaudeConfig(
        api_key = api_key,
        model = model,
        max_tokens = max_tokens,
        base_url = base_url
    )
}

def public claude_config_from_env(model : string = CLAUDE_DEFAULT_MODEL;
                                  max_tokens : int = CLAUDE_DEFAULT_MAX_TOKENS;
                                  base_url : string = CLAUDE_DEFAULT_BASE_URL) : ClaudeConfig {
    //! Create a ClaudeConfig reading the API key from the ANTHROPIC_API_KEY environment variable.
    //! Panics if the variable is not set.
    if (!has_env_variable("ANTHROPIC_API_KEY")) {
        panic("ANTHROPIC_API_KEY environment variable is not set")
    }
    return <- ClaudeConfig(
        api_key = get_env_variable("ANTHROPIC_API_KEY"),
        model = model,
        max_tokens = max_tokens,
        base_url = base_url
    )
}

// ============================================================================
// v1 — HTTP client
// ============================================================================

def private make_headers(config : ClaudeConfig) : table<string; string> {
    return <- { "x-api-key" => config.api_key, "anthropic-version" => ANTHROPIC_VERSION, "content-type" => "application/json" }
}

def public create_message(config : ClaudeConfig; var params : MessageCreateParams; var error : string&) : Message {
    //! Send a Messages API request and return the parsed response.
    //! Sets ``error`` to a non-empty string on failure (network error, HTTP error, or JSON parse error).
    //! Modifies ``params`` in place to apply config defaults for model and max_tokens.
    if (empty(params.model)) {
        params.model = config.model
    }
    if (params.max_tokens == 0) {
        params.max_tokens = config.max_tokens
    }
    let body = build_request_json(params)
    let url = "{config.base_url}/v1/messages"
    var headers <- make_headers(config)
    var result : Message
    error = ""
    POST(url, body, headers) <| $(var resp : HttpResponse?) {
        if (resp.status_code != http_status.OK) {
            peek(resp.body) <| $(text : string#) {
                error = "HTTP {int(resp.status_code)}: {text}"
            }
        } else {
            peek(resp.body) <| $(text : string#) {
                result = parse_response(string(text), error)
            }
        }
    }
    return <- result
}

def public ask(config : ClaudeConfig; prompt : string; var error : string&) : string {
    //! One-shot convenience: send a user message and return the text response.
    var params : MessageCreateParams
    params.messages |> emplace(user_message(prompt))
    var msg = create_message(config, params, error)
    if (!empty(error)) {
        return ""
    }
    return get_text(msg)
}

def public run_tool_loop(config : ClaudeConfig;
                         var params : MessageCreateParams;
                         handler : block<(tc : ToolUseBlock) : string>;
                         var error : string&;
                         max_iterations : int = 10) : Message {
    //! Run a tool-use loop: send the request, call tools via ``handler``, feed results back,
    //! and repeat until Claude stops requesting tools or ``max_iterations`` is reached.
    //! The ``handler`` block receives each ToolUseBlock and must return the tool result as a string.
    var msg = create_message(config, params, error)
    for (_ in range(max_iterations)) {
        if (!empty(error) || !has_tool_use(msg)) {
            break
        }
        // build assistant turn with the response content
        var assistant_blocks : array<ContentBlockParam>
        for (blk in msg.content) {
            if (blk is _text) {
                assistant_blocks |> emplace(text_param((blk as _text).text))
            } elif (blk is _tool_use) {
                let tc & = unsafe(blk as _tool_use)
                var inp = deconst(tc.input)
                assistant_blocks |> emplace(tool_use_param(tc.id, tc.name, inp))
            }
        }
        params.messages |> emplace(assistant_message(assistant_blocks))
        // build tool results
        var result_blocks : array<ContentBlockParam>
        for (blk in msg.content) {
            if (blk is _tool_use) {
                let tc & = unsafe(blk as _tool_use)
                let result_text = invoke(handler, tc)
                result_blocks |> emplace(tool_result_param(tc.id, result_text))
            }
        }
        params.messages |> emplace(user_message(result_blocks))
        msg = create_message(config, params, error)
    }
    return <- msg
}
