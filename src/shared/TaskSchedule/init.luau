--!strict
--!optimize 2

--[=[ 
	@class TaskSchedule
	Utility for scheduling, deferring, spawning, and delaying function execution 
	while tracking active coroutine threads. 

	Each time a scheduled function is executed through this module, the current 
	running coroutine is stored internally. Future calls (spawn, delay, defer)
	will attempt to reuse stored threads for efficiency.
]=]
local TaskSchedule = {}
local Threads = {} :: { thread }

--[=[
	@within TaskSchedule
	@method Call
	Executes a function immediately and stores the current coroutine into 
	the internal thread stack.

	@param func (...any) -> () -- Function to execute.
	@param ... any -- Arguments passed to the function.

	```lua
	local scheduler = require(TaskSchedule)
	scheduler.Call(function(message)
		print("Immediate:", message)
	end, "Hello!")
	```
]=]
function TaskSchedule.Call(func: (...any) -> (), ...)
	func(...)
	table.insert(Threads, coroutine.running())
end

--[=[
	@within TaskSchedule
	@method Thread
	Main coroutine loop used internally for thread recycling.
	This yields until a function + args are passed in, which are 
	then executed through `Call`.

	```lua
	task.spawn(function()
		TaskSchedule.Thread()
	end)
	```
]=]
function TaskSchedule.Thread(): thread
	while true do
		TaskSchedule.Call(coroutine.yield())
	end
end

--[=[
	@within TaskSchedule
	@method delay
	Schedules a function to be executed after a duration.  
	Reuses stored coroutine threads when available.

	@param duration number -- Time to wait before executing.
	@param func (...any) -> () -- Function to execute.
	@param ... any -- Arguments passed to the function.
	@return thread -- The created or reused coroutine.

	```lua
	local scheduler = TaskSchedule

	scheduler:delay(1, function()
		print("Executed after 1 second!")
	end)
	```
]=]
function TaskSchedule:delay(duration: number, func: (...any) -> (), ...: any)
	return task.delay(duration, table.remove(Threads) or task.spawn(TaskSchedule.Thread), func, ...)
end

--[=[
	@within TaskSchedule
	@method defer
	Defers execution of a function to the next heartbeat, reusing thread 
	instances when available.

	@param func (...any) -> () -- Function to execute.
	@param ... any -- Arguments passed to the function.
	@return thread -- The created or reused coroutine.

	```lua
	local scheduler = TaskSchedule

	scheduler:defer(function()
		print("Deferred to next Heartbeat")
	end)
	```
]=]
function TaskSchedule:defer(func: (...any) -> (), ...: any)
	return task.defer(table.remove(Threads) or task.spawn(TaskSchedule.Thread), func, ...)
end

--[=[
	@within TaskSchedule
	@method spawn
	Spawns a function immediately on a new or recycled coroutine.

	@param func (...any) -> () -- Function to execute.
	@param ... any -- Arguments passed to the function.
	@return thread -- The created or reused coroutine.

	```lua
	local scheduler = TaskSchedule

	scheduler:spawn(function()
		print("Spawned immediately!")
	end)
	```
]=]
function TaskSchedule:spawn(func: (...any) -> (), ...: any)
	return task.spawn(table.remove(Threads) or task.spawn(TaskSchedule.Thread), func, ...)
end

--[=[
	@interface TaskSchedule
	.defer (self: TaskSchedule, func: (...any) -> (), ...any) -> thread
	.spawn (self: TaskSchedule, func: (...any) -> (), ...any) -> thread
	.delay (self: TaskSchedule, duration: number, func: (...any) -> (), ...any) -> thread
]=]
export type TaskSchedule = {
	defer: (self: TaskSchedule, func: (...any) -> (), ...any) -> thread,
	spawn: (self: TaskSchedule, func: (...any) -> (), ...any) -> thread,
	delay: (self: TaskSchedule, duration: number, func: (...any) -> (), ...any) -> thread,
}

return TaskSchedule :: TaskSchedule
