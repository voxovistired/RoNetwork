--[[
	Reason for this is because in some places (especially with when we have to fire unreliably), strings can produce large packet sizes.
	To absolve this issue, we can just use this registry which acts as a hash map to directly reference connections on both the server and client, making overhead slim to none.
	
	It is easy to implement something in here, just do as follows:
	
	1. Create a unique string that is not already in use.
	2. Create a unique number that is not already in use.
	
	Example:
	
	```lua
		-- Create a unique string that is not already in use.
		["UpdateCharacterPosition"] = 1;
	```
	
	The network will automatically convert the string to the number, and then convert it back to the string on the other end.
]]
return table.freeze({})
