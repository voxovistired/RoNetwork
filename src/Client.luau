--!strict
--!native
--!optimize 2

local Shared = require(script.Parent.Shared)
local Compression = Shared.Compression
local pack = table.pack
local Heartbeat = game:GetService("RunService").Heartbeat

export type OnOptions = {
	type: Shared.RemoteConnection?,
}

local Client = {}

--[[
	Listen for an incoming connection from the server (or bindable).
	
	-- Simple (defaults to REMOTE_EVENT):
	Network.Client:On("UpdateHUD", function(hudData) ... end)

	-- With options:
	Network.Client:On("GetClientData", callback, { type = "REMOTE_FUNCTION" })
]]
function Client:On(ConnectionName: string, Callback: (...any) -> any?, Options: OnOptions?): ()
	local opts: OnOptions = Options or {}
	local connectionType: Shared.RemoteConnection = opts.type or "REMOTE_EVENT"

	-- Client callbacks don't receive a Player argument, but the internal
	-- system dispatches without one on client side, so this is compatible.
	Shared.SetConnection(ConnectionName, connectionType, Callback :: any, nil, nil)
end

--[[
	Fire a RemoteEvent to the server.
	
	Network.Client:Fire("RequestItem", itemId)
]]
function Client:Fire(ConnectionName: string, ...: any): ()
	if not Shared.IS_CLIENT then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local RE = Shared.GetRE()

	if RE then
		RE:FireServer(connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Fire an UnreliableRemoteEvent to the server.
	
	Network.Client:FireUnreliable("MousePosition", pos)
]]
function Client:FireUnreliable(ConnectionName: string, ...: any): ()
	if not Shared.IS_CLIENT then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local URE = Shared.GetURE()

	if URE then
		URE:FireServer(connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Invoke the server via RemoteFunction and wait for a response.
	
	local inventory = Network.Client:Invoke("GetInventory")
]]
function Client:Invoke(ConnectionName: string, ...: any): any?
	if not Shared.IS_CLIENT then
		return nil
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(ConnectionName)
	local packedTable: { any? } = pack(...)

	return Shared.YieldUntilRFResponse(ConnectionName, function()
		return Shared.GetRF():InvokeServer(connectionIdentifier, Compression.Compress(packedTable))
	end)
end

--[[
	Fire a BindableEvent for client-to-client (same-context) communication.
	
	Network.Client:Dispatch("UIEvent", data)
]]
function Client:Dispatch(ConnectionName: string, ...: any): ()
	Shared.FireBindable(ConnectionName, ...)
end

--[[
	Remove a registered connection.
	
	Network.Client:Off("UpdateHUD")
	Network.Client:Off("GetClientData", "REMOTE_FUNCTION")
]]
function Client:Off(ConnectionName: string, ConnectionType: Shared.RemoteConnection?): Shared.Connection | nil
	return Shared.RemoveConnection(ConnectionName, ConnectionType or "REMOTE_EVENT")
end

--[[
	Set up a one-shot signal that waits for a single fire then auto-removes.
	
	local signal = Network.Client:Signal("ServerReady")
	local args = signal.Wait()
]]
function Client:Signal(SignalName: string): { Wait: () -> any? }
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
	Fire a signal to the server.
	
	Network.Client:FireSignal("PlayerReady", data)
]]
function Client:FireSignal(SignalName: string, ...: any): ()
	if not Shared.IS_CLIENT then
		return
	end

	local connectionIdentifier: number | string = Shared.EncodeConnectionName(`Signal{SignalName}`)
	local RE = Shared.GetRE()

	if RE then
		RE:FireServer(connectionIdentifier, Compression.Compress(pack(...)))
	end
end

--[[
	Get the underlying remote instance.
]]
function Client:GetRemote(RemoteType: Shared.RemoteConnection): any?
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

return Client
