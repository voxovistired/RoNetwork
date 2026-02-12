--!strict
--!native
--!optimize 2
--[[
	Ratelimiting:
		A ratelimiting module programmed strictly typechecked, and with unit tests. Made with the intention to help assist with networking.
		
		Originated from Madwork's Ratelimiter,
		Enhanced by @aaronrtwo (The Forsaken Team).
]]

-- Types
export type RateLimiterResult = "OK" | "BAD"
export type RateLimiterAlgorithm = "DEFAULT" | "TOKEN" | "LEAKY" | "SLIDING_WINDOW"
export type RateLimiterAlgorithmSettings =
	{ [string]: any }
	| {
		-- Default Algorithm Settings
		rate: number?,

		-- Token Algorithm Settings
		maxTokens: number?,
		fillRate: number?,

		-- Leaky Algorithm Settings
		capacity: number?,
		leakRate: number?,

		-- Sliding Window Algorithm Settings
		windowSize: number?, -- IN SECONDS
		maxEvents: number?,
	}
export type RateLimiterParameters = {
	-- Token Parameters
	consume: number?,
}
export type RateLimiterVariables = {
	__playerSources: { [Player]: number },
	__algorithm: RateLimiterAlgorithm,
	__algorithmSettings: RateLimiterAlgorithmSettings,
	__internalState: { [any]: any },
}

-- Services
local Players = game:GetService("Players") :: Players
local HttpService = game:GetService("HttpService") :: HttpService

-- Variables
local ExistingLimiters: { [RateLimiter]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local ExistingPlayers: { [Player]: boolean } = setmetatable({}, {
	__len = function(t: { any })
		local n: number = 0
		for _ in t do
			n += 1
		end
		return n
	end,
}) :: any

-- Constants
local min, max = math.min, math.max
local insert, remove = table.insert, table.remove
local getTime = os.clock
local IS_DEBUG: boolean = false
local RATELIMITER_DEFAULTS: { [string]: any } = {
	-- Default Settings
	RATE = (1 / 35),

	-- Token Settings
	FILL_RATE = 2,
	CONSUME = 1,
	MAX_TOKENS = 10,

	-- Leaky Settings
	LEAK_RATE = 1,
	CAPACITY = 10,

	-- Sliding Window Settings
	WINDOW_SIZE = 5, -- seconds
	MAX_EVENTS = 10, -- allowed events in the window
}

local function debugWarn(display: string): ()
	if IS_DEBUG then
		warn(display)
	end
end

-- Static Methods for Checking.
local AlgorithmCheck = {}

-- Ratelimiter Object
local Ratelimiter = {}
Ratelimiter.__index = Ratelimiter

export type RateLimiter = typeof(setmetatable(
	{} :: RateLimiterVariables & {
		-- Methods
		Check: (self: RateLimiter, player: Player, parameters: RateLimiterParameters?) -> RateLimiterResult,
		GetState: (self: RateLimiter, player: Player) -> (),
		Remove: (self: RateLimiter, player: Player) -> number?,
		Cleanup: (self: RateLimiter) -> (),
		Destroy: (self: RateLimiter) -> (),
	},
	Ratelimiter
))

--[[
	Checks if the given player is within the specifc rate limit.
	@param player The player to check the rate limit of.
	@param parameters The parameters to check the rate limit with.
]]
function Ratelimiter:Check(player: Player?, parameters: RateLimiterParameters?): RateLimiterResult
	-- This must be checked just to ensure that we have an actual player being passed through.
	if (not player or not player:IsA("Player")) or not ExistingPlayers[player] then
		return "BAD"
	end

	local algorithm: RateLimiterAlgorithm = self.__algorithm
	return AlgorithmCheck[algorithm](self, player, parameters)
end

--[[
	Displays the current state with a given player, that includes the internal state. (SHOULD ONLY BE USED FOR DEBUGGING)
	@param player The player to display the state of.
]]
function Ratelimiter:GetState(): ()
	warn(
		("\n[%s] State:\nAlgorithm: %s\nSettings: %s\nSources: %s\nInternal: %s"):format(
			script.Name,
			self.__algorithm,
			HttpService:JSONEncode(self.__algorithmSettings),
			HttpService:JSONEncode(self.__playerSources),
			HttpService:JSONEncode(self.__internalState)
		)
	)
end

--[[
	Removes the player reference from the Ratelimiter object.
	@param player The player to remove.
]]
function Ratelimiter:Remove(player: Player): number?
	local currentRate: number = self.__playerSources[player]
	self.__playerSources[player] = nil

	-- Remove the player reference from any internal trackers.
	local algorithm: RateLimiterAlgorithm = self.__algorithm
	if algorithm == "TOKEN" then
		self.__internalState.tokens[player] = nil
	elseif algorithm == "SLIDING_WINDOW" then
		self.__internalState.events[player] = nil
	elseif algorithm == "LEAKY" then
		self.__internalState.queue[player] = nil
	end

	return currentRate
end

--[[
	Removes any references that are within the Ratelimiter object that aren't necessary.
]]
function Ratelimiter:Cleanup(): ()
	self.__playerSources = {}

	local algorithm: RateLimiterAlgorithm = self.__algorithm
	if algorithm == "TOKEN" then
		self.__internalState.tokens = {}
	elseif algorithm == "SLIDING_WINDOW" then
		self.__internalState.events = {}
	elseif algorithm == "LEAKY" then
		self.__internalState.queue = {}
	end
end

--[[
	Destroy the Ratelimiter object.
]]
function Ratelimiter:Destroy(): ()
	self:Cleanup()
	ExistingLimiters[self] = nil
	setmetatable(self, nil)
end

local Ratelimit = {}

--[[
	Creates a new ratelimiter object.
	@param algorithm The algorithm for the limiter to use.
	@param algorithmSettings The settings for the ratelimit algorithm.
]]
function Ratelimit.new(algorithm: RateLimiterAlgorithm?, algorithmSettings: RateLimiterAlgorithmSettings?): RateLimiter
	local newRatelimiter = {
		__playerSources = {},
		__algorithm = algorithm or "DEFAULT" :: RateLimiterAlgorithm,
		__algorithmSettings = algorithmSettings or {} :: RateLimiterAlgorithmSettings,
		__internalState = {},
	} :: RateLimiterVariables

	setmetatable(newRatelimiter, Ratelimiter)

	-- Helper method to help setup the internal state.
	local function __set(key: string, default: any)
		newRatelimiter.__internalState[key] = (algorithmSettings and algorithmSettings[key]) or default
	end

	-- Algorithms require some internal state immediately.
	if algorithm == nil or algorithm == "DEFAULT" then
		__set("rate", RATELIMITER_DEFAULTS.RATE)
	elseif algorithm == "TOKEN" then
		__set("maxTokens", RATELIMITER_DEFAULTS.MAX_TOKENS)
		__set("fillRate", RATELIMITER_DEFAULTS.FILL_RATE)
		newRatelimiter.__internalState.tokens = {}
	elseif algorithm == "LEAKY" then
		__set("capacity", RATELIMITER_DEFAULTS.CAPACITY)
		__set("leakRate", RATELIMITER_DEFAULTS.LEAK_RATE)
		newRatelimiter.__internalState.queue = {}
	elseif algorithm == "SLIDING_WINDOW" then
		__set("windowSize", RATELIMITER_DEFAULTS.WINDOW_SIZE)
		__set("maxEvents", RATELIMITER_DEFAULTS.MAX_EVENTS)
		newRatelimiter.__internalState.events = {}
	end

	ExistingLimiters[newRatelimiter] = true
	return newRatelimiter :: any
end

function AlgorithmCheck.DEFAULT(self: RateLimiter, player: Player): RateLimiterResult
	local playerSources: { [Player]: number } = self.__playerSources
	local algorithmSettings: RateLimiterAlgorithmSettings = self.__algorithmSettings
	local currentTime: number = getTime()
	local currentRateTime: number = playerSources[player]

	local rate: number = algorithmSettings.rate :: number

	-- If the current rate time for the player exists, we check to see if it can go through with anything.
	if currentRateTime then
		currentRateTime = max(currentTime, currentRateTime + rate)
		local isOk: boolean = (currentRateTime - currentTime < 1)
		if isOk then
			playerSources[player] = currentRateTime
			return "OK"
		end

		debugWarn(`[{script}]: Ratelimiting user: {player}!`)
		return "BAD"
	end

	playerSources[player] = currentTime + rate
	return "OK"
end

function AlgorithmCheck.TOKEN(self: RateLimiter, player: Player, parameters: RateLimiterParameters): RateLimiterResult
	local playerSources: { [Player]: number } = self.__playerSources
	local internalState: { [any]: any } = self.__internalState
	local algorithmSettings: RateLimiterAlgorithmSettings = self.__algorithmSettings
	local currentTime: number = getTime()
	local currentRateTime: number = playerSources[player]

	-- If the player has just been created in here, make sure they have the max amount of tokens.
	if not internalState.tokens[player] then
		internalState.tokens[player] = algorithmSettings.maxTokens
	end

	local elapsed: number = currentRateTime and (currentTime - currentRateTime) or 0
	local amount: number = parameters and parameters.consume or RATELIMITER_DEFAULTS.CONSUME
	internalState.tokens[player] = min(
		(internalState.tokens[player] or 0) + (elapsed * (algorithmSettings.fillRate) :: number),
		(algorithmSettings.maxTokens) :: number
	)
	playerSources[player] = currentTime

	-- Check to see if we have enough tokens to process this.
	if internalState.tokens[player] >= amount then
		internalState.tokens[player] -= amount
		return "OK"
	end

	debugWarn(`[{script}]: Ratelimiting user: {player}!`)
	return "BAD"
end

function AlgorithmCheck.LEAKY(self: RateLimiter, player: Player): RateLimiterResult
	local playerSources: { [Player]: number } = self.__playerSources
	local internalState: { [any]: any } = self.__internalState
	local algorithmSettings: RateLimiterAlgorithmSettings = self.__algorithmSettings
	local currentTime: number = getTime()
	local currentRateTime: number = playerSources[player]

	local elapsed: number = currentRateTime and (currentTime - currentRateTime) or 0
	local leaked: number = elapsed * (algorithmSettings.leakRate) :: number
	local capacity: number = algorithmSettings.capacity :: number
	internalState.queue[player] = max(0, (internalState.queue[player] or 0) :: number - leaked)
	playerSources[player] = currentTime

	if internalState.queue[player] < capacity then
		internalState.queue[player] += 1
		return "OK"
	end

	debugWarn(`[{script}]: Ratelimiting user: {player}!`)
	return "BAD"
end

function AlgorithmCheck.SLIDING_WINDOW(self: RateLimiter, player: Player): RateLimiterResult
	local playerSources: { [Player]: number } = self.__playerSources
	local internalState: { [any]: any } = self.__internalState
	local algorithmSettings: RateLimiterAlgorithmSettings = self.__algorithmSettings
	local currentTime: number = getTime()

	if not internalState.events[player] then
		internalState.events[player] = {}
	end

	local events: { [number]: number } = internalState.events[player]
	local windowSize: number = algorithmSettings.windowSize :: number
	local maxEvents: number = algorithmSettings.maxEvents :: number

	-- Remove events outside the window
	while (#events > 0) and ((currentTime - events[1]) > windowSize) do
		remove(events, 1)
	end

	if #events < maxEvents then
		insert(events, currentTime)
		playerSources[player] = currentTime
		return "OK"
	end

	debugWarn(`[{script}]: Ratelimiting user: {player}!`)
	return "BAD"
end

-- Initialize any player references.
for _, player: Player in (Players:GetPlayers()) do
	ExistingPlayers[player] = true
end

-- Establish connections.
Players.PlayerAdded:Connect(function(player: Player)
	ExistingPlayers[player] = true
end)

Players.PlayerRemoving:Connect(function(player: Player)
	ExistingPlayers[player] = nil
	for limiter: RateLimiter in ExistingLimiters do
		limiter:Remove(player)
	end
end)

return Ratelimit
