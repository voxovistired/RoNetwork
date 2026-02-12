--!strict
--!native
--!optimize 2

local Shared = {}

-- Services
local RunService = game:GetService("RunService")

-- Libraries
local pack = table.pack

-- Constants
Shared.IS_SERVER = RunService:IsServer()
Shared.IS_CLIENT = RunService:IsClient()
Shared.IS_STUDIO = RunService:IsStudio()

local DISPLAY_NAME: string = script.Parent:GetFullName()

local RF_TIMEOUT: number = 15

-- Classes
local Compression = require(script.Parent.lib.Compression)
local Validation = require(script.Parent.lib.Validation)
local Ratelimit = require(script.Parent.packages.Ratelimit)

-- Registry
local CONNECTION_REGISTRY: { [string]: number } = require(script.Parent.ConnectionRegistry) :: { [string]: number }
local ID_TO_CONNECTION: { [number]: string } = {}
for name: string, id: number in CONNECTION_REGISTRY do
	ID_TO_CONNECTION[id] = name
end

-- Shared state
Shared.Connections = {} :: { [string]: Connection }
Shared.Signals = {} :: { [string]: RBXScriptConnection? }

-- Remotes (populated by init)
Shared.RE = nil :: RemoteEvent?
Shared.RF = nil :: RemoteFunction?
Shared.URE = nil :: UnreliableRemoteEvent?
Shared.BE = nil :: BindableEvent?

-- Re-export for use
Shared.Compression = Compression
Shared.Validation = Validation
Shared.Ratelimit = Ratelimit

function Shared.DisplayWarn(message: string): ()
	assert(type(message) == "string", "bad message")
	if not Shared.IS_STUDIO then
		return
	end
	warn(`[{DISPLAY_NAME}]: {message}`)
end

function Shared.EncodeConnectionName(name: string): number | string
	local ID: number | string = CONNECTION_REGISTRY[name]
	if ID then
		return ID
	end
	return name
end

function Shared.DecodeConnectionName(identifier: number | string): string?
	if typeof(identifier) == "number" then
		local name: string = ID_TO_CONNECTION[identifier]
		if name then
			return name
		end
		Shared.DisplayWarn(`[DecodeConnectionName]: Could not decode connection ID: {identifier}`)
		return nil
	elseif typeof(identifier) == "string" then
		return identifier
	end
	Shared.DisplayWarn(`[DecodeConnectionName]: Invalid identifier type: {typeof(identifier)}`)
	return nil
end

function Shared.YieldUntilRFResponse(connectionName: string, callMethod: () -> any?): nil | any?
	local result: any? = nil
	local done: boolean = false

	task.spawn(function()
		local success: boolean, response: any = pcall(callMethod)
		if not done then
			done = true
			result = if success then response else nil
			if not success then
				Shared.DisplayWarn(`[YieldUntilRFResponse]: Internal Error: {connectionName} :: {response}`)
			end
		end
	end)

	local elapsed: number = 0
	while not done and elapsed < RF_TIMEOUT do
		elapsed += task.wait()
	end

	if not done then
		done = true
		Shared.DisplayWarn(`[YieldUntilRFResponse]: Timed out after {RF_TIMEOUT}s: {connectionName}`)
	end

	return result
end

function Shared.OnConnection(
	player: Player?,
	Type: RemoteConnection,
	connectionIdentifier: number | string,
	compressedArgs: buffer
): any
	local connectionName: string? = Shared.DecodeConnectionName(connectionIdentifier)

	if not connectionName then
		Shared.DisplayWarn(`[onConnection]: Failed to decode connection identifier: {connectionIdentifier}`)
		return
	end

	local connection: Connection? = Shared.Connections[connectionName]
	if connection ~= nil then
		if not (connection.Type == Type) then
			return
		end

		if Shared.IS_SERVER and player and connection.RateLimiter then
			local consume: number = connection.RateLimitConfig and connection.RateLimitConfig.consume or 1
			local result = connection.RateLimiter:Check(player, { consume = consume })

			if result == "BAD" then
				Shared.DisplayWarn(`[{connectionName}]: Rate limit exceeded for {player.Name}`)
				return
			end
		end

		local arguments: any = Compression.Decompress(compressedArgs)
		if connection.Schema and Shared.IS_SERVER and player then
			local isValid: boolean, errorMessage: string? =
				Validation.ValidateArguments(connectionName, player.Name, arguments, connection.Schema)

			if not isValid then
				Shared.DisplayWarn(errorMessage or "Validation failed")
				return
			end
		end

		if player then
			return Shared.Connections[connectionName].Callback(player, unpack(arguments))
		else
			return Shared.Connections[connectionName].Callback(unpack(arguments))
		end
	end

	Shared.DisplayWarn(`[onConnection]: Failed to find a callback method for: {connectionName}`)
	return
end

-- Remote getters
function Shared.GetRE(): RemoteEvent
	local newRE: RemoteEvent?
	if Shared.IS_SERVER then
		newRE = Shared.RE or Instance.new("RemoteEvent")
		newRE.Parent = script
	else
		newRE = Shared.RE or script:WaitForChild("RemoteEvent", 15) :: RemoteEvent?
	end
	return newRE :: RemoteEvent
end

function Shared.GetRF(): RemoteFunction
	local newRF: RemoteFunction?
	if Shared.IS_SERVER then
		newRF = Shared.RF or Instance.new("RemoteFunction")
		newRF.Parent = script
	else
		newRF = Shared.RF or script:WaitForChild("RemoteFunction", 15) :: RemoteFunction?
	end
	return newRF :: RemoteFunction
end

function Shared.GetURE(): UnreliableRemoteEvent
	local newURE: UnreliableRemoteEvent?
	if Shared.IS_SERVER then
		newURE = Shared.URE or Instance.new("UnreliableRemoteEvent")
		newURE.Parent = script
	else
		newURE = Shared.URE or script:WaitForChild("UnreliableRemoteEvent", 15) :: UnreliableRemoteEvent?
	end
	return newURE :: UnreliableRemoteEvent
end

function Shared.GetBE(): BindableEvent
	local newBE: BindableEvent?
	if Shared.IS_SERVER then
		newBE = Shared.BE or Instance.new("BindableEvent")
		newBE.Parent = script
	else
		newBE = Shared.BE or script:WaitForChild("Event", 15) :: BindableEvent?
	end
	return newBE :: BindableEvent
end

-- Shared connection management
function Shared.SetConnection(
	ConnectionName: string,
	ConnectionType: RemoteConnection,
	Callback: (player: Player, ...any) -> any?,
	Schema: TypeSchema?,
	RateLimitConfig: RateLimitConfig?
): ()
	assert(ConnectionName, `need ConnectionName, must be string`)
	assert(ConnectionType, `need ConnectionType, must be RemoteConnection`)
	assert(Callback, `need Callback, must be ( player: Player, ... any ) -> any?`)

	local rateLimiter = nil
	if Shared.IS_SERVER and RateLimitConfig then
		rateLimiter = Shared.Ratelimit.new("TOKEN", {
			maxTokens = RateLimitConfig.maxTokens or 10,
			fillRate = RateLimitConfig.fillRate or 2,
		})
	end

	local NewConnection: Connection = {
		Name = ConnectionName,
		Type = ConnectionType,
		Callback = Callback,
		Schema = Schema,
		RateLimiter = rateLimiter,
		RateLimitConfig = RateLimitConfig,
	}

	Shared.Connections[ConnectionName] = NewConnection
end

function Shared.RemoveConnection(ConnectionName: string, ConnectionType: RemoteConnection): Connection | nil
	local currentConnection: Connection = Shared.Connections[ConnectionName]

	if currentConnection then
		if not (currentConnection.Type == ConnectionType) then
			return nil
		end

		if currentConnection.RateLimiter then
			currentConnection.RateLimiter:Destroy()
		end

		Shared.Connections[ConnectionName] = nil
		return currentConnection
	end

	return nil
end

function Shared.FireBindable(ConnectionName: string, ...: any): ()
	if Shared.BE then
		local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
		Shared.BE:Fire(connectionIdentifier, Compression.Compress(pack(...)))
	end
end

-- Setup remotes and wire connections
function Shared.Initialize(): ()
	Shared.RE = Shared.GetRE()
	Shared.RF = Shared.GetRF()
	Shared.URE = Shared.GetURE()
	Shared.BE = Shared.GetBE()

	local RE: RemoteEvent? = Shared.RE
	local RF: RemoteFunction? = Shared.RF
	local URE: UnreliableRemoteEvent? = Shared.URE
	local BE: BindableEvent? = Shared.BE

	if Shared.IS_SERVER then
		Shared.Signals = {
			RemoteEvent = RE and RE.OnServerEvent:Connect(function(player, ...)
				Shared.OnConnection(player, "REMOTE_EVENT", ...)
			end),
			UnreliableRemoteEvent = URE and URE.OnServerEvent:Connect(function(player, ...)
				Shared.OnConnection(player, "UREMOTE_EVENT", ...)
			end),
			BindableEvent = BE and BE.Event:Connect(function(...)
				Shared.OnConnection(nil, "BINDABLE_EVENT", ...)
			end),
		}
	else
		Shared.Signals = {
			RemoteEvent = RE and RE.OnClientEvent:Connect(function(...)
				Shared.OnConnection(nil, "REMOTE_EVENT", ...)
			end),
			UnreliableRemoteEvent = URE and URE.OnClientEvent:Connect(function(...)
				Shared.OnConnection(nil, "UREMOTE_EVENT", ...)
			end),
			BindableEvent = BE and BE.Event:Connect(function(...)
				Shared.OnConnection(nil, "BINDABLE_EVENT", ...)
			end),
		}
	end

	if RF then
		if Shared.IS_SERVER then
			RF.OnServerInvoke = function(player, ...)
				return Shared.OnConnection(player, "REMOTE_FUNCTION", ...)
			end
		else
			RF.OnClientInvoke = function(...)
				return Shared.OnConnection(nil, "REMOTE_FUNCTION", ...)
			end
		end
	end
end

-- Types
export type TypeSchema = Validation.TypeSchema
export type TypeConstraints = Validation.TypeConstraints
export type SchemaEntry = Validation.SchemaEntry

export type RateLimitConfig = {
	maxTokens: number?,
	fillRate: number?,
	consume: number?,
}

export type Connection = {
	Name: string,
	Type: RemoteConnection,
	Callback: (player: Player, ...any) -> any?,
	Schema: TypeSchema?,
	RateLimiter: any?,
	RateLimitConfig: RateLimitConfig?,
}

export type RemoteConnection = "REMOTE_EVENT" | "REMOTE_FUNCTION" | "UREMOTE_EVENT" | "BINDABLE_EVENT"

return Shared
