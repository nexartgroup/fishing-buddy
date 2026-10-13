-- harness/botserver.lua
-- ---------------------------------------------------------------------------
-- A small MODEL of what AzerothCore + mod-playerbots do with the chat lines the
-- addon sends.  It exists so the offline tests can run the addon against
-- something that answers like the server does.  It is written from the C++
-- sources, not measured on a real server, and covers only what the Auto module
-- touches.  Where a rule comes from the sources the file/line is given
-- (mod-playerbots HEAD 037c014, AzerothCore master of 2026-10).
--
--   local Server = require("botserver")
--   local srv = Server.attach(env, { selfbot_level = 2, gm = false, ... })
--
-- Options (all optional):
--   selfbot_level  AiPlayerbot.SelfBotLevel: 0 off, 1 GM only (server default), 2 everybody,
--                  3+ everybody and switched on silently at login      (PlayerbotMgr.cpp:1100-1123, 1733)
--   gm             the account is a game master (CanBeGameMaster)
--   active         the self bot is ON when the test starts
--   persisted      list of non-combat strategies stored in the DB; restored at activation (Load)
--   latency        one-way network latency in seconds (default 0.08)
--   tick           bot AI tick: a command is executed this long after it arrived (default 0.3)
--   reply_visible  the client shows the bot's whisper to oneself (default true; UNVERIFIED on a real client)
--   repeat_delay   AiPlayerbot.RepeatDelay: the same reply text within this time is not sent again (2 s;
--                  PlayerbotAI.cpp:3041-3043)
--   whisper_filter GM account without '.whispers on': whispers to oneself are refused (ChatHandler.cpp:408)
--   module_missing mod-playerbots is not installed ('There is no such command')
--   end_fishing_after  seconds after 'master fishing' was set that the bot drops it again by itself
--                  (EndMasterFishingAction: no water within range; not saved to the DB)
--   mount_owned    the character owns a mount: with the strategy 'mount' it mounts itself shortly
--                  after activation / after fishing was set (CheckMountStateAction.cpp)
-- ---------------------------------------------------------------------------

local Server = {}
Server.__index = Server

-- AiFactory.cpp:584-588 (+ class strategies, left out)
local DEFAULT_NC = { "nc", "food", "chat", "follow", "default", "force rebuff", "quest", "loot",
                     "gather", "duel", "pvp", "buff", "mount", "emote" }

-- strategy names the engine knows; an unknown name is ignored without a message (Engine.cpp:362-377)
local KNOWN = {}
for _, n in ipairs(DEFAULT_NC) do KNOWN[n] = true end
for _, n in ipairs({ "master fishing", "grind", "rpg", "new rpg", "travel", "bdps", "dps assist", "pet",
                     "heal", "cure", "stay", "guard", "debug" }) do KNOWN[n] = true end

local function copy_set(list)
   local s = {}
   for _, n in ipairs(list) do s[n] = true end
   return s
end

local function sorted_list(set)
   local l = {}
   for n in pairs(set) do l[#l + 1] = n end
   table.sort(l)
   return l
end

function Server.attach(env, opts)
   opts = opts or {}
   local self = setmetatable({}, Server)
   self.env = env
   self.latency = opts.latency or 0.08
   self.tick = opts.tick or 0.3
   self.level = opts.selfbot_level or 2
   self.gm = opts.gm or false
   self.persisted = opts.persisted and copy_set(opts.persisted) or nil
   self.reply_visible = opts.reply_visible ~= false
   self.repeat_delay = opts.repeat_delay or 2.0
   self.whisper_filter = opts.whisper_filter or false
   self.module_missing = opts.module_missing or false
   self.end_fishing_after = opts.end_fishing_after
   self.mount_owned = opts.mount_owned or false
   self.active = false
   self.nc = nil
   self.said = {}              -- plain SAY lines (spoken aloud)
   self.received = {}          -- lines the bot AI received: { t=, text= }
   self.dropped = {}           -- lines the core dropped: { why=, text= }
   self.last_said = {}
   self.toggles = 0            -- how often '.playerbots bot self' was handled
   env.on_send = function(entry) self:receive(entry) end
   if opts.active or opts.login_auto then
      -- login_auto: AiPlayerbot.SelfBotLevel > 2 switches the self bot on silently at every login
      -- (PlayerbotMgr.cpp:1733-1734); the client sees no message.
      self:activate(true)
   end
   return self
end

-- ---------------------------------------------------------------------------
-- output towards the client
-- ---------------------------------------------------------------------------

function Server:system(text)
   self.env:after(self.latency, function() self.env:chat_event("CHAT_MSG_SYSTEM", text) end)
end

-- the bot answers its master (= the player himself) with a whisper
function Server:tell(text)
   local now = self.env.now
   local last = self.last_said[text]
   if last and (now - last) < self.repeat_delay then
      return              -- PlayerbotAI::TellMasterNoFacing: same text within RepeatDelay is not repeated
   end
   self.last_said[text] = now
   if not self.reply_visible then return end
   local me = self.env.G.UnitName("player")
   self.env:after(self.latency, function() self.env:chat_event("CHAT_MSG_WHISPER", text, me) end)
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

function Server:activate(silent)
   self.active = true
   -- PlayerbotRepository::Load: clears the nc engine, adds +chat, applies the stored list
   if self.persisted then
      self.nc = {}
      for n in pairs(self.persisted) do self.nc[n] = true end
      self.nc.chat = true
   else
      self.nc = copy_set(DEFAULT_NC)
   end
   self.activated_at = self.env.now
   self:consider_mount(10.0)
end

function Server:deactivate()
   self.active = false
   self.nc = nil
end

function Server:save()
   -- ChangeStrategyAction.cpp: every +,-,~,! through the 'nc' chat command stores the whole set
   self.persisted = {}
   for n in pairs(self.nc) do self.persisted[n] = true end
end

function Server:consider_mount(delay)
   if not self.mount_owned then return end
   self.env:after(delay, function()
      if self.active and self.nc and self.nc.mount and not self.env.world.mounted then
         self.env.world.mounted = true       -- CheckMountStateAction: idle self bot mounts itself
      end
   end)
end

function Server:has(name)
   return self.active and self.nc and self.nc[name] and true or false
end

function Server:strategies()
   return self.nc and sorted_list(self.nc) or {}
end

-- ---------------------------------------------------------------------------
-- input from the client
-- ---------------------------------------------------------------------------

function Server:toggle()
   self.toggles = self.toggles + 1
   if self.active then
      self:deactivate()
      self:system("SelfBot is now deactivated.")
   elseif self.level == 0 then
      self:system("SelfBot is disabled server-wide.")
   elseif self.level == 1 and not self.gm then
      self:system("SelfBot is restricted for this account.")
   else
      self:activate()
      self:system("SelfBot is now active.")
   end
end

function Server:receive(e)
   local ct, text = e.chattype, e.text
   if ct == "SAY" then
      local low = text:lower()
      if low:sub(1, 1) == "." and low:sub(2, 2) ~= "." and low:sub(2, 2) ~= " " and #low > 1 then
         -- ChatHandler::ParseCommands: runs for every chat type before the type switch (ChatHandler.cpp:307)
         if self.module_missing then
            self:system("There is no such command.")
         elseif low:match("^%.playerbots?%s+bot%s+self%s*$") and not low:match("^%.playerbot%s") then
            self:toggle()
         else
            self:system("There is no such command.")
         end
      else
         self.said[#self.said + 1] = text         -- spoken aloud
      end
   elseif ct == "PARTY" or ct == "RAID" then
      local w = self.env.world
      if (w.party or 0) == 0 and (w.raid or 0) == 0 then
         -- ChatHandler.cpp:451-461: no group -> bare return, nothing reaches any script hook
         self.dropped[#self.dropped + 1] = { why = "no group", text = text }
         return
      end
      self:to_bot(text)
   elseif ct == "WHISPER" then
      local me = self.env.G.UnitName("player")
      if not e.target or e.target:lower() ~= me:lower() then
         return                                   -- whisper to somebody else: not modelled
      end
      if self.whisper_filter then
         self:system(string.format(self.env.G.ERR_CHAT_PLAYER_NOT_FOUND_S, me))
         self.dropped[#self.dropped + 1] = { why = "whispers filtered", text = text }
         return
      end
      -- Player::Whisper delivers the line twice (CHAT_MSG_WHISPER_INFORM and CHAT_MSG_WHISPER)
      self.env:after(self.latency, function()
         self.env:chat_event("CHAT_MSG_WHISPER_INFORM", text, me)
         self.env:chat_event("CHAT_MSG_WHISPER", text, me)
      end)
      self:to_bot(text)
   end
end

function Server:to_bot(text)
   self.env:after(self.latency + self.tick, function() self:bot_command(text) end)
end

-- PlayerbotAI::HandleCommand -> ExternalEventHelper::ParseChatCommand -> ChangeNonCombatStrategyAction
function Server:bot_command(text)
   if not self.active then return end                       -- no PlayerbotAI: a whisper to oneself is plain chat
   self.received[#self.received + 1] = { t = self.env.now, text = text }
   if not self.nc.chat then return end                      -- the 'chat' strategy holds the command triggers
   local param = text:match("^nc%s+(.*)$")
   if not param then return end
   local before_fishing = self.nc["master fishing"]
   local changed = false
   for item in param:gmatch("[^,]+") do
      local op, name = item:sub(1, 1), item:sub(2)
      if op == "+" then
         if KNOWN[name] then self.nc[name] = true end
         changed = true
      elseif op == "-" then
         self.nc[name] = nil
         changed = true
      elseif op == "~" then
         if self.nc[name] then self.nc[name] = nil elseif KNOWN[name] then self.nc[name] = true end
         changed = true
      elseif op == "!" then
         self.nc = copy_set(DEFAULT_NC)                      -- SelectiveResetStrategies
         changed = true
      elseif op == "?" then
         self:tell("Strategies: " .. table.concat(sorted_list(self.nc), ", "))
      end
   end
   if changed then self:save() end
   if self.nc["master fishing"] and not before_fishing then
      self:consider_mount(2.0)
      if self.end_fishing_after then
         local at = self.activated_at
         self.env:after(self.end_fishing_after, function()
            if self.active and self.nc then self.nc["master fishing"] = nil end   -- in memory only
         end)
      end
   end
end

-- ---------------------------------------------------------------------------
-- other addons, as the tests need them
-- ---------------------------------------------------------------------------

-- Behaves like Botpad 1.2 (BP_Bot.lua): on EVERY "SelfBot is now active." it queues whispers
--   nc !, co !, <mode set>  0.35 s apart, unless some addon holds it (Botpad.Bot.Hold, 1.3).
-- Returns the Botpad table installed in the global environment.
function Server.install_botpad_stub(env, with_hold)
   local G = env.G
   local BP = { Bot = { holders = {}, bursts = 0 } }
   G.Botpad = BP
   if with_hold then
      function BP.Bot.Hold(owner) BP.Bot.holders[owner] = true end
      function BP.Bot.Release(owner) BP.Bot.holders[owner] = nil end
   end
   local f = G.CreateFrame("Frame")
   f:RegisterEvent("CHAT_MSG_SYSTEM")
   f:SetScript("OnEvent", function(self, event, msg)
      if tostring(msg):lower():find("selfbot is now active", 1, true) then
         if next(BP.Bot.holders) then return end
         BP.Bot.bursts = BP.Bot.bursts + 1
         local me = G.UnitName("player")
         for i, cmd in ipairs({ "ll normal", "nc !", "co !", "nc +chat,+follow,+gather,+loot,+mount,+quest" }) do
            env:after(0.02 + 0.35 * (i - 1), function() G.SendChatMessage(cmd, "WHISPER", nil, me) end)
         end
      end
   end)
   return BP
end

return Server
