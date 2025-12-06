--!strict
--!optimize 2

--- Requires
local Task = require(script.Parent.TaskSchedule)

--- Internal error function used after signal destruction
local function signal_error_func()
	error("Cannot fire a deleted signal", 2)
end

--- Static Functions
local error_signal = {
	Wait = signal_error_func,
	Fire = signal_error_func,
	Once = signal_error_func,
	Connect = signal_error_func,
	Destroy = signal_error_func,
	DisconnectAll = signal_error_func,
}

--- Types

--[=[
	@within Signal
   @Type Func (T...) -> ()
]=]
type Func<T...> = (T...) -> ()

--[=[
	@within Signal
	@interface StaticSignal
	
	.Proxy RBXScriptConnection?
	.Next StaticConnection
	.Previous StaticConnection
]=]
type StaticSignal<T...> = {
	Proxy: RBXScriptConnection?,
	Next: Connection<T...>,
	Previous: Connection<T...>,
}

--[=[
	@within Signal
	@interface StaticConnection	
	.Once boolean
	.Connected boolean
	.Thread thread
	.Function Func<T...>
]=]
type StaticConnection<T... = ()> = {
	Once: boolean,
	Connected: boolean,

	Thread: thread,
	Function: Func<T...>,
}

--[=[
	@within Signal
	@interface Identity
	
	.Wait (self) -> T...
	.Fire (self, T...) -> ()
	
	.Once (self, callback: Func<T...>) -> Connection<T...>
	.Connect (self, callback: Func<T...>) -> Connection<T...>
	
	.Destroy (self) -> ()
	.DisconnectAll (self) -> ()
]=]
export type Identity<T... = ()> = StaticSignal<T...> & {
	Wait: (self: Identity<T...>) -> T...,
	Fire: (self: Identity<T...>, T...) -> (),

	Once: (self: Identity<T...>, callback: Func<T...>) -> Connection<T...>,
	Connect: (self: Identity<T...>, callback: Func<T...>) -> Connection<T...>,

	Destroy: (self: Identity<T...>) -> (),
	DisconnectAll: (self: Identity<T...>) -> (),
}

--[=[
	@within Signal
	@interface Connection
	.Destroy (self) -> ()
	.Disconnect (self) -> ()
]=]
export type Connection<T... = ()> = StaticSignal<T...> & StaticConnection<T...> & {
	Destroy: (self: Connection<T...>) -> (),
	Disconnect: (self: Connection<T...>) -> (),
}

--- Connection

local Connection = {}
Connection.__index = Connection

--[=[
	@method Disconnect
	@within Connection

	Disconnects this connection from the signal.  
	After disconnection, the callback will no longer be fired.

	If this connection had a waiting coroutine (created through `Signal:Wait`) 
	and the coroutine is still suspended, it will be cancelled. A warning 
	including a traceback is emitted to aid debugging.

	This method is automatically called for `.Once` connections after firing.

	```lua
	local conn = signal:Connect(function(msg)
		print(msg)
	end)

	conn:Disconnect()
	```
]=]
function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	if self.Thread then
		if coroutine.status(self.Thread) == "suspended" then
			warn(debug.traceback(self.Thread, "signal disconnected; yielded thread cancelled", 2))
			task.cancel(self.Thread)
		end
	end
	self.Previous.Next = self.Next
	self.Next.Previous = self.Previous
end

--[=[
	@method Destroy
	@within Connection

	Alias for `Connection:Disconnect`.  
	Provided for API completeness and parity with common Roblox objects.

	```lua
	conn:Destroy()
	```
]=]
Connection.Destroy = Connection.Disconnect

-- Make Connection strict
setmetatable(Connection, {
	__index = function(_tb, key)
		error(("Attempt to get Connection::%s (not a valid member)"):format(tostring(key)), 2)
	end,
	__newindex = function(_tb, key, _value)
		error(("Attempt to set Connection::%s (not a valid member)"):format(tostring(key)), 2)
	end,
})

--- Signal
local Signal = {}
Signal.__index = Signal

--[=[
	@method new
	@within Signal
	@return Signal
	Constructs a Signal Object
	
	```lua
	local Signal = require(...)
	local sig = Signal.new()
	```
]=]
local function constructor<T...>(): Identity<T...>
	local self = (setmetatable({}, Signal) :: any) :: Identity<T...>
	self.Previous = self :: any
	self.Next = self :: any
	return self :: Identity<T...>
end

--[=[
	@method wrap
	@within Signal
	@param scriptSignal RBXScriptSignal 
	@return Identity<T...>
	Wraps an `RBXScriptSignal` inside this custom Signal implementation.
	Any time the original RBXScriptSignal fires, the wrapped Signal will fire 
	with the same arguments.

	```lua
	local wrapped = Signal.wrap(workspace.ChildAdded)
	wrapped:Connect(function(child)
		print("New child:", child.Name)
	end)
	```
]=]
local function wrap<T...>(scriptSignal: RBXScriptSignal): Identity<T...>
	assert(
		typeof(scriptSignal) == "RBXScriptSignal",
		"Argument #1 to Signal.Wrap must be a RBXScriptSignal; got " .. typeof(scriptSignal)
	)
	local signal = constructor()
	signal.Proxy = scriptSignal:Connect(function(...)
		signal:Fire(...)
	end)
	return (signal :: any) :: Identity<T...>
end

--[=[
	@method Wait
	@within Signal
	@return T...
	Yields the current thread until the signal fires.
	This is functionally similar to `RBXScriptSignal:Wait()`.  
	When the signal fires, the yielded thread is resumed with the fired values.
	Internally, a temporary `.Once` connection is created.  
	If this connection is disconnected before firing, the waiting thread is cancelled.

	```lua
	local a, b = signal:Wait()
	print("Signal fired with:", a, b)
	```
]=]
function Signal:Wait<T...>()
	local connection = (setmetatable({}, Connection) :: any) :: Connection<T...>
	connection.Previous = self.Previous
	connection.Next = self :: any
	connection.Once = true
	connection.Connected = true
	connection.Thread = coroutine.running()
	self.Previous.Next = connection
	self.Previous = connection
	return coroutine.yield()
end

--[=[
	@method Fire
	@within Signal
	@param T... any
	Invokes all connected callbacks with the provided arguments.
	- `.Once` connections are automatically disconnected after being fired.
	- Callbacks are scheduled using `TaskSchedule:defer` for functions, or 
	  `task.spawn` for coroutine-based waits (`Signal:Wait`).
	- Ensures safe iteration even if callbacks disconnect during firing.

	```lua
	signal:Fire(10, 20)
	```
]=]
function Signal:Fire<T...>(...: T...)
	local connection = self.Next :: Connection<T...>
	while connection ~= self :: any do
		local nextConnection = connection.Next :: Connection<T...>
		if connection.Connected then
			if connection.Function then
				Task:defer(connection.Function, ...)
			else
				task.spawn(connection.Thread, ...)
			end
			if connection.Once then
				connection:Disconnect()
			end
		end
		connection = nextConnection
	end
end

--[=[
	@method Once
	@within Signal
	@param callback Func<T...>
	@return Connection<T...>
	Connects a callback that will fire exactly once.  
	After the callback runs, the connection automatically disconnects.

	```lua
	signal:Once(function(msg)
		print("Received once:", msg)
	end)
	```
]=]
function Signal:Once<T...>(func: (...any) -> ())
	local connection = (setmetatable({}, Connection) :: any) :: Connection<T...>
	connection.Previous = self.Previous
	connection.Next = self :: any
	connection.Once = true
	connection.Connected = true
	connection.Function = func
	self.Previous.Next = connection
	self.Previous = connection
	return connection
end

--[=[
	@method Connect
	@within Signal
	@param callback Func<T...>
	@return Connection<T...>
	Connects a persistent callback which fires every time the signal is fired.
	Returns a connection object that can later be disconnected or destroyed.

	```lua
	local conn = signal:Connect(function(x)
		print("Fired:", x)
	end)
	```
]=]

function Signal:Connect<T...>(func: (...any) -> ())
	local connection = (setmetatable({}, Connection) :: any) :: Connection<T...>
	connection.Previous = self.Previous
	connection.Next = self :: any
	connection.Once = false
	connection.Connected = true
	connection.Function = func
	self.Previous.Next = connection
	self.Previous = connection
	return connection
end

--[=[
	@method DisconnectAll
	@within Signal
	Disconnects every active connection from this signal.
	Any pending coroutine from `Wait()` is cancelled.  
	This fully resets the internal linked list of connections.

	```lua
	signal:DisconnectAll()
	```
]=]
function Signal:DisconnectAll<T...>()
	local connection = self.Next :: Connection<T...>

	while connection ~= self :: any do
		local nextConnection = connection.Next
		if connection.Connected then
			connection:Disconnect()
		end
		connection = nextConnection
	end

	self.Next = self
	self.Previous = self
end

--[=[
	@method Destroy
	@within Signal
	Permanently destroys the signal.
	- Disconnects all listeners  
	- Disconnects any wrapped RBXScriptSignal proxy  
	- Replaces all methods with error-throwing stubs  
	- Prevents mutation of the destroyed signal  
	After destruction, firing or connecting will throw an error.

	```lua
	signal:Destroy()
	signal:Fire() -- error
	```
]=]
function Signal:Destroy<T...>()
	self:DisconnectAll()
	local proxyHandler = rawget(self, "Proxy") :: RBXScriptConnection?
	if proxyHandler and proxyHandler.Connected then
		proxyHandler:Disconnect()
	end
	setmetatable(self, {
		__index = error_signal,
		__newindex = function()
			error("Attempt to modify a destroyed signal", 2)
		end,
	})
end

--- Make signal Strict
setmetatable(Signal, {
	__index = function(_tb, key)
		error(("Attempt to get Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end,
	__newindex = function(_tb, key, _value)
		error(("Attempt to set Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end,
})

return {
	new = constructor,
	wrap = wrap,
}
