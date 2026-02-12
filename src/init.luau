--!strict
--!native
--!optimize 2

local Shared = require(script.Shared)
local Compression = Shared.Compression
local pack = table.pack
local Heartbeat = game:GetService("RunService").Heartbeat

local IS_SERVER = Shared.IS_SERVER
local IS_CLIENT = Shared.IS_CLIENT

-- Initialize remotes and wire up event listeners
Shared.Initialize()

-- New API: Network.Server / Network.Client
local Server = require(script.Server)
local Client = require(script.Client)

-- Legacy API
local Network: Network = {} :: Network

-- Expose sub-modules
(Network :: any).Server = Server;
(Network :: any).Client = Client

function Network:SetConnection<T...>(
	ConnectionName: string,
	ConnectionType: RemoteConnection,
	Callback: (player: Player, T...) -> any?,
	Schema: Shared.TypeSchema?,
	RateLimitConfig: RateLimitConfig?
): ()
	Shared.SetConnection(ConnectionName, ConnectionType, Callback, Schema, RateLimitConfig)
end

function Network:SetSignal(SignalName: string): { Wait: () -> any? }
	local signalFired: boolean = false
	local arguments: { any? } = {}

	Shared.SetConnection(`Signal{SignalName}`, "REMOTE_EVENT", function(...: any)
		signalFired = true
		arguments = pack(...)
		Shared.RemoveConnection(`Signal{SignalName}`, "REMOTE_EVENT")
		return
	end)

	return {
		Wait = function()
			repeat
				Heartbeat:Wait()
			until signalFired
			return arguments
		end,
	}
end

function Network:FireSignal(SignalName: string, Player: Player?, ...: any): ()
	if IS_CLIENT then
		Network:FireServerConnection(`Signal{SignalName}`, "REMOTE_EVENT", ...)
	elseif IS_SERVER and Player then
		Network:FireClientConnection(Player, `Signal{SignalName}`, "REMOTE_EVENT", ...)
	end
end

function Network:FireClientConnection(
	plr: Player,
	ConnectionName: string,
	ConnectionType: RemoteConnection,
	...: any
): any?
	if IS_CLIENT then
		return
	end
	if (not plr) or (not plr:IsA("Player")) then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)

	if ConnectionType == "REMOTE_EVENT" and Shared.RE then
		Shared.GetRE():FireClient(plr, connectionIdentifier, Compression.Compress(pack(...)))
	elseif ConnectionType == "UREMOTE_EVENT" and Shared.URE then
		Shared.GetURE():FireClient(plr, connectionIdentifier, Compression.Compress(pack(...)))
	elseif ConnectionType == "REMOTE_FUNCTION" and Shared.RF then
		local packedTable: { any? } = pack(...)
		return Shared.YieldUntilRFResponse(ConnectionName, function()
			return Shared.GetRF():InvokeClient(plr, connectionIdentifier, Compression.Compress(packedTable))
		end)
	end

	return
end

function Network:FireAllClientConnection(ConnectionName: string, ConnectionType: RemoteConnection, ...: any): ()
	if IS_CLIENT or (ConnectionType == "REMOTE_FUNCTION") then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)

	if ConnectionType == "REMOTE_EVENT" then
		Shared.GetRE():FireAllClients(connectionIdentifier, Compression.Compress(pack(...)))
	elseif ConnectionType == "UREMOTE_EVENT" then
		Shared.GetURE():FireAllClients(connectionIdentifier, Compression.Compress(pack(...)))
	end
end

function Network:FireServerConnection(ConnectionName: string, ConnectionType: RemoteConnection, ...: any): any?
	if IS_SERVER then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)

	if ConnectionType == "REMOTE_EVENT" then
		Shared.GetRE():FireServer(connectionIdentifier, Compression.Compress(pack(...)))
	elseif ConnectionType == "UREMOTE_EVENT" then
		Shared.GetURE():FireServer(connectionIdentifier, Compression.Compress(pack(...)))
	elseif ConnectionType == "REMOTE_FUNCTION" then
		local packedTable: { any? } = pack(...)
		return Shared.YieldUntilRFResponse(ConnectionName, function()
			return Shared.GetRF():InvokeServer(connectionIdentifier, Compression.Compress(packedTable))
		end)
	end

	return
end

function Network:FireConnection(ConnectionName: string, ...: any): ()
	Shared.FireBindable(ConnectionName, ...)
end

function Network:GetRemote(
	RemoteType: RemoteConnection
): RemoteEvent? | RemoteFunction? | UnreliableRemoteEvent? | BindableEvent? | nil
	if RemoteType == "REMOTE_EVENT" then
		return Shared.GetRE()
	elseif RemoteType == "UREMOTE_EVENT" then
		return Shared.GetURE()
	elseif RemoteType == "REMOTE_FUNCTION" then
		return Shared.GetRF()
	elseif RemoteType == "BINDABLE_EVENT" then
		return Shared.GetBE()
	end

	Shared.DisplayWarn(`Could not locate the remote, maybe check the requested remote?`)
	return nil
end

function Network:RemoveConnection(ConnectionName: string, ConnectionType: RemoteConnection): Connection | nil
	return Shared.RemoveConnection(ConnectionName, ConnectionType)
end

-- Type Exports
export type TypeSchema = Shared.TypeSchema
export type TypeConstraints = Shared.TypeConstraints
export type SchemaEntry = Shared.SchemaEntry

export type RateLimitConfig = Shared.RateLimitConfig
export type Connection = Shared.Connection
export type RemoteConnection = Shared.RemoteConnection

export type Network = {
	-- New API
	Server: typeof(Server),
	Client: typeof(Client),

	-- Legacy API
	SetConnection: <T...>(
		self: Network,
		ConnectionName: string,
		ConnectionType: RemoteConnection,
		Callback: (player: Player, T...) -> any? | nil,
		Schema: Shared.TypeSchema?,
		RateLimitConfig: RateLimitConfig?
	) -> (),

	RemoveConnection: (self: Network, ConnectionName: string, ConnectionType: RemoteConnection) -> Connection | nil,
	FireConnection: (self: Network, ConnectionName: string, ...any) -> (),

	SetSignal: (self: Network, SignalName: string) -> { Wait: () -> any? },
	FireSignal: (self: Network, SignalName: string, Player: Player?, ...any) -> (),

	FireClientConnection: (
		self: Network,
		plr: Player,
		ConnectionName: string,
		ConnectionType: RemoteConnection,
		...any
	) -> any?,
	FireAllClientConnection: (self: Network, ConnectionName: string, ConnectionType: RemoteConnection, ...any) -> (),

	FireServerConnection: (self: Network, ConnectionName: string, ConnectionType: RemoteConnection, ...any) -> any?,

	GetRemote: (
		self: Network,
		RemoteType: RemoteConnection
	) -> RemoteEvent? | RemoteFunction? | UnreliableRemoteEvent? | BindableEvent? | nil,
}

return Network
