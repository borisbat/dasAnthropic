options gen2
options no_unused_block_arguments = false
options no_unused_function_arguments = false
options indenting = 4

require anthropic/anthropic
require daslib/fio
require strings

// Interactive streaming chat with Claude.
// Requires ANTHROPIC_API_KEY environment variable.
//
// Usage: daslang.exe example_chat.das

[export]
def main() {
    if (!has_env_variable("ANTHROPIC_API_KEY")) {
        print("Error: ANTHROPIC_API_KEY environment variable is not set\n")
        return
    }
    var config <- claude_config_from_env()
    var params : MessageCreateParams
    params.system = "You are a helpful assistant. Keep responses concise."
    print("Chat with Claude (streaming). Type 'quit' to exit.\n\n")
    while (true) {
        fprint(fstdout(), "You: ")
        fflush(fstdout())
        var line = fgets(fstdin())
        if (empty(line)) {
            break
        }
        line = strip(line)
        if (line == "quit" || line == "exit") {
            break
        }
        if (empty(line)) {
            continue
        }
        params.messages |> emplace(user_message(line))
        fprint(fstdout(), "\nClaude: ")
        var error : string
        var full_text = ""
        create_message_stream(config, params, $(event : StreamEvent) {
            if (event is _content_block_delta) {
                let ev & = unsafe(event as _content_block_delta)
                if (ev.delta is _text_delta) {
                    let fragment = (ev.delta as _text_delta).text
                    fprint(fstdout(), fragment)
                    fflush(fstdout())
                    full_text = "{full_text}{fragment}"
                }
            }
        }, error)
        print("\n")
        if (!empty(error)) {
            print("Error: {error}\n")
            break
        }
        // add assistant response to conversation history
        params.messages |> emplace(assistant_message(full_text))
        print("\n")
    }
}
