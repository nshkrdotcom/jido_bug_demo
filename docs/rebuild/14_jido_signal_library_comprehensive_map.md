# Jido Signal Library Comprehensive Map

## Overview

This document provides a complete mapping of the jido_signal library structure, documenting every module, function, type, and their relationships. This serves as the definitive AS-IS reference for the signal system implementation.

## Library Structure

```
jido_signal/lib/
├── jido_signal.ex                  # Core Signal module
├── jido_signal/
│   ├── application.ex              # OTP application
│   ├── bus.ex                      # Central signal bus
│   ├── bus/                        # Bus components (7 files)
│   ├── dispatch.ex                 # Signal dispatching
│   ├── dispatch/                   # Dispatch adapters (9 files)
│   ├── error.ex                    # Error handling
│   ├── id.ex                       # UUID7 ID generation
│   ├── journal.ex                  # Event journaling
│   ├── journal/                    # Journal adapters (3 files)
│   ├── registry.ex                 # Process registry
│   ├── router.ex                   # Signal routing
│   ├── router/                     # Router components (3 files)
│   ├── serialization/              # Serialization (6 files)
│   ├── topology.ex                 # System topology
│   └── util.ex                     # Utilities
```

## Core Modules

### jido_signal.ex
**Purpose**: Core Signal structure implementing CloudEvents v1.0.2 specification with Jido extensions  
**Dependencies**: Jido.Signal.Dispatch, Jido.Signal.ID, TypedStruct

#### Module: Jido.Signal (lines 1-895)
- **Behaviors**: Provides `use Jido.Signal` macro for custom Signal types
- **Attributes**: CloudEvents spec compliance

#### Types (lines 45-85)
- `@type t :: %__MODULE__{}` - Main Signal struct with CloudEvents fields
- `@type signal_type :: String.t()` - Signal type string
- `@type metadata :: map()` - Additional metadata
- `@type data :: map()` - Signal payload

#### CloudEvents Fields (lines 90-120)
- `specversion` - CloudEvents version (default: "1.0.2")
- `id` - Unique identifier (UUID7)
- `type` - Event type (required)
- `source` - Event source (required)
- `subject` - Event subject (optional)
- `time` - Timestamp (default: now)
- `datacontenttype` - Content type (default: "application/json")
- `data` - Event data (default: %{})

#### Jido Extensions (lines 125-135)
- `jido_dispatch` - Dispatch configuration (optional)
- `jido_meta` - Additional Jido metadata (optional)

#### Public Functions
- `new/1` (lines 150-220) - Creates a new Signal with validation
- `new!/1` (lines 225-235) - Creates a Signal, raising on error
- `from_map/1` (lines 240-280) - Creates Signal from map representation
- `serialize/2` (lines 285-320) - Serializes Signal to binary
- `deserialize/2` (lines 325-360) - Deserializes binary to Signal
- `map_to_signal_data/2` (lines 365-400) - Converts structs to Signal format

#### Private Functions
- `validate_signal/1` (lines 450-520) - Validates signal structure
- `normalize_type/1` (lines 525-540) - Normalizes type field
- `extract_fields/2` (lines 545-580) - Field extraction helper

#### Macro Functions (use Jido.Signal)
- Generates custom signal types with predefined fields
- Provides builder functions for type-safe signal creation

---

### jido_signal/application.ex
**Purpose**: OTP Application module managing Signal infrastructure  
**Dependencies**: Supervisor

#### Module: Jido.Signal.Application (lines 1-65)
- **Behaviors**: Application

#### Public Functions
- `start/2` (lines 15-45) - Starts the application supervision tree
- `stop/1` (lines 50-55) - Stops the application

#### Children Started
1. Registry (name: Jido.Signal.Registry, keys: :unique)
2. Task.Supervisor (name: Jido.Signal.TaskSupervisor)

---

### jido_signal/bus.ex
**Purpose**: Central signal bus for routing, filtering, and distributing signals  
**Dependencies**: Bus.State, Bus.Stream, Bus.Subscriber, Bus.Snapshot, Router, Dispatch

#### Module: Jido.Signal.Bus (lines 1-1250)
- **Behaviors**: GenServer

#### Types (lines 35-55)
- `@type server :: GenServer.server()`
- `@type path :: String.t() | [String.t()]`
- `@type subscription_id :: String.t()`
- `@type snapshot_id :: String.t()`
- `@type options :: keyword()`

#### Public Functions
- `start_link/1` (lines 80-95) - Starts a bus process
- `child_spec/1` (lines 100-115) - Returns supervisor child spec
- `subscribe/3` (lines 120-180) - Subscribe to signals matching path patterns
- `unsubscribe/3` (lines 185-210) - Unsubscribe from signals
- `publish/2` (lines 215-250) - Publish signals to subscribers
- `replay/4` (lines 255-310) - Replay historical signals
- `snapshot_create/2` (lines 315-340) - Create signal snapshot
- `snapshot_list/1` (lines 345-360) - List available snapshots
- `snapshot_read/2` (lines 365-385) - Read snapshot content
- `snapshot_delete/2` (lines 390-410) - Delete snapshot
- `ack/3` (lines 415-440) - Acknowledge signal receipt
- `reconnect/3` (lines 445-470) - Reconnect client after disconnect

#### GenServer Callbacks
- `init/1` (lines 500-550) - Initialize bus state
- `handle_call/3` (lines 555-850) - Handle synchronous requests
- `handle_cast/2` (lines 855-950) - Handle asynchronous messages
- `handle_info/2` (lines 955-1050) - Handle system messages
- `terminate/2` (lines 1055-1080) - Cleanup on termination

#### Private Functions
- `do_publish/2` (lines 1100-1180) - Internal publish logic
- `notify_subscribers/2` (lines 1185-1220) - Send to subscribers
- `filter_signals/2` (lines 1225-1245) - Path-based filtering

---

### jido_signal/bus/bus_state.ex
**Purpose**: State management for the signal bus  
**Dependencies**: Router, Signal

#### Module: Jido.Signal.Bus.State (lines 1-420)
- **Behaviors**: Uses TypedStruct

#### Types (lines 25-45)
- `@type t :: %__MODULE__{}` - Bus state struct
- `@type signal_log :: %{String.t() => Signal.t()}`
- `@type subscriptions :: %{String.t() => Subscriber.t()}`

#### Struct Fields
- `log` - Ordered map of signals by ID
- `max_log_size` - Maximum signals to retain
- `subscriptions` - Active subscriptions
- `router` - Signal router instance
- `snapshots` - Saved snapshots
- `config` - Bus configuration

#### Public Functions
- `append_signals/2` (lines 80-120) - Add signals to log
- `log_to_list/1` (lines 125-140) - Convert log to sorted list
- `truncate_log/2` (lines 145-170) - Limit log size
- `clear_log/1` (lines 175-185) - Clear all signals
- `add_route/2` (lines 190-210) - Add routing rule
- `remove_route/2` (lines 215-235) - Remove routing rule
- `has_subscription?/2` (lines 240-250) - Check subscription exists
- `get_subscription/2` (lines 255-265) - Get subscription details
- `add_subscription/3` (lines 270-290) - Add new subscription
- `remove_subscription/3` (lines 295-320) - Remove subscription
- `update_subscription/3` (lines 325-345) - Update subscription

#### Private Functions
- `ensure_log_size/1` (lines 370-400) - Maintain log size limit
- `sort_by_timestamp/1` (lines 405-415) - Sort signals chronologically

---

### jido_signal/bus/bus_subscriber.ex
**Purpose**: Subscription management for signal bus  
**Dependencies**: Bus.State, Bus.PersistentSubscription, Error

#### Module: Jido.Signal.Bus.Subscriber (lines 1-380)
- **Behaviors**: Uses TypedStruct

#### Types (lines 20-35)
- `@type t :: %__MODULE__{}` - Subscriber struct
- `@type dispatch_config :: Dispatch.dispatch_config()`

#### Struct Fields
- `id` - Unique subscription ID
- `path` - Path pattern to match
- `dispatch` - Dispatch configuration
- `client_pid` - Client process PID
- `created_at` - Creation timestamp
- `persistent?` - Persistence flag
- `last_ack` - Last acknowledged signal

#### Public Functions
- `subscribe/4` (lines 60-140) - Create new subscription
- `unsubscribe/3` (lines 145-200) - Remove subscription
- `deliver/3` (lines 205-250) - Deliver signal to subscriber
- `acknowledge/3` (lines 255-280) - Process acknowledgment

#### Private Functions
- `validate_subscription/1` (lines 300-350) - Validate subscription params
- `setup_persistent/2` (lines 355-375) - Setup persistent subscription

---

### jido_signal/dispatch.ex
**Purpose**: Flexible signal dispatching system with multiple adapters  
**Dependencies**: Various dispatch adapters, Error

#### Module: Jido.Signal.Dispatch (lines 1-680)
- **Behaviors**: None (facade pattern)

#### Types (lines 35-55)
- `@type adapter :: atom()` - Adapter module
- `@type adapter_opts :: keyword()` - Adapter-specific options
- `@type dispatch_config :: {adapter, adapter_opts}`
- `@type dispatch_configs :: dispatch_config | [dispatch_config]`
- `@type batch_opts :: keyword()` - Batch processing options

#### Built-in Adapters (lines 60-80)
- `:pid` - Direct process delivery
- `:named` - Named process delivery
- `:pubsub` - Phoenix.PubSub broadcast
- `:logger` - Elixir Logger output
- `:console` - Console output
- `:noop` - No operation
- `:http` - HTTP webhook
- `:webhook` - Alias for HTTP
- `:bus` - Signal bus delivery

#### Public Functions
- `validate_opts/1` (lines 100-150) - Validate dispatch configuration
- `dispatch/2` (lines 155-220) - Synchronous signal dispatch
- `dispatch_async/2` (lines 225-280) - Asynchronous signal dispatch
- `dispatch_batch/3` (lines 285-380) - Batch signal dispatch
- `adapter_for/1` (lines 385-420) - Resolve adapter module

#### Private Functions
- `do_dispatch/3` (lines 450-520) - Internal dispatch logic
- `validate_adapter/2` (lines 525-560) - Validate adapter config
- `handle_dispatch_error/3` (lines 565-600) - Error handling

---

### jido_signal/dispatch/adapter.ex
**Purpose**: Behavior definition for dispatch adapters  
**Dependencies**: None (behavior definition)

#### Module: Jido.Signal.Dispatch.Adapter (lines 1-85)
- **Behaviors**: None (defines behavior)

#### Callbacks (lines 25-45)
- `@callback validate_opts(opts :: keyword()) :: :ok | {:error, term()}`
- `@callback deliver(signal :: Signal.t(), opts :: keyword()) :: :ok | {:error, term()}`

#### Optional Callbacks (lines 50-60)
- `@callback batch_deliver(signals :: [Signal.t()], opts :: keyword()) :: :ok | {:error, term()}`

---

### jido_signal/dispatch/pid.ex
**Purpose**: Direct process delivery adapter  
**Dependencies**: Dispatch.Adapter behavior

#### Module: Jido.Signal.Dispatch.PidAdapter (lines 1-180)
- **Behaviors**: Jido.Signal.Dispatch.Adapter

#### Options Schema (lines 20-35)
- `target` - Target PID (required)
- `delivery_mode` - :sync or :async (default: :async)
- `timeout` - Sync timeout in ms (default: 5000)
- `message_format` - :signal or :wrapped (default: :signal)

#### Public Functions
- `validate_opts/1` (lines 50-85) - Validate PID and delivery options
- `deliver/2` (lines 90-150) - Send signal to process

#### Private Functions
- `send_signal/3` (lines 160-175) - Format and send message

---

### jido_signal/dispatch/named.ex
**Purpose**: Named process delivery adapter  
**Dependencies**: Dispatch.Adapter behavior, Util

#### Module: Jido.Signal.Dispatch.NamedAdapter (lines 1-160)
- **Behaviors**: Jido.Signal.Dispatch.Adapter

#### Options Schema (lines 20-30)
- `name` - Process name (required)
- `registry` - Optional registry module
- Other options passed to PidAdapter

#### Public Functions
- `validate_opts/1` (lines 45-70) - Validate process name
- `deliver/2` (lines 75-130) - Resolve name and deliver

#### Private Functions
- `resolve_name/2` (lines 140-155) - Name to PID resolution

---

### jido_signal/dispatch/pubsub.ex
**Purpose**: Phoenix.PubSub broadcast adapter  
**Dependencies**: Dispatch.Adapter behavior, Phoenix.PubSub

#### Module: Jido.Signal.Dispatch.PubSubAdapter (lines 1-150)
- **Behaviors**: Jido.Signal.Dispatch.Adapter

#### Options Schema (lines 20-30)
- `pubsub` - PubSub module (required)
- `topic` - Topic to broadcast (required)
- `serializer` - Optional serializer

#### Public Functions
- `validate_opts/1` (lines 45-70) - Validate PubSub configuration
- `deliver/2` (lines 75-120) - Broadcast signal

---

### jido_signal/dispatch/logger.ex
**Purpose**: Elixir Logger output adapter  
**Dependencies**: Dispatch.Adapter behavior, Logger

#### Module: Jido.Signal.Dispatch.LoggerAdapter (lines 1-140)
- **Behaviors**: Jido.Signal.Dispatch.Adapter

#### Options Schema (lines 20-30)
- `level` - Log level (default: :info)
- `prefix` - Log prefix (default: "[Signal]")
- `metadata` - Include metadata? (default: true)

#### Public Functions
- `validate_opts/1` (lines 45-60) - Validate log level
- `deliver/2` (lines 65-110) - Log signal

#### Private Functions
- `format_signal/2` (lines 120-135) - Format for logging

---

### jido_signal/dispatch/http.ex
**Purpose**: HTTP webhook delivery adapter  
**Dependencies**: Dispatch.Adapter behavior, HTTPoison/Req

#### Module: Jido.Signal.Dispatch.HttpAdapter (lines 1-280)
- **Behaviors**: Jido.Signal.Dispatch.Adapter

#### Options Schema (lines 25-45)
- `url` - Target URL (required)
- `method` - HTTP method (default: :post)
- `headers` - Additional headers
- `timeout` - Request timeout (default: 30000)
- `serializer` - Signal serializer
- `retry_count` - Max retries (default: 3)
- `retry_delay` - Retry delay ms (default: 1000)

#### Public Functions
- `validate_opts/1` (lines 60-90) - Validate URL and options
- `deliver/2` (lines 95-180) - Send HTTP request
- `batch_deliver/2` (lines 185-230) - Batch HTTP delivery

#### Private Functions
- `do_request/3` (lines 240-275) - Execute HTTP request with retries

---

### jido_signal/router.ex
**Purpose**: Trie-based signal routing with wildcards and priorities  
**Dependencies**: Router.Engine, Router.Validator, Error

#### Module: Jido.Signal.Router (lines 1-850)
- **Behaviors**: Uses TypedStruct for nested structs

#### Types (lines 40-65)
- `@type path :: String.t() | [String.t()]`
- `@type match :: :exact | :prefix | :wildcard | fun()`
- `@type priority :: -100..100`
- `@type target :: any()`
- `@type route_spec :: {path, target} | {path, target, opts}`

#### Structs
- `Route` - Individual route configuration
- `Router` - Router instance with trie
- `TrieNode` - Trie node structure
- `HandlerInfo` - Handler with priority
- `PatternMatch` - Compiled pattern

#### Public Functions
- `new/1` (lines 100-130) - Create router from routes
- `new!/1` (lines 135-145) - Create router, raise on error
- `add/2` (lines 150-190) - Add routes to router
- `remove/2` (lines 195-220) - Remove routes by path
- `merge/2` (lines 225-250) - Merge two routers
- `list/1` (lines 255-270) - List all routes
- `validate/1` (lines 275-290) - Validate route structures
- `route/2` (lines 295-340) - Route signal to handlers
- `matches?/2` (lines 345-380) - Check if type matches pattern
- `filter/2` (lines 385-410) - Filter signals by pattern
- `has_route?/2` (lines 415-430) - Check route exists
- `normalize/1` (lines 435-480) - Normalize route specifications

#### Private Functions
- `insert_route/2` (lines 500-580) - Insert route into trie
- `lookup_handlers/2` (lines 585-650) - Find matching handlers
- `compile_pattern/1` (lines 655-700) - Compile wildcard patterns
- `sort_by_priority/1` (lines 705-720) - Sort handlers by priority

---

### jido_signal/router/engine.ex
**Purpose**: Trie-based routing engine implementation  
**Dependencies**: None

#### Module: Jido.Signal.Router.Engine (lines 1-480)
- **Behaviors**: None (pure functions)

#### Public Functions
- `new/0` (lines 30-35) - Create empty trie
- `insert/4` (lines 40-120) - Insert handler into trie
- `lookup/2` (lines 125-220) - Find handlers for path
- `remove/2` (lines 225-300) - Remove path from trie
- `fold/3` (lines 305-350) - Fold over trie nodes
- `to_list/1` (lines 355-380) - Convert trie to list

#### Private Functions
- `split_path/1` (lines 400-415) - Split path into segments
- `merge_handlers/2` (lines 420-440) - Merge handler lists
- `walk_trie/3` (lines 445-475) - Traverse trie structure

---

### jido_signal/error.ex
**Purpose**: Standardized error handling with structured error types  
**Dependencies**: TypedStruct

#### Module: Jido.Signal.Error (lines 1-380)
- **Behaviors**: Exception protocol

#### Types (lines 20-35)
- `@type error_type :: atom()` - Error classification
- `@type t :: %__MODULE__{}` - Error struct

#### Error Types
- `:validation_error` - Invalid input
- `:execution_error` - Runtime failure
- `:timeout` - Operation timeout
- `:routing_error` - Routing failure
- `:dispatch_error` - Dispatch failure
- `:serialization_error` - Serialization failure
- `:not_found` - Resource not found

#### Public Functions
- `new/4` (lines 60-80) - Create error with all fields
- `validation_error/3` (lines 85-95) - Create validation error
- `execution_error/3` (lines 100-110) - Create execution error
- `timeout/3` (lines 115-125) - Create timeout error
- `routing_error/3` (lines 130-140) - Create routing error
- `dispatch_error/3` (lines 145-155) - Create dispatch error
- `serialization_error/3` (lines 160-170) - Create serialization error
- `not_found/3` (lines 175-185) - Create not found error
- `to_map/1` (lines 190-210) - Convert to plain map
- `capture_stacktrace/0` (lines 215-225) - Get current stacktrace
- `format_nimble_config_error/3` (lines 230-280) - Format config errors
- `format_nimble_validation_error/3` (lines 285-335) - Format validation errors

---

### jido_signal/id.ex
**Purpose**: UUID7-based signal ID generation with monotonic ordering  
**Dependencies**: Uniq.UUID

#### Module: Jido.Signal.ID (lines 1-420)
- **Behaviors**: None

#### Types (lines 20-30)
- `@type uuid7 :: String.t()` - UUID7 string
- `@type timestamp :: non_neg_integer()` - Unix milliseconds
- `@type comparison :: :lt | :eq | :gt`

#### Public Functions
- `generate/0` (lines 45-60) - Generate UUID7 with current timestamp
- `generate!/0` (lines 65-70) - Generate UUID7 only (no metadata)
- `generate_sequential/2` (lines 75-95) - Generate with specific sequence
- `generate_batch/1` (lines 100-130) - Generate multiple ordered UUIDs
- `extract_timestamp/1` (lines 135-165) - Get embedded timestamp
- `compare/2` (lines 170-200) - Chronological comparison
- `valid?/1` (lines 205-220) - Validate UUID7 format
- `sequence_number/1` (lines 225-250) - Extract sequence number
- `format_sortable/1` (lines 255-270) - Format as sortable string

#### Private Functions
- `parse_uuid/1` (lines 300-350) - Parse UUID components
- `extract_time_bits/1` (lines 355-380) - Extract timestamp bits
- `validate_version/1` (lines 385-400) - Validate UUID version

---

### jido_signal/serialization/serializer.ex
**Purpose**: Behavior and facade for serialization strategies  
**Dependencies**: Serialization.Config

#### Module: Jido.Signal.Serialization.Serializer (lines 1-180)
- **Behaviors**: None (defines behavior)

#### Types (lines 20-30)
- `@type serializable :: any()`
- `@type serialized :: binary()`
- `@type opts :: keyword()`

#### Callbacks (lines 35-45)
- `@callback serialize(data :: serializable, opts) :: {:ok, serialized} | {:error, term()}`
- `@callback deserialize(binary :: serialized, opts) :: {:ok, serializable} | {:error, term()}`

#### Public Functions
- `default_serializer/0` (lines 60-70) - Get configured serializer
- `serialize/2` (lines 75-110) - Serialize using configured/specified serializer
- `deserialize/2` (lines 115-150) - Deserialize using configured/specified serializer

---

### jido_signal/serialization/json_serializer.ex
**Purpose**: JSON serialization implementation  
**Dependencies**: Jason, Serializer behavior

#### Module: Jido.Signal.Serialization.JsonSerializer (lines 1-220)
- **Behaviors**: Jido.Signal.Serialization.Serializer

#### Options (lines 20-30)
- `pretty` - Pretty print JSON (default: false)
- `escape` - HTML escape (default: true)
- `maps` - Decode as maps (default: true)

#### Public Functions
- `serialize/2` (lines 45-100) - Convert to JSON binary
- `deserialize/2` (lines 105-160) - Parse JSON binary

#### Private Functions
- `prepare_for_json/1` (lines 180-215) - Convert structs to maps

---

### Additional Serialization Modules

#### jido_signal/serialization/erlang_term_serializer.ex
- Erlang term format serialization using `:erlang.term_to_binary/2`

#### jido_signal/serialization/msgpack_serializer.ex
- MessagePack format serialization

#### jido_signal/serialization/config.ex
- Serialization configuration management

#### jido_signal/serialization/type_provider.ex
- Type information for deserialization

#### jido_signal/serialization/module_name_type_provider.ex
- Module name-based type detection

---

## Bus Components

### jido_signal/bus/bus_snapshot.ex
**Purpose**: Snapshot creation and management for signal history  
**Dependencies**: Bus.State, Signal

#### Module: Jido.Signal.Bus.Snapshot (lines 1-280)
- **Behaviors**: Uses TypedStruct

#### Public Functions
- `create/2` (lines 50-100) - Create new snapshot
- `list/1` (lines 105-120) - List all snapshots
- `read/2` (lines 125-150) - Read snapshot content
- `delete/2` (lines 155-180) - Delete snapshot
- `apply/2` (lines 185-220) - Apply snapshot to bus

---

### jido_signal/bus/bus_stream.ex
**Purpose**: Signal stream filtering and replay functionality  
**Dependencies**: Signal, Router

#### Module: Jido.Signal.Bus.Stream (lines 1-320)
- **Behaviors**: None

#### Public Functions
- `filter/3` (lines 40-80) - Filter signals by criteria
- `replay/4` (lines 85-150) - Replay signals in time range
- `paginate/3` (lines 155-200) - Paginate signal results
- `transform/2` (lines 205-240) - Transform signal stream

---

### jido_signal/bus/middleware.ex
**Purpose**: Middleware behavior for signal processing  
**Dependencies**: None (behavior definition)

#### Module: Jido.Signal.Bus.Middleware (lines 1-120)
- **Behaviors**: None (defines behavior)

#### Callbacks
- `@callback call(signal :: Signal.t(), next :: fun()) :: {:ok, Signal.t()} | {:error, term()}`

---

### jido_signal/bus/middleware_pipeline.ex
**Purpose**: Middleware execution orchestration  
**Dependencies**: Middleware behavior

#### Module: Jido.Signal.Bus.MiddlewarePipeline (lines 1-180)
- **Behaviors**: None

#### Public Functions
- `new/1` (lines 30-45) - Create pipeline from middleware list
- `call/2` (lines 50-90) - Execute pipeline on signal
- `add/2` (lines 95-110) - Add middleware to pipeline
- `remove/2` (lines 115-130) - Remove middleware

---

### jido_signal/bus/persistent_subscription.ex
**Purpose**: Durable subscription handling with acknowledgments  
**Dependencies**: Journal, Subscriber

#### Module: Jido.Signal.Bus.PersistentSubscription (lines 1-420)
- **Behaviors**: GenServer

#### Public Functions
- `start_link/1` (lines 50-70) - Start persistent subscription
- `deliver/2` (lines 75-100) - Deliver signal
- `acknowledge/2` (lines 105-130) - Acknowledge receipt
- `get_checkpoint/1` (lines 135-150) - Get last checkpoint
- `replay_from_checkpoint/1` (lines 155-200) - Replay from checkpoint

---

### jido_signal/bus/recorded_signal.ex
**Purpose**: Signal recording with metadata for journaling  
**Dependencies**: Signal

#### Module: Jido.Signal.Bus.RecordedSignal (lines 1-120)
- **Behaviors**: Uses TypedStruct

#### Struct Fields
- `signal` - Original signal
- `recorded_at` - Recording timestamp
- `sequence` - Sequence number
- `metadata` - Recording metadata

---

## Additional Components

### jido_signal/journal.ex
**Purpose**: Event journal management for signal persistence  
**Dependencies**: Journal.Persistence

#### Module: Jido.Signal.Journal (lines 1-380)
- **Behaviors**: GenServer

#### Public Functions
- `start_link/1` (lines 50-70) - Start journal
- `append/2` (lines 75-100) - Append to journal
- `read/3` (lines 105-150) - Read range
- `stream/2` (lines 155-190) - Stream entries
- `checkpoint/2` (lines 195-220) - Create checkpoint
- `compact/1` (lines 225-250) - Compact journal

---

### jido_signal/journal/persistence.ex
**Purpose**: Behavior for journal storage adapters  
**Dependencies**: None (behavior definition)

#### Module: Jido.Signal.Journal.Persistence (lines 1-120)
- **Behaviors**: None (defines behavior)

#### Callbacks
- `@callback init(opts) :: {:ok, state} | {:error, term()}`
- `@callback append(entries, state) :: {:ok, state} | {:error, term()}`
- `@callback read(range, state) :: {:ok, entries} | {:error, term()}`
- `@callback checkpoint(id, state) :: :ok | {:error, term()}`

---

### jido_signal/registry.ex
**Purpose**: Process registry utilities  
**Dependencies**: Registry

#### Module: Jido.Signal.Registry (lines 1-180)
- **Behaviors**: None

#### Public Functions
- `register/3` (lines 30-50) - Register process
- `unregister/2` (lines 55-70) - Unregister process
- `lookup/2` (lines 75-90) - Lookup process
- `list/1` (lines 95-110) - List registrations
- `via_tuple/2` (lines 115-130) - Create via tuple

---

### jido_signal/topology.ex
**Purpose**: System topology management for distributed signals  
**Dependencies**: None

#### Module: Jido.Signal.Topology (lines 1-280)
- **Behaviors**: None

#### Public Functions
- `nodes/0` (lines 30-40) - List topology nodes
- `add_node/2` (lines 45-70) - Add node to topology
- `remove_node/1` (lines 75-90) - Remove node
- `sync/0` (lines 95-120) - Sync topology
- `broadcast/2` (lines 125-160) - Topology-aware broadcast

---

### jido_signal/util.ex
**Purpose**: Common utility functions  
**Dependencies**: Registry

#### Module: Jido.Signal.Util (lines 1-120)
- **Behaviors**: None

#### Types (lines 15-20)
- `@type server :: GenServer.server()`

#### Public Functions
- `via_tuple/2` (lines 30-50) - Create registry via tuple
- `whereis/2` (lines 55-80) - Find process by name/pid

---

## Architectural Patterns

1. **CloudEvents Compliance**: Full CloudEvents v1.0.2 specification implementation
2. **Behavior-Based Architecture**: Extensive use of behaviors for extensibility
3. **Trie-Based Routing**: Efficient path-based routing with wildcard support
4. **Pluggable Adapters**: Multiple dispatch mechanisms with common interface
5. **Middleware Pipeline**: Extensible signal processing pipeline
6. **UUID7 IDs**: Monotonic, timestamp-based identifiers for ordering
7. **Persistent Subscriptions**: Durable subscriptions with acknowledgment
8. **Snapshot Support**: Point-in-time signal snapshots
9. **Multiple Serialization Formats**: JSON, Erlang terms, MessagePack
10. **Journal Persistence**: Event sourcing with pluggable storage
11. **Registry Integration**: Process discovery and management
12. **Batch Operations**: Efficient batch dispatch and processing
13. **Stream Processing**: Signal filtering and transformation
14. **Distributed Topology**: Multi-node signal distribution
15. **Comprehensive Error Handling**: Structured errors with context

## Module Dependency Graph

```
Jido.Signal (Core)
├── Bus (Central Hub)
│   ├── State (State Management)
│   ├── Subscriber (Subscription Logic)
│   ├── Stream (Signal Filtering)
│   ├── Snapshot (Persistence)
│   ├── Middleware (Processing Pipeline)
│   ├── PersistentSubscription (Durable Subscriptions)
│   └── RecordedSignal (Signal Metadata)
├── Router (Path-Based Routing)
│   ├── Engine (Trie Implementation)
│   ├── Validator (Route Validation)
│   └── Inspect (Debug Utilities)
├── Dispatch (Signal Delivery)
│   ├── Adapter (Behavior Definition)
│   ├── PidAdapter (Process Delivery)
│   ├── NamedAdapter (Named Process)
│   ├── PubSubAdapter (Phoenix.PubSub)
│   ├── LoggerAdapter (Logger Output)
│   ├── ConsoleAdapter (Console Output)
│   ├── HttpAdapter (HTTP Delivery)
│   ├── BusAdapter (Bus Delivery)
│   └── NoopAdapter (No Operation)
├── ID (UUID7 Generation)
├── Error (Structured Errors)
├── Serialization (Format Conversion)
│   ├── Serializer (Behavior/Facade)
│   ├── JsonSerializer (JSON Format)
│   ├── ErlangTermSerializer (Erlang Terms)
│   ├── MsgpackSerializer (MessagePack)
│   ├── Config (Configuration)
│   └── TypeProvider (Type Management)
├── Journal (Event Persistence)
│   ├── Persistence (Behavior)
│   ├── EtsAdapter (ETS Storage)
│   └── InMemoryAdapter (Memory Storage)
├── Registry (Process Registry)
├── Topology (Distributed Nodes)
└── Util (Common Utilities)
```

## Key Design Decisions

1. **CloudEvents as Foundation**: Using industry standard for event structure
2. **Jido Extensions**: Adding framework-specific fields (jido_dispatch, jido_meta)
3. **Trie Routing**: Chosen for efficient wildcard pattern matching
4. **Multiple Dispatch Adapters**: Flexibility in signal delivery mechanisms
5. **UUID7 for IDs**: Provides chronological ordering and uniqueness
6. **Persistent Subscriptions**: Supporting reliable event delivery
7. **Pluggable Serialization**: Support for multiple formats
8. **Journal Abstraction**: Pluggable event storage
9. **Middleware Pipeline**: Extensible signal processing
10. **Batch Operations**: Performance optimization for bulk operations

## Notable Observations

1. **Comprehensive Feature Set**: Full-featured event processing system
2. **Well-Structured Modules**: Clear separation of concerns
3. **Extensibility Points**: Multiple behavior definitions for customization
4. **Performance Considerations**: Batch operations, caching, efficient routing
5. **Production Ready**: Error handling, persistence, monitoring
6. **Documentation**: Most modules have good documentation
7. **Testing Hooks**: Many functions designed for testability
8. **Distributed Support**: Topology management for multi-node setups

## Integration Points with Jido

1. **Agent Communication**: Agents use signals for all communication
2. **Bus Sensor**: Jido has commented-out bus sensor due to circular dependency
3. **Signal Types**: Agent-specific signal types (jido.agent.*)
4. **Dispatch Configuration**: Jido_dispatch field for agent routing
5. **Error Types**: Shared error structure patterns
6. **ID Generation**: Both libraries use same ID generation approach

This comprehensive map provides a complete view of the jido_signal library structure, showing how it implements a sophisticated event-driven messaging system that serves as the communication backbone for the Jido agent framework.