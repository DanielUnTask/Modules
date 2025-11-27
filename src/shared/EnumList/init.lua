--- Classes
local EnumList = {}
EnumList.Prototype = {}

--- Private Types

--[=[
   .interface EnumItem
     string Name
     number Value
     EnumList EnumType
]=]
type Item<EnumParent> = {
	Name: string,
	Value: number,
	EnumType: EnumParent,
}

--[=[
   .interface EnumItem
     string Name
     number Value
     EnumList EnumType
]=]
type InternalEnum<CustomEnum> = { [string]: Item<CustomEnum> }

--- Public Types

--[=[
   .interface EnumList
     string _kind
     table _values
     function GetItems(self: EnumList): table
     function GetItem(self: EnumList, name: string): EnumItem
     function GetItemByValue(self: EnumList, value: number): EnumItem
     function GetItemByValueUnsafe(self: EnumList, value: number): EnumItem
]=]
export type EnumList<CustomEnum> =
	typeof(setmetatable({} :: any, {}))
	& CustomEnum
	& InternalEnum<CustomEnum>
	& typeof(EnumList.Prototype)

--- Internal Methods
local enumitem_metatable = {
	__tostring = function<EnumParent>(self: Item<EnumParent>)
		return `{self.EnumType}.{self.Name}`
	end,
	__eq = function(self, b)
		return type(b) == "table" and getmetatable(b)._kind == "EnumItem" and tostring(self) == tostring(b)
	end,
	_kind = "EnumItem",
}

--[=[
   Creates a new EnumItem instance.

   This function is used internally by EnumList to construct
   strongly-typed enum values. EnumItem objects are lightweight
   wrappers containing the name, numeric value, and parent EnumList.

   Each call returns a *new instance* (EnumItems are not cached),
   but all instances representing the same enum entry are considered
   equal via the `__eq` metamethod.

   @param name string  
      The key/name of the enum entry.  

   @param value number  
      The numerical value associated with this entry.  

   @param parent EnumList  
      The EnumList this item belongs to. Used to ensure type 
      identity and `EnumType` checking.

   @return EnumItem  
      A new EnumItem instance with fields:
        - Name: string  
        - Value: number  
        - EnumType: EnumList  
]=]
local newItem = function<EnumParent>(name: string, value: number, parent: EnumParent): Item<EnumParent>
	return setmetatable({
		Name = name,
		Value = value,
		EnumType = parent,
	}, enumitem_metatable) :: any
end

--- Constructor
local enumlist_metatable = {
	__index = function(self, key)
		return if self._values[key] then newItem(key, self._values[key], self) else EnumList.Prototype[key]
	end,

	__tostring = function(self)
		return self._kind
	end,

	_kind = "EnumList",
}

--[=[
   Creates a new EnumList definition.

   This function constructs an EnumList object representing a set
   of named enum entries mapped to numeric values. The returned object
   supports property-style access to enum items:

      local MyEnum = EnumList.new("MyEnum", { Foo = 0, Bar = 1 })
      print(MyEnum.Foo) --> MyEnum.Foo

   Accessing a key dynamically generates a new EnumItem instance
   associated with this EnumList.

   The EnumList also exposes helper methods through its prototype,
   such as:
      - GetName()
      - GetItems()
      - BelongsTo(obj)

   @param name string  
      The public-facing name of the enum type. This becomes the
      `_kind` value and is used for identification, tostring(), and
      debug output.

   @param values table<string, number>  
      A table mapping string keys to numeric values.  
      Example: { Red = 1, Blue = 2, Green = 3 }

   @return EnumList  
      A new EnumList instance that:
        - Exposes all keys in `values` as EnumItem fields.
        - Inherits utility methods from EnumList.Prototype.
        - Defines `_kind` and `_values` internally.
]=]
local newList = function<CustomEnum>(name: string, values: CustomEnum & { [string]: number }): EnumList<CustomEnum>
	return setmetatable({
		_kind = name,
		_values = values,
	}, enumlist_metatable) :: any
end

--- Public Functions

--[=[
   Returns all EnumItem objects contained in this EnumList,
   sorted by their numeric value (ascending).

   Each entry in the returned array is a new EnumItem instance
   constructed from the internal definition.

   @return {EnumItem}  
   A numerically-indexed array of EnumItem objects.
]=]
function EnumList.Prototype:GetItems(): { [number]: any }
	local sortedKeys: { number? } = {}
	local result = {}

	-- Sort by numeric value
	for key, value in self._values do
		sortedKeys[value] = key
	end

	for _, key in ipairs(sortedKeys) do
		table.insert(result, newItem(key, self._values[key], self))
	end

	return result
end

--[=[
   Returns the name of this EnumList.

   This corresponds to the internal `_kind` field assigned
   when the EnumList was created.

   @return string  
   The name of the EnumList.
]=]
function EnumList.Prototype:GetName(): string
	return self._kind
end

--[=[
   Checks whether the given object is an EnumItem belonging
   to this EnumList.

   This is useful for validating enum parameters at runtime.

   @param obj any  
   The value to check.

   @return boolean  
   True if `obj` is an EnumItem and its parent EnumList
   matches this EnumList. False otherwise.
]=]
function EnumList.Prototype:BelongsTo(obj: any): boolean
	return type(obj) == "table" and obj.EnumType == self
end

return {
	new = newList,
}
