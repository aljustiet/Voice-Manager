local client = require "discordia".storage.client
local commandParse = require "commands/commandParse"
local commandFinalize = require "commands/commandFinalize"
local locale = require "locale"

-- this function is also used by embeds, they will supply ids and capacity value
return function (message, ids, capacity)
	if not ids then
		capacity = tonumber(message.content:match('capacity%s*".-"%s*(.-)$') or message.content:match("capacity%s*(.-)$"))
		
		if capacity and (capacity > 99 or capacity < -1) then
			message:reply(locale.capacityOOB)
			return "Capacity OOB"
		end
		
		ids = commandParse(message, message.content:match('"(.-)"'), "capacity", capacity)
		if not ids[1] then return ids end -- message for logger
	end
	
	return commandFinalize.capacity(message, ids, capacity)
end