local client = require "client"
local locale = require "locale"
local config = require "config"

local guilds = require "storage/guilds"
local channels = require "storage/channels"

local okEmbed = require "embeds/ok"
local warningEmbed = require "embeds/warning"
local chatInfoEmbed = require "embeds/chatInfo"

local hostPermissionCheck = require "funcs/hostPermissionCheck"
local templateInterpreter = require "funcs/templateInterpreter"
local ratelimiter = require "utils/ratelimiter"

local permission = require "discordia".enums.permission

local subcommands = {
	rename = function (interaction, chat, name)
		local limit, retryIn = ratelimiter:limit("companionName", chat.id)
		local success, err

		if limit == -1 then
			return "Ratelimit reached", warningEmbed(locale.ratelimitReached:format(retryIn))
		else
			local channelData, guildData = channels[interaction.member.voiceChannel.id], guilds[interaction.guild.id]
			if channelData.parent and channelData.parent.companionTemplate and channelData.parent.companionTemplate:match("%%rename%%") then
				success, err = chat:setName(templateInterpreter(channelData.parent.companionTemplate, interaction.member, channelData.position, name):discordify())
			elseif guildData.companionTemplate and guildData.companionTemplate:match("%%rename%%") then
				success, err = chat:setName(templateInterpreter(guildData.companionTemplate, interaction.member, channelData.position, name):discordify())
			else
				success, err = chat:setName(name:discordify())
			end
		end

		if success then
			return "Successfully changed chat name", okEmbed(locale.nameConfirm:format(chat.name).."\n"..locale[limit == 0 and "ratelimitReached" or "ratelimitRemaining"]:format(retryIn))
		else
			return "Couldn't change chat name: "..err, warningEmbed(locale.renameError)
		end
	end,

	hide = function (interaction, chat, user)
		chat:getPermissionOverwriteFor(chat.guild:getMember(user)):denyPermissions(permission.readMessages)
		return "Hidden the chat from user", okEmbed(locale.hideConfirm:format(user.mentionString))
	end,

	show = function (interaction, chat, user)
		chat:getPermissionOverwriteFor(chat.guild:getMember(user)):allowPermissions(permission.readMessages)
		return "Made the chat visible to user", okEmbed(locale.showConfirm:format(user.mentionString))
	end,

	mute = function (interaction, chat, user)
		chat:getPermissionOverwriteFor(chat.guild:getMember(user)):denyPermissions(permission.sendMessages)
		return "Muted mentioned members", okEmbed(locale.hideConfirm:format(user.mentionString))
	end,

	unmute = function (interaction, chat, user)
		chat:getPermissionOverwriteFor(chat.guild:getMember(user)):clearPermissions(permission.sendMessages)
		return "Unmuted mentioned members", okEmbed(locale.showConfirm:format(user.mentionString))
	end,

	clear = function (interaction, chat, amount)
		local trueAmount = 0

		if amount then
			repeat
				local bulk = chat:getMessages(amount > 100 and 100 or amount)
				trueAmount = trueAmount + #bulk
				chat:bulkDelete(bulk)
				amount = amount > 100 and amount - 100 or 0
			until amount == 0
		else
			local first = chat:getFirstMessage()
			repeat
				local bulk = chat:getMessagesAfter(first, 100)
				if #bulk == 0 then
					chat:bulkDelete({first})
					trueAmount = trueAmount + 1
					break
				else
					chat:bulkDelete(bulk)
					trueAmount = trueAmount + #bulk
				end
			until false
		end

		return "Successfully cleared "..trueAmount.." messages", okEmbed(locale.clearConfirm:format(trueAmount))
	end,

	save = function (interaction, chat, amount)
		return "unfinished", warningEmbed(locale.unfinishedCommand)
	end
}

return function (interaction, subcommand, argument)
	local voiceChannel = interaction.member.voiceChannel

	if not channels[voiceChannel.id] then
		return "User not in room", warningEmbed(locale.notInRoom)
	end

	if subcommand == "view" then
		return "Sent room info", chatInfoEmbed(voiceChannel)
	end

	local chat = client:getChannel(channels[voiceChannel.id].companion)
	if not chat then
		return "Room doesn't have a chat", warningEmbed(locale.noCompanion)
	end

	if interaction.member:hasPermission(chat, permission.administrator) or config.owners[interaction.user.id] then
		return subcommands[subcommand](interaction, chat, argument)
	elseif channels[voiceChannel.id].host == interaction.author.id then
		if hostPermissionCheck(interaction.member, voiceChannel, subcommand) then
			return subcommands[subcommand](interaction, chat, argument)
		end
		return "Not a host", warningEmbed(locale.notHost)
	end
	return "Insufficient permissions", warningEmbed(locale.badHostPermission)
end
