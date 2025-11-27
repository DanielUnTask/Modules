--!strict
--!optimize 2

--[[
   A lightweight, strictly-typed custom signal implementation.
   Supports one-shot and persistent connections, yielding waits, RBXScriptSignal wrapping,
   and strict behavior for safer development.

   Signal.new() -> Signal
   Signal.wrap(RBXScriptSignal) -> Signal


   Signal Methods:
    - Signal:Connect(func) -> Connection
    - Signal:Once(func) -> Connection
    - Signal:Wait() -> ...arguments
    - Signal:Fire(...)
    - Signal:DisconnectAll()
    - Signal:Destroy()


   Connection Methods:
    - Connection:Disconnect()
    - Connection:Destroy() (alias)


   Connections have these fields:
    - Connected: boolean
    - Once: boolean
    - Function: callback
    - Thread: coroutine thread (for :Wait)


   ::warnings::
     * Destroyed signals cannot be fired or connected.
     * Uses a doubly-linked list for efficient connection traversal.
     * TaskSchedule is used for deferred execution when available.
]]

--- Requires
local TaskSchedule = require(script.Parent.TaskSchedule)

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
	@interface Func
	@within Signal
	
	Represents a strongly typed callback function.
	Receives variadic arguments of type `T...` and returns no results.

	::notes::
	 - Callbacks must *not* yield unless explicitly intended.
	 - Any error thrown by the callback propagates to the scheduler executing it.
	 - If used in combination with `Signal:Wait()`, it is mutually exclusive 
	  (a connection cannot have both Function and Thread fields set).

	Example:
	```lua
	local function onEvent(a: number, b: string)
		print(a, b)
	end
	```
]=]
type Func<T...> = (T...) -> ()

--[=[
	@interface StaticSignal
	@within Signal

	Internal doubly-linked list node used by the Signal system.
	You should never construct or modify this manually.

	::fields::
	 - Proxy: RBXScriptConnection?
	  Used only when wrapping a RBXScriptSignal.

	 - Next: Connection<T...>
	 - Previous: Connection<T...>
	   Pointers of the circular linked list used to store active connections.

	::warning::
	 - These fields are considered internal and must never be relied upon externally.
	 - Modifying these fields directly breaks the integrity of the signal system.
]=]
type StaticSignal<T...> = {
	Proxy: RBXScriptConnection?,
	Next: Connection<T...>,
	Previous: Connection<T...>,
}

--[=[
	@interface StaticConnection
	@within Signal

	Internal shared layout of every connection object.

	::fields::
	 - Connected: boolean  
	   Indicates if this connection is currently active.

	 - Once: boolean  
	   Whether the connection auto-disconnects after first Fire.

	 - Thread: thread?  
	   Contains a coroutine **only** when created by `Signal:Wait()`.
	   If present, `.Function` will be nil.

	 - Function: Func<T...>?  
	   Callback invoked for normal `Connect` or `Once` listeners.
	   If present, `.Thread` will be nil.

	::warning::
	 - A StaticConnection is either a callback *or* a waiting coroutine—never both.
	 - Invalid manual changes to these fields may cause hard-to-debug issues.
]=]
type StaticConnection<T... = ()> = {
	Once: boolean,
	Connected: boolean,

	Thread: thread,
	Function: Func<T...>,
}

--[=[
	@interface Identity
	@within Signal

	The public-facing Signal type.

	Exposes all runtime operations available to consumers while
	embedding the internal linked-list structure.

	Methods:
	 - Wait(): T...
	 - Fire(...: T...)
	 - Connect(callback): Connection
	 - Once(callback): Connection
	 - DisconnectAll()
	 - Destroy()

	::warning::
	 - After destruction, *all* method calls throw errors.
	 - A destroyed signal cannot be restored.
	 - Do not store the Signal table itself inside the callbacks you connect 
	   unless intentionally creating self-references.
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
	@interface Connection
	@within Signal

	Public wrapper for an internal connection node.

	Strict object:
	 - Unknown property access throws an error.
	 - Unknown assignment throws an error.

	Methods:
	 - Disconnect()
	 - Destroy() — alias of Disconnect()

	::warnings::
	 - Once a Connection is disconnected, it cannot be reused.
	 - Storing references to disconnected connections is safe but not useful.
]=]
export type Connection<T... = ()> = StaticSignal<T...> & StaticConnection<T...> & {
	Destroy: (self: Connection<T...>) -> (),
	Disconnect: (self: Connection<T...>) -> (),
}

--- Connection

local Connection = {}
Connection.__index = Connection

--[=[
	Disconnects this connection from its parent Signal.

	Calling `Disconnect()` multiple times is safe;  
	subsequent calls have no effect.
]=]
function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	self.Previous.Next = self.Next
	self.Next.Previous = self.Previous
end

--[=[
	Alias de `Connection:Disconnect()`.

	Behaves identically to `Disconnect()`.  
	Provided for API parity and readability when explicitly destroying a connection.
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
	Creates and returns a new Signal object.
	
	@return Signal<T...> — A new strictly-typed signal instance.

	Example:
	```lua
	local signal = Signal.new()
	```
]=]
local function constructor<T...>(): Identity<T...>
	local self = (setmetatable({}, Signal) :: any) :: Identity<T...>
	self.Previous = self :: any
	self.Next = self :: any
	return self :: any
end

--[=[
	Wraps `RBXScriptSignal` into a custom Signal instance.
	The wrapped signal will fire whenever the original event fires.

	@param scriptSignal RBXScriptSignal -- The event to wrap.
	@return Signal<T...> -- A new signal instance wrapping the given RBXScriptSignal. 
	
	::warning::
	Throws if the argument is not an `RBXScriptSignal`.

	Example:
	```lua
	local s = Signal.wrap(workspace.ChildAdded)
	s:Connect(function(child)
		print("Added:", child)
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
	Yields the current thread until the signal fires once.

	Returns the arguments passed to the next call of `:Fire()`.

	@return T...

	::warnings::
	 - :Wait() - creates a hidden one-shot connection. If the signal is destroyed 
	   before firing, the thread will remain suspended forever.
	 - Avoid calling `:Wait()` inside performance-critical code paths 
	   (e.g., in Heartbeat) to prevent coroutine buildup.
	 - Yielding inside callbacks or schedulers may cause deadlocks 
	   if misused with `Wait()`.

	Example:
	```lua
	task.spawn(function()
		print("Waiting...")
		local a, b = MySignal:Wait()
		print("Got:", a, b)
	end)

	MySignal:Fire(10, "hello")
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
	Fires the signal and invokes all connected callbacks.

	@param ... T... — Arguments forwarded to all listeners.

	::notes::
	* Connections flagged as `.Once` are automatically disconnected.
	* `Signal:Wait()` listeners are resumed instead of invoking a function.
	* Callbacks are executed via `TaskSchedule:defer` when available.

	Example:
	```lua
	signal:Fire('Daniel', Vector3.zero)
	```
]=]
function Signal:Fire<T...>(...: T...)
	local connection = self.Next
	while connection ~= self do
		local nextConnection = connection.Next :: Connection<T...>
		if connection.Connected then
			if connection.Function then
				TaskSchedule:defer(connection.Function, ...)
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
	Connects a callback to the signal that will run once, then disconnect.

	@param func Func<T...> — Callback invoked on next `:Fire()`.
	@return Connection<T...> — The resulting one-shot connection.

	Example:
	```lua
	signal:Once(function()
		print("This prints only once!")
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
	Connects a persistent listener to the signal.
	Callback runs every time `:Fire()` is invoked.

	@param func Func<T...> — Listener to register.
	@return Connection<T...> — A Connection object controlling this listener.

	Example:
	```lua
	local conn = signal:Connect(function(x)
		print("Received:", x)
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
	Disconnects *all* active connections on this signal.

	Does not destroy the signal itself;  
	after calling this, the signal behaves as if freshly created.

	Example:
	```lua
	signal:DisconnectAll()
	```
]=]
function Signal:DisconnectAll<T...>()
	local connection = self.Next

	while connection ~= self do
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
	Permanently destroys the signal.

	After destruction:
	 - All existing connections are disconnected.
	 - Wrapped RBXScriptSignals are disconnected.
	 - All public methods (Connect, Once, Wait, Fire, etc.) throw errors.

	::warnings::
	 -  Destroyed signals cannot be fired or connected — any attempt throws.
	 -  Do NOT store a destroyed signal in tables or global state; calls on it will fail.
	 -  Calling Destroy() multiple times is safe, but only the first has effect.
	 -  If a coroutine is waiting via `Wait()`, it will stay suspended forever.

	Example:
	```lua
	signal:Destroy()
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
