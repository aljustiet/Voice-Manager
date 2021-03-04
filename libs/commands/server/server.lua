local locale = require "locale"
local permissionCheck = require "funcs/permissionCheck"
local permission = require "discordia".enums.permission

local subcommands = {
	role = require "commands/server/role",
	limit = require "commands/server/limit",
	permissions = require "commands/server/permissions",
	prefix = require "commands/server/prefix"
}

return function (message)
	if not message.member:hasPermission(permission.manageChannels) then
		return "Bad user permissions", "warning", locale.badPermissions
	end
	
	local subcommand, argument = message.content:match("server%s*(%a*)%s*(.-)$")
	
	if subcommand == "" or argument == "" then
		return "Sent server info", "serverInfo", message.guild
	end
	
	local isPermitted, logMsg, userMsg = permissionCheck(message, lobby)
	if not isPermitted then
		return logMsg, "warning", userMsg
	end
	
	if subcommands[subcommand] then
		return subcommands[subcommand](message, argument)
	else
		return "Bad server subcommand", "warning", locale.badSubcommand
	end
end