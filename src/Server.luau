--!strict
--!native
--!optimize 2

local Shared = require(script.Parent.Shared)
local Compression = Shared.Compression
local pack = table.pack
local Heartbeat = game:GetService("RunService").Heartbeat

export type OnOptions = {
	type: Shared.RemoteConnection?,
	schema: Shared.TypeSchema?,
	rateLimit: Shared.RateLimitConfig?,
}

local Server = {}

--[[
	Listen for an incoming connection from the client (or bindable).
	
	-- Simple (defaults to REMOTE_EVENT):
	Network.Server:On("GetInventory", function(player, itemId) ... end)

	-- With options:
	Network.Server:On("GetInventory", callback, {
		type = "REMOTE_FUNCTION",
		schema = { ... },
		rateLimit = { maxTokens = 10, fillRate = 2 },
	})
]]
function Server:On(ConnectionName: string, Callback: (player: Player, ...any) -> any?, Options: OnOptions?): ()
	local opts: OnOptions = Options or {}
	local connectionType: Shared.RemoteConnection = opts.type or "REMOTE_EVENT"

	Shared.SetConnection(ConnectionName, connectionType, Callback, opts.schema, opts.rateLimit)
end

--[[
	Fire a RemoteEvent to a single player.
	
	Network.Server:Fire(player, "UpdateHUD", hudData)
]]
function Server:Fire(plr: Player, ConnectionName: string, ...: any): ()
	if not Shared.IS_SERVER then
		return
	end
	if (not plr) or (not plr:IsA("Player")) then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local RE = Shared.GetRE()

	if RE then
		RE:FireClient(plr, connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Fire an UnreliableRemoteEvent to a single player.
	
	Network.Server:FireUnreliable(player, "PositionUpdate", pos)
]]
function Server:FireUnreliable(plr: Player, ConnectionName: string, ...: any): ()
	if not Shared.IS_SERVER then
		return
	end
	if (not plr) or (not plr:IsA("Player")) then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local URE = Shared.GetURE()

	if URE then
		URE:FireClient(plr, connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Fire a RemoteEvent to ALL players.
	
	Network.Server:FireAll("GlobalAnnouncement", message)
]]
function Server:FireAll(ConnectionName: string, ...: any): ()
	if not Shared.IS_SERVER then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local RE = Shared.GetRE()

	if RE then
		RE:FireAllClients(connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Fire an UnreliableRemoteEvent to ALL players.
	
	Network.Server:FireAllUnreliable("PositionSync", positions)
]]
function Server:FireAllUnreliable(ConnectionName: string, ...: any): ()
	if not Shared.IS_SERVER then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local URE = Shared.GetURE()

	if URE then
		URE:FireAllClients(connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Invoke a RemoteFunction on a specific client and wait for a response.
	
	local result = Network.Server:Invoke(player, "ClientCalculation", data)
]]
function Server:Invoke(plr: Player, ConnectionName: string, ...: any): any?
	if not Shared.IS_SERVER then
		return nil
	end
	if (not plr) or (not plr:IsA("Player")) then
		return nil
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local packedTable: { any? } = pack(...)

	return Shared.YieldUntilRFResponse(ConnectionName, function()
		return Shared.GetRF():InvokeClient(plr, connectionIdentifier, Compression.Compress(packedTable))
	end)
end

--[[
	Fire a BindableEvent for server-to-server communication.
	
	Network.Server:Dispatch("InternalEvent", data)
]]
function Server:Dispatch(ConnectionName: string, ...: any): ()
	Shared.FireBindable(ConnectionName, ...)
end

--[[
	Remove a registered connection.
	
	Network.Server:Off("GetInventory")
	Network.Server:Off("GetInventory", "REMOTE_FUNCTION")  -- if non-default type
]]
function Server:Off(ConnectionName: string, ConnectionType: Shared.RemoteConnection?): Shared.Connection | nil
	return Shared.RemoveConnection(ConnectionName, ConnectionType or "REMOTE_EVENT")
end

--[[
	Set up a one-shot signal that waits for a single fire then auto-removes.
	
	local signal = Network.Server:Signal("PlayerReady")
	local args = signal.Wait()
]]
function Server:Signal(SignalName: string): { Wait: () -> any? }
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

--[[
	Fire a signal to a specific player (client will pick it up via Network.Client:Signal).
	
	Network.Server:FireSignal("PlayerReady", player, data)
]]
function Server:FireSignal(SignalName: string, Player: Player, ...: any): ()
	if not Shared.IS_SERVER then
		return
	end
	if not Player then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(`Signal{SignalName}`)
	local RE: RemoteEvent = Shared.GetRE()

	if RE then
		RE:FireClient(Player, connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Get the underlying remote instance.
	
	local re = Network.Server:GetRemote("REMOTE_EVENT")
]]
function Server:GetRemote(RemoteType: Shared.RemoteConnection): any?
	if RemoteType == "REMOTE_EVENT" then
		return Shared.GetRE()
	elseif RemoteType == "UREMOTE_EVENT" then
		return Shared.GetURE()
	elseif RemoteType == "REMOTE_FUNCTION" then
		return Shared.GetRF()
	elseif RemoteType == "BINDABLE_EVENT" then
		return Shared.GetBE()
	end

	return nil
end

return Server
