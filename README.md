# Network

Single-remote multiplexed networking for Roblox with built-in compression, schema validation, and token-bucket rate limiting.

## Features

- **Single-remote multiplexing** — all communication routes through one RemoteEvent, RemoteFunction, UnreliableRemoteEvent, and BindableEvent
- **Argument compression** — automatic serialization/deserialization via buffer-based compression
- **Schema validation** — validate incoming arguments on the server with type-checked schemas
- **Rate limiting** — built-in token-bucket rate limiting per connection
- **Connection registry** — frequently used connection names are encoded as numeric IDs to save bandwidth
- **Clean API** — `Network.Server` and `Network.Client` with intuitive methods like `:On`, `:Fire`, `:Invoke`, and `:Dispatch`
- **Backward compatible** — legacy API (`SetConnection`, `FireClientConnection`, etc.) is fully preserved

## Installation

### Wally

Add to your `wally.toml`:

```toml
[dependencies]
network = "voxovistired/network@1.2.0"
```

### Rojo

Clone the repository and sync the `src` directory into your project via your `*.project.json`.

## Usage

### Server

```lua
local Network = require(path.to.Network)

-- Listen for a remote event
Network.Server:On("GetInventory", function(player, itemId)
    return getInventory(player)
end, {
    type = "REMOTE_FUNCTION",
    schema = { { name = "itemId", type = "string" } },
    rateLimit = { maxTokens = 10, fillRate = 2 },
})

-- Fire to a single player
Network.Server:Fire(player, "UpdateHUD", hudData)

-- Fire to all players
Network.Server:FireAll("Announcement", message)

-- Fire unreliable (e.g. position sync)
Network.Server:FireUnreliable(player, "PositionUpdate", pos)

-- Invoke a client and wait for response
local result = Network.Server:Invoke(player, "ClientCalculation", data)

-- Server-to-server communication via BindableEvent
Network.Server:Dispatch("InternalEvent", data)

-- Remove a connection
Network.Server:Off("GetInventory", "REMOTE_FUNCTION")
```

### Client

```lua
local Network = require(path.to.Network)

-- Listen for a remote event from the server
Network.Client:On("UpdateHUD", function(hudData)
    updateUI(hudData)
end)

-- Fire to the server
Network.Client:Fire("RequestItem", itemId)

-- Invoke the server and wait for response
local inventory = Network.Client:Invoke("GetInventory")

-- Client-to-client communication via BindableEvent
Network.Client:Dispatch("UIEvent", data)

-- Remove a connection
Network.Client:Off("UpdateHUD")
```

### Signals

One-shot signals that auto-remove after firing:

```lua
-- Server: wait for a signal
local signal = Network.Server:Signal("PlayerReady")
local args = signal.Wait()

-- Client: fire the signal
Network.Client:FireSignal("PlayerReady", data)
```

## API Reference

### `Network.Server`

| Method | Description |
|---|---|
| `:On(name, callback, options?)` | Register a connection. Options: `{ type?, schema?, rateLimit? }` |
| `:Off(name, type?)` | Remove a connection. Defaults to `REMOTE_EVENT` |
| `:Fire(player, name, ...)` | Fire a RemoteEvent to one player |
| `:FireAll(name, ...)` | Fire a RemoteEvent to all players |
| `:FireUnreliable(player, name, ...)` | Fire an UnreliableRemoteEvent to one player |
| `:FireAllUnreliable(name, ...)` | Fire an UnreliableRemoteEvent to all players |
| `:Invoke(player, name, ...)` | Invoke a RemoteFunction on a client (with timeout) |
| `:Dispatch(name, ...)` | Fire a BindableEvent (server-to-server) |
| `:Signal(name)` | Create a one-shot signal |
| `:FireSignal(name, player, ...)` | Fire a signal to a player |
| `:GetRemote(type)` | Get the underlying remote instance |

### `Network.Client`

| Method | Description |
|---|---|
| `:On(name, callback, options?)` | Register a connection. Options: `{ type? }` |
| `:Off(name, type?)` | Remove a connection. Defaults to `REMOTE_EVENT` |
| `:Fire(name, ...)` | Fire a RemoteEvent to the server |
| `:FireUnreliable(name, ...)` | Fire an UnreliableRemoteEvent to the server |
| `:Invoke(name, ...)` | Invoke a RemoteFunction on the server (with timeout) |
| `:Dispatch(name, ...)` | Fire a BindableEvent (client-to-client) |
| `:Signal(name)` | Create a one-shot signal |
| `:FireSignal(name, ...)` | Fire a signal to the server |
| `:GetRemote(type)` | Get the underlying remote instance |

### Connection Types

| Type | Remote |
|---|---|
| `REMOTE_EVENT` | RemoteEvent |
| `REMOTE_FUNCTION` | RemoteFunction |
| `UREMOTE_EVENT` | UnreliableRemoteEvent |
| `BINDABLE_EVENT` | BindableEvent |

### Rate Limit Config

```lua
{
    maxTokens = 10,  -- max tokens in bucket
    fillRate = 2,    -- tokens added per second
    consume = 1,     -- tokens consumed per request
}
```

### Schema Validation

```lua
{
    { name = "itemId", type = "string", constraints = { maxLength = 50 } },
    { name = "count", type = "number", constraints = { min = 1, max = 100, integer = true } },
}
```

Supported types: `string`, `number`, `boolean`, `Vector3`, `Vector2`, `Vector3int16`, `Vector2int16`, `CFrame`, `Color3`, `UDim2`, `Instance`, `table`.

## Contributing

Contributions are welcome. Please ensure your code passes linting and formatting before submitting a PR:

```bash
selene ./modules
stylua ./modules
```