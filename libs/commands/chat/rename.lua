local locale = require "locale"
local guilds = require "storage/guilds"
local channels = require "storage/channels"

local hostCheck = require "funcs/hostCheck"
local hostPermissionCheck = require "funcs/hostPermissionCheck"
local templateInterpreter = require "funcs/templateInterpreter"
local ratelimiter = require "utils/ratelimiter"

ratelimiter("companionName", 2, 60*10)

return function (message, chat, name)
	local channel = hostCheck(message)
	if not channel then
		return "Not a host", "warning", locale.notHost
	end
	
	local isPermitted = hostPermissionCheck(message.member, channel, "rename")
	if not isPermitted then
		return "Insufficient permissions", "warning", locale.badHostPermission
	end
	
	local limit, retryIn = ratelimiter:limit("companionName", chat.id)
	local success, err
	
	if limit == -1 then
		return "Ratelimit reached", "warning", locale.ratelimitReached:format(retryIn)
	else
		local channelData, guildData = channels[channel.id], guilds[channel.guild.id]
		if channelData.parent and channelData.parent.companionTemplate and channelData.parent.companionTemplate:match("%%rename%%") then
			success, err = chat:setName(templateInterpreter(channelData.parent.companionTemplate, message.member, channelData.position, name):discordify())
		elseif guildData.companionTemplate and guildData.companionTemplate:match("%%rename%%") then
			success, err = chat:setName(templateInterpreter(guildData.companionTemplate, message.member, channelData.position, name):discordify())
		else
			success, err = chat:setName(name:discordify())
		end
	end
	
	if success then
		return "Successfully changed chat name", "ok", locale.nameConfirm:format(chat.name).."\n"..locale[limit == 0 and "ratelimitReached" or "ratelimitRemaining"]:format(retryIn)
	else
		return "Couldn't change chat name: "..err, "warning", locale.hostError
	end
end