local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Networking = require(ReplicatedStorage:WaitForChild("Shared").Networking);

Networking.Server:Subscribe("TestEvent", "RF", function(player: Player): any?
	return "Testing remote function!";
end);