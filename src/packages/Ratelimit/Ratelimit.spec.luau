return function()
	local Ratelimit = require(script.Parent.Ratelimit)
	describe("new", function()
		it("should create a new Ratelimiter", function()
			local newRatelimiter: Ratelimit.RateLimiter = Ratelimit.new()
			expect(newRatelimiter).to.be.ok()
		end)

		it("should check the player reference correctly", function()
			local newRatelimiter: Ratelimit.RateLimiter = Ratelimit.new()
			expect(newRatelimiter:Check(game.Players:GetPlayers()[1])).to.be.equal("OK")
		end)

		it("should properly create and try out the leaky algorithm", function()
			local newRatelimiter: Ratelimit.RateLimiter = Ratelimit.new("LEAKY")
			expect(newRatelimiter:Check(game.Players:GetPlayers()[1])).to.be.equal("OK")
		end)

		it("should properly create and try out the token algorithm", function()
			local newRatelimiter: Ratelimit.RateLimiter = Ratelimit.new("TOKEN")
			expect(newRatelimiter:Check(game.Players:GetPlayers()[1])).to.be.equal("OK")
		end)

		it("should properly create and try out the sliding window algorithm", function()
			local newRatelimiter: Ratelimit.RateLimiter = Ratelimit.new("SLIDING_WINDOW")
			expect(newRatelimiter:Check(game.Players:GetPlayers()[1])).to.be.equal("OK")
		end)
	end)
end
