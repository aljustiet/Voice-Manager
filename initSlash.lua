local https = require "coro-http"
local json = require "json"
local token = "Bot "..require "token".token
local timer = require "timer"

--local id = "601347755046076427" -- vm
local id = "676787135650463764" -- rat
local guild = "669676999211483144"

local domain = "https://discord.com/api/v8"
local GLOBAL_COMMANDS = string.format("%s/applications/%s/commands", domain, id)
local GLOBAL_COMMAND = string.format("%s/applications/%s/commands/%s", domain, id,"%s")
local GUILD_COMMANDS = string.format("%s/applications/%s/guilds/%s/commands", domain, id, "%s")
local GUILD_COMMAND = string.format("%s/applications/%s/guilds/%s/commands/%s", domain, id, "%s", "%s")

local printf = function (...)
	print(string.format(...))
end

local function parseErrors(ret, errors, key)
	for k, v in pairs(errors) do
		if k == '_errors' then
			for _, err in ipairs(v) do
				table.insert(ret, string.format('%s in %s : %s', err.code, key or 'payload', err.message))
			end
		else
			if key then
				parseErrors(ret, v, string.format(k:find("^[%a_][%a%d_]*$") and '%s.%s' or tonumber(k) and '%s[%d]' or '%s[%q]', key, k))
			else
				parseErrors(ret, v, k)
			end
		end
	end
	return table.concat(ret, '\n\t')
end

local function request (method, url, payload, retries)
	local success, res, msg = pcall(https.request, method, url,
		{{"Authorization", token},{"Content-Type", "application/json"},{"Accept", "application/json"}}, payload and json.encode(payload))
	local delay, maxRetries = 300, 5
	retries = retries or 0

	if not success then
		return nil, res
	end

	for i, v in ipairs(res) do
		res[v[1]:lower()] = v[2]
		res[i] = nil
	end

	if res['x-ratelimit-remaining'] == '0' then
		delay = math.max(1000 * res['x-ratelimit-reset-after'], delay)
	end

	local data = json.decode(msg, 1, json.null)

	if res.code < 300 then
		printf('SUCCESS : %i - %s : %s %s', res.code, res.reason, method, url)
		return data or true, nil
	else
		if type(data) == 'table' then

			local retry
			if res.code == 429 then -- TODO: global ratelimiting
				delay = data.retry_after*1000
				retry = retries < maxRetries
			elseif res.code == 502 then
				delay = delay + math.random(2000)
				retry = retries < maxRetries
			end

			if retry then
				printf('WARNING : %i - %s : retrying after %i ms : %s %s', res.code, res.reason, delay, method, url)
				timer.sleep(delay)
				return request(method, url, payload, retries + 1)
			end

			if data.code and data.message then
				msg = string.format('HTTP ERROR %i : %s', data.code, data.message)
			else
				msg = 'HTTP ERROR'
			end
			if data.errors then
				msg = parseErrors({msg}, data.errors)
			end

			printf('ERROR : %i - %s : %s %s', res.code, res.reason, method, url)
			return nil, msg, delay
		end
	end
end

local CommandManager = {
	commandType = {
		"chatInput","user","message",
		chatInput = 1,
		user = 2,
		message = 3
	},
	commandOptionType = {
		"subcommand","subcommandGroup","string","integer","boolean","user","channel","role","mentionable","number",
		subcommand = 1,
		subcommandGroup = 2,
		string = 3,
		integer = 4,
		boolean = 5,
		user = 6,
		channel = 7,
		role = 8,
		mentionable = 9,
		number = 10
	}
}

function CommandManager.getGlobalCommands ()
	return request("GET", GLOBAL_COMMANDS)
end

function CommandManager.getGlobalCommand (id)
	return request("GET", GLOBAL_COMMAND:format(id))
end

function CommandManager.createGlobalCommand (payload)
	return request("POST", GLOBAL_COMMANDS, payload)
end

function CommandManager.editGlobalCommand (id, payload)
	return request("PATCH", GLOBAL_COMMAND:format(id), payload)
end

function CommandManager.editGlobalCommands (payload)
	return request("PATCH", GLOBAL_COMMANDS, payload)
end

function CommandManager.deleteGlobalCommand (id)
	return request("DELETE", GLOBAL_COMMAND:format(id))
end

function CommandManager.overwriteGlobalCommands(payload)
	return request("PUT", GLOBAL_COMMANDS)
end

function CommandManager.getGuildCommands (guild)
	return request("GET", GUILD_COMMANDS:format(guild))
end

function CommandManager.getGuildCommand (guild, id)
	return request("GET", GUILD_COMMAND:format(guild, id))
end

function CommandManager.createGuildCommand (guild, payload)
	return request("POST", GUILD_COMMANDS:format(guild), payload)
end

function CommandManager.editGuildCommand (guild, id, payload)
	return request("PATCH", GUILD_COMMAND:format(guild, id), payload)
end

function CommandManager.editGuildCommands (guild, payload)
	return request("PATCH", GUILD_COMMANDS:format(guild), payload)
end

function CommandManager.deleteGuildCommand (guild, id)
	return request("DELETE", GUILD_COMMAND:format(guild, id))
end

function CommandManager.overwriteGuildCommands(guild, payload)
	return request("PUT", GUILD_COMMANDS)
end

local channelType = require "discordia".enums.channelType
local commandType = CommandManager.commandType
local commandOptionType = CommandManager.commandOptionType

local commandsStructure = {
	{
		name = "help",
		description = "A help command!",
		options = {
			{
				name = "article",
				description = "Which help article do you need?",
				type = commandOptionType.string,
				choices = {
					{
						name = "lobby",
						value = "lobby"
					},
					{
						name = "matchmaking",
						value = "matchmaking"
					},
					{
						name = "companion",
						value = "companion"
					},
					{
						name = "room",
						value = "room"
					},
					{
						name = "chat",
						value = "chat"
					},
					{
						name = "server",
						value = "server"
					},
					{
						name = "misc",
						value = "misc"
					}
				}
			}
		}
	},
	{
		name = "view",
		description = "Show registered lobbies",
		options = {
			{
				name = "lobby",
				description = "A lobby to be viewed",
				type = commandOptionType.channel,
				channel_types = {
					channelType.voice
				}
			}
		}
	},
	{
		name = "lobby",
		description = "Configure lobby settings",
		options = {
			{
				name = "view",
				description = "Show registered lobbies",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "lobby",
						description = "A lobby to be viewed",
						type = commandOptionType.channel,
						channel_types = {
							channelType.voice
						}
					}
				}
			},
			{
				name = "add",
				description = "Register a new lobby",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "channel",
						description = "A channel to be registered",
						type = commandOptionType.channel,
						required = true,
						channel_types = {
							channelType.voice
						}
					}
				}
			},
			{
				name = "remove",
				description = "Remove an existing lobby",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "lobby",
						description = "A lobby to be removed",
						type = commandOptionType.channel,
						required = true,
						channel_types = {
							channelType.voice
						}
					}
				}
			},
			{
				name = "name",
				description = "Configure what name a room will have when it's created",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "name",
						description = "Name a room will have when it's created",
						type = commandOptionType.string
					}
				}
			},
			{
				name = "category",
				description = "Select a category in which rooms will be created",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "category",
						description = "Category in which rooms will be created",
						type = commandOptionType.channel,
						channel_types = {
							channelType.category
						}
					}
				}
			},
			{
				name = "bitrate",
				description = "Select new rooms' bitrate",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "bitrate",
						description = "New rooms' bitrate",
						type = commandOptionType.integer,
						min_value = 8,
						max_value = 384
					}
				}
			},
			{
				name = "capacity",
				description = "Select new rooms' capacity",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "capacity",
						description = "New rooms' capacity",
						type = commandOptionType.integer,
						min_value = 0,
						max_value = 99
					}
				}
			},
			{
				name = "permissions",
				description = "Give room hosts' access to different commands",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "moderate",
						description = "Permission to use moderation commands",
						type = commandOptionType.boolean
					},
					{
						name = "manage",
						description = "Permission to manage room properties",
						type = commandOptionType.boolean
					},
					{
						name = "rename",
						description = "Permission to rename room",
						type = commandOptionType.boolean
					},
					{
						name = "resize",
						description = "Permission to change room capacity",
						type = commandOptionType.boolean
					},
					{
						name = "bitrate",
						description = "Permission to change room bitrate",
						type = commandOptionType.boolean
					},
					{
						name = "mute",
						description = "Permission to mute users in room",
						type = commandOptionType.boolean
					}
				}
			},
			{
				name = "role",
				description = "Change the default role bot uses to manage user permissions",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "role",
						description = "The default role bot uses to manage user permissions",
						type = commandOptionType.role
					}
				}
			}
		}
	},
	{
		name = "matchmaking",
		description = "Configure matchmaking lobby settings",
		options = {
			{
				name = "view",
				description = "Show registered matchmaking lobbies",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "lobby",
						description = "A lobby to be viewed",
						type = commandOptionType.channel,
						channel_types = {
							channelType.voice
						}
					}
				}
			},
			{
				name = "add",
				description = "Register a new matchmaking lobby",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "channel",
						description = "A channel to be registered",
						type = commandOptionType.channel,
						required = true,
						channel_types = {
							channelType.voice
						}
					}
				}
			},
			{
				name = "remove",
				description = "Remove an existing matchmaking lobby",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "lobby",
						description = "A matchmaking lobby to be removed",
						type = commandOptionType.channel,
						required = true,
						channel_types = {
							channelType.voice
						}
					}
				}
			},
			{
				name = "target",
				description = "Select a target for matchmaking pool",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "target",
						description = "A target for matchmaking pool",
						type = commandOptionType.channel,
						channel_types = {
							channelType.voice, channelType.category
						}
					}
				}
			},
			{
				name = "mode",
				description = "Select the matchmaking mode",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "mode",
						description = "A matchmaking mode",
						type = commandOptionType.string,
						choices = {
							{
								name = "random",
								value = "random"
							},
							{
								name = "max",
								value = "max"
							},
							{
								name = "min",
								value = "min"
							},
							{
								name = "first",
								value = "first"
							},
							{
								name = "last",
								value = "last"
							}
						}
					}
				}
			}
		}
	},
	{
		name = "companion",
		description = "Configure lobby companion settings",
		options = {
			{
				name = "view",
				description = "Show lobbies with enabled companion chats",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "lobby",
						description = "A lobby to be viewed",
						type = commandOptionType.channel,
						channel_types = {
							channelType.voice
						}
					}
				}
			},
			{
				name = "enable",
				description = "Enable companion chats for selected lobby",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "lobby",
						description = "Selected lobby",
						type = commandOptionType.channel,
						required = true,
						channel_types = {
							channelType.voice
						}
					},
					{
						name = "enabled",
						description = "Enable or disable",
						type = commandOptionType.boolean,
						required = true
					}
				}
			},
			{
				name = "category",
				description = "Select a category in which a companion chat will be created",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "category",
						description = "A category in which a companion chat will be created",
						type = commandOptionType.channel,
						channel_types = {
							channelType.category
						}
					}
				}
			},
			{
				name = "name",
				description = "Configure what name a chat will have when it's created",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "name",
						description = "Name a chat will have when it's created",
						type = commandOptionType.string
					}
				}
			},
			{
				name = "greeting",
				description = "Configure a message that will be automatically sent to chat when it's created",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "greeting",
						description = "A message that will be automatically sent to chat when it's created",
						type = commandOptionType.string
					}
				}
			},
			{
				name = "log",
				description = "Enable chat logging. Logs will be sent as files to a channel of your choosing",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "channel",
						description = "A channel where logs will be sent",
						type = commandOptionType.channel,
						channel_types = {
							channelType.text
						}
					}
				}
			}
		}
	},
	{
		name = "server",
		description = "Configure server settings",
		options = {
			{
				name = "view",
				description = "Show server settings",
				type = commandOptionType.subcommand
			},
			{
				name = "limit",
				description = "Configure the global limit of channels created by the bot",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "limit",
						description = "Maximum amount of channels the bot will create",
						type = commandOptionType.integer,
							min_value = 0,
							max_value = 500
					}
				}
			},
			{
				name = "permissions",
				description = "Give people in voice channels access to different commands",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "moderate",
						description = "Permission to use moderation commands",
						type = commandOptionType.boolean
					},
					{
						name = "manage",
						description = "Permission to manage room properties",
						type = commandOptionType.boolean
					},
					{
						name = "rename",
						description = "Permission to rename their room",
						type = commandOptionType.boolean
					},
					{
						name = "resize",
						description = "Permission to change room capacity",
						type = commandOptionType.boolean
					},
					{
						name = "bitrate",
						description = "Permission to change room bitrate",
						type = commandOptionType.boolean
					},
					{
						name = "mute",
						description = "Permission to mute users in their room",
						type = commandOptionType.boolean
					}
				}
			},
			{
				name = "role",
				description = "Change the default role bot uses to manage user permissions",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "role",
						description = "The default role bot uses to manage user permissions",
						type = commandOptionType.role
					}
				}
			}
		}
	},
	{
		name = "room",
		description = "Configure room settings",
		options = {
			{
				name = "view",
				description = "Show room settings",
				type = commandOptionType.subcommand
			},
			{
				name = "host",
				description = "Ping current room host and transfer room ownership",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to transfer ownership to",
						type = commandOptionType.user
					}
				}
			},
			{
				name = "invite",
				description = "Send people an invite to immediately connect to the room",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to send an invite to",
						type = commandOptionType.user
					}
				}
			},
			{
				name = "rename",
				description = "Change the name of the room",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "name",
						description = "New room name",
						type = commandOptionType.string,
						required = true
					}
				}
			},
			{
				name = "resize",
				description = "Change the capacity of the room",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "capacity",
						description = "New room capacity",
						type = commandOptionType.integer,
						min_value = 0,
						max_value = 99,
						required = true
					}
				}
			},
			{
				name = "bitrate",
				description = "Change the bitrate",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "bitrate",
						description = "New room bitrate",
						type = commandOptionType.integer,
						min_value = 8,
						max_value = 384,
						required = true
					}
				}
			},
			{
				name = "mute",
				description = "Mute a user",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to mute",
						type = commandOptionType.user,
						required = true
					}
				}
			},
			{
				name = "unmute",
				description = "Unmute a user",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to unmute",
						type = commandOptionType.user,
						required = true
					}
				}
			},
			{
				name = "kick",
				description = "Kick a user from your room",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to kick",
						type = commandOptionType.user,
						required = true
					}
				}
			},
			{
				name = "blocklist",
				description = "Manage the blocklist in your room",
				type = commandOptionType.subcommandGroup,
				options = {
					{
						name = "view",
						description = "Display your current blocklist",
						type = commandOptionType.subcommand
					},
					{
						name = "add",
						description = "Add users to the blocklist",
						type = commandOptionType.subcommand,
						options = {
							{
								name = "user",
								description = "User that you want to add to blocklist",
								type = commandOptionType.user,
								required = true
							}
						}
					},
					{
						name = "remove",
						description = "Remove users from the blocklist",
						type = commandOptionType.subcommand,
						options = {
							{
								name = "user",
								description = "User that you want to remove from the blocklist",
								type = commandOptionType.user,
								required = true
							}
						}
					},
					{
						name = "clear",
						description = "Clear the blocklist",
						type = commandOptionType.subcommand
					}
				}
			},
			{
				name = "reservations",
				description = "Manage the reservations in your room",
				type = commandOptionType.subcommandGroup,
				options = {
					{
						name = "view",
						description = "Display your current reservations",
						type = commandOptionType.subcommand
					},
					{
						name = "add",
						description = "Reserve a place for a user",
						type = commandOptionType.subcommand,
						options = {
							{
								name = "user",
								description = "User that you want to add to reservations",
								type = commandOptionType.user,
								required = true
							}
						}
					},
					{
						name = "remove",
						description = "Remove a reservation for a user",
						type = commandOptionType.subcommand,
						options = {
							{
								name = "user",
								description = "User that you want to remove from reservations",
								type = commandOptionType.user,
								required = true 
							}
						}
					},
					{
						name = "clear",
						description = "Clear the reservations",
						type = commandOptionType.subcommand
					},
					{
						name = "lock",
						description = "Add all users that are currently in the room to room's reservations",
						type = commandOptionType.subcommand
					}
				}
			}
		}
	},
	{
		name = "chat",
		description = "Configure chat settings",
		options = {
			{
				name = "view",
				description = "Show chat settings",
				type = commandOptionType.subcommand
			},
			{
				name = "rename",
				description = "Change the name of the chat",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "name",
						description = "New chat name",
						type = commandOptionType.string,
						required = true
					}
				}
			},
			{
				name = "mute",
				description = "Mute a user",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to mute",
						type = commandOptionType.user,
						required = true
					}
				}
			},
			{
				name = "unmute",
				description = "Unmute a user",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to unmute",
						type = commandOptionType.user,
						required = true
					}
				}
			},
			{
				name = "hide",
				description = "Hide the chat from mentioned user",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to hide the chat from",
						type = commandOptionType.user,
						required = true
					}
				}
			},
			{
				name = "show",
				description = "Show the chat to mentioned user",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "user",
						description = "User that you want to show the chat to",
						type = commandOptionType.user,
						required = true
					}
				}
			},
			{
				name = "clear",
				description = "Delete messages in the chat",
				type = commandOptionType.subcommand,
				options = {
					{
						name = "amount",
						description = "How many messages to delete",
						type = commandOptionType.integer
					}
				}
			}
		}
	},
	{
		name = "reset",
		description = "Reset bot settings",
		options = {
			{
				name = "lobby",
				description = "Lobby settings",
				type = commandOptionType.subcommandGroup,
				options = {
					{
						name = "name",
						description = "Set new room name to default \"%nickname's room\"",
						type = commandOptionType.subcommand
					},
					{
						name = "category",
						description = "Set new room category to lobby's category",
						type = commandOptionType.subcommand
					},
					{
						name = "bitrate",
						description = "Set new room bitrate to 64",
						type = commandOptionType.subcommand
					},
					{
						name = "capacity",
						description = "Set new room capacity to copy from lobby",
						type = commandOptionType.subcommand
					},
					{
						name = "permissions",
						description = "Disable all room permissions",
						type = commandOptionType.subcommand
					},
					{
						name = "role",
						description = "Reset default managed role to @everyone",
						type = commandOptionType.subcommand
					}
				}
			},
			{
				name = "matchmaking",
				description = "Matchmaking lobby settings",
				type = commandOptionType.subcommandGroup,
				options = {
					{
						name = "target",
						description = "Reset matchmaking target to current category",
						type = commandOptionType.subcommand
					},
					{
						name = "mode",
						description = "Reset matchmaking mode to random",
						type = commandOptionType.subcommand
					}
				}
			},
			{
				name = "companion",
				description = "Lobby companion settings",
				type = commandOptionType.subcommandGroup,
				options = {
					{
						name = "category",
						description = "Reset companion category to use lobby settings",
						type = commandOptionType.subcommand
					},
					{
						name = "name",
						description = "Reset companion name to \"private-chat\"",
						type = commandOptionType.subcommand
					},
					{
						name = "greeting",
						description = "Disable companion greeting",
						type = commandOptionType.subcommand
					},
					{
						name = "log",
						description = "Disable companion logging",
						type = commandOptionType.subcommand
					}
				}
			},
			{
				name = "server",
				description = "Server settings",
				type = commandOptionType.subcommandGroup,
				options = {
					{
						name = "limit",
						description = "Reset channel creation limit to 500 (server max)",
						type = commandOptionType.subcommand
					},
					{
						name = "permissions",
						description = "Disable all global bot permissions",
						type = commandOptionType.subcommand
					},
					{
						name = "role",
						description = "Reset default global managed role to @everyone",
						type = commandOptionType.subcommand
					}
				}
			}
		}
	},
	{
		name = "Invite",
		type = commandType.user
	}
}

coroutine.wrap(function ()
	CommandManager.overwriteGuildCommands(guild,commandsStructure)
end)()

return CommandManager