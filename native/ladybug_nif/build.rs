fn main() {
    // Ladybug extensions (vector, fts, llm, ...) are dlopen'ed at runtime and
    // resolve engine symbols from the host process. rustc restricts a cdylib's
    // exported symbols to the Rust/NIF entry points, which hides the statically
    // linked lbug C++ engine symbols and makes every extension fail to load.
    // Explicitly re-export the engine's mangled C++ symbols (functions/methods,
    // vtables, typeinfo) from the NIF library.
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    match target_os.as_str() {
        // "*4lbug*" matches every mangled C++ symbol in the lbug namespace:
        // methods (_ZN4lbug / _ZNK4lbug), vtables (_ZTVN4lbug), typeinfo
        // (_ZTI/_ZTSN4lbug), static guards, thunks, etc.
        // "*yyjson*" covers the bundled yyjson C library (yyjson_* and
        // unsafe_yyjson_*), which the llm/json extensions also resolve
        // from the host.
        "macos" => {
            for pattern in ["*4lbug*", "*yyjson*"] {
                println!("cargo:rustc-link-arg=-Wl,-exported_symbol,{pattern}");
            }
        }
        // On Linux no link-arg can achieve this: rustc's generated version
        // script hides the symbols and overrides -rdynamic,
        // --export-dynamic-symbol, and --dynamic-list. Instead, the linker
        // wrapper configured in .cargo/config.toml strips the version script,
        // and lib.rs promotes the loaded NIF into the global symbol scope
        // (the BEAM dlopens NIFs with RTLD_LOCAL).
        "linux" => {}
        _ => {}
    }
}
