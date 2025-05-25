local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Networking = require(ReplicatedStorage:WaitForChild("Shared").Networking);

local startBench = tick();
print(Networking.Client:Fire("TestEvent", "RF"))
print("Time took: " .. tick() - startBench)