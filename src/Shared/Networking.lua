--!strict
--!optimize 2
local Network = {};

-- Services
local RunService = game:GetService("RunService");

-- Variables
local EventRegistry: { [RemoteEnum]: { [string]: { (any) -> any? } } } = {
	["RE"] = {};
	["RF"] = {};
	["URE"] = {};	
};

-- Enums
type RemoteEnum = string | "RE" | "RF" | "URE";

-- Helper Functions
local function displayPrint(text: string): () print(`[Network/{RunService:IsServer() and `Server` or `Client`}]: {text}`) end;
local function displayWarn(text: string): () warn(`[Network/{RunService:IsServer() and `Server` or `Client`}]: {text}`) end;
local function GetRE(): RemoteEvent
	local r: RemoteEvent = script:FindFirstChild("RE") :: RemoteEvent;
	if (r == nil) then
		if (RunService:IsClient()) then
			r = script:WaitForChild("RE", 15) :: RemoteEvent
		else
			r = Instance.new("RemoteEvent");
			r.Name = "RE";
			r.Parent = script;
		end
	end
	return r;
end
local function GetRF(): RemoteFunction
	local r: RemoteFunction = script:FindFirstChild("RF") :: RemoteFunction;
	if (r == nil) then
		if (RunService:IsClient()) then
			r = script:WaitForChild("RF", 15) :: RemoteFunction
		else
			r = Instance.new("RemoteFunction");
			r.Name = "RF";
			r.Parent = script;
		end
	end
	return r;
end
local function GetURE(): UnreliableRemoteEvent
	local r: UnreliableRemoteEvent = script:FindFirstChild("URE") :: UnreliableRemoteEvent;
	if (r == nil) then
		if (RunService:IsClient()) then
			r = script:WaitForChild("URE", 15) :: UnreliableRemoteEvent
		else
			r = Instance.new("UnreliableRemoteEvent");
			r.Name = "URE";
			r.Parent = script;
		end	
	end
	return r;
end

--[[
	Helper function to be used in both subscribe functions.
	
	Basically, this helps connect a callback to any given connection that is setup with the 'name' paramater under a given Remote Type.
	
	@param name: string | The name of the event you want to subscribe to.
	@param rType: RemoteEnum | The given remote type that you are going to subscribe under.
	@param handler: (player: Player) -> any? | The callback to be called when the given event is called.
]]
local function _subscribeToEvent(name: string, rType: RemoteEnum, handler: (player: Player) -> any?)
	-- Create listener table
	local EventListener = {};

	-- Functions
	function EventListener:Disconnect()
		if not (EventListener[rType][name]) then
			return;
		end

		if (#EventListener[rType][name] > 1) then
			local _pos: number? = table.find(EventListener[rType][name], handler);
			if (_pos) then return table.remove(EventListener[rType][name], _pos) end; -- If it exists, we then remove it from the registry.
		else
			EventRegistry[rType][name] = nil;
		end

		return nil;
	end

	if not (EventRegistry[rType][name]) then
		EventRegistry[rType][name] = {};
	end

	if (#EventRegistry[rType][name] == 1) and (rType == "RF") then
		table.remove(EventRegistry[rType][name], 1);
	end
	table.insert(EventRegistry[rType][name], handler);
end

-- Create subdirectories for client and server.
if (RunService:IsClient()) then
	Network.Client = {};
	local function onEventReached(headerBuf: buffer, ...)
		local _header: { string } = buffer.tostring(headerBuf):split("::");
		local _event: { (any) -> any? } = EventRegistry[_header[2]][_header[1]];
		if not (_event) then 
			return;
		end;

		for i = 1, #_event do
			local _eventConnection: (any) -> any? = _event[i];
			local success: boolean, response: any = pcall(_eventConnection, ...);
			if not (success) then
				displayWarn(`Issue with connection {_header[1]} with response of: {debug.traceback(response, 3)}`);
			end

			if (_header[2] == "RF") then
				return success and response or nil;
			end
		end
	end

	-- Setup listeners.
	local setupSuccess, response = pcall(function()
		GetRE().OnClientEvent:Connect(onEventReached);
		GetURE().OnClientEvent:Connect(onEventReached);
		GetRF().OnClientInvoke = onEventReached;
		
		return `Successful!`
	end)

	if not (setupSuccess) then
		displayWarn(`There was an issue with setting up the listeners. Response: {debug.traceback(response, 3)}`);
	end

	-- Client Network methods.
	--[[
	    Basically subscribe to a certain name under a given remote type; which, is called whenever the server inquires for it.
    	Also provides a :Disconnect() method if you would like to disconnect it later on.
    	
		@param name: string | The name of the event you want to subscribe to.
		@param rType: RemoteEnum | The given remote type that you are going to subscribe under.
		@param handler: (player: Player) -> any? | The callback to be called when the given event is called.
	]]
	function Network.Client:Subscribe(name: string, rType: RemoteEnum, handler: (player: Player) -> any?)
		_subscribeToEvent(name, rType, handler);
	end

	--[[
		Fires the server and inquires the provided name and given remote type you give, as well with any additional parameters.
		
		@param name: string | The name of the event you want to call on the server.
		@param rType: RemoteEnum | The given remote type that you are going to call under.
		@param ... | Any additional paramaters you want to pass when firing to the server.
	]]
	function Network.Client:Fire(name: string, rType: RemoteEnum, ...)
		local _headerBuf: buffer = buffer.fromstring(name .. '::' .. rType);
		if (rType == "RE") then
			GetRE():FireServer(_headerBuf, ...);
		elseif (rType == "URE") then
			GetURE():FireServer(_headerBuf, ...);
		elseif (rType == "RF") then
			return GetRF():InvokeServer(_headerBuf, ...);
		end
		return;
	end

	if (RunService:IsStudio()) and (setupSuccess) then
		displayPrint(`Established a connection to the Server.`);
	end
else
	Network.Server = {};
	local function onEventReached(plr: Player, headerBuf: buffer, ...)
		local _header: { string } = buffer.tostring(headerBuf):split("::");
		local _event: { (any) -> any? } = EventRegistry[_header[2]][_header[1]];
		if not (_event) then 
			return;
		end;

		for i = 1, #_event do
			local _eventConnection: (any) -> any? = _event[i];
			local success: boolean, response: any = pcall(_eventConnection, plr, ...);
			if not (success) then
				displayWarn(`[Server/Network] Issue with connection {_header[1]} with response of: {debug.traceback(response, 3)}`);
			end

			if (_header[2] == "RF") then
				return success and response or nil;
			end
		end
	end

	-- Setup listeners.
	local setupSuccess, response = pcall(function()
		GetRE().OnServerEvent:Connect(onEventReached);
		GetURE().OnServerEvent:Connect(onEventReached);
		GetRF().OnServerInvoke = onEventReached;
		
		return "Successful!";
	end)

	if not (setupSuccess) then
		displayWarn(`There was an issue with setting up the listeners. Response: {debug.traceback(response, 3)}`);
	end

	-- Server Network methods.
	--[[
	    Basically subscribe to a certain name under a given remote type; which, is called whenever the server inquires for it.
    	Also provides a :Disconnect() method if you would like to disconnect it later on.
    	
		@param name: string | The name of the event you want to subscribe to.
		@param rType: RemoteEnum | The given remote type that you are going to subscribe under.
		@param handler: (player: Player) -> any? | The callback to be called when the given event is called.
	]]
	function Network.Server:Subscribe(name: string, rType: RemoteEnum, handler: (player: Player) -> any?)
		_subscribeToEvent(name, rType, handler);
	end

	--[[
		Fires towards the given player and inquires the provided name and given remote type you give, as well with any additional parameters.
		
		@param plr: Player | The player that you are looking to call to.
		@param name: string | The name of the event you want to call on the player.
		@param rType: RemoteEnum | The given remote type that you are going to call under.
		@param ... | Any additional paramaters you want to pass when firing to the player.
	]]
	function Network.Server:Fire(plr: Player, name: string, rType: RemoteEnum, ...)
		local _headerBuf: buffer = buffer.fromstring(name .. '::' .. rType);
		if (rType == "RE") then
			GetRE():FireClient(plr, _headerBuf, ...);
		elseif (rType == "URE") then
			GetURE():FireClient(plr, _headerBuf, ...);
		elseif (rType == "RF") then
			return GetRF():InvokeClient(plr, _headerBuf, ...);
		end
		return;
	end

	--[[
		Fires towards all player(s) and inquires the provided name and given remote type you give, as well with any additional parameters.
		.
		@param name: string | The name of the event you want to call on the player(s).
		@param rType: RemoteEnum | The given remote type that you are going to call under.
		@param ... | Any additional paramaters you want to pass when firing to the player(s).
	]]
	function Network.Server:FireAll(name: string, rType: RemoteEnum, ...)
		local _headerBuf: buffer = buffer.fromstring(name .. '::' .. rType);

		-- We can't fire to all actors through remote functions.
		if (rType == "RF") then 
			return;
		end;

		if (rType == "RE") then
			GetRE():FireAllClients(_headerBuf, ...);
		elseif (rType == "URE") then
			GetURE():FireAllClients(_headerBuf, ...);
		end
	end

	if (RunService:IsStudio()) and (setupSuccess) then
		displayPrint(`Initialized Network on Server.`);
	end
end

return Network;