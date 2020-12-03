local discordia = require "discordia"
local locale = require "locale"
local lobbies = require "storage/lobbies"

local client = discordia.storage.client
local permission = discordia.enums.permission
local channelType = discordia.enums.channelType
local commandParse = require "commands/commandParse"
local commandFinalize = require "commands/commandFinalize"

-- this function is also used by embeds, they will supply ids and target
return function (message, ids, target)
	if not ids then
		target = message.content:match('target%s*".-"%s*(.-)$') or message.content:match('target%s*(.-)$')
		
		local potentialTarget = client:getChannel(target)
		if potentialTarget and potentialTarget.type ~= channelType.voice and potentialTarget ~= channelType.category then
			potentialTarget = nil
		elseif not potentialTarget then
			if not message.guild then
				message:reply(locale.noID)
				return "Target by name in dm"
			end
			
			local categories = message.guild.categories:toArray("position", function (category) return category.name:lower() == target:lower() end)
			local localLobbies = message.guild.voiceChannels:toArray("position", function (channel) return lobbies[channel.id] and channel.name:lower() == target:lower() end)
			
			potentialTarget = categories[1] or localLobbies[1]
			target = potentialTarget and potentialTarget.id or ""
		end
		
		if potentialTarget then
			if potentialTarget.type == channelType.voice and lobbies[target].target and client:getChannel(lobbies[target].target).type == channelType.voice then
				message:reply(locale.badTarget.." "..potentialTarget.name)
				return "Target is matchmaking lobby"
			end
			
			if not potentialTarget.guild:getMember(message.author):hasPermission(potentialTarget, permission.manageChannels) then
				message:reply(locale.badUserPermission.." "..potentialTarget.name)
				return "User doesn't have permission to manage the target"
			end
			
			if not potentialTarget.guild.me:hasPermission(potentialTarget, permission.manageChannels) then
				message:reply(locale.badBotPermission.." "..potentialTarget.name)
				return "Bot doesn't have permission to manage the target"
			end
		end
		
		ids = commandParse(message, message.content:match('"(.-)"'), "target", target)
		if not ids[1] then return ids end -- message for logger
	end
	
	return commandFinalize.target(message, ids, target)
end