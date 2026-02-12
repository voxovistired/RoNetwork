--!strict
--!native
--!optimize 2

--[[
	Compression Module
	Handles buffer-based serialization and deserialization for network data.
	Supports: nil, boolean, number, string, Vector3, Vector2, Vector3int16, Vector2int16, CFrame, Color3, UDim2, tables, and JSON fallback.
]]

-- Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- Constants
local IS_SERVER: boolean = RunService:IsServer()
local IS_STUDIO: boolean = RunService:IsStudio()
local MAX_PACKET_SIZE: number = 4_000
local MAX_TABLE_DEPTH: number = 10
local MAX_TABLE_SIZE: number = 1000

local TYPE_NULL: number = 0
local TYPE_BOOLEAN: number = 1
local TYPE_NUMBER: number = 2
local TYPE_STRING: number = 3
local TYPE_VECTOR3: number = 4
local TYPE_VECTOR2: number = 5
local TYPE_CFRAME: number = 6
local TYPE_COLOR3: number = 7
local TYPE_UDIM2: number = 8
local TYPE_TABLE: number = 9
local TYPE_JSON_FALLBACK: number = 10
local TYPE_VECTOR3INT16: number = 11
local TYPE_VECTOR2INT16: number = 12

-- Local references
local Encode, Decode = HttpService.JSONEncode, HttpService.JSONDecode

local function displayWarn(message: string): ()
	if not IS_STUDIO then
		return
	end
	warn(`[Network/Compression]: {message}`)
end

local function calculateValueSize(value: any, depth: number?): number
	depth = depth or 0
	if depth > MAX_TABLE_DEPTH then
		error("Table nesting too deep, possible attack.")
	end

	local valueType: string = typeof(value)
	local size: number = 1

	if valueType == "nil" then
		return size
	elseif valueType == "boolean" then
		return size + 1
	elseif valueType == "number" then
		return size + 8
	elseif valueType == "string" then
		return size + 4 + #value
	elseif valueType == "Vector3" then
		return size + 12
	elseif valueType == "Vector2" then
		return size + 8
	elseif valueType == "Vector3int16" then
		return size + 6
	elseif valueType == "Vector2int16" then
		return size + 4
	elseif valueType == "CFrame" then
		return size + 48
	elseif valueType == "Color3" then
		return size + 12
	elseif valueType == "UDim2" then
		return size + 16
	elseif valueType == "table" then
		size += 4

		local count: number = 0
		for index: any, tableValue: any in value do
			count += 1
			if count > MAX_TABLE_SIZE then
				error("Table too large, possible attack.")
			end

			size += calculateValueSize(index, depth + 1)
			size += calculateValueSize(tableValue, depth + 1)
		end

		return size
	else
		local success: boolean, response: any = pcall(function()
			return Encode(HttpService, value)
		end)

		if success and (response ~= "null") then
			return size + 4 + #response
		end

		displayWarn(`[{script}/__calculateValueSize]: Could not calculate size of value: {value}, type: {valueType}`)
		return size
	end
end

local function writeValue(bufferToWrite: buffer, offset: number, value: any): number
	local valueType: string = typeof(value)

	if valueType == "nil" then
		buffer.writeu8(bufferToWrite, offset, TYPE_NULL)

		return offset + 1
	elseif valueType == "boolean" then
		buffer.writeu8(bufferToWrite, offset, TYPE_BOOLEAN)

		buffer.writeu8(bufferToWrite, offset + 1, value and 1 or 0)

		return offset + 2
	elseif valueType == "number" then
		buffer.writeu8(bufferToWrite, offset, TYPE_NUMBER)

		buffer.writef64(bufferToWrite, offset + 1, value)

		return offset + 9
	elseif valueType == "string" then
		buffer.writeu8(bufferToWrite, offset, TYPE_STRING)

		local valueSize: number = #value
		buffer.writeu32(bufferToWrite, offset + 1, valueSize)
		buffer.writestring(bufferToWrite, offset + 5, value)

		return offset + 5 + valueSize
	elseif valueType == "Vector3" then
		buffer.writeu8(bufferToWrite, offset, TYPE_VECTOR3)

		buffer.writef32(bufferToWrite, offset + 1, value.X)
		buffer.writef32(bufferToWrite, offset + 5, value.Y)
		buffer.writef32(bufferToWrite, offset + 9, value.Z)

		return offset + 13
	elseif valueType == "Vector2" then
		buffer.writeu8(bufferToWrite, offset, TYPE_VECTOR2)

		buffer.writef32(bufferToWrite, offset + 1, value.X)
		buffer.writef32(bufferToWrite, offset + 5, value.Y)

		return offset + 9
	elseif valueType == "Vector3int16" then
		buffer.writeu8(bufferToWrite, offset, TYPE_VECTOR3INT16)

		buffer.writei16(bufferToWrite, offset + 1, value.X)
		buffer.writei16(bufferToWrite, offset + 3, value.Y)
		buffer.writei16(bufferToWrite, offset + 5, value.Z)

		return offset + 7
	elseif valueType == "Vector2int16" then
		buffer.writeu8(bufferToWrite, offset, TYPE_VECTOR2INT16)

		buffer.writei16(bufferToWrite, offset + 1, value.X)
		buffer.writei16(bufferToWrite, offset + 3, value.Y)

		return offset + 5
	elseif valueType == "CFrame" then
		buffer.writeu8(bufferToWrite, offset, TYPE_CFRAME)

		local x: number, y: number, z: number, r00: number, r01: number, r02: number, r10: number, r11: number, r12: number, r20: number, r21: number, r22: number =
			value:GetComponents()
		buffer.writef32(bufferToWrite, offset + 1, x)
		buffer.writef32(bufferToWrite, offset + 5, y)
		buffer.writef32(bufferToWrite, offset + 9, z)
		buffer.writef32(bufferToWrite, offset + 13, r00)
		buffer.writef32(bufferToWrite, offset + 17, r01)
		buffer.writef32(bufferToWrite, offset + 21, r02)
		buffer.writef32(bufferToWrite, offset + 25, r10)
		buffer.writef32(bufferToWrite, offset + 29, r11)
		buffer.writef32(bufferToWrite, offset + 33, r12)
		buffer.writef32(bufferToWrite, offset + 37, r20)
		buffer.writef32(bufferToWrite, offset + 41, r21)
		buffer.writef32(bufferToWrite, offset + 45, r22)

		return offset + 49
	elseif valueType == "Color3" then
		buffer.writeu8(bufferToWrite, offset, TYPE_COLOR3)

		buffer.writef32(bufferToWrite, offset + 1, value.R)
		buffer.writef32(bufferToWrite, offset + 5, value.G)
		buffer.writef32(bufferToWrite, offset + 9, value.B)

		return offset + 13
	elseif valueType == "UDim2" then
		buffer.writeu8(bufferToWrite, offset, TYPE_UDIM2)

		buffer.writef32(bufferToWrite, offset + 1, value.X.Scale)
		buffer.writef32(bufferToWrite, offset + 5, value.X.Offset)
		buffer.writef32(bufferToWrite, offset + 9, value.Y.Scale)
		buffer.writef32(bufferToWrite, offset + 13, value.Y.Offset)

		return offset + 17
	elseif valueType == "table" then
		buffer.writeu8(bufferToWrite, offset, TYPE_TABLE)

		local count: number = 0
		for _ in value do
			count += 1
		end

		buffer.writeu32(bufferToWrite, offset + 1, count)
		offset += 5

		for index: any, tableValue: any in value do
			offset = writeValue(bufferToWrite, offset, index)
			offset = writeValue(bufferToWrite, offset, tableValue)
		end

		return offset
	else
		local success: boolean, response: any = pcall(function()
			return Encode(HttpService, value)
		end)

		if success and (response ~= "null") then
			buffer.writeu8(bufferToWrite, offset, TYPE_JSON_FALLBACK)

			local size: number = #response
			buffer.writeu32(bufferToWrite, offset + 1, size)
			buffer.writestring(bufferToWrite, offset + 5, response)

			return offset + 5 + size
		else
			displayWarn(`[{script}/__writeValue]: Unsupported data type: {valueType}`)
			buffer.writeu8(bufferToWrite, offset, TYPE_NULL)
			return offset + 1
		end
	end
end

local function readValue(bufferToRead: buffer, offset: number): (any, number)
	local valueType: number = buffer.readu8(bufferToRead, offset)
	offset += 1

	if valueType == TYPE_NULL then
		return nil, offset
	elseif valueType == TYPE_BOOLEAN then
		local value: boolean = buffer.readu8(bufferToRead, offset) == 1

		return value, offset + 1
	elseif valueType == TYPE_NUMBER then
		local value: number = buffer.readf64(bufferToRead, offset)

		return value, offset + 8
	elseif valueType == TYPE_STRING then
		local size: number = buffer.readu32(bufferToRead, offset)
		offset += 4

		local value: string = buffer.readstring(bufferToRead, offset, size)
		return value, offset + size
	elseif valueType == TYPE_VECTOR3 then
		local x: number = buffer.readf32(bufferToRead, offset)
		local y: number = buffer.readf32(bufferToRead, offset + 4)
		local z: number = buffer.readf32(bufferToRead, offset + 8)

		return Vector3.new(x, y, z), offset + 12
	elseif valueType == TYPE_VECTOR2 then
		local x: number = buffer.readf32(bufferToRead, offset)
		local y: number = buffer.readf32(bufferToRead, offset + 4)

		return Vector2.new(x, y), offset + 8
	elseif valueType == TYPE_VECTOR3INT16 then
		local x: number = buffer.readi16(bufferToRead, offset)
		local y: number = buffer.readi16(bufferToRead, offset + 2)
		local z: number = buffer.readi16(bufferToRead, offset + 4)

		return Vector3int16.new(x, y, z), offset + 6
	elseif valueType == TYPE_VECTOR2INT16 then
		local x: number = buffer.readi16(bufferToRead, offset)
		local y: number = buffer.readi16(bufferToRead, offset + 2)

		return Vector2int16.new(x, y), offset + 4
	elseif valueType == TYPE_CFRAME then
		local x: number = buffer.readf32(bufferToRead, offset)
		local y: number = buffer.readf32(bufferToRead, offset + 4)
		local z: number = buffer.readf32(bufferToRead, offset + 8)
		local r00: number = buffer.readf32(bufferToRead, offset + 12)
		local r01: number = buffer.readf32(bufferToRead, offset + 16)
		local r02: number = buffer.readf32(bufferToRead, offset + 20)
		local r10: number = buffer.readf32(bufferToRead, offset + 24)
		local r11: number = buffer.readf32(bufferToRead, offset + 28)
		local r12: number = buffer.readf32(bufferToRead, offset + 32)
		local r20: number = buffer.readf32(bufferToRead, offset + 36)
		local r21: number = buffer.readf32(bufferToRead, offset + 40)
		local r22: number = buffer.readf32(bufferToRead, offset + 44)

		return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22), offset + 48
	elseif valueType == TYPE_COLOR3 then
		local r: number = buffer.readf32(bufferToRead, offset)
		local g: number = buffer.readf32(bufferToRead, offset + 4)
		local b: number = buffer.readf32(bufferToRead, offset + 8)

		return Color3.new(r, g, b), offset + 12
	elseif valueType == TYPE_UDIM2 then
		local xScale: number = buffer.readf32(bufferToRead, offset)
		local xOffset: number = buffer.readf32(bufferToRead, offset + 4)
		local yScale: number = buffer.readf32(bufferToRead, offset + 8)
		local yOffset: number = buffer.readf32(bufferToRead, offset + 12)

		return UDim2.new(xScale, xOffset, yScale, yOffset), offset + 16
	elseif valueType == TYPE_TABLE then
		local tableSize: number = buffer.readu32(bufferToRead, offset)
		offset += 4

		local newTable: { any } = {}
		for _ = 1, tableSize do
			local key, value

			key, offset = readValue(bufferToRead, offset)
			value, offset = readValue(bufferToRead, offset)

			newTable[key] = value
		end

		return newTable, offset
	elseif valueType == TYPE_JSON_FALLBACK then
		local size: number = buffer.readu32(bufferToRead, offset)
		offset += 4

		local json: string = buffer.readstring(bufferToRead, offset, size)
		offset += size

		local success: boolean, response: any = pcall(function()
			return Decode(HttpService, json)
		end)

		if success then
			return response, offset
		else
			displayWarn(`[{script}/__readValue]: Failed to parse data.`)
			return nil, offset
		end
	end

	return nil, offset
end

local function packBuffer(table: any): buffer?
	local size: number = calculateValueSize(table)
	--__displayWarn(`[{script}/__packBuffer]: Writing new buffer, size: {size}`)

	local newBuffer: buffer = buffer.create(size)
	writeValue(newBuffer, 0, table)
	return newBuffer
end

local function unpackBuffer(compressedBuffer: buffer): { [any]: any }
	assert(compressedBuffer and typeof(compressedBuffer) == "buffer", "bad compressedBuffer, must be buffer.")
	local value: any, _ = readValue(compressedBuffer, 0)
	return value
end

local function decompressValue(value: any): any
	if typeof(value) == "buffer" then
		if IS_SERVER and (buffer.len(value) > MAX_PACKET_SIZE) then
			error(`Buffer is too large, returning. Buffer size: {buffer.len(value)}, Max size: {MAX_PACKET_SIZE}.`)
		end

		return unpackBuffer(value)
	elseif typeof(value) == "table" then
		local result: { [any]: any } = {}

		for index: any, tableValue: any in value do
			result[index] = decompressValue(tableValue)
		end

		return result
	else
		return value
	end
end

local function compressValue(value: any, supers: { any }?): any
	if typeof(value) == "Instance" then
		return value
	elseif typeof(value) == "table" then
		local result: { [any]: any } = {}
		local currentSupers: { any } = supers or {}
		currentSupers[value] = true

		for index: any, tableValue: any in value do
			if currentSupers[tableValue] then
				displayWarn(`[{script}/__compressValue]: Recursive table detected. Key: {index}`)
				continue
			end
			result[index] = compressValue(tableValue, currentSupers)
		end

		return result
	else
		return (packBuffer(value) or value)
	end
end

local function packTableForBuffer(arguments: { [number]: any } | buffer): { [any]: any } | buffer
	local compressed = {}

	for index: any, value: any in arguments :: { [number | "n"]: any } do
		if index == "n" then
			continue
		end
		compressed[index] = compressValue(value)
	end

	return compressed :: { [any]: any }
end

local function unpackBufferForTable(arguments: { [number]: any } | buffer): { [any]: any }
	if typeof(arguments) == "string" then
		return decompressValue(arguments)
	end

	local compressed = {}

	for index: any, value: any in arguments :: { any } do
		compressed[index] = decompressValue(value)
	end

	return compressed
end

local Compression = {}

--[[
	Compresses a table of arguments into buffers for network transmission.
	@param arguments The table of values to compress
	@return Compressed table ready for network transmission
]]
function Compression.Compress(arguments: { [number]: any }): { [any]: any } | buffer
	return packTableForBuffer(arguments :: { any })
end

--[[
	Decompresses network data back into usable values.
	@param arguments The compressed data to decompress
	@return Decompressed table of values
]]
function Compression.Decompress(arguments: { [number]: any } | buffer): { [any]: any }
	return unpackBufferForTable(arguments)
end

return Compression
