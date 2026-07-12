#!/bin/bash
# Linker wrapper used on Linux (see .cargo/config.toml).
#
# rustc restricts a cdylib's exported symbols with a generated version script
# ({ global: <rust symbols>; local: *; }), which hides the statically linked
# lbug C++ engine symbols. Ladybug extensions (fts, vector, llm, json, ...)
# are dlopen'ed at runtime and resolve those symbols from this library, so
# hiding them breaks all extension loading. No stable linker flag can add
# symbols back (--export-dynamic-symbol and --dynamic-list are no-ops for
# shared libraries), so this wrapper drops the version-script argument
# entirely, restoring the default behavior of exporting all global symbols.
args=()
for a in "$@"; do
  case "$a" in
    -Wl,--version-script=*) ;;
    @*)
      # linker arguments may arrive in a response file: filter its lines
      f="${a#@}"
      grep -v -- '--version-script' "$f" > "$f.no-version-script"
      args+=("@$f.no-version-script")
      ;;
    *) args+=("$a") ;;
  esac
done
exec cc "${args[@]}"
