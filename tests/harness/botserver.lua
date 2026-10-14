-- harness/botserver.lua
-- ---------------------------------------------------------------------------
-- A small MODEL of what AzerothCore + mod-playerbots do with the chat lines the
-- addon sends.  It exists so the offline tests can run the addon against
-- something that answers the way the server does.  It is written from the C++
-- sources, not measured on a real server, and covers only what the Auto module
-- touches.  Where a rule comes from the sources the file/line is given
-- (mod-playerbots HEAD 037c014, AzerothCore master of 2026-10).
--
--   local Server = require("botserver")
--   local srv = Server.attach(env, { selfbot_level = 2, gm = false, ... })
--
-- THE TIMING RULES THAT MATTER (they broke the first version of the addon):
--   * A chat command whispered to the bot is only QUEUED (PlayerbotAI::HandleCommand pushes it on
--     chatCommands, PlayerbotAI.cpp:1120). The queue is drained at the start of the next AI update
--     (UpdateAIInternal -> HandleCommands, :513/:567), ALL entries in one pass.
--   * Every chat command becomes ExternalEvent(param) on a ChatCommandTrigger, which stores ONE
--     param (ChatCommandTrigger.cpp:15-20). So of several "nc ..." commands drained in the same
--     pass only the LAST one is executed; "co", "ll", "u" are separate triggers and all survive.
--   * A bot created by '.playerbots bot self' is "deaf" for about 10 s: its first AI tick is
--     "minimal" and then sleeps PassiveDelay = 10 s (PlayerbotAI.cpp:133,152,1539-1548,4784-4802;
--     PlayerbotAIConfig.cpp:98). The timer trigger 'check mount state' is skipped in minimal mode,
--     so a self bot cannot mount before that either.
--   * A fishing bot sleeps through the bobber wait (CanUseFishingBobberValue::Calculate ->
--     SetNextCheckDelay, FishValues.cpp) and reads no chat command until it wakes (up to ~15 s).
--
-- Options (all optional):
--   selfbot_level  AiPlayerbot.SelfBotLevel: 0 off, 1 GM only (server default), 2 everybody,
--                  3+ everybody and switched on silently at login      (PlayerbotMgr.cpp:1100-1123, 1733)
--   gm             the account is a game master (CanBeGameMaster)
--   active         the self bot is ON when the test starts (awake: the deaf window is over)
--   login_auto     as above, but "switched on by the server at login"
--   persisted      list of non-combat strategies stored in the DB; restored at activation (Load)
--   latency        one-way network latency in seconds (default 0.08)
--   tick           AI update interval while awake (default 0.3)
--   deaf           seconds after activation before the first real AI update (default 10.5)
--   busy           { cycle = 30, sleep = 15 }: while 'master fishing' is set the AI sleeps the first
--                  'sleep' seconds of every 'cycle' seconds (bobber wait)
--   reply_visible  the client shows the bot's whisper to oneself (default true; UNVERIFIED on a real client)
--   repeat_delay   AiPlayerbot.RepeatDelay in whole seconds: the same reply text within it is not sent
--                  again (PlayerbotAI.cpp:3041-3043, time(nullptr) arithmetic)
--   whisper_filter GM account without '.whispers on': whispers to oneself are refused (ChatHandler.cpp:408)
--   module_missing true: mod-playerbots is not installed ('There is no such command');
--                  'say': AllowPlayerCommands=0 on a non-GM account (the line is spoken aloud)
--   disabled       AiPlayerbot.Enabled = 0
--   end_fishing_after  seconds after 'master fishing' was set that the bot drops it again by itself
--                  (EndMasterFishingAction: no water within range; not saved to the DB)
--   ignore_fishing the bot ignores '+master fishing' (as if the strategy name were unknown)
--   mount_owned    the character owns a mount: with the strategy 'mount' it mounts itself on an AI
--                  update after the deaf window (CheckMountStateAction.cpp), the cast takes 1.5 s
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
   self.deaf = opts.deaf or 10.5
   self.busy = opts.busy
   self.level = opts.selfbot_level or 2
   self.gm = opts.gm or false
   self.persisted = opts.persisted and copy_set(opts.persisted) or nil
   self.reply_visible = opts.reply_visible ~= false
   self.repeat_delay = opts.repeat_delay or 2
   self.whisper_filter = opts.whisper_filter or false
   self.module_missing = opts.module_missing or false
   self.disabled = opts.disabled or false
   self.end_fishing_after = opts.end_fishing_after
   self.ignore_fishing = opts.ignore_fishing or false
   self.mount_owned = opts.mount_owned or false
   self.active = false
   self.nc = nil
   self.queue = {}             -- chat commands waiting for the next AI update
   self.armed = nil            -- time of the next scheduled AI update
   self.said = {}              -- plain SAY lines (spoken aloud)
   self.received = {}          -- lines drained by an AI update: { t=, text= }
   self.executed = {}          -- nc commands that were actually executed: { t=, text= }
   self.collapsed = {}         -- nc commands that were drained but overwritten by a DIFFERENT later one (lost)
   self.dropped = {}           -- lines the core dropped: { why=, text= }
   self.last_said = {}
   self.toggles = 0            -- how often '.playerbots bot self' was handled
   env.on_send = function(entry) self:receive(entry) end
   if opts.active or opts.login_auto then
      -- login_auto: AiPlayerbot.SelfBotLevel > 2 switches the self bot on silently at every login
      -- (PlayerbotMgr.cpp:1733-1734); the client sees no message.
      self:activate(opts.active and true or false)
   end
   return self
end

-- ---------------------------------------------------------------------------
-- output towards the client
-- ---------------------------------------------------------------------------

function Server:system(text)
   self.env:after(self.latency, function() self.env:chat_event("CHAT_MSG_SYSTEM", text) end)
end

-- the bot answers its master (= the player himself) with a whisper (TellMasterNoFacing)
function Server:tell(text)
   local now = math.floor(self.env.now)
   local last = self.last_said[text]
   if last and (now - last) < self.repeat_delay then
      return              -- same text within RepeatDelay is not repeated (whole-second clock)
   end
   self.last_said[text] = now
   if not self.reply_visible then return end
   local me = self.env.G.UnitName("player")
   self.env:after(self.latency, function() self.env:chat_event("CHAT_MSG_WHISPER", text, me) end)
end

-- a reply sent through PlayerbotAI::Whisper (e.g. 'I don't have a Fishing Pole'): goes through
-- Player::Whisper, i.e. WHISPER first and WHISPER_INFORM second (Player.cpp:9694-9715)
function Server:whisper(text)
   local me = self.env.G.UnitName("player")
   self.env:after(self.latency, function()
      self.env:chat_event("CHAT_MSG_WHISPER", text, me)
      self.env:chat_event("CHAT_MSG_WHISPER_INFORM", text, me)
   end)
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

function Server:activate(awake)
   self.active = true
   self.queue = {}
   self.last_said = {}                       -- whispers[] lives in the PlayerbotAI object
   -- PlayerbotRepository::Load: clears the nc engine, adds +chat, applies the stored list
   if self.persisted then
      self.nc = {}
      for n in pairs(self.persisted) do self.nc[n] = true end
      self.nc.chat = true
   else
      self.nc = copy_set(DEFAULT_NC)
   end
   self.activated_at = self.env.now
   self.ready_at = awake and self.env.now or (self.env.now + self.deaf)
   self.mounting = false
   self.fish_since = self.nc["master fishing"] and self.env.now or nil
   if self.mount_owned then self:arm(self.ready_at) end
end

function Server:deactivate()
   self.active = false
   self.nc = nil
   self.queue = {}                           -- the PlayerbotAI (and its queue) is deleted
   self.fish_since = nil
end

function Server:save()
   -- ChangeStrategyAction.cpp: every +,-,~,! through the 'nc' chat command stores the whole set
   self.persisted = {}
   for n in pairs(self.nc) do self.persisted[n] = true end
end

function Server:has(name)
   return self.active and self.nc and self.nc[name] and true or false
end

function Server:strategies()
   return self.nc and sorted_list(self.nc) or {}
end

-- ---------------------------------------------------------------------------
-- the AI update loop
-- ---------------------------------------------------------------------------

-- when does the AI read chat commands next? (not before the deaf window is over, not while it
-- sleeps through a bobber wait, otherwise on the next tick)
function Server:next_update(t)
   local at = math.max(t, self.ready_at or t)
   if self.busy and self.fish_since and self.nc and self.nc["master fishing"] then
      local phase = (at - self.fish_since) % self.busy.cycle
      if phase < self.busy.sleep then at = at + (self.busy.sleep - phase) end
   end
   return at
end

function Server:arm(t)
   local at = self:next_update(t)
   if self.armed and self.armed <= at + 1e-9 then return end
   self.armed = at
   self.env:after(math.max(0, at - self.env.now), function()
      if self.armed ~= at then return end
      self.armed = nil
      self:update()
   end)
end

function Server:update()
   if not self.active then return end
   local env = self.env
   -- PlayerbotAI::HandleCommands: drain the whole queue; the 'nc' trigger keeps only the last param
   local q = self.queue
   self.queue = {}
   local last_nc
   for _, c in ipairs(q) do
      self.received[#self.received + 1] = { t = env.now, text = c }
      local param = c:match("^nc%s+(.*)$")
      if param then
         if last_nc then
            -- an identical repeat loses nothing; a different command overwritten by this one is lost
            if last_nc == param then
               self.repeated = (self.repeated or 0) + 1
            else
               self.collapsed[#self.collapsed + 1] = { t = env.now, text = "nc " .. last_nc }
            end
         end
         last_nc = param
      end
   end
   if last_nc and self.nc.chat then self:run_nc(last_nc) end        -- no 'chat' strategy: no command triggers
   -- triggers: an idle self bot with a mount and the strategy 'mount' mounts itself
   if self.mount_owned and self.nc.mount and not self.mounting and not env.world.mounted then
      self.mounting = true
      env:after(1.5, function()
         self.mounting = false
         if self.active and self.nc and self.nc.mount then env.world.mounted = true end
      end)
   end
   if self.mount_owned or #self.queue > 0 then self:arm(env.now + self.tick) end
end

-- Engine::ChangeStrategy per item, then HandleStrategyCommon ('!' resets AFTER the other items)
function Server:run_nc(param)
   local env = self.env
   self.executed[#self.executed + 1] = { t = env.now, text = "nc " .. param }
   local before_fishing = self.nc["master fishing"]
   local changed, bang = false, false
   for item in param:gmatch("[^,]+") do
      local op, name = item:sub(1, 1), item:sub(2)
      if op == "+" then
         if KNOWN[name] and not (self.ignore_fishing and name == "master fishing") then self.nc[name] = true end
         changed = true
      elseif op == "-" then
         self.nc[name] = nil
         changed = true
      elseif op == "~" then
         if self.nc[name] then self.nc[name] = nil elseif KNOWN[name] then self.nc[name] = true end
         changed = true
      elseif op == "!" then
         bang = true
         changed = true
      elseif op == "?" then
         self:tell("Strategies: " .. table.concat(sorted_list(self.nc), ", "))
      end
   end
   if bang then self.nc = copy_set(DEFAULT_NC) end                  -- SelectiveResetStrategies
   if changed then self:save() end
   if self.nc["master fishing"] and not before_fishing then
      self.fish_since = env.now
      if self.end_fishing_after then
         env:after(self.end_fishing_after, function()
            if self.active and self.nc then self.nc["master fishing"] = nil; self.fish_since = nil end   -- in memory only
         end)
      end
   elseif not self.nc["master fishing"] then
      self.fish_since = nil
   end
end

-- ---------------------------------------------------------------------------
-- input from the client
-- ---------------------------------------------------------------------------

function Server:toggle()
   self.toggles = self.toggles + 1
   if self.disabled then
      self:system("|cffff0000Playerbot system is currently disabled!")
   elseif self.active then
      self:deactivate()
      self:system("SelfBot is now deactivated.")
   elseif self.level == 0 then
      self:system("SelfBot is disabled server-wide.")
   elseif self.level == 1 and not self.gm then
      self:system("SelfBot is restricted for this account.")
   else
      self:activate(false)
      self:system("SelfBot is now active.")
   end
end

function Server:receive(e)
   local ct, text = e.chattype, e.text
   if ct == "SAY" then
      local low = text:lower()
      if low:sub(1, 1) == "." and low:sub(2, 2) ~= "." and low:sub(2, 2) ~= " " and #low > 1 then
         -- ChatHandler::ParseCommands: runs for every chat type before the type switch (ChatHandler.cpp:307)
         if self.module_missing == 'say' then
            self.said[#self.said + 1] = text         -- AllowPlayerCommands=0: an unknown dot line is just text
         elseif self.module_missing then
            self:system("There is no such command.")
         elseif low:match("^%.playerbots%s+bot%s+self%s*$") then
            self:toggle()
         else
            self:system("There is no such command.")
         end
      else
         self.said[#self.said + 1] = text            -- spoken aloud
      end
   elseif ct == "PARTY" or ct == "RAID" then
      local w = self.env.world
      local grouped = (w.party or 0) > 0 or (w.raid or 0) > 0
      if ct == "RAID" then grouped = (w.raid or 0) > 0 end    -- /ra needs a raid group (ChatHandler.cpp:507-513)
      if not grouped then
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
      -- Player::Whisper delivers the line twice: CHAT_MSG_WHISPER to the target first, then
      -- CHAT_MSG_WHISPER_INFORM to the sender (Player.cpp:9694-9715)
      self.env:after(self.latency, function()
         self.env:chat_event("CHAT_MSG_WHISPER", text, me)
         self.env:chat_event("CHAT_MSG_WHISPER_INFORM", text, me)
      end)
      self:to_bot(text)
   end
end

function Server:to_bot(text)
   self.env:after(self.latency, function()
      if not self.active then return end        -- no PlayerbotAI: a whisper to oneself is plain chat
      self.queue[#self.queue + 1] = text
      self:arm(self.env.now)
   end)
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
      function BP.Bot.IsHeld() return next(BP.Bot.holders) ~= nil end
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
