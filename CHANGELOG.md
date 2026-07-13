# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- List parameter support for prepared statements: `Connection.execute/3` now
  accepts Elixir lists as parameter values (`embedding: [0.1, 0.2, ...]`),
  encoded per an element-type inference rule (all-integer -> `INT64[]`,
  any-float/mixed -> `DOUBLE[]` with integers promoted, all-boolean ->
  `BOOL[]`, all-valid-UTF-8-binary -> `STRING[]`). This also covers binding a
  list into a fixed-size `FLOAT[N]`/`DOUBLE[N]` ARRAY column (e.g. vector
  embeddings) — no new API surface was needed; a `List(Double)` param binds
  directly into a `FLOAT[N]` column. See the README's "Parameter types"
  section for the full inference table, unsupported-shape list of edge cases
  (empty lists, `nil` elements, out-of-range integers, non-UTF-8 binaries,
  improper lists, nested lists), and the charlist caveat.

### Changed

- **Breaking (error shape):** unsupported prepared-statement parameter values
  — of any type, not only lists — now return a descriptive
  `{:error, message}` from `execute/3` (and raise a descriptive `RuntimeError`
  from `execute!/3`, unchanged) naming the offending parameter, instead of
  raising a bare `ArgumentError` at the NIF boundary. Existing code that
  pattern-matches on `{:ok, results}` / `{:error, reason}` is unaffected; code
  that specifically caught `ArgumentError` from `execute/3` needs to switch to
  matching `{:error, reason}`.

## [0.2.1] - 2026-07-12

### Fixed

- Extension loading on Linux. Two problems combined to break it: rustc's
  generated version script hid the engine symbols from the NIF library's
  dynamic symbol table (no stable linker flag can re-add them, so the crate
  now links through a wrapper that strips the version script), and the BEAM
  dlopens NIFs with RTLD_LOCAL, so the NIF now promotes itself into the
  global symbol scope with RTLD_NOLOAD | RTLD_GLOBAL at load time. 0.2.0
  only worked on macOS.
- `Vector.create_index/3` and `Vector.query_index/4` validate their options
  before attempting to load the extension, matching FTS and LLM

## [0.2.0] - 2026-07-12

### Added

- Fixed-size ARRAY property type `{:array, type, size}` (e.g. `FLOAT[1536]`),
  required for vector index columns
- FTS results are now ordered by BM25 score (descending) and vector search
  results by distance (ascending)

### Changed

- Upgraded the bundled LadybugDB engine (`lbug` crate) from 0.15 to 0.18.1
- Tables created without an explicit primary key now get an auto-incrementing
  `ladybug_id SERIAL` primary key instead of `ladybug_id INT64`, so inserts no
  longer need to supply it
- FTS and LLM functions validate their options before attempting to load the
  extension, so invalid input returns a clear error even when the extension is
  not installed

### Fixed

- Extensions (fts, vector, llm, json) failed to load with "symbol not found"
  errors: the NIF library now exports the engine symbols extensions resolve at
  runtime, and the published package includes the `build.rs` that configures
  this
- `Extensions.loaded?/2` always returned `false` due to a wrong result column
  name and case-sensitive comparison
- FTS and vector index CALL statements used positional arguments for optional
  parameters, which the engine rejects; they now use named arguments
- Vector index default `pu` parameter was `500`; the engine expects a 0.0-1.0
  DOUBLE (now `0.05`)
- JSON-typed query results (json extension) crashed the NIF; they are now
  returned as serialized JSON strings

### Known Limitations

- The `httpfs` extension crashes the VM on load: the prebuilt extension binary
  is ABI-incompatible with the engine compiled from the `lbug` crate (upstream
  issue)

## [0.1.0] - 2025-01-01

### Added

- Initial release of LadybugEx
- Complete Elixir NIF bindings for LadybugDB embedded property graph database
- Full support for Cypher query language
- Database management (in-memory and persistent)
- Connection management with multiple concurrent connections
- Graph operations (nodes, relationships, properties)
- Schema management (DDL operations)
- Transaction support
- Prepared statements
- Support for array types (FLOAT[], DOUBLE[])
- Comprehensive test suite with 100% pass rate (168 tests)
- Full documentation with ExDoc
- Examples and usage guide in README

### Features

- Create and manage both in-memory and persistent databases
- Execute Cypher queries for graph operations
- Create, read, update, and delete nodes and relationships
- Schema management for node and relationship tables
- Transaction support with rollback capabilities
- Prepared statements for improved performance
- Thread-safe concurrent operations
- Extensions can be installed from LadybugDB's extension server

### Known Limitations

- LadybugDB does not support composite primary keys (only first key is used)
- Cannot add properties that don't exist in the schema
- No native shortestPath function (implemented via iterative approach)
- Reserved words require escaping with backticks
- Extensions require downloading from http://extension.ladybugdb.com/

[0.1.0]: https://github.com/tylerdavis/ladybug_ex/releases/tag/v0.1.0