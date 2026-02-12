--!strict
--!native
--!optimize 2

--[[
	Validation Module
	Handles runtime type validation and schema checking for network data.
	Provides security against malicious client data and type mismatches.
]]

-- Types
export type TypeConstraints = {
	-- Number constraints
	min: number?,
	max: number?,
	integer: boolean?,

	-- String constraints
	maxLength: number?,
	pattern: string?,

	-- Vector constraints
	maxMagnitude: number?,

	-- Instance constraints
	class: string?,

	-- Table constraints
	maxSize: number?,
}

export type SchemaEntry = {
	type: string,
	constraints: TypeConstraints?,
	optional: boolean?,
}

export type TypeSchema = { SchemaEntry }

-- Type Validators
local TypeValidators: { [string]: (value: any, constraints: TypeConstraints?) -> (boolean, string?) } = {
	number = function(v: any, constraints: TypeConstraints?): (boolean, string?)
		if type(v) ~= "number" then
			return false, "expected number"
		end

		if constraints then
			if constraints.min and v < constraints.min then
				return false, `number below min {constraints.min}`
			end

			if constraints.max and v > constraints.max then
				return false, `number above max {constraints.max}`
			end

			if constraints.integer and v % 1 ~= 0 then
				return false, "expected integer"
			end
		end

		return true, nil
	end,

	string = function(v: any, constraints: TypeConstraints?): (boolean, string?)
		if type(v) ~= "string" then
			return false, "expected string"
		end

		if constraints then
			if constraints.maxLength and #v > constraints.maxLength then
				return false, `string too long (max {constraints.maxLength})`
			end

			if constraints.pattern and not string.match(v, constraints.pattern) then
				return false, "string pattern mismatch"
			end
		end

		return true, nil
	end,

	Vector3 = function(v: any, constraints: TypeConstraints?): (boolean, string?)
		if typeof(v) ~= "Vector3" then
			return false, "expected Vector3"
		end

		if constraints then
			if constraints.maxMagnitude and v.Magnitude > constraints.maxMagnitude then
				return false, `Vector3 magnitude too large (max {constraints.maxMagnitude})`
			end
		end

		return true, nil
	end,

	Vector2 = function(v: any, constraints: TypeConstraints?): (boolean, string?)
		if typeof(v) ~= "Vector2" then
			return false, "expected Vector2"
		end

		if constraints then
			if constraints.maxMagnitude and v.Magnitude > constraints.maxMagnitude then
				return false, `Vector2 magnitude too large (max {constraints.maxMagnitude})`
			end
		end

		return true, nil
	end,

	boolean = function(v: any): (boolean, string?)
		if type(v) ~= "boolean" then
			return false, "expected boolean"
		end

		return true, nil
	end,

	Instance = function(v: any, constraints: TypeConstraints?): (boolean, string?)
		if typeof(v) ~= "Instance" then
			return false, "expected Instance"
		end

		if constraints and constraints.class then
			if not v:IsA(constraints.class) then
				return false, `expected {constraints.class}`
			end
		end

		return true, nil
	end,

	table = function(v: any, constraints: TypeConstraints?): (boolean, string?)
		if type(v) ~= "table" then
			return false, "expected table"
		end

		if constraints then
			if constraints.maxSize then
				local count: number = 0
				for _ in v do
					count += 1
					if count > constraints.maxSize then
						return false, `table too large (max {constraints.maxSize})`
					end
				end
			end
		end

		return true, nil
	end,

	CFrame = function(v: any): (boolean, string?)
		if typeof(v) ~= "CFrame" then
			return false, "expected CFrame"
		end

		return true, nil
	end,

	Color3 = function(v: any): (boolean, string?)
		if typeof(v) ~= "Color3" then
			return false, "expected Color3"
		end

		return true, nil
	end,

	UDim2 = function(v: any): (boolean, string?)
		if typeof(v) ~= "UDim2" then
			return false, "expected UDim2"
		end

		return true, nil
	end,

	Vector3int16 = function(v: any): (boolean, string?)
		if typeof(v) ~= "Vector3int16" then
			return false, "expected Vector3int16"
		end

		return true, nil
	end,

	Vector2int16 = function(v: any): (boolean, string?)
		if typeof(v) ~= "Vector2int16" then
			return false, "expected Vector2int16"
		end

		return true, nil
	end,
}

local Validation = {}

--[[
	Validates a list of arguments against a type schema.
	Returns true if all arguments match the schema, false with error message otherwise.
	
	@param connectionName The name of the connection (for error messages)
	@param playerName The name of the player sending data (for error messages)
	@param arguments The arguments to validate
	@param schema The schema to validate against
	@return (isValid: boolean, errorMessage: string?)
]]
function Validation.ValidateArguments(
	connectionName: string,
	playerName: string,
	arguments: { any },
	schema: TypeSchema
): (boolean, string?)
	for i: number, schemaEntry: SchemaEntry in schema do
		local arg: any = arguments[i]

		-- Handle optional arguments
		if (arg == nil) and schemaEntry.optional then
			continue
		end

		-- Get the validator for this type
		local validator = TypeValidators[schemaEntry.type]
		if not validator then
			return false, `[{connectionName}]: Unknown validator type: {schemaEntry.type}`
		end

		-- Validate the argument
		local isValid: boolean, errorMessage: string? = validator(arg, schemaEntry.constraints)
		if not isValid then
			return false, `[{connectionName}]: {playerName} sent invalid arg: {errorMessage}`
		end
	end

	return true, nil
end

--[[
	Registers a custom type validator.
	Useful for game-specific types or custom validation logic.
	
	@param typeName The name of the type (e.g., "CustomEnum")
	@param validator The validation function: (value, constraints) -> (isValid, errorMessage?)
]]
function Validation.RegisterValidator(
	typeName: string,
	validator: (value: any, constraints: TypeConstraints?) -> (boolean, string?)
): ()
	TypeValidators[typeName] = validator
end

--[[
	Creates a schema entry with type and optional constraints.
	Convenience function for better readability when defining schemas.
	
	@param typeName The type name (e.g., "number", "string")
	@param constraints Optional constraints for the type
	@param optional Whether this argument is optional (default: false)
	@return SchemaEntry
]]
function Validation.Entry(typeName: string, constraints: TypeConstraints?, optional: boolean?): SchemaEntry
	return {
		type = typeName,
		constraints = constraints,
		optional = optional or false,
	}
end

--[[
	Quick validators for common patterns.
	These return SchemaEntry objects for use in schemas.
]]
Validation.Validators = {
	-- Numbers
	PositiveInteger = function(max: number?): SchemaEntry
		return Validation.Entry("number", { min = 1, integer = true, max = max })
	end,

	PositiveNumber = function(max: number?): SchemaEntry
		return Validation.Entry("number", { min = 0, max = max })
	end,

	IntegerRange = function(min: number, max: number): SchemaEntry
		return Validation.Entry("number", { min = min, max = max, integer = true })
	end,

	NumberRange = function(min: number, max: number): SchemaEntry
		return Validation.Entry("number", { min = min, max = max })
	end,

	-- Strings
	ShortString = function(maxLength: number?): SchemaEntry
		return Validation.Entry("string", { maxLength = maxLength or 50 })
	end,

	AlphanumericString = function(maxLength: number?): SchemaEntry
		return Validation.Entry("string", {
			maxLength = maxLength or 50,
			pattern = "^[a-zA-Z0-9_]+$",
		})
	end,

	-- Vectors
	BoundedVector3 = function(maxMagnitude: number): SchemaEntry
		return Validation.Entry("Vector3", { maxMagnitude = maxMagnitude })
	end,

	BoundedVector2 = function(maxMagnitude: number): SchemaEntry
		return Validation.Entry("Vector2", { maxMagnitude = maxMagnitude })
	end,

	-- Instances
	ToolInstance = function(): SchemaEntry
		return Validation.Entry("Instance", { class = "Tool" })
	end,

	PartInstance = function(): SchemaEntry
		return Validation.Entry("Instance", { class = "BasePart" })
	end,

	-- Tables
	SmallTable = function(maxSize: number?): SchemaEntry
		return Validation.Entry("table", { maxSize = maxSize or 100 })
	end,

	-- Optional variants
	OptionalNumber = function(): SchemaEntry
		return Validation.Entry("number", nil, true)
	end,

	OptionalString = function(): SchemaEntry
		return Validation.Entry("string", nil, true)
	end,
}

return Validation
