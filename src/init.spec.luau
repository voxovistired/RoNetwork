return function()
	local Network = require(script.Parent)
	local Shared = require(script.Parent.Shared)
	local Server = require(script.Parent.Server)
	local Client = require(script.Parent.Client)

	local RunService = game:GetService("RunService")
	local IS_SERVER: boolean = RunService:IsServer()
	local IS_CLIENT: boolean = RunService:IsClient()

	-- Core Internals
	describe("Core Internals", function()
		describe("EncodeConnectionName", function()
			it("should return a numeric ID for registered connections", function()
				-- Insert a test entry into the registry if one exists
				local firstName: string? = nil
				local firstId: number? = nil
				for name, id in require(script.Parent.ConnectionRegistry) :: { [string]: number } do
					firstName = name
					firstId = id
					break
				end

				if firstName and firstId then
					local encoded = Shared.EncodeConnectionName(firstName)
					expect(encoded).to.equal(firstId)
				end
			end)

			it("should return the string name for unregistered connections", function()
				local encoded = Shared.EncodeConnectionName("__UNREGISTERED_TEST_CONNECTION__")
				expect(encoded).to.equal("__UNREGISTERED_TEST_CONNECTION__")
			end)
		end)

		describe("DecodeConnectionName", function()
			it("should decode a numeric ID back to a string name", function()
				local firstName: string? = nil
				local firstId: number? = nil
				for name, id in require(script.Parent.ConnectionRegistry) :: { [string]: number } do
					firstName = name
					firstId = id
					break
				end

				if firstName and firstId then
					local decoded = Shared.DecodeConnectionName(firstId)
					expect(decoded).to.equal(firstName)
				end
			end)

			it("should return the string as-is when given a string", function()
				local decoded = Shared.DecodeConnectionName("TestConnection")
				expect(decoded).to.equal("TestConnection")
			end)

			it("should return nil for an unknown numeric ID", function()
				local decoded = Shared.DecodeConnectionName(999999)
				expect(decoded).to.equal(nil)
			end)
		end)

		describe("SetConnection", function()
			it("should register a connection", function()
				Shared.SetConnection("__TEST_SET__", "REMOTE_EVENT", function() end, nil, nil)
				expect(Shared.Connections["__TEST_SET__"]).to.be.ok()
				Shared.RemoveConnection("__TEST_SET__", "REMOTE_EVENT")
			end)

			it("should store the correct type", function()
				Shared.SetConnection("__TEST_TYPE__", "REMOTE_FUNCTION", function() end, nil, nil)
				expect(Shared.Connections["__TEST_TYPE__"].Type).to.equal("REMOTE_FUNCTION")
				Shared.RemoveConnection("__TEST_TYPE__", "REMOTE_FUNCTION")
			end)

			it("should store the callback", function()
				local function testCallback()
					return "test"
				end
				Shared.SetConnection("__TEST_CB__", "REMOTE_EVENT", testCallback, nil, nil)
				expect(Shared.Connections["__TEST_CB__"].Callback).to.equal(testCallback)
				Shared.RemoveConnection("__TEST_CB__", "REMOTE_EVENT")
			end)

			it("should overwrite an existing connection with the same name", function()
				local function first()
					return 1
				end
				local function second()
					return 2
				end
				Shared.SetConnection("__TEST_OVERWRITE__", "REMOTE_EVENT", first, nil, nil)
				Shared.SetConnection("__TEST_OVERWRITE__", "REMOTE_EVENT", second, nil, nil)
				expect(Shared.Connections["__TEST_OVERWRITE__"].Callback).to.equal(second)
				Shared.RemoveConnection("__TEST_OVERWRITE__", "REMOTE_EVENT")
			end)
		end)

		describe("RemoveConnection", function()
			it("should remove a registered connection and return it", function()
				Shared.SetConnection("__TEST_REMOVE__", "REMOTE_EVENT", function() end, nil, nil)
				local removed = Shared.RemoveConnection("__TEST_REMOVE__", "REMOTE_EVENT")
				expect(removed).to.be.ok()
				expect(removed.Name).to.equal("__TEST_REMOVE__")
				expect(Shared.Connections["__TEST_REMOVE__"]).to.equal(nil)
			end)

			it("should return nil if the connection does not exist", function()
				local removed = Shared.RemoveConnection("__NONEXISTENT__", "REMOTE_EVENT")
				expect(removed).to.equal(nil)
			end)

			it("should return nil if the connection type does not match", function()
				Shared.SetConnection("__TEST_MISMATCH__", "REMOTE_EVENT", function() end, nil, nil)
				local removed = Shared.RemoveConnection("__TEST_MISMATCH__", "REMOTE_FUNCTION")
				expect(removed).to.equal(nil)
				-- cleanup
				Shared.RemoveConnection("__TEST_MISMATCH__", "REMOTE_EVENT")
			end)
		end)

		describe("OnConnection dispatch", function()
			it("should not fire callback if connection type does not match", function()
				local fired: boolean = false
				Shared.SetConnection("__TEST_DISPATCH_TYPE__", "REMOTE_EVENT", function()
					fired = true
				end, nil, nil)

				local compressed = Shared.Compression.Compress({})
				Shared.OnConnection(nil, "REMOTE_FUNCTION", "__TEST_DISPATCH_TYPE__", compressed)
				expect(fired).to.equal(false)
				Shared.RemoveConnection("__TEST_DISPATCH_TYPE__", "REMOTE_EVENT")
			end)

			it("should fire callback when type matches", function()
				local fired: boolean = false
				Shared.SetConnection("__TEST_DISPATCH_FIRE__", "BINDABLE_EVENT", function()
					fired = true
				end, nil, nil)

				local compressed = Shared.Compression.Compress({})
				Shared.OnConnection(nil, "BINDABLE_EVENT", "__TEST_DISPATCH_FIRE__", compressed)
				expect(fired).to.equal(true)
				Shared.RemoveConnection("__TEST_DISPATCH_FIRE__", "BINDABLE_EVENT")
			end)

			it("should pass arguments to the callback", function()
				local receivedArgs: { any } = {}
				Shared.SetConnection("__TEST_DISPATCH_ARGS__", "BINDABLE_EVENT", function(...)
					receivedArgs = { ... }
				end, nil, nil)

				local compressed = Shared.Compression.Compress({ "hello", 42 })
				Shared.OnConnection(nil, "BINDABLE_EVENT", "__TEST_DISPATCH_ARGS__", compressed)
				expect(receivedArgs[1]).to.equal("hello")
				expect(receivedArgs[2]).to.equal(42)
				Shared.RemoveConnection("__TEST_DISPATCH_ARGS__", "BINDABLE_EVENT")
			end)

			it("should return nil for an unknown connection name", function()
				local compressed = Shared.Compression.Compress({})
				local result = Shared.OnConnection(nil, "REMOTE_EVENT", "__DOES_NOT_EXIST__", compressed)
				expect(result).to.equal(nil)
			end)
		end)

		describe("YieldUntilRFResponse", function()
			it("should return the value on success", function()
				local result = Shared.YieldUntilRFResponse("__TEST_RF__", function()
					return "response_value"
				end)
				expect(result).to.equal("response_value")
			end)

			it("should return nil on error", function()
				local result = Shared.YieldUntilRFResponse("__TEST_RF_ERR__", function()
					error("intentional error")
				end)
				expect(result).to.equal(nil)
			end)
		end)

		describe("Remote getters", function()
			it("should return a RemoteEvent", function()
				local re = Shared.GetRE()
				expect(re).to.be.ok()
				expect(re:IsA("RemoteEvent")).to.equal(true)
			end)

			it("should return a RemoteFunction", function()
				local rf = Shared.GetRF()
				expect(rf).to.be.ok()
				expect(rf:IsA("RemoteFunction")).to.equal(true)
			end)

			it("should return an UnreliableRemoteEvent", function()
				local ure = Shared.GetURE()
				expect(ure).to.be.ok()
				expect(ure:IsA("UnreliableRemoteEvent")).to.equal(true)
			end)

			it("should return a BindableEvent", function()
				local be = Shared.GetBE()
				expect(be).to.be.ok()
				expect(be:IsA("BindableEvent")).to.equal(true)
			end)
		end)
	end)

	-- New API: Server
	describe("Server API", function()
		describe("On", function()
			it("should register a connection with default REMOTE_EVENT type", function()
				Server:On("__TEST_SERVER_ON__", function() end)
				expect(Shared.Connections["__TEST_SERVER_ON__"]).to.be.ok()
				expect(Shared.Connections["__TEST_SERVER_ON__"].Type).to.equal("REMOTE_EVENT")
				Server:Off("__TEST_SERVER_ON__")
			end)

			it("should register a connection with a specified type", function()
				Server:On("__TEST_SERVER_ON_RF__", function() end, { type = "REMOTE_FUNCTION" })
				expect(Shared.Connections["__TEST_SERVER_ON_RF__"]).to.be.ok()
				expect(Shared.Connections["__TEST_SERVER_ON_RF__"].Type).to.equal("REMOTE_FUNCTION")
				Server:Off("__TEST_SERVER_ON_RF__", "REMOTE_FUNCTION")
			end)

			it("should accept a rate limit config", function()
				Server:On("__TEST_SERVER_RL__", function() end, {
					rateLimit = { maxTokens = 5, fillRate = 1 },
				})
				local conn = Shared.Connections["__TEST_SERVER_RL__"]
				expect(conn).to.be.ok()
				if IS_SERVER then
					expect(conn.RateLimiter).to.be.ok()
				end
				Server:Off("__TEST_SERVER_RL__")
			end)
		end)

		describe("Off", function()
			it("should remove a registered connection", function()
				Server:On("__TEST_SERVER_OFF__", function() end)
				local removed = Server:Off("__TEST_SERVER_OFF__")
				expect(removed).to.be.ok()
				expect(Shared.Connections["__TEST_SERVER_OFF__"]).to.equal(nil)
			end)

			it("should return nil for a nonexistent connection", function()
				local removed = Server:Off("__NONEXISTENT_SERVER__")
				expect(removed).to.equal(nil)
			end)
		end)

		describe("Fire", function()
			it("should not error when called on server with a valid player", function()
				if not IS_SERVER then
					return
				end
				local player = game.Players:GetPlayers()[1]
				if not player then
					return
				end

				expect(function()
					Server:Fire(player, "__TEST_SERVER_FIRE__", "data")
				end).to.never.throw()
			end)

			it("should silently return on client", function()
				if not IS_CLIENT then
					return
				end
				expect(function()
					Server:Fire(nil :: any, "__TEST__", "data")
				end).to.never.throw()
			end)
		end)

		describe("FireAll", function()
			it("should not error when called on server", function()
				if not IS_SERVER then
					return
				end
				expect(function()
					Server:FireAll("__TEST_SERVER_FIREALL__", "data")
				end).to.never.throw()
			end)
		end)

		describe("FireUnreliable", function()
			it("should not error when called on server with a valid player", function()
				if not IS_SERVER then
					return
				end
				local player = game.Players:GetPlayers()[1]
				if not player then
					return
				end

				expect(function()
					Server:FireUnreliable(player, "__TEST_SERVER_URE__", "data")
				end).to.never.throw()
			end)
		end)

		describe("FireAllUnreliable", function()
			it("should not error when called on server", function()
				if not IS_SERVER then
					return
				end
				expect(function()
					Server:FireAllUnreliable("__TEST_SERVER_UREALL__", "data")
				end).to.never.throw()
			end)
		end)

		describe("Dispatch", function()
			it("should fire a bindable event without error", function()
				expect(function()
					Server:Dispatch("__TEST_SERVER_DISPATCH__", "data")
				end).to.never.throw()
			end)

			it("should trigger a registered BINDABLE_EVENT connection", function()
				local received: any = nil
				Server:On("__TEST_SERVER_DISPATCH_RECV__", function(value: any)
					received = value
				end, { type = "BINDABLE_EVENT" })

				Server:Dispatch("__TEST_SERVER_DISPATCH_RECV__", "dispatched_value")
				task.wait(0.1) -- allow bindable to propagate

				expect(received).to.equal("dispatched_value")
				Server:Off("__TEST_SERVER_DISPATCH_RECV__", "BINDABLE_EVENT")
			end)
		end)

		describe("Signal", function()
			it("should create a signal object with a Wait method", function()
				local signal = Server:Signal("__TEST_SERVER_SIGNAL__")
				expect(signal).to.be.ok()
				expect(signal.Wait).to.be.ok()
				-- cleanup
				Shared.RemoveConnection("Signal__TEST_SERVER_SIGNAL__", "REMOTE_EVENT")
			end)
		end)

		describe("GetRemote", function()
			it("should return a RemoteEvent", function()
				local re = Server:GetRemote("REMOTE_EVENT")
				expect(re).to.be.ok()
			end)

			it("should return a RemoteFunction", function()
				local rf = Server:GetRemote("REMOTE_FUNCTION")
				expect(rf).to.be.ok()
			end)

			it("should return an UnreliableRemoteEvent", function()
				local ure = Server:GetRemote("UREMOTE_EVENT")
				expect(ure).to.be.ok()
			end)

			it("should return a BindableEvent", function()
				local be = Server:GetRemote("BINDABLE_EVENT")
				expect(be).to.be.ok()
			end)

			it("should return nil for an invalid type", function()
				local result = Server:GetRemote("INVALID" :: any)
				expect(result).to.equal(nil)
			end)
		end)
	end)

	-- New API: Client
	describe("Client API", function()
		describe("On", function()
			it("should register a connection with default REMOTE_EVENT type", function()
				Client:On("__TEST_CLIENT_ON__", function() end)
				expect(Shared.Connections["__TEST_CLIENT_ON__"]).to.be.ok()
				expect(Shared.Connections["__TEST_CLIENT_ON__"].Type).to.equal("REMOTE_EVENT")
				Client:Off("__TEST_CLIENT_ON__")
			end)

			it("should register a connection with a specified type", function()
				Client:On("__TEST_CLIENT_ON_RF__", function() end, { type = "REMOTE_FUNCTION" })
				expect(Shared.Connections["__TEST_CLIENT_ON_RF__"]).to.be.ok()
				expect(Shared.Connections["__TEST_CLIENT_ON_RF__"].Type).to.equal("REMOTE_FUNCTION")
				Client:Off("__TEST_CLIENT_ON_RF__", "REMOTE_FUNCTION")
			end)
		end)

		describe("Off", function()
			it("should remove a registered connection", function()
				Client:On("__TEST_CLIENT_OFF__", function() end)
				local removed = Client:Off("__TEST_CLIENT_OFF__")
				expect(removed).to.be.ok()
				expect(Shared.Connections["__TEST_CLIENT_OFF__"]).to.equal(nil)
			end)

			it("should return nil for a nonexistent connection", function()
				local removed = Client:Off("__NONEXISTENT_CLIENT__")
				expect(removed).to.equal(nil)
			end)
		end)

		describe("Fire", function()
			it("should not error when called on client", function()
				if not IS_CLIENT then
					return
				end
				expect(function()
					Client:Fire("__TEST_CLIENT_FIRE__", "data")
				end).to.never.throw()
			end)

			it("should silently return on server", function()
				if not IS_SERVER then
					return
				end
				expect(function()
					Client:Fire("__TEST_CLIENT_FIRE__", "data")
				end).to.never.throw()
			end)
		end)

		describe("FireUnreliable", function()
			it("should not error when called on client", function()
				if not IS_CLIENT then
					return
				end
				expect(function()
					Client:FireUnreliable("__TEST_CLIENT_URE__", "data")
				end).to.never.throw()
			end)
		end)

		describe("Dispatch", function()
			it("should fire a bindable event without error", function()
				expect(function()
					Client:Dispatch("__TEST_CLIENT_DISPATCH__", "data")
				end).to.never.throw()
			end)

			it("should trigger a registered BINDABLE_EVENT connection", function()
				local received: any = nil
				Client:On("__TEST_CLIENT_DISPATCH_RECV__", function(value: any)
					received = value
				end, { type = "BINDABLE_EVENT" })

				Client:Dispatch("__TEST_CLIENT_DISPATCH_RECV__", "client_dispatched")
				task.wait(0.1)

				expect(received).to.equal("client_dispatched")
				Client:Off("__TEST_CLIENT_DISPATCH_RECV__", "BINDABLE_EVENT")
			end)
		end)

		describe("Signal", function()
			it("should create a signal object with a Wait method", function()
				local signal = Client:Signal("__TEST_CLIENT_SIGNAL__")
				expect(signal).to.be.ok()
				expect(signal.Wait).to.be.ok()
				Shared.RemoveConnection("Signal__TEST_CLIENT_SIGNAL__", "REMOTE_EVENT")
			end)
		end)

		describe("GetRemote", function()
			it("should return a RemoteEvent", function()
				local re = Client:GetRemote("REMOTE_EVENT")
				expect(re).to.be.ok()
			end)

			it("should return nil for an invalid type", function()
				local result = Client:GetRemote("INVALID" :: any)
				expect(result).to.equal(nil)
			end)
		end)
	end)

	-- Legacy API
	describe("Legacy API", function()
		describe("SetConnection", function()
			it("should register a connection", function()
				Network:SetConnection("__TEST_LEGACY_SET__", "REMOTE_EVENT", function() end)
				expect(Shared.Connections["__TEST_LEGACY_SET__"]).to.be.ok()
				Network:RemoveConnection("__TEST_LEGACY_SET__", "REMOTE_EVENT")
			end)

			it("should register with schema and rate limit config", function()
				Network:SetConnection("__TEST_LEGACY_FULL__", "REMOTE_FUNCTION", function() end, {
					{ name = "arg1", type = "string" },
				}, {
					maxTokens = 10,
					fillRate = 2,
				})

				local conn = Shared.Connections["__TEST_LEGACY_FULL__"]
				expect(conn).to.be.ok()
				expect(conn.Type).to.equal("REMOTE_FUNCTION")
				expect(conn.Schema).to.be.ok()
				Network:RemoveConnection("__TEST_LEGACY_FULL__", "REMOTE_FUNCTION")
			end)
		end)

		describe("RemoveConnection", function()
			it("should remove and return a connection", function()
				Network:SetConnection("__TEST_LEGACY_RM__", "REMOTE_EVENT", function() end)
				local removed = Network:RemoveConnection("__TEST_LEGACY_RM__", "REMOTE_EVENT")
				expect(removed).to.be.ok()
				expect(removed.Name).to.equal("__TEST_LEGACY_RM__")
			end)

			it("should return nil when type does not match", function()
				Network:SetConnection("__TEST_LEGACY_RM2__", "REMOTE_EVENT", function() end)
				local removed = Network:RemoveConnection("__TEST_LEGACY_RM2__", "REMOTE_FUNCTION")
				expect(removed).to.equal(nil)
				Network:RemoveConnection("__TEST_LEGACY_RM2__", "REMOTE_EVENT")
			end)
		end)

		describe("FireConnection", function()
			it("should fire a bindable without error", function()
				expect(function()
					Network:FireConnection("__TEST_LEGACY_BINDABLE__", "data")
				end).to.never.throw()
			end)
		end)

		describe("FireClientConnection", function()
			it("should not error on server with a valid player", function()
				if not IS_SERVER then
					return
				end
				local player = game.Players:GetPlayers()[1]
				if not player then
					return
				end

				expect(function()
					Network:FireClientConnection(player, "__TEST_LEGACY_FC__", "REMOTE_EVENT", "data")
				end).to.never.throw()
			end)

			it("should silently return on client", function()
				if not IS_CLIENT then
					return
				end
				expect(function()
					Network:FireClientConnection(nil :: any, "__TEST__", "REMOTE_EVENT", "data")
				end).to.never.throw()
			end)
		end)

		describe("FireAllClientConnection", function()
			it("should not error on server", function()
				if not IS_SERVER then
					return
				end
				expect(function()
					Network:FireAllClientConnection("__TEST_LEGACY_FAC__", "REMOTE_EVENT", "data")
				end).to.never.throw()
			end)
		end)

		describe("FireServerConnection", function()
			it("should not error on client", function()
				if not IS_CLIENT then
					return
				end
				expect(function()
					Network:FireServerConnection("__TEST_LEGACY_FS__", "REMOTE_EVENT", "data")
				end).to.never.throw()
			end)

			it("should silently return on server", function()
				if not IS_SERVER then
					return
				end
				expect(function()
					Network:FireServerConnection("__TEST_LEGACY_FS__", "REMOTE_EVENT", "data")
				end).to.never.throw()
			end)
		end)

		describe("GetRemote", function()
			it("should return a RemoteEvent", function()
				local re = Network:GetRemote("REMOTE_EVENT")
				expect(re).to.be.ok()
			end)

			it("should return a RemoteFunction", function()
				local rf = Network:GetRemote("REMOTE_FUNCTION")
				expect(rf).to.be.ok()
			end)

			it("should return an UnreliableRemoteEvent", function()
				local ure = Network:GetRemote("UREMOTE_EVENT")
				expect(ure).to.be.ok()
			end)

			it("should return a BindableEvent", function()
				local be = Network:GetRemote("BINDABLE_EVENT")
				expect(be).to.be.ok()
			end)
		end)

		describe("SetSignal", function()
			it("should return an object with a Wait method", function()
				local signal = Network:SetSignal("__TEST_LEGACY_SIGNAL__")
				expect(signal).to.be.ok()
				expect(signal.Wait).to.be.ok()
				Shared.RemoveConnection("Signal__TEST_LEGACY_SIGNAL__", "REMOTE_EVENT")
			end)
		end)
	end)

	-- Cross-compatibility: New and Legacy share state
	describe("Cross-compatibility", function()
		it("should allow Server:On to register and Legacy to remove", function()
			Server:On("__TEST_CROSS_1__", function() end)
			expect(Shared.Connections["__TEST_CROSS_1__"]).to.be.ok()

			local removed = Network:RemoveConnection("__TEST_CROSS_1__", "REMOTE_EVENT")
			expect(removed).to.be.ok()
			expect(Shared.Connections["__TEST_CROSS_1__"]).to.equal(nil)
		end)

		it("should allow Legacy SetConnection and Server:Off to remove", function()
			Network:SetConnection("__TEST_CROSS_2__", "REMOTE_EVENT", function() end)
			expect(Shared.Connections["__TEST_CROSS_2__"]).to.be.ok()

			local removed = Server:Off("__TEST_CROSS_2__")
			expect(removed).to.be.ok()
			expect(Shared.Connections["__TEST_CROSS_2__"]).to.equal(nil)
		end)

		it("should share the same connection registry between all APIs", function()
			Server:On("__TEST_CROSS_3__", function() end)
			local conn = Shared.Connections["__TEST_CROSS_3__"]
			expect(conn).to.be.ok()
			expect(conn.Name).to.equal("__TEST_CROSS_3__")
			Server:Off("__TEST_CROSS_3__")
		end)

		it("should expose Server and Client on the Network table", function()
			expect((Network :: any).Server).to.be.ok()
			expect((Network :: any).Client).to.be.ok()
		end)
	end)
end
