# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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