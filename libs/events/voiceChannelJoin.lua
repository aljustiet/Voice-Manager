local discordia = require "discordia"
local client = require "client"
local logger = require "logger"
local guilds = require "storage/guilds"
local lobbies = require "storage/lobbies"
local channels = require "storage/channels"
local matchmakers = require "utils/matchmakers"
local templateInterpreter = require "funcs/templateInterpreter"

local permission = discordia.enums.permission
local channelType = discordia.enums.channelType

local function lobbyJoin (member, lobby)
	logger:log(4, "GUILD %s LOBBY %s: %s joined", lobby.guild.id, lobby.id, member.user.id)
	
	-- parent to which a new channel will be attached
	local target = client:getChannel(lobbies[lobby.id].target) or lobby.category or lobby.guild
	
	-- target is voice channel? nothing to do here!
	if target.type == channelType.voice then
		member:setVoiceChannel()
	end
	
	if guilds[lobby.guild.id].limit <= channels:inGuild(lobby.guild.id) then return end
	
	-- determine new channel name
	local lobbyData = lobbies[lobby.id]
	local name = lobbyData.template or "%nickname's% room"
	-- potential position may change in process of name generation, so rather than query lobby for position several times, reservation is made and used throughout
	local position = lobbyData:attachChild(true)
	local needsMove
	
	if name:match("%%.-%%") then
		needsMove = name:match("%%counter%%") and true
		name = templateInterpreter(name, member, position):match("^%s*(.-)%s*$")
		if name == "" then name = templateInterpreter("%nickname's% room", member) end
	end
	
	local newChannel = target:createVoiceChannel(name)
	
	-- did we fail? statistics say "probably yes!"
	if newChannel then
		member:setVoiceChannel(newChannel.id)
		
		local companion
		if lobbyData.companionTarget then
			local companionTarget = lobbyData.companionTarget == true and (newChannel.category or newChannel.guild) or client:getChannel(lobbyData.companionTarget)
			local name = lobbyData.companionTemplate or "Private chat"
		
			if name:match("%%.-%%") then
				name = templateInterpreter(name, member, position):match("^%s*(.-)%s*$")
				if name == "" then name = "Private chat" end
			end
			
			companion = companionTarget:createTextChannel(name)
		end
		
		channels:add(newChannel.id, member.user.id, lobby.id, position, companion and companion.id or nil)
		lobbyData:attachChild(newChannel.id, position)
		newChannel:setUserLimit(lobbyData.capacity or lobby.userLimit)
		
		local perms = lobbyData.permissions:toDiscordia()
		if #perms ~= 0 and lobby.guild.me:getPermissions(newChannel):has(permission.manageRoles, table.unpack(perms)) then
			newChannel:getPermissionOverwriteFor(member):allowPermissions(table.unpack(perms))
		end
		
		if companion then
			companion:getPermissionOverwriteFor(lobby.guild.me):allowPermissions(permission.readMessages)
			companion:getPermissionOverwriteFor(lobby.guild:getRole(lobbyData.role) or lobby.guild.defaultRole):denyPermissions(permission.readMessages)
			companion:getPermissionOverwriteFor(member):allowPermissions(permission.readMessages)
			
			local perms = lobbyData.permissions:toDiscordia()
			if #perms ~= 0 and lobby.guild.me:getPermissions(companion):has(permission.manageRoles, table.unpack(perms)) then
				companion:getPermissionOverwriteFor(member):allowPermissions(table.unpack(perms))
			end
		end
		
		if needsMove then
			local children, distance = lobbyData.children, 0
			repeat
				distance = distance + 1
				if children[position + distance] ~= nil and not client:getChannel(children[position + distance]) then
					children:drain(position + distance)
				end
			until children[position + distance] ~= nil or position + distance > children.max
			if position + distance <= children.max then
				newChannel:moveUp(newChannel.position - client:getChannel(children[position + distance]).position)
			end
		end
	else
		logger:log(2, "GUILD %s LOBBY %s: Couldn't create new channel for %s", lobby.guild.id, lobby.id, member.user.id)
	end
end

local function matchmakingJoin (member, lobby)
	logger:log(4, "GUILD %s MATCHMAKING LOBBY %s: %s joined", lobby.guild.id, lobby.id, member.user.id)
	
	local target = client:getChannel(lobbies[lobby.id].target) or lobby.category
	if target then
		local children
		
		if target.type == channelType.voice then
			children = lobby.guild.voiceChannels:toArray("position", function (channel)
				if channels[channel.id] then
					local parent = client:getChannel(channels[channel.id].parent.id)
					return (parent == target) and (channel.userLimit == 0 or #channel.connectedMembers < channel.userLimit) and member:hasPermission(channel, permission.connect)
				end
			end)
		else
			children = target.voiceChannels:toArray("position", function (channel)
				return (channel ~= lobby) and (channel.userLimit == 0 or #channel.connectedMembers < channel.userLimit) and member:hasPermission(channel, permission.connect)
			end)
		end
		
		if #children == 1 then
			if member:setVoiceChannel(children[1]) then
				logger:log(4, "GUILD %s MATCHMAKING LOBBY %s: matchmade for %s", lobby.guild.id, lobby.id, target.id)
			end
			return
		elseif #children > 1 then
			if member:setVoiceChannel((matchmakers[lobbies[lobby.id].template] or matchmakers.random)(children)) then
				logger:log(4, "GUILD %s MATCHMAKING LOBBY %s: matchmade for %s", lobby.guild.id, lobby.id, target.id)
			end
			return
		else	-- if no available channels - create new or kick
			if target.type == channelType.voice then
				logger:log(4, "GUILD %s MATCHMAKING LOBBY %s: no available channels, delegating to %s", lobby.guild.id, lobby.id, target.id)
				client:emit("voiceChannelJoin", member, target)
			else
				logger:log(4, "GUILD %s MATCHMAKING LOBBY %s: no available channels, gtfo", lobby.guild.id, lobby.id)
				member:setVoiceChannel()
			end
			return
		end
	end
end

local function channelJoin (member, channel)
	logger:log(4, "GUILD %s CHANNEL %s: %s joined", lobby.guild.id, lobby.id, member.user.id)
	
	local companion = client:getChannel(channels[channel.id].companion)
	if companion then
		companion:getPermissionOverwriteFor(member):allowPermissions(permission.readMessages)
	end
end

return function (member, channel)
	if channel then
		local lobbyData = lobbies[channel.id]
		if lobbyData then
			if lobbyData.isMatchmaking then
				matchmakingJoin(member, channel)
			else
				lobbyData.mutex:lock()
				local ok, err = xpcall(lobbyJoin, debug.traceback, member, channel)
				lobbyData.mutex:unlock()	-- no fucking clue
				if not ok then error(err) end	-- no ignoring!
			end
		elseif channels[channel.id] then
			channelJoin(member, channel)
		end
	end
end