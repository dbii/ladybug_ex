use lbug::{
    Connection, Database, LogicalType, PreparedStatement, QueryResult, SystemConfig, Value,
};
use parking_lot::Mutex;
use rustler::{Encoder, Env, ListIterator, NifResult, OwnedBinary, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        nil,
        true_ = "true",
        false_ = "false",

        // Error types
        database_error,
        connection_error,
        query_error,
        type_conversion_error,

        // Graph types
        node,
        rel,
        recursive_rel,

        // Node/Rel fields
        id,
        label,
        properties,
        src,
        dst,
        nodes,
        rels,
    }
}

#[derive(Error, Debug)]
pub enum LadybugError {
    #[error("Database error: {0}")]
    Database(String),

    #[error("Connection error: {0}")]
    Connection(String),

    #[error("Query error: {0}")]
    Query(String),

    #[error("Type conversion error: {0}")]
    TypeConversion(String),
}

impl Encoder for LadybugError {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let error_atom = match self {
            LadybugError::Database(_) => atoms::database_error(),
            LadybugError::Connection(_) => atoms::connection_error(),
            LadybugError::Query(_) => atoms::query_error(),
            LadybugError::TypeConversion(_) => atoms::type_conversion_error(),
        };
        (error_atom, self.to_string()).encode(env)
    }
}

// Resource wrapper for Database - we'll leak it to get 'static lifetime
struct DatabaseResource {
    db: Arc<Database>,
}

// Resource wrapper for Connection with leaked database reference
struct ConnectionResource {
    conn: Arc<Mutex<Connection<'static>>>,
    _db: Arc<Database>, // Keep database alive
}

// Resource wrapper for PreparedStatement - using raw pointer for Send/Sync
struct PreparedStatementResource {
    stmt: *mut PreparedStatement,
    _conn: Arc<Mutex<Connection<'static>>>, // Keep connection alive
}

// Implement Send and Sync manually for PreparedStatementResource
unsafe impl Send for PreparedStatementResource {}
unsafe impl Sync for PreparedStatementResource {}

// Implement Drop to clean up the raw pointer
impl Drop for PreparedStatementResource {
    fn drop(&mut self) {
        unsafe {
            // Clean up the raw pointer
            let _ = Box::from_raw(self.stmt);
        }
    }
}

// Helper function to convert SystemConfig from Elixir keyword list
fn parse_system_config(config_term: Term) -> NifResult<SystemConfig> {
    let mut config = SystemConfig::default();
    let mut has_buffer_pool_size = false;

    if let Ok(opts) = config_term.decode::<Vec<(String, Term)>>() {
        for (key, value) in opts {
            match key.as_str() {
                "buffer_pool_size" => {
                    if let Ok(size) = value.decode::<u64>() {
                        config = config.buffer_pool_size(size);
                        has_buffer_pool_size = true;
                    }
                }
                "max_num_threads" => {
                    if let Ok(threads) = value.decode::<u64>() {
                        config = config.max_num_threads(threads);
                    }
                }
                "enable_compression" => {
                    if let Ok(enabled) = value.decode::<bool>() {
                        config = config.enable_compression(enabled);
                    }
                }
                "read_only" => {
                    if let Ok(read_only) = value.decode::<bool>() {
                        config = config.read_only(read_only);
                    }
                }
                "max_db_size" => {
                    if let Ok(size) = value.decode::<u64>() {
                        config = config.max_db_size(size);
                    }
                }
                _ => {} // Ignore unknown options
            }
        }
    }

    // Set a reasonable default buffer pool size if not specified (512MB)
    // This avoids the 8TB allocation issue
    if !has_buffer_pool_size {
        config = config.buffer_pool_size(512 * 1024 * 1024);
    }

    Ok(config)
}

// Convert Rust Value to Elixir Term
fn value_to_term<'a>(env: Env<'a>, value: &Value) -> NifResult<Term<'a>> {
    match value {
        Value::Null(_) => Ok(atoms::nil().encode(env)),
        Value::Bool(b) => Ok(b.encode(env)),
        Value::Int8(i) => Ok((*i as i64).encode(env)),
        Value::Int16(i) => Ok((*i as i64).encode(env)),
        Value::Int32(i) => Ok((*i as i64).encode(env)),
        Value::Int64(i) => Ok(i.encode(env)),
        Value::UInt8(i) => Ok((*i as u64).encode(env)),
        Value::UInt16(i) => Ok((*i as u64).encode(env)),
        Value::UInt32(i) => Ok((*i as u64).encode(env)),
        Value::UInt64(i) => Ok(i.encode(env)),
        Value::Int128(i) => Ok(i.to_string().encode(env)),
        Value::Float(f) => Ok(f.encode(env)),
        Value::Double(d) => Ok(d.encode(env)),
        Value::String(s) => Ok(s.encode(env)),
        Value::Blob(data) => {
            let mut owned = OwnedBinary::new(data.len()).unwrap();
            owned.as_mut_slice().copy_from_slice(&data);
            Ok(owned.release(env).encode(env))
        }
        Value::Date(d) => Ok(d.to_string().encode(env)),
        Value::Timestamp(t) => Ok(t.to_string().encode(env)),
        Value::TimestampTz(t) => Ok(t.to_string().encode(env)),
        Value::TimestampNs(t) => Ok(t.to_string().encode(env)),
        Value::TimestampMs(t) => Ok(t.to_string().encode(env)),
        Value::TimestampSec(t) => Ok(t.to_string().encode(env)),
        Value::Interval(i) => Ok(i.to_string().encode(env)),
        Value::UUID(u) => Ok(u.to_string().encode(env)),
        // JSON values (json extension) are returned as their serialized string
        Value::Json(j) => Ok(j.to_string().encode(env)),
        Value::List(_, items) => {
            let mut elixir_list = Vec::new();
            for item in items {
                elixir_list.push(value_to_term(env, item)?);
            }
            Ok(elixir_list.encode(env))
        }
        Value::Array(_, items) => {
            let mut elixir_list = Vec::new();
            for item in items {
                elixir_list.push(value_to_term(env, item)?);
            }
            Ok(elixir_list.encode(env))
        }
        Value::Map(_, map) => {
            let mut elixir_map = HashMap::new();
            for (k, v) in map {
                // Convert key to string for proper map keys
                let key_str = match k {
                    Value::String(s) => s.clone(),
                    _ => format!("{:?}", k),
                };
                elixir_map.insert(key_str, value_to_term(env, v)?);
            }
            Ok(elixir_map.encode(env))
        }
        Value::Struct(fields) => {
            let mut elixir_map = HashMap::new();
            for (name, value) in fields {
                elixir_map.insert(name.clone(), value_to_term(env, value)?);
            }
            Ok(elixir_map.encode(env))
        }
        Value::Node(node) => {
            // Convert InternalID to string
            let id_str = node.get_node_id().to_string();
            let label_str = node.get_label_name();
            let props = node.get_properties();

            // Convert properties to a HashMap
            let mut prop_map = HashMap::new();
            for (k, v) in props {
                prop_map.insert(k, value_to_term(env, &v)?);
            }

            // Create a HashMap for the node
            let mut node_map = HashMap::new();
            node_map.insert("node", atoms::true_().encode(env));
            node_map.insert("id", id_str.encode(env));
            node_map.insert("label", label_str.encode(env));
            node_map.insert("properties", prop_map.encode(env));

            Ok(node_map.encode(env))
        }
        Value::Rel(rel) => {
            let label_str = rel.get_label_name();
            // Convert InternalIDs to strings
            let src_str = rel.get_src_node().to_string();
            let dst_str = rel.get_dst_node().to_string();
            let props = rel.get_properties();

            // Convert properties to a HashMap
            let mut prop_map = HashMap::new();
            for (k, v) in props {
                prop_map.insert(k, value_to_term(env, &v)?);
            }

            // Create a HashMap for the relationship
            let mut rel_map = HashMap::new();
            rel_map.insert("rel", atoms::true_().encode(env));
            rel_map.insert("label", label_str.encode(env));
            rel_map.insert("src", src_str.encode(env));
            rel_map.insert("dst", dst_str.encode(env));
            rel_map.insert("properties", prop_map.encode(env));

            Ok(rel_map.encode(env))
        }
        Value::RecursiveRel { nodes, rels } => {
            let nodes_list: Vec<Term> = nodes
                .iter()
                .map(|n| {
                    // Wrap NodeVal in Value::Node
                    value_to_term(env, &Value::Node(n.clone()))
                })
                .collect::<NifResult<Vec<_>>>()?;
            let rels_list: Vec<Term> = rels
                .iter()
                .map(|r| {
                    // Wrap RelVal in Value::Rel
                    value_to_term(env, &Value::Rel(r.clone()))
                })
                .collect::<NifResult<Vec<_>>>()?;

            // Create a HashMap for the recursive relationship
            let mut rec_rel_map = HashMap::new();
            rec_rel_map.insert("recursive_rel", atoms::true_().encode(env));
            rec_rel_map.insert("nodes", nodes_list.encode(env));
            rec_rel_map.insert("rels", rels_list.encode(env));

            Ok(rec_rel_map.encode(env))
        }
        Value::InternalID(id) => Ok(id.to_string().encode(env)),
        Value::Decimal(d) => Ok(d.to_string().encode(env)),
        Value::Union { types: _, value } => {
            // Just encode the inner value for now
            value_to_term(env, value)
        }
    }
}

// Convert query results to Elixir terms
fn query_result_to_terms<'a>(env: Env<'a>, mut result: QueryResult) -> NifResult<Vec<Term<'a>>> {
    let mut rows = Vec::new();

    // Get column names from the result
    let columns: Vec<String> = result.get_column_names();

    // Iterate through results using next() which returns Option
    while let Some(values) = result.next() {
        let mut row_map = HashMap::new();

        // values is likely Vec<Value> based on the API
        let values: Vec<Value> = values;

        for (i, value) in values.iter().enumerate() {
            if i < columns.len() {
                let column_name: &String = &columns[i];
                let value_term = value_to_term(env, value)?;
                row_map.insert(column_name.clone(), value_term);
            }
        }

        // Convert HashMap to Elixir map term
        rows.push(row_map.encode(env));
    }

    Ok(rows)
}

// NIF Functions

#[rustler::nif]
fn open_database<'a>(env: Env<'a>, path: String, config: Term<'a>) -> NifResult<Term<'a>> {
    let system_config = parse_system_config(config)?;

    // Create parent directory if it doesn't exist
    if let Some(parent) = std::path::Path::new(&path).parent() {
        if !parent.exists() {
            if let Err(e) = std::fs::create_dir_all(parent) {
                return Ok((atoms::error(), format!("Failed to create directory: {}", e)).encode(env));
            }
        }
    }

    match Database::new(&path, system_config) {
        Ok(db) => {
            let resource = ResourceArc::new(DatabaseResource {
                db: Arc::new(db),
            });
            Ok((atoms::ok(), resource).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

#[rustler::nif]
fn in_memory_database<'a>(env: Env<'a>, config: Term<'a>) -> NifResult<Term<'a>> {
    let system_config = parse_system_config(config)?;

    match Database::new(":memory:", system_config) {
        Ok(db) => {
            let resource = ResourceArc::new(DatabaseResource {
                db: Arc::new(db),
            });
            Ok((atoms::ok(), resource).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

#[rustler::nif]
fn new_connection<'a>(
    env: Env<'a>,
    database_resource: ResourceArc<DatabaseResource>,
) -> NifResult<Term<'a>> {
    // Get the database from the resource
    let db_arc = Arc::clone(&database_resource.db);

    // Create a leaked reference to satisfy 'static lifetime requirement
    // This is a workaround - in production, consider using a different approach
    let db_ptr: *const Database = Arc::as_ptr(&db_arc);
    let db_ref: &'static Database = unsafe { &*db_ptr };

    match Connection::new(db_ref) {
        Ok(conn) => {
            let resource = ResourceArc::new(ConnectionResource {
                conn: Arc::new(Mutex::new(conn)),
                _db: db_arc,
            });
            Ok((atoms::ok(), resource).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

#[rustler::nif]
fn query<'a>(
    env: Env<'a>,
    connection_resource: ResourceArc<ConnectionResource>,
    query_str: String,
) -> NifResult<Term<'a>> {
    let conn_mutex = Arc::clone(&connection_resource.conn);
    let conn = conn_mutex.lock();

    match conn.query(&query_str) {
        Ok(result) => {
            match query_result_to_terms(env, result) {
                Ok(rows) => Ok((atoms::ok(), rows).encode(env)),
                Err(e) => Ok((atoms::error(), format!("Failed to convert results: {:?}", e)).encode(env)),
            }
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

#[rustler::nif]
fn prepare<'a>(
    env: Env<'a>,
    connection_resource: ResourceArc<ConnectionResource>,
    query_str: String,
) -> NifResult<Term<'a>> {
    let conn_mutex = Arc::clone(&connection_resource.conn);
    let conn = conn_mutex.lock();

    match conn.prepare(&query_str) {
        Ok(stmt) => {
            // Box and leak the PreparedStatement to get a raw pointer
            let stmt_ptr = Box::into_raw(Box::new(stmt));
            let resource = ResourceArc::new(PreparedStatementResource {
                stmt: stmt_ptr,
                _conn: Arc::clone(&conn_mutex),
            });
            Ok((atoms::ok(), resource).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

#[rustler::nif]
fn execute<'a>(
    env: Env<'a>,
    connection_resource: ResourceArc<ConnectionResource>,
    prepared_resource: ResourceArc<PreparedStatementResource>,
    params: Vec<(String, Term<'a>)>,
) -> NifResult<Term<'a>> {
    // Convert Elixir terms to Ladybug Values. Any unsupported parameter value
    // (scalar or list) returns a descriptive `{:error, message}` naming the
    // parameter instead of raising a bare ArgumentError at the NIF boundary —
    // see term_to_value_named.
    //
    // All caller-controlled validation/conversion work (including the Value
    // clones for param_refs below) happens BEFORE the connection mutex is
    // acquired, so a large or malformed parameter can never stall other
    // connections' callers while holding the lock; only the actual
    // bind/execute runs under it.
    let mut params_with_values: Vec<(String, Value)> = Vec::with_capacity(params.len());
    for (name, term) in params {
        match term_to_value_named(&name, term) {
            Ok(value) => params_with_values.push((name, value)),
            Err(message) => return Ok((atoms::error(), message).encode(env)),
        }
    }

    // Now convert to the expected format with string references
    let param_refs: Vec<(&str, Value)> = params_with_values
        .iter()
        .map(|(name, value)| (name.as_str(), value.clone()))
        .collect();

    let conn_mutex = Arc::clone(&connection_resource.conn);
    let conn = conn_mutex.lock();

    // Get the PreparedStatement from raw pointer - UNSAFE
    let stmt = unsafe { &mut *prepared_resource.stmt };

    match conn.execute(stmt, param_refs) {
        Ok(result) => {
            match query_result_to_terms(env, result) {
                Ok(rows) => Ok((atoms::ok(), rows).encode(env)),
                Err(e) => Ok((atoms::error(), format!("Failed to convert results: {:?}", e)).encode(env)),
            }
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

/// Converts an Elixir term to a Ladybug `Value`, tagging any failure with the
/// parameter name so `execute/3` can return `{:error, message}` instead of
/// raising a bare `ArgumentError` at the NIF boundary. This covers every
/// unsupported parameter type, not only lists.
///
/// List parameters are decoded per the element-type inference rules
/// documented in the README's "Parameter types" section: an all-integer list
/// becomes `List(Int64)`; an all-float (or mixed int+float, with ints
/// promoted) list becomes `List(Double)`; an all-boolean list becomes
/// `List(Bool)`; an all-valid-UTF-8-binary list becomes `List(String)`.
/// Anything else — heterogeneous elements, `nil` elements, out-of-range
/// integers, non-UTF-8 binaries, atoms, nested lists, improper lists, or an
/// empty list — returns a descriptive error instead of encoding.
fn term_to_value_named(name: &str, term: Term) -> Result<Value, String> {
    if term.is_list() {
        return list_term_to_value(name, term);
    }

    if let Ok(i) = term.decode::<i64>() {
        Ok(Value::Int64(i))
    } else if let Ok(f) = term.decode::<f64>() {
        Ok(Value::Double(f))
    } else if let Ok(s) = term.decode::<String>() {
        Ok(Value::String(s))
    } else if let Ok(b) = term.decode::<bool>() {
        Ok(Value::Bool(b))
    } else if term.is_atom() {
        // Check for nil
        if term.atom_to_string().unwrap_or_default() == "nil" {
            Ok(Value::Null(LogicalType::Any))
        } else {
            Ok(Value::String(term.atom_to_string().unwrap_or_default()))
        }
    } else {
        Err(format!("unsupported parameter type for ${name}"))
    }
}

/// Largest integer magnitude exactly representable as an IEEE-754 double
/// (2^53). Integers beyond this are rejected in mixed numeric lists rather
/// than silently rounded (pure-integer lists keep full i64 fidelity and
/// never hit this check).
const MAX_EXACT_F64_INT: i64 = 1 << 53;

/// Converts an integer to f64 for mixed-numeric-list promotion, rejecting
/// values outside the exactly representable range `-2^53..=2^53`.
fn int_to_exact_f64(name: &str, i: i64) -> Result<f64, String> {
    if (-MAX_EXACT_F64_INT..=MAX_EXACT_F64_INT).contains(&i) {
        Ok(i as f64)
    } else {
        Err(format!(
            "integer {i} in mixed numeric list for ${name} exceeds exact f64 range"
        ))
    }
}

/// Decodes a non-empty, proper Elixir list into a `Value::List` in a single
/// pass: each element is decoded exactly once, directly into its `Value`,
/// while the inferred element type is tracked as the pass goes. The only
/// re-visit of already-decoded values is the Int64 -> Double rewrite when a
/// float first appears after integers (promotion genuinely requires it), and
/// that touches each element at most once overall — conversion stays O(n)
/// with no intermediate `Vec<Term>` copy and no multiple inference scans.
///
/// Safety: Rustler's `ListIterator` panics if it reaches an improper list's
/// non-nil tail (see rustler's `types::list::ListIterator::next`). This
/// function establishes that `term` is a proper list via `Term::list_length()`
/// — which returns `Err` for improper lists without panicking — before ever
/// constructing a `ListIterator`, so the descriptive error below is actually
/// reachable instead of crashing the NIF.
fn list_term_to_value(name: &str, term: Term) -> Result<Value, String> {
    #[derive(PartialEq)]
    enum Kind {
        Unknown,
        Int,
        Double,
        Bool,
        Str,
    }

    let len = term
        .list_length()
        .map_err(|_| format!("unsupported parameter type for ${name}: improper list"))?;

    if len == 0 {
        return Err(format!(
            "empty list parameters are unsupported for ${name} — no element type can be inferred"
        ));
    }

    let hetero = || format!("unsupported parameter type for ${name}: heterogeneous list");

    // Safe: `list_length()` succeeded above, so `term` is a proper list and
    // this iterator cannot hit the improper-tail panic path.
    let iter = term
        .decode::<ListIterator>()
        .map_err(|_| format!("unsupported parameter type for ${name}: invalid list"))?;

    let mut kind = Kind::Unknown;
    let mut values: Vec<Value> = Vec::with_capacity(len);

    for item in iter {
        if item.is_atom() {
            let b = match item.atom_to_string().unwrap_or_default().as_str() {
                "true" => true,
                "false" => false,
                "nil" => {
                    return Err(format!(
                        "unsupported parameter type for ${name}: null-containing list"
                    ))
                }
                _ => {
                    return Err(format!(
                        "unsupported parameter type for ${name}: atom inside list"
                    ))
                }
            };
            match kind {
                Kind::Unknown => kind = Kind::Bool,
                Kind::Bool => {}
                _ => return Err(hetero()),
            }
            values.push(Value::Bool(b));
        } else if item.is_integer() {
            let i = item.decode::<i64>().map_err(|_| {
                format!("unsupported parameter type for ${name}: integer out of range in list")
            })?;
            match kind {
                Kind::Unknown => {
                    kind = Kind::Int;
                    values.push(Value::Int64(i));
                }
                Kind::Int => values.push(Value::Int64(i)),
                Kind::Double => values.push(Value::Double(int_to_exact_f64(name, i)?)),
                _ => return Err(hetero()),
            }
        } else if item.is_float() {
            let f = item.decode::<f64>().map_err(|_| {
                format!("unsupported parameter type for ${name}: invalid float in list")
            })?;
            match kind {
                Kind::Unknown => kind = Kind::Double,
                Kind::Double => {}
                Kind::Int => {
                    // First float after integers: promote what's already
                    // collected. Each element is rewritten at most once over
                    // the whole conversion, so this stays O(n).
                    for v in values.iter_mut() {
                        if let Value::Int64(i) = *v {
                            *v = Value::Double(int_to_exact_f64(name, i)?);
                        }
                    }
                    kind = Kind::Double;
                }
                _ => return Err(hetero()),
            }
            values.push(Value::Double(f));
        } else if item.is_binary() {
            let s = item.decode::<String>().map_err(|_| {
                format!("unsupported parameter type for ${name}: invalid UTF-8 binary in list")
            })?;
            match kind {
                Kind::Unknown => kind = Kind::Str,
                Kind::Str => {}
                _ => return Err(hetero()),
            }
            values.push(Value::String(s));
        } else if item.is_list() {
            // Nested lists are a non-goal (see PRD §3).
            return Err(format!(
                "unsupported parameter type for ${name}: nested list"
            ));
        } else {
            return Err(format!(
                "unsupported parameter type for ${name}: unsupported element type in list"
            ));
        }
    }

    let logical_type = match kind {
        Kind::Int => LogicalType::Int64,
        Kind::Double => LogicalType::Double,
        Kind::Bool => LogicalType::Bool,
        Kind::Str => LogicalType::String,
        // len > 0 and every loop iteration either sets `kind` or returns an
        // error, so this is defensive rather than reachable.
        Kind::Unknown => {
            return Err(format!(
                "unsupported parameter type for ${name}: could not infer list element type"
            ))
        }
    };

    Ok(Value::List(logical_type, values))
}

// Define the NIF module with on_load
rustler::init!(
    "Elixir.LadybugEx.Native",
    [
        open_database,
        in_memory_database,
        new_connection,
        query,
        prepare,
        execute
    ],
    load = on_load
);

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(DatabaseResource, env);
    rustler::resource!(ConnectionResource, env);
    rustler::resource!(PreparedStatementResource, env);
    #[cfg(target_os = "linux")]
    promote_self_to_global_scope();
    true
}

/// Ladybug extensions are dlopen'ed at runtime with undefined engine symbols
/// that the dynamic linker must resolve from already-loaded libraries. The
/// BEAM loads NIF libraries with RTLD_LOCAL, which keeps this library's
/// symbols out of the global lookup scope, so extension loading fails with
/// "undefined symbol" errors. Re-dlopening ourselves with RTLD_NOLOAD |
/// RTLD_GLOBAL promotes the already-loaded library into the global scope
/// without loading a second copy.
#[cfg(target_os = "linux")]
fn promote_self_to_global_scope() {
    use std::os::raw::{c_char, c_int, c_void};

    #[repr(C)]
    struct DlInfo {
        dli_fname: *const c_char,
        dli_fbase: *mut c_void,
        dli_sname: *const c_char,
        dli_saddr: *mut c_void,
    }

    extern "C" {
        fn dladdr(addr: *const c_void, info: *mut DlInfo) -> c_int;
        fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    }

    const RTLD_NOW: c_int = 0x2;
    const RTLD_NOLOAD: c_int = 0x4;
    const RTLD_GLOBAL: c_int = 0x100;

    unsafe {
        let mut info: DlInfo = std::mem::zeroed();
        let probe = promote_self_to_global_scope as *const c_void;
        if dladdr(probe, &mut info) != 0 && !info.dli_fname.is_null() {
            dlopen(info.dli_fname, RTLD_NOW | RTLD_GLOBAL | RTLD_NOLOAD);
        }
    }
}