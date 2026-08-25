/// C-ABI entry point exported by the shared library.
export fn greet_message() [*:0]const u8 {
    return "hello from libgreet";
}
