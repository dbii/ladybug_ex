# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LadybugEx is an Elixir library providing NIF bindings to LadybugDB, a high-performance embedded property graph database with Cypher query support. The library uses Rustler to bridge Elixir with a Rust NIF that interfaces with the C++ LadybugDB engine.

## Build and Development Commands

```bash
# Install dependencies
mix deps.get

# Compile (automatically builds Rust NIF)
mix compile

# Run all tests
mix test

# Run specific test file
mix test test/ladybug_ex/connection_test.exs

# Run specific test
mix test test/ladybug_ex/connection_test.exs:LINE_NUMBER

# Generate documentation
mix docs

# Format code
mix format
```

## Architecture

The codebase has a layered architecture:

1. **Rust NIF Layer** (`native/ladybug_nif/`)
   - `src/lib.rs`: Main NIF implementation with FFI bindings to LadybugDB C++
   - Handles resource management for Database and Connection objects
   - Manages type conversions between Rust/C++ and Elixir

2. **Elixir API Modules** (`lib/ladybug_ex/`)
   - `native.ex`: Direct interface to Rust NIFs, all functions return `:ok` or `{:error, String.t()}`
   - `database.ex`: Database lifecycle (open/in_memory/close)
   - `connection.ex`: Query execution, transactions, prepared statements
   - `graph.ex`: High-level graph operations (nodes, relationships, paths)
   - `schema.ex`: DDL operations for node/relationship tables and indexes
   - `prepared_statement.ex`: Type definition for prepared statements

## Key Implementation Details

### Error Handling Pattern
All Native module functions follow a consistent pattern:
- Success: `:ok` or `{:ok, result}`
- Error: `{:error, reason}` where reason is a string

The API modules wrap these with bang functions that raise on error.

### Resource Management
- Database and Connection are Rust resources managed via Rustler
- Resources are reference-counted and automatically cleaned up
- Connections hold references to their parent Database

### Type System
The schema supports 25+ property types including primitives, dates, lists, and maps. See `lib/ladybug_ex/schema.ex` for the complete type mapping.

### Transaction Handling
Transactions use a functional approach with automatic rollback on error:
```elixir
Connection.transaction(conn, fn conn ->
  # Operations here
  {:ok, result}
end)
```

### Query Result Format
Query results are returned as lists of maps with string keys:
```elixir
[%{"name" => "Alice", "age" => 30}]
```

## Testing Structure

- Unit tests for each module in `test/ladybug_ex/`
- Integration test in `test/integration/graph_operations_test.exs`
- All tests use in-memory databases for isolation
- Tests cover both success and error paths

## Common Development Tasks

### Adding New NIF Functions
1. Add Rust implementation in `native/ladybug_nif/src/lib.rs`
2. Add Elixir declaration in `lib/ladybug_ex/native.ex`
3. Wrap in appropriate API module with error handling
4. Add tests covering success and error cases

### Working with Schema Types
When adding support for new property types:
1. Update type atom mapping in `lib/ladybug_ex/schema.ex`
2. Add corresponding Rust type conversion in NIF layer
3. Test with actual database operations

### Debugging NIF Issues
- Check `native/ladybug_nif/Cargo.toml` for dependency versions
- Build logs show Rust compilation errors
- Use `:debug` mode in development for better error messages