local locale = require "locale"
local guilds = require "storage/guilds"
local botPermissions = require "utils/botPermissions"

return function (message, permissions)
	local permissionBits = botPermissions()
	
	for permission in permissions:gmatch("%a+") do
		if permissionBits.bits[permission] then
			permissionBits.bitfield = permissionBits.bitfield + permissionBits.bits[permission]
		elseif not (permission == "allow" or permission == "deny") then
			return "Unknown permission provided", "warning", locale.permissionsBadInput:format(permission)
		end
	end
	
	local guildData = guilds[message.guild.id]
	if message.content:match("allow") then
		permissionBits = guildData.permissions + permissionBits
	elseif message.content:match("deny") then
		permissionBits = guildData.permissions - permissionBits
	end
	
	guildData:setPermissions(permissionBits)
	return "Server permissions set", "warning", locale.permissionsConfirm
end