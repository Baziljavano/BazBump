local discordia = require('discordia')
local client = discordia.Client()
local json = require('json')
local fs = require('fs')

local CONFIG_FILE = "config2.json"
local COOLDOWN = 1800

local configs = {}          -- guildId -> { bumpChannel, ad }
local bumpCooldowns = {}    -- guildId -> timestamp
local pendingRequests = {} -- [targetGuildId] = { requesterGuildIds }
local trackedRequests = {} -- messageId -> {requestGuild, receiverGuild}

local userCooldowns = {} -- [userId] = timestamp
local USER_COOLDOWN = 300 -- 5 minutes

-- Load saved config
if fs.existsSync(CONFIG_FILE) then
  local raw = fs.readFileSync(CONFIG_FILE)
  configs = json.decode(raw) or {}
end

local function saveConfig()
  fs.writeFileSync(CONFIG_FILE, json.encode(configs, { indent = true }))
end

local function formatTime(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  return string.format("%02dh %02dm %02ds", h, m, s)
end

local function extractInviteCode(adText)
  return adText:match("discord%.gg/([%w%-]+)")
      or adText:match("discordapp%.com/invite/([%w%-]+)")
      or adText:match("discord%.com/invite/([%w%-]+)")
end

local function getServerNameByInvite(inviteCode)
  if not inviteCode then
    return nil -- Prevents attempting to concatenate nil
  end

  local url = "https://discord.com/api/v10/invites/" .. inviteCode .. "?with_counts=true"
  local headers = {
    {"User-Agent", "DiscordBot (https://github.com/yourbot, 1.0)"}
  }

  local res, body = require("coro-http").request("GET", url, headers)

  if res.code == 200 then
    local data = require("json").decode(body)
    if data.guild and data.guild.name then
      return data.guild.name
    end
  end

  return nil
end

-- Register client
client:on("ready", function()
	print("Logged in as " .. client.user.username)
end)

client:on('messageCreate', function(message)
  if not message.guild or message.author.bot then return end

  local guildId = message.guild.id
  local channelId = message.channel.id
  local userId = message.author.id
  local content = message.content

  -- Initialize config for server
  if not configs[guildId] then
  configs[guildId] = {
    bumpChannel = nil,
    ad = nil,
    partnerChannel = nil,
    requestChannel = nil,
    GlobalAdChannel = nil,
  }
end


  if content:lower() == "b!help" then
  message.channel:send([[
🤖 **BazBump Commands**

🛠️ **Setup**
`b!setupad [text]` — Set your server's ad message. must include an invite link
`b!preview` — The appearance of your advertisement

🚀 **Bumping**
`b!bump` — Send your ad to all other servers' bump channels  
`b!status` — Check your bump cooldown time
`b!setupbumpch` — Set the current channel as your server's bump destination

🤝 **Partnerships**
`b!partner [optional: serverId]` — Send a partnership request to a random server or directly using its id  
`b!setupreqch` — Set the current channel as channel to receive incoming partnership requests. not recommended to be set to a public channel
`b!setuppartnerch` — Set the current channel as channel for partnerships. not recommended to be set to a public chatroom
React with ✅ to accept a partnership  
React with ❌ to deny a partnership

🌐 **Global Advertising**
`b!setupglobalad` — Set the current channel to let your members send their ad to multiple servers

📋 **Misc**
`b!help` — Show this help message
`b!about` — About this bot & Informations
	]])
  return
end

  if content:lower() == "b!about" then
    message.channel:send([[
BazBump is a bot that promotes your server to thousands of users! this bot also finds for server partnerships.
In ]]..#client.guilds..[[ servers
Made in Indonesia by `bazil_j` with Lua
    ]])
  end

  if content == "b!setuppartnerch" then
  configs[guildId].partnerChannel = channelId
  saveConfig()
  message:reply("✅ Partner channel set.")
  return
end

if content == "b!setupreqch" then
  configs[guildId].requestChannel = channelId
  saveConfig()
  message:reply("✅ Request channel set.")
  return
end

if content:lower():sub(1, 9) == "b!partner" then
  local targetId = content:match("b!partner%s+(%d+)")

  if not targetId then
    -- Pick a random target that has a requestChannel and no existing request
    local possibleTargets = {}

    for id, conf in pairs(configs) do
      if id ~= guildId and conf.requestChannel then
        -- Skip if already requested
        local requests = pendingRequests[id] or {}
        local alreadyRequested = false
        for _, requester in ipairs(requests) do
          if requester == guildId then
            alreadyRequested = true
            break
          end
        end

        if not alreadyRequested then
          table.insert(possibleTargets, id)
        end
      end
    end

    if #possibleTargets == 0 then
      message:reply("⚠️ No available servers to request a partnership with.")
      return
    end

    -- Pick a target from filtered list
    targetId = possibleTargets[math.random(1, #possibleTargets)]
  end

  if targetId == guildId then
    message:reply("Why would someone want to partner with their own server??? <:the_rock:1395375623127433286>")
    return
  end

  if not configs[targetId] then
    message:reply("❌ Invalid or unregistered server ID.")
    return
  end

  -- Check again if already requested
  pendingRequests[targetId] = pendingRequests[targetId] or {}
  for _, existing in ipairs(pendingRequests[targetId]) do
    if existing == guildId then
      message:reply("⚠️ You already sent a request to this server.")
      return
    end
  end

  -- Add to pending list
  table.insert(pendingRequests[targetId], guildId)

  -- Send the request
  local sourceAd = configs[guildId].ad or ""
  local targetAd = configs[targetId].ad or ""

  local sourceName = message.guild.name
  local inviteCode = extractInviteCode(sourceAd)
  local fetchedName = getServerNameByInvite(inviteCode)
  if fetchedName then sourceName = fetchedName end

  local requestChannel = client:getChannel(configs[targetId].requestChannel or "")
  if requestChannel then
    local sentMessage = requestChannel:send("📬 Partnership request from **" .. sourceName .. "**\n" ..
      sourceAd .. "\nReact with ✅ to accept, ❌ to deny.")
    sentMessage:addReaction("✅")
    sentMessage:addReaction("❌")
    trackedRequests[sentMessage.id] = {
      requestGuild = guildId,
      receiverGuild = targetId
    }
  end

  local destName = "a server"
  local destInvite = extractInviteCode(targetAd)
  local fetchedDest = getServerNameByInvite(destInvite)
  if fetchedDest then destName = fetchedDest end

  message.channel:send("✅ Partner request sent to **" .. destName .. "**.")
  return
end

  -- Command: !setupbump
  if content:lower() == "b!setupbumpch" then
    configs[guildId].bumpChannel = channelId
    saveConfig()
    message:reply("✅ This channel has been set as your bump destination.")
    return
  end

  -- Command: !setupad [your text here]
  if content:lower():sub(1, 10) == "b!setupad " then
    local ad = content:sub(11)
    if ad:find("@everyone") or ad:find("@here") or ad:find("@everyone") and ad:find("@here") then
      message:reply("⚠️ It's not allowed to use pings in your ad!")
    else
      configs[guildId].ad = ad
      saveConfig()
      message:reply("✅ Server ad saved.")
    end
    return
  end

  -- Command: !previewad
  if content:lower() == "b!preview" then
    local ad = configs[guildId].ad
    if not ad then
      message:reply("⚠️ No ad has been set. Use `b!setupad [text]`.")
    else
      message.channel:send(ad)
    end
    return
  end

  -- Command: !bump
  if content:lower() == "b!bump" then
    local config = configs[guildId]
    if not config.ad then
      message:reply("⚠️ No ad set. Use `b!setupad` first.")
      return
    end

    if not config.bumpChannel then
      message:reply("⚠️ No channel set. Use `b!setupbumpch` first.")
      return
    end

    local now = os.time()
    local lastBump = bumpCooldowns[guildId] or 0
    local remaining = COOLDOWN - (now - lastBump)

    if remaining > 0 then
      message:reply("🕒 You can bump again in `" .. formatTime(remaining) .. "`.")
      return
    end

    bumpCooldowns[guildId] = now
    message:reply("✅ Your server has been bumped successfully!")

	for otherGuildId, otherConfig in pairs(configs) do
  		local targetChannel = client:getChannel(otherConfig.bumpChannel or "")
  		if targetChannel then
    		targetChannel:send(
      		"📢 **Bump from " .. message.guild.name .. "!**\n\n" ..
      		config.ad.."\n\n🚀 Bumped by: "..message.author.name
    		)
  		end
	end
    return
  end

   if content == "b!setupglobalad" then
  configs[guildId].GlobalAdChannel = channelId
  saveConfig()
  message:reply('✅ This channel is now set for global advertisements')
  return
end

if configs[guildId].GlobalAdChannel == channelId then
  local now = os.time()
  local last = userCooldowns[userId] or 0
  local remaining = USER_COOLDOWN - (now - last)

  if remaining > 0 then
    message:reply("⏳ Please wait `" .. formatTime(remaining) .. "` before advertising again.")
    return
  end

  userCooldowns[userId] = now

  -- Broadcast ad to all bump channels
  local count = 0
  for otherGuildId, conf in pairs(configs) do
    local target = client:getChannel(conf.GlobalAdChannel or "")
    if target then
      target:send(message.content.."\n📣 sent by **"..message.author.name.."**\n📢 sent from **"..message.guild.name.."**")
      count = count + 1
    end
  end

  message:reply("✅ Your ad was sent to **" .. count .. "** servers.")
  return
end


  -- Command: !bumpstatus
  if content:lower() == "b!status" then
    local now = os.time()
    local lastBump = bumpCooldowns[guildId] or 0
    local remaining = COOLDOWN - (now - lastBump)
    if remaining > 0 then
      message:reply("🕒 Next bump in `" .. formatTime(remaining) .. "`.")
    else
      message:reply("✅ You can bump now.")
    end
    return
  end
end)

client:on("reactionAdd", function(reaction, userId)
  local message = reaction.message
  if not message or not message.guild then return end

  local emojiName = reaction.emojiName
  if not emojiName then return end

  local requestData = trackedRequests[message.id]
  if not requestData then return end

  local requesterId = requestData.requestGuild
  local receiverId = requestData.receiverGuild

  local requesterConf = configs[requesterId]
  local receiverConf = configs[receiverId]

  if not requesterConf or not receiverConf then return end

  if emojiName == "✅" then
    -- Accept partnership
    receiverConf.partners = receiverConf.partners or {}
    requesterConf.partners = requesterConf.partners or {}

    local function addUnique(t, v)
      for _, x in ipairs(t) do if x == v then return end end
      table.insert(t, v)
    end

    addUnique(receiverConf.partners, requesterId)
    addUnique(requesterConf.partners, receiverId)

    saveConfig()

    message.channel:send("🤝 Partnership with `" .. requesterId .. "` accepted.")

    local partnerChannel = client:getChannel(requesterConf.partnerChannel or "")
    local partnerChannel2 = client:getChannel(receiverConf.partnerChannel or "")
    if partnerChannel then
      partnerChannel:send("🤝 New partner!\n" .. receiverConf.ad)
    end
    if partnerChannel2 then
      partnerChannel2:send("🤝 New partner!\n" .. requesterConf.ad)
    end

    trackedRequests[message.id] = nil
    return
  end

  if emojiName == "❌" then
    message.channel:send("❌ Partnership with `" .. requesterId .. "` denied.")
    trackedRequests[message.id] = nil
    return
  end
end)

client:run("Bot "..os.getenv("TOKEN"))