-- scenarios.lua
-- ---------------------------------------------------------------------------
-- Offline boot harness for Fishing Buddy ("does it load, does it initialise, does
-- Auto-Angeln start and stop").  Lua 5.1.
--
--   lua5.1 scenarios.lua [REPO_DIR] [--only a,b,c] [--list] [--verbose] [--expect-fail a,b]
--
-- Exit status: 0 if every scenario passes (scenarios named in --expect-fail are
-- allowed to fail and are reported as "xfail"), 1 otherwise.
--
-- It loads the addon exactly as the 3.3.5a client does: TOC order, XML <Script>/
-- <Include>, XML frames and their script handlers, SavedVariables assigned after
-- the files ran, then ADDON_LOADED, VARIABLES_LOADED, SPELLS_CHANGED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD with a fishing pole in the main hand.  Every Lua error is
-- recorded with its traceback (nothing is swallowed), and every SendChatMessage
-- call is recorded.
--
-- What this proves and what it cannot: see README.txt ("Honest boundary").
-- ---------------------------------------------------------------------------

local here = (arg[0]:match("^(.*)/[^/]*$")) or "."
package.path = here .. "/harness/?.lua;" .. package.path
local Wow = require("wowenv")
local Server = require("botserver")

-- ---------------------------------------------------------------------------
-- command line
-- ---------------------------------------------------------------------------

local repo = here .. "/.."
local only, expect_fail, verbose, list_only, show_trace = nil, {}, false, false, false
do
   local i = 1
   while i <= #arg do
      local a = arg[i]
      if a == "--only" then only = {}; for n in arg[i + 1]:gmatch("[^,]+") do only[n] = true end; i = i + 2
      elseif a == "--expect-fail" then for n in arg[i + 1]:gmatch("[^,]+") do expect_fail[n] = true end; i = i + 2
      elseif a == "--verbose" then verbose = true; i = i + 1
      elseif a == "--list" then list_only = true; i = i + 1
      elseif a == "--trace" then show_trace = true; i = i + 1
      else repo = a; i = i + 1 end
   end
end
repo = repo:gsub("/+$", "")

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function serialize(v, indent)
   indent = indent or ""
   local t = type(v)
   if t == "table" then
      local parts = {}
      for k, x in pairs(v) do
         parts[#parts + 1] = ("%s  [%s] = %s,"):format(indent, serialize(k, ""), serialize(x, indent .. "  "))
      end
      return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
   elseif t == "string" then return string.format("%q", v)
   elseif t == "number" or t == "boolean" or t == "nil" then return tostring(v)
   else return "nil" end
end

-- what WoW does with SavedVariables: write them as Lua source, read them back next session
local function roundtrip(tbl)
   if tbl == nil then return nil end
   local fn = assert(loadstring("return " .. serialize(tbl)))
   return fn()
end

local function strip_colors(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function chat_has(env, needle)
   for _, l in ipairs(env.chat) do
      if strip_colors(l):find(needle, 1, true) then return true end
   end
   return false
end

local function sent_texts(env)
   local t = {}
   for _, s in ipairs(env.sent) do t[#t + 1] = ("%s:%s"):format(s.chattype, s.text) end
   return t
end

-- the client's login sequence for an addon that is already loaded
local function login(env, opts)
   opts = opts or {}
   local G = env.G
   env:fire("ADDON_LOADED", env.addon)
   env:fire("VARIABLES_LOADED")
   env:fire("SPELLS_CHANGED")
   env.logged_in = true
   env:fire("PLAYER_LOGIN")
   env:fire("PLAYER_ENTERING_WORLD")
end

local function new_env(o)
   local base = { repo = repo, locale = "enUS", bom = "strip", legacy_globals = true }
   for k, v in pairs(o or {}) do base[k] = v end
   local env = Wow.new(base)
   -- a cooperative server (mod-playerbots, SelfBotLevel 2, bot off) answers whatever the addon sends
   env.server = Server.attach(env, base.server)
   return env
end

local function boot(o)
   local env = new_env(o)
   env:load_addon()
   login(env, o)
   return env
end

-- ---------------------------------------------------------------------------
-- checks (collected per scenario)
-- ---------------------------------------------------------------------------

local Result = {}
Result.__index = Result
local function new_result(name, descr) return setmetatable({ name = name, descr = descr, checks = {}, failed = 0 }, Result) end
function Result:check(cond, what, detail)
   self.checks[#self.checks + 1] = { ok = cond and true or false, what = what, detail = detail }
   if not cond then self.failed = self.failed + 1 end
end

-- ---------------------------------------------------------------------------
-- the standard "can I start auto fishing" drive
-- ---------------------------------------------------------------------------

local function check_boot(r, env, label)
   label = label or "boot"
   r:check(#env.errors == 0, label .. ": no Lua error while loading/initialising", #env.errors > 0 and (#env.errors .. " error(s), first: " .. env.errors[1].message) or nil)
   local FB = env.G.FishingBuddy
   r:check(FB ~= nil and FB.OnLoad ~= nil, label .. ": FishingBuddy core table is complete (FishingBuddy.OnLoad exists)")
   r:check(FB and FB.IsLoaded and FB.IsLoaded() == true, label .. ": FishingBuddy.IsLoaded() is true after VARIABLES_LOADED")
   r:check(env.G.SlashCmdList and env.G.SlashCmdList.fishingbuddy ~= nil, label .. ": /fb slash command is registered")
   r:check(chat_has(env, "loaded"), label .. ": the 'Fishing Buddy ... loaded' banner appeared in the chat frame")
   r:check(FB and FB.Auto ~= nil, label .. ": FishingBuddy.Auto module exists")
   r:check(env.G.FishingAutoPanel ~= nil, label .. ": Auto panel frame was created (VARIABLES_LOADED handler ran)")
   if env.G.FishingAutoPanel then
      r:check(env.G.FishingAutoPanel:IsVisible() == 1, label .. ": Auto panel is visible with a pole equipped")
   end
   r:check(FB and FB.StartedFishing ~= nil, label .. ": fishing mode started (pole recognised by LibFishing)")
end

local function drive_auto(r, env)
   local FB = env.G.FishingBuddy
   if not (FB and FB.Auto and FB.Auto.Toggle) then
      r:check(false, "auto: FishingBuddy.Auto.Toggle is callable")
      return
   end
   local srv = env.server
   env:clear_sent()
   local n0 = #env.errors
   env:call("FishingBuddy.Auto.Toggle()", FB.Auto.Toggle)
   local t = sent_texts(env)
   r:check(#env.errors == n0, "auto: Toggle() raised no Lua error")
   r:check(FB.Auto.IsRunning(), "auto: running after Toggle()")
   r:check(t[1] == "WHISPER:nc ?" and #t == 1,
           "auto: Toggle() first asks the bot for its strategies (whisper 'nc ?'), nothing else yet", "sent: " .. table.concat(t, " | "))
   env:advance(45, 0.1)
   t = sent_texts(env)
   r:check(srv.active, "auto: the self bot was switched on (it was off)")
   r:check(srv.casts >= 1 and not srv:has("master fishing"), "auto: the loop cast ('do go fishing'); the strategy 'master fishing' was never set",
           "casts: " .. srv.casts .. "; " .. table.concat(srv:strategies(), ", "))
   r:check(srv.toggles == 1, "auto: '.playerbots bot self' was sent exactly once", "toggles: " .. srv.toggles)
   r:check(#srv.dropped == 0 and #srv.said == 0, "auto: nothing was dropped by the core and nothing was said aloud",
           "dropped: " .. #srv.dropped .. ", said: " .. #srv.said)
   r:check(#srv.collapsed == 0, "auto: no nc command was overwritten by a later one in the same AI update",
           #srv.collapsed .. " collapsed")
   r:check(chat_has(env, "Auto fishing started") or chat_has(env, "Auto-Angeln gestartet"), "auto: 'started' message printed (after the check)")
   r:check(FB.Auto.GetState().step == "run", "auto: session reached the 'run' step")
   -- time passes: panel refresh + watchdog + the loop (a bite every 12 s in the model)
   env:clear_sent()
   local n1 = #env.errors
   local casts0 = srv.casts
   env:advance(100, 0.5)
   r:check(#env.errors == n1, "auto: 100 s of OnUpdate (panel refresh + watchdog + loop) raised no Lua error")
   t = sent_texts(env)
   local moves, goes, ncs = 0, 0, 0
   for _, x in ipairs(t) do
      if x == "WHISPER:do move near water" then moves = moves + 1 end
      if x == "WHISPER:do go fishing" then goes = goes + 1 end
      if x:find("WHISPER:nc ", 1, true) then ncs = ncs + 1 end
   end
   r:check(moves >= 4 and moves == goes, "auto: the loop sends 'do move near water' + 'do go fishing' before every cast",
           "move: " .. moves .. ", go: " .. goes .. "; sent: " .. table.concat(t, " | "))
   r:check(srv.casts - casts0 == goes and ncs == 0, "auto: every pair produced a cast, and no 'nc' command is sent while fishing",
           "casts: " .. (srv.casts - casts0) .. ", nc: " .. ncs)
   -- the catches of the loop are counted; a simulated extra catch too
   local stats = FB.Stats and FB.Stats.Get and FB.Stats.Get()
   local caught = stats and stats.catches or 0
   r:check(caught >= 4, "auto: Stats module counted the catches of the loop", "catches=" .. tostring(caught))
   env.world.loot = { 13754 }
   env.world.loot_is_fishing = true
   local n2 = #env.errors
   env:fire("LOOT_OPENED")
   r:check(#env.errors == n2, "auto: LOOT_OPENED (simulated catch) raised no Lua error")
   stats = FB.Stats and FB.Stats.Get and FB.Stats.Get()
   r:check(stats and stats.catches == caught + 1, "auto: Stats module counted the simulated catch", stats and ("catches=" .. tostring(stats.catches)) or "no stats")
   -- stop
   env:clear_sent()
   env:call("FishingBuddy.Auto.Toggle() #2", FB.Auto.Toggle)
   r:check(not FB.Auto.IsRunning(), "auto: stopped after second Toggle()")
   r:check(chat_has(env, "caught " .. (caught + 1)) or chat_has(env, (caught + 1) .. " F"), "auto: stop summary reports the catches")
   env:advance(30, 0.1)
   t = sent_texts(env)
   r:check(t[1] == "WHISPER:nc +mount,-master fishing,?", "auto: stop takes the strategy back in ONE command and restores 'mount'", "sent: " .. table.concat(t, " | "))
   r:check(not srv.active, "auto: after the strategy is gone the self bot is switched off again (we switched it on)")
   r:check(srv.persisted and not srv.persisted["master fishing"] and srv.persisted["mount"], "auto: the stored strategy set is clean again ('master fishing' gone, 'mount' back)")
   r:check(#srv.collapsed == 0, "auto: ... and again no overwritten nc command")
end

-- ---------------------------------------------------------------------------
-- scenarios
-- ---------------------------------------------------------------------------

local scenarios = {}
local function scenario(name, descr, fn) scenarios[#scenarios + 1] = { name = name, descr = descr, fn = fn } end

scenario("lenient-client",
   "client tolerates a UTF-8 BOM and still provides this/arg1/event; fresh SavedVariables; enUS; pole equipped",
   function(r)
      local env = boot{ bom = "strip", legacy_globals = true }
      check_boot(r, env)
      drive_auto(r, env)
      -- UI paths a player touches: /fb window, every options tab, the command editor
      local n = #env.errors
      env:slash("/fb")
      for i = 1, 8 do
         local tab = env.G["FishingBuddyOptionTab" .. i]
         if tab then env:run_script(tab, "OnClick", "LeftButton") end
      end
      env:slash("/fb auto edit")
      env:slash("/fb auto status")
      env:slash("/fb stats")
      env:slash("/fb help")
      r:check(#env.errors == n, "ui: /fb window, all option tabs, /fb auto edit|status, /fb stats, /fb help raised no Lua error",
              #env.errors > n and env.errors[n + 1].message or nil)
      -- key binding bodies (what the keybind does), exactly as compiled from Bindings.xml
      local b = io.open(repo .. "/Bindings.xml", "rb")
      if b then
         local src = b:read("*a"); b:close()
         local xml = require("xmlparse").parse(src)
         for _, bind in ipairs(xml.children) do
            if bind.tag == "Binding" and bind.attrs.name == "FISHINGBUDDY_AUTOFISH" then
               local fn = assert(loadstring("return function(keystate) " .. bind.text .. "\n end", "=Bindings.xml:FISHINGBUDDY_AUTOFISH"))
               setfenv(fn, env.G)
               env:clear_sent()
               local n3 = #env.errors
               env:call("binding FISHINGBUDDY_AUTOFISH", fn(), "down")
               r:check(#env.errors == n3 and env.G.FishingBuddy.Auto.IsRunning(), "binding: FISHINGBUDDY_AUTOFISH (keystate=down) toggles Auto on")
               env:call("binding FISHINGBUDDY_AUTOFISH", fn(), "up")
               r:check(env.G.FishingBuddy.Auto.IsRunning(), "binding: keystate=up does nothing")
               env:call("stop", env.G.FishingBuddy.Auto.Stop)
            end
         end
         local G = env.G
         local missing = {}
         for _, bind in ipairs(xml.children) do
            if bind.tag == "Binding" then
               if G["BINDING_NAME_" .. bind.attrs.name] == nil then missing[#missing + 1] = "BINDING_NAME_" .. bind.attrs.name end
               if bind.attrs.header and G["BINDING_HEADER_" .. bind.attrs.header] == nil then missing[#missing + 1] = "BINDING_HEADER_" .. bind.attrs.header end
            end
         end
         r:check(#missing == 0, "bindings: every <Binding> has its BINDING_NAME_/BINDING_HEADER_ global", #missing > 0 and table.concat(missing, ", ") or nil)
      end
      -- slash path to start/stop
      env:clear_sent()
      env:slash("/fb auto on")
      local t1 = sent_texts(env)
      r:check(env.G.FishingBuddy.Auto.IsRunning() and t1[1] == "WHISPER:nc ?", "slash: '/fb auto on' starts auto fishing (asks the bot first)", table.concat(t1, " | "))
      env:advance(15, 0.1)
      r:check(env.server.casts >= 1, "slash: ... and the bot casts")
      env:slash("/fb auto off")
      r:check(not env.G.FishingBuddy.Auto.IsRunning(), "slash: '/fb auto off' stops it")
      env:advance(10, 0.1)
      r:check(not env.server.active, "slash: ... and the self bot is switched off again")
      -- logout
      local n4 = #env.errors
      env:fire("PLAYER_LOGOUT")
      r:check(#env.errors == n4, "PLAYER_LOGOUT raised no Lua error")
      r.env = env
   end)

scenario("strict-client",
   "most defensive reading of 3.3.5a: BOM in .lua rejected, unterminated last TOC line ignored, no legacy this/arg1 (all three UNVERIFIED)",
   function(r)
      local env = boot{ bom = "reject", legacy_globals = false, toc_last_line = "drop" }
      check_boot(r, env)
      drive_auto(r, env)
      r.env = env
   end)

scenario("toc-last-line-dropped",
   "client ignores the last TOC line when it has no line terminator (FishingBuddy.toc ends with 'FishingAuto.lua' and no newline) -- UNVERIFIED client behaviour",
   function(r)
      local env = boot{ bom = "strip", toc_last_line = "drop" }
      r:check(env.toc_dropped == nil, "TOC: every listed file is loaded", env.toc_dropped and ("not loaded: " .. env.toc_dropped) or nil)
      check_boot(r, env)
      r:check(env.G.FishingBuddy_ToggleAutoFishing ~= nil, "macro function FishingBuddy_ToggleAutoFishing exists")
      env:slash("/fb auto")
      r:check(env.G.FishingBuddy.Auto ~= nil and env.G.FishingBuddy.Auto.IsRunning and env.G.FishingBuddy.Auto.IsRunning(), "'/fb auto' starts auto fishing")
      r.env = env
   end)

scenario("bom-rejected",
   "only the BOM question: client rejects BOM'd .lua files, legacy globals present",
   function(r)
      local env = boot{ bom = "reject", legacy_globals = true }
      check_boot(r, env)
      drive_auto(r, env)
      r.env = env
   end)

scenario("no-legacy-globals",
   "BOM tolerated, but the client has no global this/event/arg1..9 in script handlers",
   function(r)
      local env = boot{ bom = "strip", legacy_globals = false }
      check_boot(r, env)
      drive_auto(r, env)
      r.env = env
   end)

scenario("second-session",
   "SavedVariables written by a previous session are loaded by the next one (round-tripped through Lua source)",
   function(r)
      local env1 = boot{ bom = "strip" }
      env1:fire("PLAYER_LOGOUT")
      -- change a few settings the way a player would, so non-default values are saved
      env1.G.FishingBuddy.SetSetting("AutoFishMaxMinutes", 30)
      env1.G.FishingBuddy.SetSetting("AutoFishLoopCommands", ".playerbots bot self\n/w %p do move near water\n/p co +loot\n/w %p co +loot\n/w %p do go fishing")
      local saved = { FishingBuddy_Info = roundtrip(env1.G.FishingBuddy_Info), FishingBuddy_Player = roundtrip(env1.G.FishingBuddy_Player) }
      local env = boot{ bom = "strip", saved = saved }
      check_boot(r, env, "boot#2")
      local FB = env.G.FishingBuddy
      r:check(FB.GetSetting("AutoFishMaxMinutes") == 30, "persisted setting AutoFishMaxMinutes=30 was read back")
      env:clear_sent()
      env:call("toggle", FB.Auto.Toggle)
      env:advance(15, 0.1)
      local t = sent_texts(env)
      local joined = table.concat(t, " | ")
      r:check(env.server.casts >= 1, "custom loop block: the bot cast", joined)
      local gotloot = false
      for _, rcv in ipairs(env.server.received) do if rcv.text == "co +loot" then gotloot = true end end
      r:check(gotloot, "custom loop block: the extra line 'co +loot' (whisper) reached the bot", joined)
      r:check(env.server.toggles == 1, "the legacy line '.playerbots bot self' in the saved block was NOT sent as an extra toggle", "toggles: " .. env.server.toggles)
      r:check(not joined:find("PARTY:", 1, true), "the '/p' line of the saved block is not sent while ungrouped", joined)
      r:check(chat_has(env, "Removed '.playerbots bot self'"), "the player is told that the toggle line was removed")
      r:check(chat_has(env, "not in a group"), "the player is told that a '/p' line cannot reach the bot while ungrouped")
      env:advance(120, 0.5)
      r:check(env.G.FishingBuddy.Auto.IsRunning(), "with MaxMinutes=30 it is still running after 120 s")
      r.env = env
   end)

scenario("old-savedvars",
   "SavedVariables left behind by older Fishing Buddy layouts (pre-0.9.7 flat tables, per-realm settings, empty per-character table)",
   function(r)
      local variants = {
         ["pre-0.9.7 flat layout"] = function()
            return {
               FishingBuddy_Info = {
                  Version = 9000,
                  ZoneIndex = { "Stranglethorn Vale" },
                  SubZones = { [1000] = 1, [1001] = "Booty Bay" },
                  FishTotals = { [1000] = 3, [1001] = 3 },
                  FishingSkill = { [1001] = 100 },
                  FishingHoles = { [1001] = { [6358] = 3 } },
                  Fishies = { [6358] = { name = "Oily Blackmouth", texture = "Interface\\Icons\\INV_Misc_Fish_06", quality = 1 } },
                  Settings = { Testchar = { EasyCast = 1, ClickToSwitch = 1 } },
                  Outfit = { Testchar = {} }, WasWearing = { Testchar = {} },
               },
               FishingBuddy_Player = nil,
            }
         end,
         ["per-realm settings, per-char table present"] = function()
            return {
               FishingBuddy_Info = {
                  Version = 9700,
                  ZoneIndex = { "Stranglethorn Vale" }, Fishies = {},
                  TestRealm = { Settings = { Testchar = { EasyCast = 1 } }, Outfit = { Testchar = {} }, WasWearing = { Testchar = {} } },
               },
               FishingBuddy_Player = { Settings = { EasyCast = 1 }, Outfit = {}, WasWearing = {} },
            }
         end,
         ["empty tables"] = function()
            return { FishingBuddy_Info = {}, FishingBuddy_Player = {} }
         end,
         ["settings only"] = function()
            return { FishingBuddy_Info = nil, FishingBuddy_Player = { Settings = { AutoFishMaxMinutes = 5 } } }
         end,
         ["current layout, newer Version number"] = function()
            return { FishingBuddy_Info = { Version = 99999, ZoneIndex = {}, Fishies = {}, enUS = { SubZones = {}, FishTotals = {}, FishingSkill = {}, FishingHoles = {} }, Locales = { enUS = 1 } },
                     FishingBuddy_Player = { Settings = {}, Outfit = {}, WasWearing = {} } }
         end,
      }
      local names = {}
      for name in pairs(variants) do names[#names + 1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
         local env = boot{ bom = "strip", saved = variants[name]() }
         r:check(#env.errors == 0, "[" .. name .. "] boots without Lua error", #env.errors > 0 and (env.errors[1].context .. ": " .. env.errors[1].message) or nil)
         r:check(env.G.FishingBuddy.IsLoaded() and env.G.FishingAutoPanel ~= nil, "[" .. name .. "] addon initialised, Auto panel exists")
         if #env.errors == 0 and env.G.FishingBuddy.Auto then
            env:call("toggle", env.G.FishingBuddy.Auto.Toggle)
            env:advance(15, 0.1)
            r:check(env.G.FishingBuddy.Auto.IsRunning() and env.server.casts >= 1, "[" .. name .. "] Toggle() starts auto fishing and the bot casts", table.concat(sent_texts(env), " | "))
         end
      end
   end)

scenario("lure-in-bags",
   "lures (Shiny Bauble) are in the bags and none is applied: exercises the loop's lure branch (command, retries, give-up) and the lure button",
   function(r)
      local env = boot{ bom = "strip", world = { bags_have_lure = true, lure_seconds = 0 }, server = { lure_applies = false } }
      local FB = env.G.FishingBuddy
      r:check(#env.errors == 0, "boot: no Lua error", #env.errors > 0 and env.errors[1].message or nil)
      local best = FB.API.GetBestLure and FB.API.GetBestLure()
      r:check(best ~= nil, "GetBestLure() finds the lure in the bags", best and best.n or "nil")
      env:clear_sent()
      env:call("toggle", FB.Auto.Toggle)
      env:advance(120, 0.5)
      local texts = sent_texts(env)
      local lurelines = 0
      for _, t in ipairs(texts) do if t:find("^WHISPER:u ") then lurelines = lurelines + 1 end end
      r:check(#env.errors == 0, "2 minutes of loop with a missing lure: no Lua error", #env.errors > 0 and env.errors[1].message or nil)
      r:check(lurelines == 3, "lure command is sent 3 times and then given up", "lure lines: " .. lurelines .. "; all: " .. table.concat(texts, " | "))
      r:check(env.G.FishingAutoLureButton and env.G.FishingAutoLureButton:GetAttribute("type") == "item", "lure button is armed with the item")
      r.env = env
   end)

scenario("deDE",
   "German client (the reporter writes German): deDE strings, 'Angeln' skill name",
   function(r)
      local env = boot{ bom = "strip", locale = "deDE" }
      check_boot(r, env)
      drive_auto(r, env)
      r.env = env
   end)

scenario("esES-zhCN-ruRU",
   "other locales boot (they fall back to enUS for the Auto strings)",
   function(r)
      for _, loc in ipairs{ "esES", "zhCN", "ruRU", "frFR" } do
         local env = boot{ bom = "strip", locale = loc }
         r:check(#env.errors == 0, loc .. ": boots without Lua error", #env.errors > 0 and env.errors[1].message or nil)
         r:check(env.G.FishingAutoPanel ~= nil, loc .. ": Auto panel exists")
         local n = #env.errors
         env:call("toggle", env.G.FishingBuddy.Auto.Toggle)
         env:advance(10, 0.5)
         env:call("toggle", env.G.FishingBuddy.Auto.Toggle)
         r:check(#env.errors == n, loc .. ": toggle on/off raises no Lua error", #env.errors > n and env.errors[n + 1].message or nil)
      end
   end)

scenario("pole-not-cached",
   "item 6256 is not in the client's item cache (fresh private-server character): LibFishing falls back to the texture check",
   function(r)
      local env = boot{ bom = "strip", world = { pole_item_cached = false } }
      check_boot(r, env)
      drive_auto(r, env)
      r.env = env
   end)

scenario("late-equip",
   "no pole at login; the player equips one later -> panel appears, fishing mode starts, then the pole is removed during a run",
   function(r)
      local env = new_env{ bom = "strip", world = { pole_equipped = false } }
      env:load_addon()
      login(env)
      local FB = env.G.FishingBuddy
      r:check(#env.errors == 0, "boot without pole: no Lua error")
      r:check(FB.StartedFishing == nil, "no fishing mode without a pole")
      r:check(env.G.FishingAutoPanel:IsVisible() == nil, "panel hidden without pole (AutoFishPanelOnlyWithPole default)")
      env:clear_sent()
      env:call("toggle", FB.Auto.Toggle)
      r:check(not FB.Auto.IsRunning() and #env.sent == 0, "Toggle() without pole: refuses to start and sends nothing")
      r:check(chat_has(env, "Equip a fishing pole"), "Toggle() without pole: tells the player to equip a pole")
      env.world.pole_equipped = true
      env:fire("ITEM_LOCK_CHANGED")
      env:fire("PLAYER_EQUIPMENT_CHANGED", 16)
      r:check(FB.StartedFishing ~= nil, "equipping a pole starts fishing mode")
      env:advance(1, 0.5)
      r:check(env.G.FishingAutoPanel:IsVisible() == 1, "panel appears after equipping a pole")
      env:clear_sent()
      env:call("toggle", FB.Auto.Toggle)
      r:check(FB.Auto.IsRunning(), "Toggle() after equipping starts auto fishing")
      env:advance(15, 0.1)
      r:check(env.server.casts >= 1, "... and the bot casts")
      env.world.pole_equipped = false
      env:clear_sent()
      env:advance(5, 0.5)
      r:check(not FB.Auto.IsRunning(), "watchdog stops auto fishing when the pole is removed")
      local texts = sent_texts(env)
      r:check(texts[1] == "WHISPER:nc +mount,-master fishing,?", "stop commands were sent on that automatic stop", table.concat(texts, " | "))
      env:advance(10, 0.1)
      r:check(not env.server.active, "... and the self bot we switched on was switched off again")
      r:check(#env.errors == 0, "no Lua error in the whole sequence", #env.errors > 0 and env.errors[1].message or nil)
      r.env = env
   end)

scenario("easycast",
   "original Fishing Buddy 'Easy Cast' (double right click casts): option off by default; with it on, a double click prepares the secure button",
   function(r)
      local env = boot{ bom = "strip" }
      local FB, G = env.G.FishingBuddy, env.G
      r:check(#env.errors == 0, "boot: no Lua error")
      r:check(FB.GetSetting("EasyCast") == 0 or FB.GetSetting("EasyCast") == nil, "EasyCast is OFF by default", "EasyCast=" .. tostring(FB.GetSetting("EasyCast")))
      env.override_bindings = {}
      env:run_script(G.WorldFrame, "OnMouseDown", "RightButton"); env:advance(0.2, 0.05)
      env:run_script(G.WorldFrame, "OnMouseDown", "RightButton")
      r:check(#env.override_bindings == 0, "default settings: a double right click does nothing (no override binding set)")
      FB.SetSetting("EasyCast", 1)
      env:advance(2, 0.5)
      env.override_bindings = {}
      env:run_script(G.WorldFrame, "OnMouseDown", "RightButton"); env:advance(0.2, 0.05)
      local n = #env.errors
      env:run_script(G.WorldFrame, "OnMouseDown", "RightButton")
      r:check(#env.errors == n, "EasyCast on: double right click raised no Lua error", #env.errors > n and env.errors[n + 1].message or nil)
      r:check(#env.override_bindings == 1 and env.override_bindings[1].key == "BUTTON2" and env.override_bindings[1].button == "FB_FishingButton",
              "EasyCast on: BUTTON2 is overridden to click FB_FishingButton", env.override_bindings[1] and env.override_bindings[1].key or "none")
      local btn = G.FB_FishingButton
      r:check(btn and btn:GetAttribute("type") == "spell" and btn:GetAttribute("spell") == "Fishing",
              "EasyCast on: secure button is set to cast the spell 'Fishing'", btn and tostring(btn:GetAttribute("spell")) or "no button")
      r.env = env
   end)

-- What-if: a bundled library fails to load (missing file, or another addon's incompatible copy wins
-- in LibStub/DongleStub).  Not a claim that this happens; it shows how far one failure reaches.
for _, w in ipairs{
   { "astrolabe-fails", "Libs/Astrolabe/Astrolabe.lua" },
   { "tourist-fails", "Libs/LibTourist-3.0/LibTourist-3.0.lua" },
   { "locations-file-fails", "FishingLocationsFrame.lua" },
} do
   scenario("whatif-" .. w[1], "WHAT-IF " .. w[2] .. " does not load (all other files normal) -- how far does one failure reach?",
      function(r)
         local env = boot{ bom = "strip", fail_files = { [w[2]] = true } }
         r.env = env
         local FB = env.G.FishingBuddy
         r:check(FB and FB.IsLoaded and FB.IsLoaded(), "FishingBuddy initialised")
         r:check(env.G.FishingAutoPanel ~= nil, "Auto panel created")
         if FB and FB.Auto then
            env:clear_sent()
            env:call("toggle", FB.Auto.Toggle)
            r:check(env.G.FishingBuddy.Auto.IsRunning() and sent_texts(env)[1] == "WHISPER:nc ?", "Toggle() starts by asking the bot", table.concat(sent_texts(env), " | "))
         else
            r:check(false, "FishingBuddy.Auto exists")
         end
      end)
end

scenario("no-NONE_KEY",
   "the client does NOT define the global NONE_KEY (used by FishingOutfitManager.lua:278 and LibFishing:463)",
   function(r)
      local env = boot{ bom = "strip", no_none_key = true }
      r:check(#env.errors == 0, "boot: no Lua error", #env.errors > 0 and (#env.errors .. " error(s), first: " .. env.errors[1].message) or nil)
      drive_auto(r, env)
      r.env = env
   end)

-- ---------------------------------------------------------------------------
-- Auto fishing against the server model (tests/harness/botserver.lua)
-- ---------------------------------------------------------------------------

local function Auto(env) return env.G.FishingBuddy.Auto end

local function start(env, secs)
   env:call("Auto.Toggle", Auto(env).Toggle)
   env:advance(secs or 45, 0.1)
end

local function stop(env, secs)
   env:call("Auto.Stop", Auto(env).Stop)
   env:advance(secs or 35, 0.1)
end

local function count_sent(env, text)
   local n = 0
   for _, e in ipairs(env.sent) do if e.text == text then n = n + 1 end end
   return n
end

local function count_sent_matching(env, plain)
   local n = 0
   for _, e in ipairs(env.sent) do if e.text:find(plain, 1, true) then n = n + 1 end end
   return n
end

local function sent_type(env, chattype)
   local n = 0
   for _, e in ipairs(env.sent) do if e.chattype == chattype then n = n + 1 end end
   return n
end

local function no_errors(r, env, what)
   r:check(#env.errors == 0, (what or "scenario") .. ": no Lua error",
           #env.errors > 0 and (env.errors[1].context .. ": " .. env.errors[1].message) or nil)
end

-- the invariant behind the whole protocol: the bot keeps only the LAST nc command per AI update
local function no_collapse(r, env, what)
   r:check(#env.server.collapsed == 0, (what or "scenario") .. ": no nc command was overwritten by a later one in the same AI update",
           #env.server.collapsed .. " collapsed: " .. (env.server.collapsed[1] and env.server.collapsed[1].text or ""))
end

local function saved_of(env)
   return { FishingBuddy_Info = roundtrip(env.G.FishingBuddy_Info), FishingBuddy_Player = roundtrip(env.G.FishingBuddy_Player) }
end

scenario("auto-old-commands-fail-solo",
   "MODEL CHECK: the lines the 0.9.9 build sent ('.playerbots bot self' as SAY, '/p nc +master fishing' as PARTY) leave a solo player with an idle bot",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local G, srv = env.G, env.server
      G.SendChatMessage(".playerbots bot self", "SAY")
      G.SendChatMessage("nc +master fishing", "PARTY")
      env:advance(30, 0.1)
      r:check(srv.active, "the toggle works: the self bot is on")
      r:check(not srv:has("master fishing"), "... but the strategy never arrives (the party line is dropped)")
      r:check(#srv.dropped == 1 and srv.dropped[1].why == "no group", "the core dropped exactly the party line", #srv.dropped .. " dropped")
      -- the same player in a group: the old lines work
      local env2 = boot{ bom = "strip", world = { party = 1 } }
      env2.G.SendChatMessage(".playerbots bot self", "SAY")
      env2.G.SendChatMessage("nc +master fishing", "PARTY")
      env2:advance(30, 0.1)
      r:check(env2.server:has("master fishing"), "grouped: the old party line reaches the bot (why it 'worked' for some setups)")
   end)

scenario("auto-model-collapse",
   "MODEL CHECK: two nc whispers in the same AI update -> only the last one runs; co/ll are separate triggers; the bot is deaf for ~10 s after activation",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local G, srv = env.G, env.server
      G.SendChatMessage(".playerbots bot self", "SAY")
      env:advance(1, 0.1)
      local me = G.UnitName("player")
      G.SendChatMessage("nc -mount", "WHISPER", nil, me)
      G.SendChatMessage("nc +master fishing", "WHISPER", nil, me)
      G.SendChatMessage("co +aoe", "WHISPER", nil, me)
      env:advance(5, 0.1)
      r:check(#srv.received == 0, "deaf window: nothing was read 6 s after activation")
      env:advance(10, 0.1)
      r:check(#srv.received == 3, "after the window all three queued commands are drained", #srv.received .. " received")
      r:check(srv:has("master fishing") and srv:has("mount"), "only the LAST nc ran: '+master fishing' yes, '-mount' lost")
      r:check(#srv.collapsed == 1, "and the model counted the overwritten command", #srv.collapsed .. " collapsed")
      -- '!' resets after the other items, in the same command
      srv:run_nc("!,+master fishing")
      r:check(not srv:has("master fishing"), "'nc !,+master fishing' ends with the defaults (the reset runs last)")
   end)

scenario("auto-solo",
   "solo player, self bot off (the reported case): one preparation command ('-mount', '-master fishing'), then the loop casts; Stop gives 'mount' back and switches the bot off",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      start(env)
      local st = Auto(env).GetState()
      r:check(st.running and st.step == "run", "running, step 'run'", st.step)
      r:check(srv.casts >= 1 and not srv:has("mount"), "the bot fishes (the loop cast) and has no 'mount'")
      r:check(srv.toggles == 1 and st.ownsBot, "one toggle, and the addon knows it switched the bot on")
      r:check(sent_type(env, "PARTY") == 0, "no party chat is sent")
      r:check(count_sent(env, "nc ?,-mount,-master fishing,?") == 1, "the preparation went out as ONE command (before-list, -mount, -master fishing, after-list)")
      r:check(count_sent_matching(env, "+master fishing") == 0 and count_sent(env, "nc -mount") == 0, "... and not as separate nc lines; 'master fishing' is never added")
      r:check(#srv.dropped == 0 and #srv.said == 0, "nothing dropped by the core, nothing said aloud")
      no_collapse(r, env)
      stop(env)
      r:check(not srv.active and srv.toggles == 2, "Stop switches the bot off again (we had switched it on)")
      r:check(srv.persisted and not srv.persisted["master fishing"] and srv.persisted["mount"], "the stored set is clean: no 'master fishing', 'mount' back")
      no_collapse(r, env, "after Stop")
      no_errors(r, env)
   end)

scenario("auto-bot-already-on",
   "the self bot is already on (BotPad / AutoTravel / SelfBotLevel > 2): Start must NOT toggle it off; Stop must leave it on and give 'mount' back",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      local srv = env.server
      r:check(srv.active, "precondition: the bot is on at login without any message")
      env:advance(15, 0.5)                    -- the first AI update is over: the bot hears chat commands
      start(env, 30)
      r:check(srv.toggles == 0, "Start did not send '.playerbots bot self'", "toggles: " .. srv.toggles)
      r:check(srv.casts >= 1 and not srv:has("mount"), "the bot fishes, 'mount' was removed")
      r:check(not Auto(env).GetState().ownsBot, "the addon does not claim the bot")
      r:check(count_sent(env, "nc -mount,?") == 1, "warm start: the list was known, so no leading '?'")
      stop(env)
      r:check(srv.active and srv.toggles == 0, "Stop leaves the bot on (not ours) and sends no toggle")
      r:check(not srv:has("master fishing") and srv:has("mount"), "... but gives 'mount' back")
      no_collapse(r, env)
      no_errors(r, env)
   end)

scenario("auto-bot-already-on-deaf",
   "the same, but Start comes within seconds of the login: the freshly activated bot has not heard its first command yet -- the answer 'deactivated' reveals it, the second toggle puts things back, the bot is not claimed",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      local srv = env.server
      start(env, 45)
      r:check(srv.toggles == 2, "off + on again: the addon could not know", "toggles: " .. srv.toggles)
      r:check(srv.active and srv.casts >= 1, "the bot is on and fishes")
      r:check(not Auto(env).GetState().ownsBot, "after the correction the bot is back in the state it was in: not ours")
      stop(env)
      r:check(srv.active and srv.toggles == 2, "Stop leaves the bot on", "toggles: " .. srv.toggles)
      r:check(not srv:has("master fishing"), "... and takes the strategy back")
      no_collapse(r, env)
      no_errors(r, env)
   end)

scenario("auto-refused",
   "the server refuses the self bot (SelfBotLevel 1 without GM rights, or 0): clear message, nothing else is sent, not 'running'",
   function(r)
      for _, case in ipairs{
         { name = "level 1, no GM", server = { selfbot_level = 1, gm = false }, text = "restricted for this account" },
         { name = "level 0",        server = { selfbot_level = 0 },             text = "disabled server-wide" },
         { name = "Enabled=0",      server = { disabled = true },               text = "currently disabled" },
      } do
         local env = boot{ bom = "strip", server = case.server }
         r.env = env
         start(env, 20)
         r:check(not Auto(env).IsRunning(), "[" .. case.name .. "] not running")
         r:check(chat_has(env, case.text), "[" .. case.name .. "] the refusal text is shown")
         r:check(chat_has(env, "The server refuses the self bot"), "[" .. case.name .. "] the addon explains it")
         r:check(chat_has(env, "SelfBotLevel"), "[" .. case.name .. "] and names the server setting")
         r:check(count_sent_matching(env, "master fishing") == 0, "[" .. case.name .. "] no strategy command was sent")
         r:check(env.server.toggles == 1, "[" .. case.name .. "] exactly one toggle attempt")
      end
      -- a GM at level 1 may use it
      local env = boot{ bom = "strip", server = { selfbot_level = 1, gm = true } }
      start(env)
      r:check(Auto(env).IsRunning() and env.server.casts >= 1, "[level 1, GM] works")
   end)

scenario("auto-no-module",
   "mod-playerbots is not installed ('There is no such command'): the addon gives up with an explanation instead of claiming to run",
   function(r)
      local env = boot{ bom = "strip", server = { module_missing = true } }
      r.env = env
      start(env, 20)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(chat_has(env, "No answer to '.playerbots bot self'"), "the player is told that nobody answered")
      r:check(#env.server.said == 0, "nothing was spoken aloud")
      -- AllowPlayerCommands = 0 on a non-GM account: the dot line is spoken in /say (unavoidable; the toggle line has to be sent)
      local env2 = boot{ bom = "strip", server = { module_missing = "say" } }
      start(env2, 20)
      r:check(not Auto(env2).IsRunning() and chat_has(env2, "No answer to"), "AllowPlayerCommands=0: same outcome")
      r:check(#env2.server.said == 1, "... and the single toggle line was spoken aloud (the only unavoidable leak)", #env2.server.said .. " said")
   end)

scenario("auto-whispers-blocked",
   "GM account without '.whispers on': whispers to oneself are refused -> the addon says so",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 1, gm = true, whisper_filter = true } }
      r.env = env
      start(env)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(chat_has(env, ".whispers on"), "the message names '.whispers on'")
   end)

scenario("auto-deaf-bot",
   "the bot is on but ignores commands (strategy 'chat' removed): Start toggles twice to reload the stored set and does not claim the bot",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      srv.persisted = {}
      for _, n in ipairs{ "nc", "food", "follow", "default", "quest", "loot", "gather", "mount" } do srv.persisted[n] = true end
      srv:activate(true)
      srv.nc.chat = nil                       -- deaf
      start(env, 70)
      r:check(srv.toggles == 2, "two toggles (off, on): Load re-adds +chat", "toggles: " .. srv.toggles)
      r:check(srv.casts >= 1, "after that the bot casts")
      r:check(not Auto(env).GetState().ownsBot, "the bot was on before, so it stays on after Stop")
      stop(env)
      r:check(srv.active, "Stop leaves it on")
      no_collapse(r, env)
   end)

scenario("auto-botpad-old",
   "Botpad without the Hold interface replays 'nc !' + a mode set after EVERY 'SelfBot is now active': the addon waits it out and sends last",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, false)
      start(env, 60)
      r:check(BP.Bot.bursts == 1, "Botpad did its burst once", "bursts: " .. BP.Bot.bursts)
      r:check(env.server.casts >= 1, "the preparation survived the burst (ours was the last nc in the queue) and the bot casts")
      r:check(count_sent(env, "nc ?,-mount,-master fishing,?") == 1, "no retry was needed")
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run", "running")
   end)

scenario("auto-botpad-hold",
   "Botpad 1.3: the addon asks Botpad to hold its mode while running; Botpad skips its burst; released on stop, every run again",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, true)
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(BP.Bot.holders["Fishing Buddy"], "hold is requested before the bot is switched on")
      env:advance(45, 0.1)
      r:check(BP.Bot.bursts == 0, "Botpad did not replay its mode", "bursts: " .. BP.Bot.bursts)
      r:check(env.server.casts >= 1, "the bot casts")
      stop(env)
      r:check(next(BP.Bot.holders) == nil, "hold released after the stop sequence")
      -- a second run in the same session takes the hold again
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(BP.Bot.holders["Fishing Buddy"], "second run: hold requested again")
      env:advance(45, 0.1)
      r:check(BP.Bot.bursts == 0 and env.server.casts >= 1, "second run: still no burst, the bot casts")
      stop(env)
      r:check(next(BP.Bot.holders) == nil, "second run: released")
      -- also released when the start fails
      local env2 = boot{ bom = "strip", server = { selfbot_level = 0 } }
      local BP2 = Server.install_botpad_stub(env2, true)
      start(env2, 20)
      r:check(next(BP2.Bot.holders) == nil, "hold released when the server refuses")
   end)

scenario("auto-botpad-hold-errors",
   "a Hold/Release that raises an error must not break Start/Stop or leave the addon in a half state",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, true)
      BP.Bot.Hold = function() error("boom in Hold") end
      BP.Bot.Release = function() error("boom in Release") end
      start(env, 45)
      r:check(Auto(env).IsRunning() and env.server.casts >= 1, "start works although Hold raised")
      stop(env)
      r:check(not Auto(env).IsRunning() and not env.server.active, "stop works although Release raised")
   end)

scenario("auto-mount",
   "a self bot with a mount mounts itself (strategy 'mount'): '-mount' is in the very first command, so the character never mounts; restored afterwards",
   function(r)
      local env = boot{ bom = "strip", server = { mount_owned = true } }
      r.env = env
      local srv = env.server
      start(env)
      r:check(not srv:has("mount"), "'mount' is off while fishing")
      env:advance(90, 0.5)
      r:check(not env.world.mounted, "the character did not mount (the first drained command already carried -mount)")
      stop(env)
      r:check(not srv.active and srv.persisted and srv.persisted["mount"], "bot off again, 'mount' restored in the stored set")
      -- option off: the model mounts the character and the addon warns
      local env2 = boot{ bom = "strip", server = { mount_owned = true } }
      env2.G.FishingBuddy.SetSetting("AutoFishNoMount", 0)
      start(env2, 40)
      env2:advance(30, 0.5)
      r:check(env2.world.mounted, "with the option off the model mounts the character")
      r:check(chat_has(env2, "You are mounted"), "... and the addon warns about it")
      -- 'mount' is restored only if it was there
      local env3 = boot{ bom = "strip", server = { mount_owned = true, active = true,
         persisted = { "nc", "chat", "follow", "default" } } }
      start(env3, 30)
      stop(env3)
      r:check(not env3.server:has("mount"), "a stored set without 'mount' does not get one added on Stop")
      r:check(count_sent_matching(env3, "-mount") == 0 and count_sent_matching(env3, "master fishing") == 0,
              "warm start without 'mount' in the list: nothing to prepare, no nc command besides the probe")
   end)

scenario("auto-start-mounted",
   "mounted at Start: refuse with a hint, send nothing",
   function(r)
      local env = boot{ bom = "strip", world = { mounted = true } }
      r.env = env
      env:clear_sent()
      start(env, 5)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(#env.sent == 0, "nothing was sent")
      r:check(chat_has(env, "Dismount first"), "hint shown")
   end)

scenario("auto-echo-hidden",
   "the whispers to oneself and the bot's 'Strategies:' answers stay out of the chat window; other players' whispers do not",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env)
      local shown = table.concat(env.chat_display, "\n")
      r:check(#env.chat_hidden >= 4, "echoes were hidden", #env.chat_hidden .. " hidden")
      r:check(not shown:find("master fishing", 1, true) and not shown:find("Strategies:", 1, true) and not shown:find("nc ?", 1, true),
              "none of them was displayed", shown)
      r:check(shown:find("SelfBot is now active", 1, true) ~= nil, "the server's own message is still shown")
      local ok = env:chat_event("CHAT_MSG_WHISPER", "Strategies: just a stranger", "Somebody")
      r:check(ok, "a whisper from another player is displayed even if it looks similar")
      env.G.FishingBuddy.SetSetting("AutoFishHideEcho", 0)
      env.chat_display = {}
      env:chat_event("CHAT_MSG_WHISPER", "Strategies: a, b", env.G.UnitName("player"))
      r:check(#env.chat_display == 1, "with the option off nothing is hidden")
   end)

scenario("auto-no-reply",
   "the client never shows the bot's answer (or it is suppressed): after the wait the start is accepted as UNVERIFIED with a warning",
   function(r)
      local env = boot{ bom = "strip", server = { reply_visible = false } }
      r.env = env
      start(env, 60)
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run", "running")
      r:check(env.server.casts >= 1 and not env.server:has("mount"), "the bot casts and mount was removed (blindly, in the first command)")
      r:check(chat_has(env, "did not answer the strategy check"), "the player is told that the start could not be confirmed")
      r:check(count_sent(env, "nc ?,-mount,-master fishing,?") == 1, "no pointless retries")
      -- Stop without visible answers: waits, then switches off
      env:clear_sent()
      local t0 = env.now
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(15, 0.1)
      r:check(env.server.active, "15 s after Stop the bot is still waiting for a confirmation (not switched off yet)")
      env:advance(20, 0.1)
      r:check(not env.server.active, "after the stop wait it is switched off anyway")
      r:check(count_sent(env, "nc +mount,-master fishing,?") >= 2, "the removal was repeated (the same command, never a different nc)",
              count_sent(env, "nc +mount,-master fishing,?") .. " sends")
      no_collapse(r, env)
   end)

scenario("auto-stop-early",
   "Stop right after the bot was switched on (before any strategy was set): the bot is switched off again, nothing left behind",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(3.2, 0.1)
      r:check(env.server.active, "precondition: bot is on")
      r:check(count_sent_matching(env, "master fishing") == 0, "precondition: nothing set yet")
      stop(env, 5)
      r:check(not env.server.active, "bot off")
      r:check(not env.server.persisted or not env.server.persisted["master fishing"], "no stored strategy")
   end)

scenario("auto-stop-during-toggle",
   "Stop while '.playerbots bot self' is still in flight: the late answer is undone, whichever way it went",
   function(r)
      -- bot off -> the toggle switches it on; Stop pressed before the answer arrives
      local env = boot{ bom = "strip" }
      r.env = env
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(3.02, 0.01)
      r:check(Auto(env).GetState().step == "toggle", "precondition: toggle sent, answer outstanding", Auto(env).GetState().step)
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(10, 0.1)
      r:check(not env.server.active, "the bot we switched on is switched off again")
      r:check(env.server.toggles == 2, "exactly one undo toggle", "toggles: " .. env.server.toggles)
      -- bot silently on (deaf probe): the toggle switches it OFF; Stop before the answer -> switched back on
      local env2 = boot{ bom = "strip" }
      env2.server:activate(true)
      env2.server.nc.chat = nil                 -- on but does not answer the probe
      env2:call("Auto.Toggle", Auto(env2).Toggle)
      env2:advance(3.02, 0.01)
      env2:call("Auto.Stop", Auto(env2).Stop)
      env2:advance(10, 0.1)
      r:check(env2.server.active, "a bot that was on before is on again after the undo")
   end)

scenario("auto-foreign-off",
   "somebody switches the self bot off during the run, or during the stop wait: the addon never switches it back on",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      start(env)
      srv:toggle()                                          -- the user clicks Botpad's BOT AUS
      env:advance(10, 0.1)
      r:check(not Auto(env).IsRunning(), "the run ended")
      r:check(chat_has(env, "switched off"), "with a reason")
      r:check(not srv.active and srv.toggles == 2, "and the bot stayed off (no toggle from the addon)", "toggles: " .. srv.toggles)
      -- during the stop wait
      local env2 = boot{ bom = "strip", server = { tick = 0.3 } }
      start(env2)
      env2:call("Auto.Stop", Auto(env2).Stop)
      env2.server:toggle()                                  -- switched off while we wait for the confirmation
      env2:advance(10, 0.1)
      r:check(not env2.server.active and env2.server.toggles == 2, "no second toggle after a foreign switch-off during the stop wait", "toggles: " .. env2.server.toggles)
      r:check(Auto(env2).GetState().step == "idle", "the stop sequence ended")
   end)

scenario("auto-bot-sleeping",
   "the bot is asleep (does not read chat) and answers late while the character is channelling: Start does not toggle it, Stop waits for the bot to wake up and gives 'mount' back",
   function(r)
      local env = boot{ bom = "strip", world = { channeling = true },
         server = { active = true, persisted = { "nc", "chat", "follow", "default", "mount" } } }
      r.env = env
      local srv = env.server
      srv.ready_at = env.now + 17                           -- asleep for the next 17 s
      start(env, 40)
      r:check(srv.toggles == 0, "no toggle: the probe wait was extended because the character is channelling", "toggles: " .. srv.toggles)
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run", "running")
      srv.ready_at = env.now + 17                           -- and asleep again when Stop comes
      stop(env, 60)
      r:check(srv.active and not srv:has("master fishing") and srv:has("mount"), "Stop waited for the bot to wake up and gave 'mount' back; the bot (not ours) stays on")
      no_collapse(r, env)
   end)

scenario("auto-late-answers",
   "a slow connection: replies take up to ~1 s each way; everything still works",
   function(r)
      local env = boot{ bom = "strip", server = { latency = 1.0 } }
      r.env = env
      start(env, 60)
      r:check(Auto(env).IsRunning() and env.server.casts >= 1, "running, the bot casts")
      r:check(env.server.toggles == 1, "one toggle", "toggles: " .. env.server.toggles)
      stop(env, 40)
      r:check(not env.server.active and env.server.persisted and not env.server.persisted["master fishing"], "stopped cleanly")
   end)

scenario("auto-settings-migration",
   "saved command blocks that still hold the 0.9.9 defaults are replaced by the new defaults; edited blocks stay; the retired start/keep-alive blocks are simply no longer used",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishStartCommands = ".playerbots bot self\r\n/p nc +master fishing",
         AutoFishKeepAliveCommands = "/p nc +master fishing\n",
         AutoFishStopCommands = "/p nc -master fishing\n.playerbots bot self",
         AutoFishLureCommands = "/p u %l",
      }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved }
      r.env = env
      local S = env.G.FishingBuddy_Player.Settings
      r:check(S.AutoFishStopCommands == nil and S.AutoFishLureCommands == nil, "the old stop and lure defaults were cleared")
      start(env)
      r:check(env.server.casts >= 1 and #env.server.dropped == 0, "and the new defaults work: the retired start block ('nc +master fishing') is not used")
      r:check(count_sent_matching(env, "+master fishing") == 0, "no '+master fishing' was sent")
      local saved2 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishLoopCommands = "/w %p do move near water\n/w %p do go fishing\n/w %p co +loot" }, Outfit = {}, WasWearing = {} } }
      local env2 = boot{ bom = "strip", saved = saved2 }
      r:check(env2.G.FishingBuddy_Player.Settings.AutoFishLoopCommands == "/w %p do move near water\n/w %p do go fishing\n/w %p co +loot", "an edited loop block is kept")
   end)

scenario("auto-custom-blocks",
   "edited loop block: a legacy toggle line is dropped from the STORED block (once, with a note); '/p nc' lines are merged into the single nc command, "
   .. "solo or grouped; other lines are sent as written, before every cast",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishLoopCommands = ".playerbots bot self\n/p nc +gather\n/p co +loot\n/w %p co +aoe\n/w %p do move near water\n/w %p do go fishing" }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved }
      r.env = env
      start(env)
      local joined = table.concat(sent_texts(env), " | ")
      r:check(env.server.casts >= 1, "the custom loop block casts", joined)
      r:check(env.server.toggles == 1, "the legacy toggle line did not cause a second toggle", "toggles: " .. env.server.toggles)
      r:check(count_sent_matching(env, "nc +gather") >= 1 and sent_type(env, "PARTY") == 0, "'/p nc ...' was merged into a whisper, not sent as party chat", joined)
      local gotloot, gotaoe = false, false
      for _, rcv in ipairs(env.server.received) do
         if rcv.text == "co +loot" then gotloot = true end
         if rcv.text == "co +aoe" then gotaoe = true end
      end
      r:check(gotloot and gotaoe, "the 'co' lines (solo '/p' and '/w') reached the bot", joined)
      r:check(chat_has(env, "Removed '.playerbots bot self'"), "the player is told that the toggle line was removed")
      r:check(chat_has(env, "not in a group"), "and that a '/p' line goes to the own bot while ungrouped")
      local S = env.G.FishingBuddy_Player.Settings.AutoFishLoopCommands
      r:check(S and not S:find("playerbots", 1, true), "the stored block no longer contains the toggle line", tostring(S))
      no_collapse(r, env)
      -- grouped: the nc line still goes to the own bot (whisper), a plain /p line goes to the party
      local saved2 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishLoopCommands = "/p nc +gather\n/p hello party\n/w %p do move near water\n/w %p do go fishing" }, Outfit = {}, WasWearing = {} } }
      local env2 = boot{ bom = "strip", saved = saved2, world = { party = 2 } }
      start(env2)
      r:check(env2.server.casts >= 1, "grouped: the bot casts")
      local hello = count_sent(env2, "hello party")
      r:check(hello >= 1 and sent_type(env2, "PARTY") == hello, "grouped: the plain /p line is real party chat, nothing else goes to the party")
      r:check(not chat_has(env2, "not in a group"), "no warning when grouped")
      no_collapse(r, env2, "grouped")
   end)

scenario("auto-trip",
   "AutoTravel: no Start during a trip; no new cast during a trip; a stop during a trip leaves the bot to AutoTravel",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      env.G.AutoTravel = { active = true }
      env:clear_sent()
      start(env, 5)
      r:check(not Auto(env).IsRunning() and #env.sent == 0, "Start refused while a trip is running, nothing sent")
      r:check(chat_has(env, "AutoTravel trip is running"), "with a hint")
      env.G.AutoTravel.active = false
      start(env)
      r:check(Auto(env).IsRunning(), "running after the trip")
      env.G.AutoTravel = { active = true }
      env:advance(30, 0.5)                    -- a cast that is under way ends
      env:clear_sent()
      env:advance(120, 0.5)
      r:check(count_sent_matching(env, "do go fishing") == 0 and count_sent_matching(env, "do move near water") == 0,
              "no cast during the trip", "sent: " .. table.concat(sent_texts(env), " | "))
      env.G.AutoTravel.active = false
      env:advance(40, 0.5)
      r:check(count_sent_matching(env, "do go fishing") >= 1, "the loop resumes after the trip")
      -- stop in the middle of a trip that relies on the bot (supportOn)
      env.G.AutoTravel = { active = true, supportOn = true }
      stop(env)
      r:check(env.server.active, "the bot stays on: AutoTravel is using it")
      r:check(not env.server:has("master fishing") and env.server:has("mount"), "... and 'mount' is given back")
   end)

scenario("auto-logout",
   "PLAYER_LOGOUT / /reload while running: the removal goes out, the bot is NOT switched off in the same frame; the next session finishes the job",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env)
      env:clear_sent()
      env:fire("PLAYER_LOGOUT")
      local t = sent_texts(env)
      r:check(t[1] == "WHISPER:nc +mount,-master fishing" and #t == 1, "only the removal is sent (no toggle in the same frame)", table.concat(t, " | "))
      env:advance(3, 0.1)
      r:check(env.server.active and not env.server:has("master fishing") and env.server:has("mount"), "the bot executed it before anything else happened")
      local pend = env.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(pend) == "table" and pend.ownsBot == true and pend.restore == true, "a pending cleanup was saved for the next session")
      -- /reload: new Lua state, same character, the bot is still on
      local env2 = boot{ bom = "strip", saved = saved_of(env),
         server = { active = true, persisted = (function() local l = {} for n in pairs(env.server.persisted) do l[#l + 1] = n end return l end)() } }
      r.env = env2
      env2:advance(30, 0.1)
      r:check(not env2.server.active, "the new session found the bot we had switched on and switched it off")
      r:check(env2.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "pending flag cleared")
      r:check(env2.server.persisted and not env2.server.persisted["master fishing"] and env2.server.persisted["mount"], "stored set clean")
      -- pending flag but the bot is off (real logout): nothing to do, flag cleared, nothing sent but the probe
      local env3 = boot{ bom = "strip", saved = saved_of(env) }
      env3.G.FishingBuddy_Player.Settings.AutoFishPending = { ownsBot = true, restore = true }
      env3:fire("PLAYER_LOGIN")
      env3:advance(30, 0.1)
      r:check(env3.server.toggles == 0, "bot off: no toggle is sent blindly", "toggles: " .. env3.server.toggles)
      local kept = env3.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(kept) == "table" and kept.restore == true and kept.tries == 1,
              "the note stays (the bot did not answer, the leftovers may still be stored) and counts this login")
   end)

scenario("auto-logout-while-stopping",
   "/reload while the stop sequence is still waiting: the bot is not forgotten",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env, 55)
      env.server.ready_at = env.now + 100      -- the bot stops reading chat: the removal stays queued
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(0.5, 0.1)
      r:check(Auto(env).GetState().stopping, "precondition: stop sequence pending (the bot has not answered)")
      env:fire("PLAYER_LOGOUT")
      local pend = env.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(pend) == "table" and pend.ownsBot == true, "pending cleanup saved")
      r:check(not Auto(env).GetState().stopping, "and the pending shutdown was dropped cleanly")
      -- /reload: the new session finds the bot still on and cleans up
      local env2 = boot{ bom = "strip", saved = saved_of(env),
         server = { active = true, persisted = (function() local l = {} for n in pairs(env.server.persisted) do l[#l + 1] = n end return l end)() } }
      r.env = env2
      r:check(not env2.server:has("mount"), "precondition: 'mount' is still missing on the bot")
      env2:advance(40, 0.1)
      r:check(not env2.server.active, "the next session switched the bot we had started off again")
      r:check(not env2.server.persisted["master fishing"] and env2.server.persisted["mount"], "... after restoring 'mount'")
      r:check(env2.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "pending flag cleared")
      no_errors(r, env2)
   end)

scenario("auto-failing-stop-handler",
   "an error in another addon's AUTO_STOP_EVT handler must not leave the strategy set, the bot on or Botpad held",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, true)
      env.G.FishingBuddy.API.RegisterHandlers({ [env.G.FBConstants.AUTO_STOP_EVT] = function() error("handler exploded") end })
      start(env)
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(35, 0.1)
      r:check(not env.server.active and not env.server:has("master fishing"), "strategy taken back and bot off despite the failing handler")
      r:check(next(BP.Bot.holders) == nil, "Botpad released")
      r:check(#env.errors >= 1, "the handler's error was reported (not swallowed)")
   end)

scenario("auto-diag",
   "/fb auto diag and /fb auto probe print without errors and show the state",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env)
      env.chat = {}
      env:slash("/fb auto diag")
      r:check(chat_has(env, "self bot on"), "diag shows the self bot state")
      r:check(chat_has(env, "master fishing"), "diag shows the strategies the bot reported")
      r:check(chat_has(env, "-> /w"), "diag shows the trace of what was sent")
      r:check(chat_has(env, "seconds ago"), "... with relative times")
      env:slash("/fb auto probe")
      r:check(chat_has(env, "busy"), "probe while a session runs is refused politely")
      stop(env)
      env.chat = {}
      env:slash("/fb auto probe")
      env:advance(3, 0.1)
      r:check(chat_has(env, "Asked the bot"), "probe outside a session explains where the answer shows up")
      no_errors(r, env)
   end)

scenario("auto-warnings",
   "conflicting strategies and a bot without a pole are reported",
   function(r)
      local env = boot{ bom = "strip", server = { active = true, persisted = { "nc", "chat", "follow", "default", "grind", "mount" } } }
      r.env = env
      start(env, 30)
      r:check(chat_has(env, "Other bot strategies are active (grind"), "grind warning")
      env.server:whisper("I don't have a Fishing Pole")
      env:advance(2, 0.1)
      r:check(chat_has(env, "no fishing pole"), "the bot's complaint about the pole is shown")
   end)

scenario("auto-old-botpad-minimal",
   "Botpad before 1.3 in mode Minimal makes the bot deaf: a specific warning at Start",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      Server.install_botpad_stub(env, false)
      env.G.BotpadDB = { Mode = "minimal" }
      start(env, 5)
      r:check(chat_has(env, "Botpad before 1.3"), "warned")
   end)

-- Optional: the REAL Botpad (needs a checkout; BOTPAD_DIR or ../../BotPad next to the repo)
local function botpad_dir()
   local d = os.getenv("BOTPAD_DIR") or (repo .. "/../BotPad")
   local f = io.open(d .. "/Botpad.toc", "r")
   if f then f:close() return d end
   return nil
end

scenario("auto-real-botpad",
   "the real Botpad (>= 1.3) loaded next to the addon: no mode burst, 'master fishing' stays (SKIPPED when no Botpad checkout is found)",
   function(r)
      local dir = botpad_dir()
      if not dir then
         io.write("   (SKIPPED: no Botpad checkout; set BOTPAD_DIR)\n")
         r.skipped = true
         return
      end
      local env = new_env{ bom = "strip" }
      env:load_addon()
      env.G.IsAddOnLoaded = function(n) return n == "FishingBuddy" end
      for line in io.lines(dir .. "/Botpad.toc") do
         local f = line:match("^(BP_[%w_]+%.lua)%s*$")
         if f then env:load_lua(dir .. "/" .. f, "load " .. f) end
      end
      env:fire("ADDON_LOADED", "Botpad"); env:fire("PLAYER_LOGIN")
      login(env)
      r.env = env
      r:check(#env.errors == 0, "no Lua error", #env.errors > 0 and (env.errors[1].context .. ": " .. env.errors[1].message) or nil)
      if not env.G.Botpad.Bot.Hold then
         r:check(false, "this Botpad has no Hold interface (needs 1.3)")
         return
      end
      start(env, 45)
      r:check(env.server.casts >= 1, "the bot casts and went on casting")
      r:check(count_sent(env, "nc !") == 0 and count_sent(env, "co !") == 0, "Botpad did not send its reset")
      r:check(env.G.Botpad.Bot.IsHeld(), "Botpad is held while running")
      stop(env)
      r:check(not env.G.Botpad.Bot.IsHeld(), "... and released afterwards")
      -- Botpad's own ON handling after the hold is released: a later activation gets its mode again
      env.server:toggle(); env:advance(15, 0.1); env.server:toggle(); env:advance(2, 0.1)
      env.server:toggle(); env:advance(15, 0.1)
      r:check(count_sent(env, "nc !") >= 1, "after Release Botpad applies its mode again on the next activation")
   end)

-- ---------------------------------------------------------------------------
-- scenarios added after the independent review / mutation run (see git log)
-- ---------------------------------------------------------------------------

-- proposed_scenarios.lua  (mutation-testing lens)
-- ---------------------------------------------------------------------------
-- Extra scenarios for tests/scenarios.lua.  They close the gaps that a mutation run over FishingAuto.lua
-- found: small code changes (mutants) that the 52 existing scenarios do not notice.  Paste this block into
-- tests/scenarios.lua directly above the "-- run" section (after the scenario "auto-real-botpad"); it uses the
-- helpers that file defines (boot, start, stop, Auto, count_sent, count_sent_matching, sent_type, no_errors,
-- no_collapse, chat_has, strip_colors, sent_texts, saved_of, Server).
--
-- Every scenario passes on the unmodified FishingAuto.lua and fails on the mutants named in the "[...]" tag
-- above it (mutant ids refer to rv_mutation/mutants.py).  Offline only: stub client + server model, nothing
-- here was run in a real game.
-- ---------------------------------------------------------------------------

local PX = {}

function PX.chat_count(env, needle)
   local n = 0
   for _, l in ipairs(env.chat) do
      if strip_colors(l):find(needle, 1, true) then n = n + 1 end
   end
   return n
end

function PX.panel_texts(env)
   local out = {}
   for _, st in pairs(env.state) do
      if type(st.text) == "string" then
         local t = strip_colors(st.text)
         if t:find("Auto Fishing:", 1, true) or t:find("/h", 1, true) or t:find("slots", 1, true) then out[#out + 1] = t end
      end
   end
   return table.concat(out, " || ")
end

function PX.count_lure_lines(env)
   local n = 0
   for _, e in ipairs(env.sent) do if e.text:find("^u ") then n = n + 1 end end
   return n
end

function PX.received(srv, text)
   local n = 0
   for _, rcv in ipairs(srv.received) do if rcv.text == text then n = n + 1 end end
   return n
end

function PX.until_step(env, step, maxsecs)
   local guard = 0
   while Auto(env).GetState().step ~= step and guard < (maxsecs or 60) * 100 do env:advance(0.01, 0.01); guard = guard + 1 end
   return Auto(env).GetState().step == step
end

-- [Bs4, Bs10, O07] a foreign switch-off during the run: the addon is idle at once (nothing to take back from a dead bot)
scenario("auto-foreign-off-late",
   "somebody switches the self bot off during the run: the addon is idle within seconds, sends no removal into the void and never switches the bot back on",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      start(env)
      env:clear_sent()
      srv:toggle()                                           -- the user clicks Botpad's BOT AUS
      env:advance(5, 0.1)
      r:check(not Auto(env).IsRunning() and Auto(env).GetState().step == "idle", "5 s later the addon is idle, not waiting for a dead bot", Auto(env).GetState().step)
      r:check(count_sent_matching(env, "master fishing") == 0, "no removal command was sent to the switched-off bot", table.concat(sent_texts(env), " | "))
      env:advance(45, 0.1)                                   -- longer than STOP_WAIT
      r:check(not srv.active and srv.toggles == 2, "the bot stayed off (no toggle from the addon)", "toggles: " .. srv.toggles)
      r:check(Auto(env).GetState().step == "idle", "and the addon is still idle", Auto(env).GetState().step)
      no_errors(r, env)
   end)

-- [O06] with replies the client never shows, a second run in the same session must still clean up
scenario("auto-no-reply-second-run",
   "the client never shows the bot's answers: a SECOND run in the same session still takes the strategy back and switches the bot off",
   function(r)
      local env = boot{ bom = "strip", server = { reply_visible = false } }
      r.env = env
      local srv = env.server
      start(env, 60)
      stop(env, 40)
      r:check(not srv.active and srv.toggles == 2, "run 1: bot off again", "toggles: " .. srv.toggles)
      start(env, 60)
      r:check(Auto(env).IsRunning() and srv.casts >= 1, "run 2: running, the bot casts")
      stop(env, 40)
      r:check(not srv.active, "run 2: the bot is switched off again (it is not left running with 'master fishing')")
      r:check(srv.persisted and not srv.persisted["master fishing"], "run 2: the stored set is clean")
      no_errors(r, env)
   end)

-- [W01, H02, H03] only the player's OWN whispers are the bot's answers
scenario("auto-stranger-whisper",
   "a 'Strategies:' whisper from another player is ignored; the player's own name (any case, with -Realm) is accepted",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      env:chat_event("CHAT_MSG_WHISPER", "Strategies: nc, chat, grind", "Somebody")
      r:check(Auto(env).GetState().strategies == nil, "a stranger's list is not taken for the bot's answer")
      env:chat_event("CHAT_MSG_WHISPER", "Strategies: nc, chat", "Testchar-TestRealm")
      r:check(Auto(env).GetState().strategies == "nc, chat", "the own name with a -Realm suffix is accepted", tostring(Auto(env).GetState().strategies))
      env:chat_event("CHAT_MSG_WHISPER", "Strategies: nc, food", "testchar")
      r:check(Auto(env).GetState().strategies == "nc, food", "the own name in lower case is accepted", tostring(Auto(env).GetState().strategies))
      -- during a start: the stranger's list must not make the addon believe a bot is listening
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(0.5, 0.1)
      env:chat_event("CHAT_MSG_WHISPER", "Strategies: chat, master fishing", "Somebody")
      env:advance(50, 0.1)
      r:check(srv.toggles == 1 and srv.active, "the bot was still switched on (the stranger did not stop the toggle)", "toggles: " .. srv.toggles)
      r:check(Auto(env).IsRunning() and srv.casts >= 1, "and it fishes")
      no_errors(r, env)
   end)

-- [W03, W04, Sx7] "I don't have a Fishing Pole" -- once per run, only during a run
scenario("auto-pole-complaint-once",
   "the bot's pole complaint is shown once per run (not on every message) and not at all outside a run",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      srv:whisper("I don't have a Fishing Pole")
      env:advance(2, 0.1)
      r:check(PX.chat_count(env, "no fishing pole") == 0, "no warning outside a run")
      start(env)
      for _ = 1, 3 do srv:whisper("I don't have a Fishing Pole"); env:advance(1, 0.1) end
      r:check(PX.chat_count(env, "no fishing pole") == 1, "three complaints in one run: one warning", PX.chat_count(env, "no fishing pole") .. " warnings")
      stop(env)
      start(env)
      srv:whisper("I don't have a Fishing Pole"); env:advance(1, 0.1)
      r:check(PX.chat_count(env, "no fishing pole") == 2, "the next run warns again", PX.chat_count(env, "no fishing pole") .. " warnings")
   end)

-- [A01, A02, A03] an AutoTravel trip that begins while the start is under way or the loop runs
scenario("auto-trip-during-start",
   "AutoTravel starts a trip right after Start, or while the loop runs: nothing is sent during the trip and the loop follows within seconds afterwards",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(1, 0.1)
      env.G.AutoTravel = { active = true }
      env:advance(25, 0.1)
      r:check(count_sent_matching(env, "master fishing") == 0 and count_sent_matching(env, "do go fishing") == 0,
              "nothing is prepared or cast while the trip is running", "sent: " .. table.concat(sent_texts(env), " | "))
      local deferred = 0
      for _, l in ipairs(Auto(env).GetTrace()) do if l.text:find("apply deferred", 1, true) then deferred = deferred + 1 end end
      r:check(deferred >= 2 and deferred <= 8, "the deferral is re-tried every ~5 s, not on every tick", deferred .. " deferrals in the trace")
      env.G.AutoTravel.active = false
      env:advance(45, 0.1)
      r:check(Auto(env).IsRunning() and srv.casts >= 1, "after the trip the bot casts")
      no_errors(r, env)
      -- the same for a trip that begins while the loop is running
      local env2 = boot{ bom = "strip" }
      local srv2 = env2.server
      start(env2)
      r:check(srv2.casts >= 1, "precondition: casting")
      env2.G.AutoTravel = { active = true }
      env2:advance(30, 0.1)                                   -- the cast under way ends
      env2:clear_sent()
      env2:advance(30, 0.1)
      r:check(count_sent_matching(env2, "do go fishing") == 0, "no cast is started during the trip")
      env2.G.AutoTravel.active = false
      env2:advance(10, 0.1)
      r:check(count_sent_matching(env2, "do go fishing") >= 1, "... and the loop resumes right after the trip (within the 5 s re-check)")
      no_errors(r, env2, "second case")
   end)

-- [T01] AutoTravel active but not relying on the bot: the bot we switched on is switched off
scenario("auto-trip-no-support",
   "a stop during an AutoTravel trip that does NOT rely on the self bot (supportOn false) still switches off the bot the addon started",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env)
      env.G.AutoTravel = { active = true, supportOn = false }
      stop(env)
      r:check(not env.server.active, "the bot is switched off")
      r:check(not env.server:has("master fishing"), "and the strategy is taken back")
      no_errors(r, env)
   end)

-- [A12] the removal is repeated at a bounded rate when the bot does not answer
scenario("auto-stop-resend-rate",
   "the bot never answers the removal: the same command is repeated every ~3 s for 24 s (about 8 times), not hundreds of times",
   function(r)
      local env = boot{ bom = "strip", server = { reply_visible = false } }
      r.env = env
      start(env, 60)
      env:clear_sent()
      stop(env, 40)
      local n = count_sent(env, "nc +mount,-master fishing,?")
      r:check(n >= 5 and n <= 10, "5..10 sends of the removal in the stop wait", "sends: " .. n)
      r:check(not env.server.active, "afterwards the bot is switched off")
      no_collapse(r, env)
   end)

-- [E01-E05, S01, S06, H03, H05, C02, C04, B04, N01, N02, Sx6] what a hand-edited command block can contain
scenario("auto-custom-block-lines",
   "an edited loop block: '/w OTHER' goes to that player, '/1' to the channel, dot lines are SAY, unknown slashes go through the chat box, "
   .. "own-name / case variants are merged into the one nc command, stray commas make no empty op, a '/p' line warns once per run",
   function(r)
      local block = table.concat({
         "-- a comment must never be spoken aloud",
         "/w testchar nc +gather",
         "/W %p co +loot",
         "/w %p nc +loot, ,+quest",
         "/w Somebody hello there",
         "/1 trade hello",
         ".server info",
         "/dance now",
         "/w %p do move near water",
         "/w %p do go fishing",
      }, "\n")
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishLoopCommands = block }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved }
      r.env = env
      local srv = env.server
      start(env)
      local joined = table.concat(sent_texts(env), " | ")
      r:check(srv.casts >= 1, "the bot casts with the custom block", joined)
      r:check(count_sent(env, "nc +gather,+loot,+quest") >= 1,
              "both own-name lines (lower-case name, empty op in between) were merged into the single nc command", joined)
      r:check(count_sent_matching(env, ",,") == 0, "no empty op", joined)
      local seen = {}
      for _, e in ipairs(env.sent) do seen[e.text] = e end
      local sends = count_sent(env, "do go fishing")
      r:check(seen["-- a comment must never be spoken aloud"] == nil, "the comment line was not sent", joined)
      r:check(seen["hello there"] and seen["hello there"].chattype == "WHISPER" and seen["hello there"].target == "Somebody",
              "'/w Somebody ...' went to Somebody", joined)
      r:check(count_sent(env, "hello there") == sends, "and once per cast (not to oneself)", count_sent(env, "hello there") .. " vs " .. sends)
      r:check(seen["trade hello"] and seen["trade hello"].chattype == "CHANNEL" and seen["trade hello"].target == 1,
              "'/1 ...' went to channel number 1", joined)
      r:check(seen[".server info"] and seen[".server info"].chattype == "SAY", "a dot line is sent as SAY", joined)
      local boxed = table.concat(env.sent_by_chatbox or {}, " | ")
      r:check(boxed:find("/dance now", 1, true) ~= nil, "an unknown slash command goes through the chat box", boxed)
      r:check(not table.concat(env.chat_display, "\n"):find("co +loot", 1, true), "the echo of '/W %p co +loot' (upper-case slash word) is recognised as own and hidden")
      -- raid only (GetNumPartyMembers() == 0): '/p' is real group chat, not a line to oneself
      local saved2 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishLoopCommands = "/w %p do move near water\n/w %p do go fishing\n/p hello raid" }, Outfit = {}, WasWearing = {} } }
      local env2 = boot{ bom = "strip", saved = saved2, world = { raid = 5 } }
      start(env2)
      local raids = count_sent(env2, "hello raid")
      r:check(raids >= 1 and sent_type(env2, "PARTY") == raids, "in a raid '/p' is sent as party chat")
      -- a stop block without any nc line, sent in the quick (logout) form: nothing like 'nc ' is sent
      local saved3 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishStopCommands = "/w %p co -loot" }, Outfit = {}, WasWearing = {} } }
      local env3 = boot{ bom = "strip", saved = saved3, server = { active = true, persisted = { "nc", "chat", "follow", "default" } } }
      env3:advance(15, 0.5)
      start(env3, 30)
      env3:clear_sent()
      env3:fire("PLAYER_LOGOUT")
      r:check(count_sent(env3, "co -loot") == 1 and count_sent_matching(env3, "nc") == 0, "quick stop with a block without nc: no empty 'nc ' command",
              table.concat(sent_texts(env3), " | "))
      -- '/p' lines while ungrouped: the warning appears once per run, even for several lines, and again in the next run
      local saved4 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishLoopCommands = "/p nc +gather\n/w %p do move near water\n/w %p do go fishing" }, Outfit = {}, WasWearing = {} } }
      local env4 = boot{ bom = "strip", saved = saved4 }
      start(env4)
      r:check(PX.chat_count(env4, "not in a group") == 1, "[only an nc line] warned once", PX.chat_count(env4, "not in a group") .. " warnings")
      stop(env4)
      start(env4)
      r:check(PX.chat_count(env4, "not in a group") == 2, "the next run warns again", PX.chat_count(env4, "not in a group") .. " warnings")
      local saved5 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishLoopCommands = "/p nc +gather\n/p co +loot\n/p co +aoe\n/w %p do move near water\n/w %p do go fishing" }, Outfit = {}, WasWearing = {} } }
      local env5 = boot{ bom = "strip", saved = saved5 }
      start(env5)
      r:check(PX.chat_count(env5, "not in a group") == 1, "[three /p lines] warned once", PX.chat_count(env5, "not in a group") .. " warnings")
   end)

-- [E01, G05, G03] legacy toggle lines in every spelling; a block that is nothing but a toggle line; comments in the lure block
scenario("auto-legacy-toggle-lines",
   "'.playerbots bot self' in any spelling is dropped from a stored block; a Stop block that was only that line falls back to the default - also for the quick logout form; "
   .. "a whitespace-only block shows the default in the editor",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishLoopCommands = ".playerbot bot self\n.PLAYERBOTS BOT SELF\n/w %p do move near water\n/w %p do go fishing",
         AutoFishStopCommands = ".playerbots bot self",
      }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved }
      r.env = env
      local srv = env.server
      start(env)
      r:check(srv.toggles == 1 and srv.casts >= 1, "no extra toggle from the legacy spellings", "toggles: " .. srv.toggles)
      r:check(count_sent(env, ".playerbot bot self") == 0 and count_sent(env, ".PLAYERBOTS BOT SELF") == 0, "the legacy lines were not sent as chat")
      stop(env)
      r:check(srv.persisted and not srv.persisted["master fishing"] and srv.persisted["mount"], "the Stop block that held only the toggle line fell back to the default: 'mount' is back")
      r:check(not srv.active, "bot off again")
      env.G.FishingBuddy.SetSetting("AutoFishLoopCommands", "   \n  ")
      Auto(env).ShowEditor()
      local ed = env.G.FishingAutoEditor
      r:check(ed and ed.boxes[1]:GetText() == "/w %p do move near water\n/w %p do go fishing", "a whitespace-only stored block shows the default in the editor", ed and ed.boxes[1]:GetText() or "no editor")
      no_errors(r, env)
      -- the quick form is sent only once: the very first use of the cleaned Stop block must already be the default
      local saved2 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishStopCommands = ".playerbots bot self" }, Outfit = {}, WasWearing = {} } }
      local env2 = boot{ bom = "strip", saved = saved2 }
      start(env2)
      env2:clear_sent()
      env2:fire("PLAYER_LOGOUT")
      r:check(sent_texts(env2)[1] == "WHISPER:nc +mount,-master fishing", "logout with a toggle-only Stop block still sends the default removal", table.concat(sent_texts(env2), " | "))
   end)

-- [Wd1, Hl2, Hl3, Hl4, E01] the lure logic runs only during a run; the lure line carries the item link; retries are spaced
scenario("auto-lure-idle",
   "a missing lure with a lure in the bags: nothing is sent while Auto fishing is off; during a run the command carries the item link and is sent BEFORE a cast, "
   .. "three attempts, then given up (fishing goes on); a comment line in the lure block is not spoken, the option 'let the bot apply the lure' off falls back to a warning",
   function(r)
      local env = boot{ bom = "strip", world = { bags_have_lure = true, lure_seconds = 0 }, server = { lure_applies = false } }
      r.env = env
      env:clear_sent()
      env:advance(120, 0.5)
      r:check(#env.sent == 0, "auto fishing off: the watchdog sends nothing", table.concat(sent_texts(env), " | "))
      env.G.FishingBuddy.SetSetting("AutoFishLureCommands", "-- apply the lure\n/w %p u %l")
      start(env, 100)
      local times, line = {}, nil
      for _, e in ipairs(env.sent) do
         if e.text:find("^u ") then line = line or e.text; times[#times + 1] = e.t end
      end
      r:check(line and line:find("|Hitem:", 1, true) ~= nil, "the lure command carries an item link", tostring(line))
      r:check(#times == 3 and times[2] - times[1] >= 8 and times[3] - times[2] >= 8, "three attempts, at least 8 s apart (the application takes 5 s)", #times .. " attempts")
      r:check(chat_has(env, "did not apply the lure"), "then the player is told, and the loop goes on without a lure")
      r:check(env.server.casts >= 1, "fishing goes on without the lure", "casts: " .. env.server.casts)
      for _, e in ipairs(env.sent) do
         if e.text:find("apply the lure", 1, true) then r:check(false, "the comment line was spoken", e.chattype .. ":" .. e.text) end
      end
      -- the bot applies the lure: one command, then it fishes with it
      local envb = boot{ bom = "strip", world = { bags_have_lure = true, lure_seconds = 0 } }
      start(envb, 60)
      local firstu, firstgo
      for i, e in ipairs(envb.sent) do
         if e.text:find("^u ") then firstu = firstu or i end
         if e.text == "do go fishing" then firstgo = firstgo or i end
      end
      r:check(firstu and firstgo and firstu < firstgo, "the lure is applied before the first cast", tostring(firstu) .. " / " .. tostring(firstgo))
      r:check(envb.server.lures == 1 and envb.world.lure_seconds > 0, "one command was enough", "lures: " .. envb.server.lures)
      r:check(envb.server.casts >= 1, "and it fishes")
      -- option off: no lure command, a warning instead
      local env2 = boot{ bom = "strip", world = { bags_have_lure = true, lure_seconds = 0 } }
      env2.G.FishingBuddy.SetSetting("AutoFishAutoLure", 0)
      start(env2, 60)
      local lines = 0
      for _, e in ipairs(env2.sent) do if e.text:find("^u ") then lines = lines + 1 end end
      r:check(lines == 0, "[option off] the bot is not asked to apply the lure", lines .. " lines")
      r:check(PX.chat_count(env2, "lure") >= 1, "[option off] the player is warned instead")
      no_errors(r, env)
   end)

-- [Wd2, Wd3, Wd5-Wd10, Ev8, Ev9, Op3, Op4, Op5] the watchdog's stop conditions and options
scenario("auto-watchdog-stops",
   "time limit, death, combat (event and watchdog), full bags (exactly at the limit) and the options that disable them",
   function(r)
      local function fresh(setup)
         local env = boot{ bom = "strip" }
         if setup then setup(env) end
         start(env, 45)
         return env
      end
      -- time limit: 1 minute
      local env = fresh(function(e) e.G.FishingBuddy.SetSetting("AutoFishMaxMinutes", 1) end)
      r.env = env
      r:check(Auto(env).IsRunning(), "[time limit 1 min] still running 45 s after the start")
      env:advance(10, 0.5)
      r:check(Auto(env).IsRunning(), "[time limit 1 min] still running after 55 s")
      env:advance(12, 0.5)
      r:check(not Auto(env).IsRunning() and chat_has(env, "time limit reached"), "[time limit 1 min] stopped after 67 s with the reason")
      -- dead
      env = fresh()
      env.world.dead = true
      env:advance(5, 0.5)
      r:check(not Auto(env).IsRunning() and chat_has(env, "you died"), "[dead] the watchdog stops the run")
      env = fresh()
      env:fire("PLAYER_DEAD")
      r:check(not Auto(env).IsRunning(), "[PLAYER_DEAD] the event stops the run at once")
      -- combat
      env = fresh()
      env.world.combat = true
      env:advance(5, 0.5)
      r:check(not Auto(env).IsRunning() and chat_has(env, "combat"), "[combat] the watchdog stops the run")
      env = fresh()
      env:fire("PLAYER_REGEN_DISABLED")
      r:check(not Auto(env).IsRunning(), "[PLAYER_REGEN_DISABLED] the event stops the run at once")
      env = fresh(function(e) e.G.FishingBuddy.SetSetting("AutoFishStopInCombat", 0) end)
      env.world.combat = true
      env:fire("PLAYER_REGEN_DISABLED")
      env:advance(10, 0.5)
      r:check(Auto(env).IsRunning(), "[combat, option off] the run goes on")
      -- bags: 2 free slots = the default limit -> stop; 3 -> go on
      env = fresh()
      env.world.free_slots = { [0] = 2, 0, 0, 0, 0 }
      env:advance(5, 0.5)
      r:check(not Auto(env).IsRunning() and chat_has(env, "bags full"), "[bags] stopped at exactly the limit (2 free)")
      env = fresh()
      env.world.free_slots = { [0] = 3, 0, 0, 0, 0 }
      env:advance(5, 0.5)
      r:check(Auto(env).IsRunning(), "[bags] 3 free slots: the run goes on")
      env = fresh(function(e) e.G.FishingBuddy.SetSetting("AutoFishStopBagsFull", 0) end)
      env.world.free_slots = { [0] = 1, 0, 0, 0, 0 }
      env:advance(70, 0.5)
      r:check(Auto(env).IsRunning(), "[bags, option off] the run goes on")
      r:check(PX.chat_count(env, "free bag slots") >= 1 and PX.chat_count(env, "free bag slots") <= 4, "... with a warning about every 30 s, not on every tick", PX.chat_count(env, "free bag slots") .. " warnings")
      -- pole taken off: the DISABLED event stops the run at once
      env = fresh()
      env.world.pole_equipped = false
      env:fire("ITEM_LOCK_CHANGED")
      env:fire("PLAYER_EQUIPMENT_CHANGED", 16)
      r:check(not Auto(env).IsRunning(), "[pole removed] the run stops with the equipment event, not only at the next watchdog tick")
   end)

-- [Sx5, Sx6/Sx7 in the scenarios above, Ev1] counters start afresh with every run
scenario("auto-second-run",
   "the catch count adds up quantities and a second run starts with a fresh count",
   function(r)
      local env = boot{ bom = "strip", server = { catch = false } }       -- the model's fish get away: only the simulated catches count
      r.env = env
      start(env)
      for _ = 1, 2 do
         env.world.loot = { 13754 }; env.world.loot_is_fishing = true
         env:fire("LOOT_OPENED"); env:advance(1, 0.5)
      end
      env.G.FishingBuddy.RunHandlers(env.G.FBConstants.ADD_FISHIE_EVT, 13754, "Raw Glossy Mightfish", "z", "s", "tex", 3)
      env:call("Auto.Stop", Auto(env).Stop)
      r:check(chat_has(env, "caught 5"), "run 1 reports 2 catches + a stack of 3", table.concat(env.chat, " | "))
      env:advance(35, 0.1)
      start(env)
      env.chat = {}
      env:slash("/fb auto status")
      r:check(chat_has(env, "caught 0"), "run 2 starts at 0 catches", table.concat(env.chat, " | "))
   end)

-- [Sx1, Sx2] Start while running / while the stop sequence is still pending
scenario("auto-start-guards",
   "'/fb auto on' while running changes nothing; Toggle during the stop sequence is refused with a hint",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(1, 0.1)
      local n = #env.sent
      env:slash("/fb auto on")
      r:check(#env.sent == n, "Start while running sends nothing", (#env.sent - n) .. " extra lines")
      env:advance(45, 0.1)
      r:check(Auto(env).IsRunning() and srv.casts >= 1 and srv.toggles == 1, "one session, one toggle")
      env:call("Auto.Stop", Auto(env).Stop)
      r:check(Auto(env).GetState().stopping, "precondition: the stop sequence is pending")
      r:check(Auto(env).GetState().ownsBot, "the state still says that the bot is ours while it is being stopped")
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(not Auto(env).IsRunning(), "Toggle during the stop sequence does not start a new run")
      r:check(chat_has(env, "still being stopped"), "and says why")
      env:advance(35, 0.1)
      r:check(not srv.active and not srv:has("master fishing"), "the stop sequence ended cleanly")
      no_errors(r, env)
   end)

-- [Sx3] a failing START handler must not derail Start (otherwise the first probe is never sent and an already running bot is toggled OFF)
scenario("auto-start-handler-error",
   "an error in another addon's AUTO_START_EVT handler must not abort Start: the bot that was already on is not toggled",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      local srv = env.server
      env:advance(15, 0.5)
      env.G.FishingBuddy.API.RegisterHandlers({ [env.G.FBConstants.AUTO_START_EVT] = function() error("start handler exploded") end })
      start(env, 30)
      r:check(Auto(env).IsRunning() and srv.casts >= 1, "running, the bot casts")
      r:check(srv.toggles == 0, "the bot that was on was not toggled", "toggles: " .. srv.toggles)
      r:check(#env.errors == 0, "no Lua error escaped from Start", #env.errors > 0 and env.errors[1].message or nil)
   end)

-- [Sk3, Se4, Se5] Stop while the toggle is in flight: the stop sequence ends as soon as the answer is in, or by itself if there is none
scenario("auto-toggle-no-answer-stop",
   "Stop while '.playerbots bot self' is in flight: whichever answer comes (refusal, switched off) ends the stop sequence and releases Botpad at once; with no answer at all it ends by itself",
   function(r)
      -- nobody answers
      local env = boot{ bom = "strip", server = { module_missing = true } }
      r.env = env
      local BP = Server.install_botpad_stub(env, true)
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(3.02, 0.01)
      r:check(Auto(env).GetState().step == "toggle", "precondition: toggle sent", Auto(env).GetState().step)
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(10, 0.1)
      r:check(not Auto(env).GetState().stopping and Auto(env).GetState().step == "idle", "[no answer] the stop sequence ended", Auto(env).GetState().step)
      r:check(next(BP.Bot.holders) == nil, "[no answer] Botpad was released")
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(Auto(env).IsRunning(), "[no answer] a new Start is possible afterwards")
      no_errors(r, env)
      -- refused
      local env2 = boot{ bom = "strip", server = { selfbot_level = 0 } }
      local BP2 = Server.install_botpad_stub(env2, true)
      env2:call("Auto.Toggle", Auto(env2).Toggle)
      env2:advance(3.02, 0.01)
      env2:call("Auto.Stop", Auto(env2).Stop)
      env2:advance(0.4, 0.05)
      r:check(not Auto(env2).GetState().stopping and next(BP2.Bot.holders) == nil, "[refused] the answer ends the stop sequence and releases Botpad at once")
      -- the bot was on and is switched OFF by the toggle
      local env3 = boot{ bom = "strip" }
      local BP3 = Server.install_botpad_stub(env3, true)
      env3.server:activate(true)
      env3.server.nc.chat = nil                              -- on, but does not answer the probe
      env3:call("Auto.Toggle", Auto(env3).Toggle)
      env3:advance(3.02, 0.01)
      env3:call("Auto.Stop", Auto(env3).Stop)
      env3:advance(0.5, 0.05)
      r:check(not Auto(env3).GetState().stopping and next(BP3.Bot.holders) == nil, "[switched off] the undo is sent, the stop sequence ends and Botpad is released at once")
   end)

-- [Se14] the refusal of the whispers arrives late (slow link): it is recognised in the apply step too
scenario("auto-whispers-blocked-slow",
   "GM account without '.whispers on' on a slow link (3.5 s each way): the refusal of the later strategy command is still recognised and explained",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 1, gm = true, whisper_filter = true, latency = 3.5 } }
      r.env = env
      start(env, 40)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(chat_has(env, ".whispers on"), "the message names '.whispers on'")
   end)

-- [Rs2] the cleanup after /reload must not disturb a run the player has already started
scenario("auto-resume-while-running",
   "the post-login cleanup finds a run in progress: it clears its flag and does nothing else (no extra probe, Botpad stays held)",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, true)
      env.G.FishingBuddy_Player.Settings.AutoFishPending = { ownsBot = true, restore = true }
      env:fire("PLAYER_LOGIN")
      start(env, 2)
      env:advance(10, 0.1)
      r:check(env.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "pending flag cleared")
      r:check(count_sent(env, "nc ?") == 1, "no second probe from the cleanup", "probes: " .. count_sent(env, "nc ?"))
      r:check(BP.Bot.holders["Fishing Buddy"], "Botpad is still held")
      r:check(not Auto(env).GetState().stopping, "no stop sequence was started")
      env:advance(45, 0.1)
      r:check(Auto(env).IsRunning() and env.server.casts >= 1, "the run went on normally")
      no_errors(r, env)
   end)

-- [Sk2, Rs4] the cleanup after login: scheduled ~6 s after login, and it ends by itself when the bot is off
scenario("auto-resume-no-answer",
   "pending cleanup but the self bot is off: the probe goes out ~6 s after login (not at once), nothing is toggled, and the addon is idle (Start possible) afterwards",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishPending = { ownsBot = true, restore = true } }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved }
      r.env = env
      env:advance(5, 0.1)
      r:check(count_sent(env, "nc ?") == 0, "no cleanup probe in the first 5 s after login", "probes: " .. count_sent(env, "nc ?"))
      env:advance(3, 0.1)
      r:check(count_sent(env, "nc ?") == 1, "the probe is out after ~6 s", "probes: " .. count_sent(env, "nc ?"))
      env:advance(30, 0.1)
      r:check(not Auto(env).GetState().stopping and Auto(env).GetState().step == "idle", "the cleanup ended (nobody answered)", Auto(env).GetState().step)
      r:check(env.server.toggles == 0, "and nothing was toggled", "toggles: " .. env.server.toggles)
      local kept = env.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(kept) == "table" and kept.tries == 1, "the note stays for the next login (tries = 1)")
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(Auto(env).IsRunning(), "a Start is possible")
      no_errors(r, env)
   end)

-- [Bs6, Bs7, Se6] a bot that is not ours still gets its 'mount' back after a logout
scenario("auto-pending-restore",
   "logout during a run on a bot that was already on: a cleanup is saved (restore only); the next session puts 'mount' back even if 'master fishing' is gone",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      env:advance(15, 0.5)
      start(env, 30)
      env:fire("PLAYER_LOGOUT")
      local pend = env.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(pend) == "table" and pend.ownsBot == false and pend.restore == true, "cleanup saved although the bot is not ours")
      -- next session: the bot is on, its stored set has neither 'master fishing' nor 'mount'
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishPending = { ownsBot = false, restore = true } }, Outfit = {}, WasWearing = {} } }
      local env2 = boot{ bom = "strip", saved = saved, server = { active = true, persisted = { "nc", "chat", "follow", "default" } } }
      env2:advance(30, 0.1)
      r:check(env2.server:has("mount"), "'mount' was restored", table.concat(env2.server:strategies(), ", "))
      r:check(env2.server.active, "the bot (not ours) stays on")
      r:check(env2.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "flag cleared")
      no_errors(r, env2)
   end)

-- [Bs2, Bs3] 'mount' is restored only if it was there AND we removed it
scenario("auto-cold-no-mount",
   "cold start of a bot whose stored strategies do not include 'mount': Stop does not add it; with the option 'keep the bot from mounting' off Stop does not add it either",
   function(r)
      local env = boot{ bom = "strip", server = { persisted = { "nc", "chat", "follow", "default" } } }
      r.env = env
      local srv = env.server
      start(env)
      stop(env)
      r:check(count_sent_matching(env, "+mount") == 0, "Stop sends no '+mount' (it was never there); no removal is needed at all", table.concat(sent_texts(env), " | "))
      r:check(srv.persisted and not srv.persisted["mount"] and not srv.persisted["master fishing"], "the stored set is as it was")
      no_collapse(r, env)
      local env2 = boot{ bom = "strip" }
      env2.G.FishingBuddy.SetSetting("AutoFishNoMount", 0)
      start(env2)
      stop(env2)
      r:check(count_sent(env2, "nc ?,-master fishing,?") == 1 and count_sent_matching(env2, "mount") == 0, "[option off] 'mount' is never touched: no '-mount' at the start, no '+mount' on Stop", table.concat(sent_texts(env2), " | "))
   end)

-- [O01, O02, O04] the older / alternative server texts
scenario("auto-legacy-messages",
   "older server texts for the self bot switching on / off / being refused are understood",
   function(r)
      for _, phrase in ipairs{ "Enable player botAI", "Playerbot AI enabled" } do
         local env = boot{ bom = "strip", server = { module_missing = true } }
         env:call("Auto.Toggle", Auto(env).Toggle)
         env:advance(3.1, 0.1)
         env:chat_event("CHAT_MSG_SYSTEM", phrase)
         r:check(Auto(env).GetState().step == "settle", "'" .. phrase .. "' counts as 'on'", Auto(env).GetState().step)
      end
      for _, phrase in ipairs{ "Disable player botAI", "Playerbot AI disabled" } do
         local env = boot{ bom = "strip", server = { module_missing = true } }
         env:call("Auto.Toggle", Auto(env).Toggle)
         env:advance(3.1, 0.1)
         env:chat_event("CHAT_MSG_SYSTEM", phrase)
         r:check(count_sent(env, ".playerbots bot self") == 2, "'" .. phrase .. "' counts as 'off' (the toggle is repeated once)", "toggles sent: " .. count_sent(env, ".playerbots bot self"))
      end
      local env = boot{ bom = "strip", server = { module_missing = true } }
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(3.1, 0.1)
      env:chat_event("CHAT_MSG_SYSTEM", "You cannot control bots yet.")
      r:check(not Auto(env).IsRunning() and chat_has(env, "refuses"), "'You cannot control bots yet' is a refusal")
   end)

-- [Bs12, O05] a refused start leaves nothing behind
scenario("auto-refused-quiet",
   "a refused start gives one message and one alert -- no 'stopped' line, no summary --, the addon knows the bot is off, and Botpad is not left held",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 0 } }
      r.env = env
      start(env, 20)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(not chat_has(env, "Auto fishing stopped") and not chat_has(env, "Ran for"), "no 'stopped' line and no run summary after a failed start")
      r:check(#(env.sounds or {}) == 1, "exactly one alert sound", #(env.sounds or {}) .. " sounds")
      r:check(Auto(env).GetState().selfState == false, "the addon records that the self bot is off", tostring(Auto(env).GetState().selfState))
      -- a refusal that arrives before the toggle (whispers to oneself blocked): Botpad must be released at once
      local env2 = boot{ bom = "strip", server = { selfbot_level = 1, gm = true, whisper_filter = true } }
      local BP2 = Server.install_botpad_stub(env2, true)
      start(env2, 2)
      r:check(not Auto(env2).IsRunning(), "[whispers blocked] not running")
      r:check(next(BP2.Bot.holders) == nil, "[whispers blocked] Botpad is not left held")
      r:check(not Auto(env2).GetState().stopping, "[whispers blocked] nothing is pending")
   end)

-- [Cf8, N03, Cf11] an ordinary run is quiet, and plays exactly its two alerts
scenario("auto-clean-run-quiet",
   "an ordinary solo run prints no warning at all (clash, mounted, pole, Botpad, party line, toggle line), plays one alert at the start and one at the stop",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env, 60)
      stop(env)
      for _, needle in ipairs{ "Other bot strategies", "You are mounted", "reports that it has no fishing pole", "Botpad before 1.3",
                               "not in a group", "Removed '.playerbots", "did not answer", "refuses", "No catch for a while" } do
         r:check(PX.chat_count(env, needle) == 0, "no '" .. needle .. "' message")
      end
      r:check(PX.chat_count(env, "Auto fishing started") == 1 and PX.chat_count(env, "Auto fishing stopped") == 1, "one 'started' and one 'stopped'")
      r:check(PX.chat_count(env, "Starting auto fishing") == 1, "the start is announced once")
      r:check(#(env.sounds or {}) == 2, "two alert sounds (confirmed, stopped)", #(env.sounds or {}) .. " sounds")
   end)

scenario("auto-clash-strategies",
   "every strategy that fights with fishing is named in the warning",
   function(r)
      local env = boot{ bom = "strip", server = { active = true, persisted = { "nc", "chat", "follow", "default", "grind", "rpg", "new rpg", "travel", "mount" } } }
      r.env = env
      start(env, 30)
      r:check(chat_has(env, "(grind, rpg, new rpg, travel)"), "grind, rpg, new rpg and travel are all listed")
   end)

-- [Cf10, Wd16] the 'mounted' warning is rate limited
scenario("auto-mounted-warning-rate",
   "mounted although the option 'keep the bot from mounting' is off: the warning is repeated about once a minute, not every tick; mounting during the start warns once",
   function(r)
      local env = boot{ bom = "strip", server = { mount_owned = true } }
      r.env = env
      env.G.FishingBuddy.SetSetting("AutoFishNoMount", 0)
      start(env, 40)
      env:advance(120, 0.5)
      r:check(env.world.mounted, "precondition: the model mounted the character")
      local n = PX.chat_count(env, "You are mounted")
      r:check(n >= 1 and n <= 4, "1..4 warnings in 160 s", n .. " warnings")
      -- the player mounts while the start is under way: the confirmation warns, the watchdog does not repeat it at once
      local env2 = boot{ bom = "strip" }
      env2:call("Auto.Toggle", Auto(env2).Toggle)
      env2:advance(5, 0.1)
      env2.world.mounted = true
      env2:advance(60, 0.5)
      r:check(PX.chat_count(env2, "You are mounted") == 1, "mounted during the start: exactly one warning in the first minute", PX.chat_count(env2, "You are mounted") .. " warnings")
   end)

-- [K04] the player is already fishing by hand when pressing the button, the bot is off
scenario("auto-channeling-bot-off",
   "the character is channelling (fishing by hand) and the bot is off: the start still switches the bot on within ~25 s",
   function(r)
      local env = boot{ bom = "strip", world = { channeling = true } }
      r.env = env
      start(env, 40)
      r:check(env.server.toggles == 1 and env.server.active, "the bot was switched on", "toggles: " .. env.server.toggles)
      r:check(Auto(env).IsRunning(), "and it runs; the loop waits for the manual cast to end", "casts: " .. env.server.casts)
      env.world.channeling = false
      env:advance(20, 0.1)
      r:check(env.server.casts >= 1, "after the manual cast the loop fishes")
   end)

-- [K07, K09, P13] how long a start takes
scenario("auto-start-latency",
   "start latency against the model: bot already awake <= 6 s; bot off <= 17 s; bot off behind an old Botpad <= 25 s (and no 'old Botpad' warning outside Minimal mode)",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      env:advance(15, 0.5)
      start(env, 6)
      r:check(Auto(env).GetState().step == "run", "[awake bot] confirmed within 6 s", Auto(env).GetState().step)
      local env2 = boot{ bom = "strip" }
      start(env2, 17)
      r:check(Auto(env2).GetState().step == "run", "[bot off] confirmed within 17 s", Auto(env2).GetState().step)
      local env3 = boot{ bom = "strip" }
      Server.install_botpad_stub(env3, false)
      env3.G.BotpadDB = { Mode = "normal" }
      start(env3, 25)
      r:check(Auto(env3).GetState().step == "run" and env3.server.casts >= 1, "[bot off, Botpad without Hold] confirmed within 25 s", Auto(env3).GetState().step)
      r:check(PX.chat_count(env3, "Botpad before 1.3") == 0, "[Botpad without Hold, mode normal] no Minimal-mode warning")
   end)

-- [K10, K11, K12, K13, K16, K17, A14] retry spacing
scenario("auto-retry-timing",
   "a bot that stops listening before it reads the preparation: three attempts, each ~23 s after the previous one (warm wait 20 s + retry delay 3 s)",
   function(r)
      local env = boot{ bom = "strip", server = { active = true } }
      r.env = env
      env:call("Auto.Toggle", Auto(env).Toggle)
      PX.until_step(env, "apply", 5)
      env.server.nc.chat = nil                              -- deaf from now on
      env:advance(90, 0.1)
      local ts = {}
      for _, e in ipairs(env.sent) do
         if e.text:find("nc -mount,?", 1, true) then ts[#ts + 1] = e.t end
      end
      r:check(#ts == 3, "three attempts", #ts .. " attempts")
      if #ts == 3 then
         local g1, g2 = ts[2] - ts[1], ts[3] - ts[2]
         r:check(g1 >= 21 and g1 <= 26, "1st -> 2nd attempt: warm wait 20 s + retry delay 3 s", string.format("%.1f s", g1))
         r:check(g2 >= 21 and g2 <= 26, "2nd -> 3rd attempt: warm wait 20 s + retry delay 3 s", string.format("%.1f s", g2))
      end
   end)

-- [Se20] a foreign switch-off while the probe is outstanding
scenario("auto-foreign-off-in-probe",
   "somebody switches the (awake) self bot off right after Start, while the probe is outstanding: the run goes on, switches the bot on itself and fishes",
   function(r)
      local env = boot{ bom = "strip", server = { active = true } }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(0.01, 0.01)
      srv:toggle()
      env:advance(60, 0.1)
      r:check(Auto(env).IsRunning() and srv.casts >= 1, "running, the bot casts")
      r:check(srv.toggles == 2 and Auto(env).GetState().ownsBot, "the addon switched the bot on and owns it now", "toggles: " .. srv.toggles)
      no_errors(r, env)
   end)

-- [St3, Se21] a bot that answered the probe but ignores the strategy command
scenario("auto-bot-deaf-after-probe",
   "the bot answers the probe, then stops listening (strategy 'chat' removed): the start is NOT accepted 'unverified', it fails with the strategy message",
   function(r)
      local env = boot{ bom = "strip", server = { active = true } }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      PX.until_step(env, "apply", 5)                         -- the strategy command is on its way (the bot has not read it yet)
      srv.nc.chat = nil
      env:advance(100, 0.1)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(chat_has(env, "did not accept the strategy change"), "the strategy message is shown")
      r:check(not chat_has(env, "did not answer the strategy check"), "and not the 'unverified' start")
      r:check(srv.active, "the bot (not ours) is left on")
   end)

-- [Se23, Se24, K12] a reply that comes after the apply wait
scenario("auto-late-apply-reply",
   "the bot sleeps through the whole apply wait (answer after 22 s): the late answer confirms the start, the command is not sent a second time",
   function(r)
      local env = boot{ bom = "strip", server = { active = true } }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      PX.until_step(env, "apply", 5)
      srv.ready_at = env.now + 22
      env:advance(60, 0.1)
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run" and srv.casts >= 1, "confirmed by the late answer")
      r:check(count_sent(env, "nc -mount,?") == 1, "the preparation command was sent once", "sent " .. count_sent(env, "nc -mount,?") .. " times")
      no_errors(r, env)
   end)

-- [K28] the diagnostic trace buffer is bounded but not tiny
scenario("auto-trace-size",
   "/fb auto diag keeps the last 40 trace lines",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env, 60)
      for _ = 1, 3 do stop(env); start(env, 45) end
      local n = #Auto(env).GetTrace()
      r:check(n == 40, "the trace holds exactly 40 lines after a long session", "lines: " .. n)
   end)

-- [F03, F04, F05, K27] the echo filter only hides the addon's own traffic, and only for a limited time
scenario("auto-echo-window",
   "echo hiding: a stranger's whisper is shown even right after a probe; the player's own later whispers (>30 s) are shown again",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local me = env.G.UnitName("player")
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(1, 0.1)
      r:check(env:chat_event("CHAT_MSG_WHISPER", "Strategies: just a stranger", "Somebody"), "a stranger's 'Strategies:' whisper is shown right after the probe")
      r:check(env:chat_event("CHAT_MSG_WHISPER", "nc ?", "Somebody"), "a stranger's whisper that equals one of our commands is shown")
      env:advance(45, 0.1)
      stop(env, 40)
      env:slash("/fb auto probe")                            -- remembers "nc ?" once more, then nothing else for two minutes
      env:advance(120, 0.5)
      r:check(env:chat_event("CHAT_MSG_WHISPER_INFORM", "nc ?", me), "2 minutes later the player's own 'nc ?' is no longer hidden as a leftover echo")
      r:check(env:chat_event("CHAT_MSG_WHISPER", "Strategies: nc, chat", me), "... and neither is an old-looking 'Strategies:' answer")
   end)

-- [Y33] old defaults are recognised even with stray blanks
scenario("auto-settings-migration-blanks",
   "saved command blocks that hold the 0.9.9 defaults with trailing blanks / tabs / empty lines are still replaced by the new defaults",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishStopCommands = "/p nc -master fishing\t\n\n .playerbots bot self\n\n",
         AutoFishLureCommands = "/p u %l  \n",
      }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved }
      r.env = env
      local S = env.G.FishingBuddy_Player.Settings
      r:check(S.AutoFishStopCommands == nil and S.AutoFishLureCommands == nil, "both old defaults were cleared")
   end)

-- [Y12-Y19] the /fb auto sub-commands
scenario("auto-slash-commands",
   "/fb auto panel | lure | probe | status | diag do what they say",
   function(r)
      local env = boot{ bom = "strip", server = { active = true } }
      r.env = env
      local srv = env.server
      local FB = env.G.FishingBuddy
      r:check(FB.GetSettingBool("AutoFishPanelVisible") and env.G.FishingAutoPanel:IsVisible() == 1, "precondition: panel visible")
      env:slash("/fb auto panel")
      r:check(not FB.GetSettingBool("AutoFishPanelVisible") and env.G.FishingAutoPanel:IsVisible() ~= 1, "'panel' hides the panel")
      env:slash("/fb auto panel")
      r:check(FB.GetSettingBool("AutoFishPanelVisible") and env.G.FishingAutoPanel:IsVisible() == 1, "'panel' shows it again")
      env.chat = {}
      env:slash("/fb auto lure")
      r:check(not FB.GetSettingBool("AutoFishAutoLure") and chat_has(env, "Let the bot apply lures off"), "'lure' switches the option off and says so")
      env:slash("/fb auto lure")
      r:check(FB.GetSettingBool("AutoFishAutoLure") and chat_has(env, "Let the bot apply lures on"), "'lure' switches it on again and says so")
      env.chat = {}
      env:slash("/fb auto status")
      r:check(chat_has(env, "Auto Fishing: OFF"), "'status' while stopped says OFF")
      env:clear_sent()
      env:slash("/fb auto probe")
      env:advance(20, 0.1)
      r:check(count_sent(env, "nc ?") == 1, "'probe' asks the bot once")
      env.chat = {}
      env:slash("/fb auto diag")
      local age
      for _, l in ipairs(env.chat) do age = age or strip_colors(l):match("Bot strategies %((%d+) s ago%)") end
      r:check(age and tonumber(age) >= 18 and tonumber(age) <= 21, "'diag' shows how old the bot's last list is (about 20 s)", tostring(age))
      no_errors(r, env)
   end)

-- [Y02-Y08, Y14, Y15] the lure logic: thresholds, give-up, reset, alert fallback
scenario("auto-lure-cycle",
   "lure handling: asked within 30 s of expiry (not before), three tries then give up, a fresh lure or '/fb auto lure' resets the give-up, "
   .. "with the option off a warning appears at the right moments",
   function(r)
      local function lure_env(seconds, setup, server)
         local env = boot{ bom = "strip", world = { bags_have_lure = true, lure_seconds = seconds }, server = server }
         if setup then setup(env) end
         return env
      end
      local env = lure_env(25)
      start(env, 40)
      r:check(PX.count_lure_lines(env) >= 1, "25 s left: the bot is asked to apply a lure")
      local env2 = lure_env(60)
      start(env2, 40)
      r:check(PX.count_lure_lines(env2) == 0, "60 s left: not yet")
      -- give up, fresh lure resets, expires again
      local env3 = lure_env(0, nil, { lure_applies = false })
      r.env = env3
      start(env3, 100)
      r:check(PX.count_lure_lines(env3) == 3, "three tries, then given up", PX.count_lure_lines(env3) .. " lines")
      r:check(chat_has(env3, "did not apply the lure"), "and the player is told")
      env3.world.lure_seconds = 600
      env3:advance(10, 0.5)
      env3.world.lure_seconds = 0
      env3:advance(100, 0.5)
      r:check(PX.count_lure_lines(env3) == 6, "a lure that sat in between resets the give-up: three more tries", PX.count_lure_lines(env3) .. " lines")
      env3:slash("/fb auto lure"); env3:slash("/fb auto lure")
      env3:advance(100, 0.5)
      r:check(PX.count_lure_lines(env3) == 9, "'/fb auto lure' off/on resets the give-up as well: three more tries", PX.count_lure_lines(env3) .. " lines")
      no_errors(r, env3)
      -- option off: warnings only, once a minute, with the right text
      local env4 = lure_env(0, function(e) e.G.FishingBuddy.SetSetting("AutoFishAutoLure", 0) end)
      start(env4, 130)
      local gone = PX.chat_count(env4, "Your lure has expired")
      r:check(PX.count_lure_lines(env4) == 0 and gone >= 1 and gone <= 3, "[option off, lure expired] a warning every ~60 s, no command", gone .. " warnings")
      local env5 = lure_env(20, function(e) e.G.FishingBuddy.SetSetting("AutoFishAutoLure", 0) end)
      start(env5, 40)
      r:check(PX.chat_count(env5, "Lure expires in") >= 1 and PX.chat_count(env5, "Your lure has expired") == 0, "[option off, 20 s left] the 'expires in N seconds' text")
      local env6 = lure_env(0, function(e) e.G.FishingBuddy.SetSetting("AutoFishAutoLure", 0); e.G.FishingBuddy.SetSetting("AutoFishLureAlert", 0) end)
      start(env6, 130)
      r:check(PX.chat_count(env6, "lure") == 0 or (PX.chat_count(env6, "lure") == PX.chat_count(env6, "Let the bot apply lures")), "[both options off] no lure warning", PX.chat_count(env6, "Your lure has expired") .. " warnings")
   end)

-- [Y29-Y31] the chat types a block line can use and the placeholders
scenario("auto-chat-types",
   "'/s /y /p /g /o /ra /rw /bg' map to their chat types; %z and %s are the zone and the sub zone",
   function(r)
      local cases = {
         { "/s say it", "SAY", "say it" }, { "/y yell it", "YELL", "yell it" }, { "/p party it", "PARTY", "party it" },
         { "/g guild it", "GUILD", "guild it" }, { "/o officer it", "OFFICER", "officer it" }, { "/ra raid it", "RAID", "raid it" },
         { "/rw warn it", "RAID_WARNING", "warn it" }, { "/bg bg it", "BATTLEGROUND", "bg it" },
      }
      local lines = { "/w %p do move near water", "/w %p do go fishing" }
      for _, c in ipairs(cases) do lines[#lines + 1] = c[1] end
      lines[#lines + 1] = "/s here: %z | %s | %q"
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishLoopCommands = table.concat(lines, "\n") }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved, world = { party = 2 } }
      r.env = env
      start(env)
      local seen = {}
      for _, e in ipairs(env.sent) do seen[e.text] = e.chattype end
      for _, c in ipairs(cases) do
         r:check(seen[c[3]] == c[2], c[1] .. " -> " .. c[2], tostring(seen[c[3]]))
      end
      r:check(seen["here: Stranglethorn Vale | Booty Bay | %q"] == "SAY", "%z = zone, %s = sub zone, an unknown placeholder stays", table.concat(sent_texts(env), " | "))
      no_errors(r, env)
   end)

-- [Y01, Y11] the numbers the player reads: run time in the summary, catch rate on the panel
scenario("auto-summary-and-panel",
   "the summary shows h:mm:ss for long runs; the panel shows 'starting' then 'ON', the catch rate only after 30 s, and OFF after the stop",
   function(r)
      local env = boot{ bom = "strip", server = { catch = false } }       -- only the simulated catch counts
      r.env = env
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(2, 0.1)
      r:check(PX.panel_texts(env):find("Auto Fishing: starting", 1, true) ~= nil, "panel: starting while the start is being confirmed", PX.panel_texts(env))
      r:check(PX.until_step(env, "run"), "confirmed")
      env:advance(1, 0.5)
      r:check(PX.panel_texts(env):find("Auto Fishing: ON", 1, true) ~= nil, "panel: ON", PX.panel_texts(env))
      env.world.loot = { 13754 }; env.world.loot_is_fishing = true
      env:fire("LOOT_OPENED")
      env:advance(5, 0.5)
      r:check(PX.panel_texts(env):find("1 Fish  |  0/h", 1, true) ~= nil, "panel: one catch, rate still 0/h during the first 30 s", PX.panel_texts(env))
      env:advance(60, 0.5)
      local rate = PX.panel_texts(env):match("1 Fish  |  (%d+)/h")
      r:check(rate and tonumber(rate) > 30 and tonumber(rate) < 80, "panel: after ~85 s the rate is about 40/h", tostring(rate))
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(35, 0.5)
      r:check(PX.panel_texts(env):find("Auto Fishing: OFF", 1, true) ~= nil, "panel: OFF after the stop", PX.panel_texts(env))
      -- long run: h:mm:ss
      local env2 = boot{ bom = "strip" }
      env2:call("Auto.Toggle", Auto(env2).Toggle)
      env2:advance(3725, 0.5)
      r:check(Auto(env2).IsRunning(), "precondition: still running after 3725 s")
      env2:call("Auto.Stop", Auto(env2).Stop)
      r:check(chat_has(env2, "Ran for 1:02:05"), "summary: 3725 s = 1:02:05")
   end)

-- [Z19] Stop / "/fb auto off" while nothing runs
scenario("auto-stop-when-off",
   "'/fb auto off' while auto fishing is off does nothing: no 'stopped' message, no summary, nothing sent, other addons' STOP handlers are not called",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local stops = 0
      env.G.FishingBuddy.API.RegisterHandlers({ [env.G.FBConstants.AUTO_STOP_EVT] = function() stops = stops + 1 end })
      env:clear_sent()
      env.chat = {}
      env:slash("/fb auto off")
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(2, 0.1)
      r:check(not chat_has(env, "Auto fishing stopped") and not chat_has(env, "Ran for"), "no 'stopped' message and no summary")
      r:check(#env.sent == 0, "nothing was sent")
      r:check(stops == 0, "no STOP event for other addons", "stop events: " .. stops)
      r:check(#(env.sounds or {}) == 0, "no alert sound")
   end)

-- [Z15] the cleanup after login keeps waiting for the bot (a sleeping bot answers late)
scenario("auto-resume-slow-bot",
   "pending cleanup, the bot answers the probe but reads the removal only 5 s later: the cleanup waits for it and then switches the bot off",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishPending = { ownsBot = true, restore = true } }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved,
         server = { active = true, persisted = { "nc", "chat", "follow", "default", "master fishing" } } }
      r.env = env
      local srv = env.server
      local guard = 0
      while count_sent_matching(env, "-master fishing") == 0 and guard < 3000 do env:advance(0.01, 0.01); guard = guard + 1 end
      srv.ready_at = env.now + 5                             -- the bot falls asleep just after answering the probe
      env:advance(40, 0.1)
      r:check(not srv.active, "the bot we had switched on is off after all")
      r:check(srv.persisted and not srv.persisted["master fishing"] and srv.persisted["mount"], "and its stored set is clean")
      no_errors(r, env)
   end)

-- [P04, P05, P09, P11] a Hold that raises: Botpad does not hold, so the addon must wait out the burst -- and report the errors
scenario("auto-botpad-hold-errors-strict",
   "Hold and Release raise: the addon waits for the Botpad burst like with an old Botpad (our nc is not overwritten), and the errors are reported",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, true)
      local holds = 0
      BP.Bot.Hold = function() holds = holds + 1; error("boom in Hold") end
      BP.Bot.Release = function() error("boom in Release") end
      start(env, 60)
      r:check(BP.Bot.bursts == 1, "Botpad burst once (it was not held)", "bursts: " .. BP.Bot.bursts)
      r:check(count_sent(env, "nc ?,-mount,-master fishing,?") == 1, "no retry was needed: the command went out after the burst")
      local ours = 0
      for _, c in ipairs(env.server.collapsed) do if c.text:find("master fishing", 1, true) then ours = ours + 1 end end
      r:check(ours == 0, "none of OUR nc commands was overwritten (Botpad's own burst may collapse itself)", ours .. " lost")
      local n_before = #env.errors
      r:check(n_before >= 1, "the Hold error was reported", n_before .. " errors")
      stop(env)
      r:check(#env.errors > n_before, "the Release error was reported")
      r:check(not env.server.active, "stopped cleanly")
      start(env, 5)
      r:check(holds == 2, "the second run asks Botpad to hold again (the failed Release did not leave the addon believing it still holds)", "Hold calls: " .. holds)
   end)


-- proposed_defect_scenarios.lua  (mutation-testing lens)
-- ---------------------------------------------------------------------------
-- Three scenarios that FAIL on the current FishingAuto.lua (HEAD 09f49cc).  They came out of the analysis of
-- surviving mutants: the survivor was not "equivalent", the mutant (or a small fix) behaves better than the code.
-- Paste next to proposed_scenarios.lua (same helpers); until the code is fixed list the three names in
-- tests/expected_failures.txt.  The suggested one-line fixes are in the comments and were checked in a scratch copy.
-- ---------------------------------------------------------------------------

-- Fix: in SessionEvent, branch kind == "refused", set  s.toggleSent = false;  before Fail(...)  (the toggle WAS answered),
-- so BeginShutdown does not wait TOGGLE_WAIT (5 s) for an answer that has already come.
scenario("auto-refusal-restart",
   "after the server refused the self bot the addon is idle at once: no 5 s 'stopping' phase that blocks the next Start",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 0 } }
      r.env = env
      start(env, 5)                                          -- the refusal arrived at ~3.1 s
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(not Auto(env).GetState().stopping and Auto(env).GetState().step == "idle", "idle right after the refusal", Auto(env).GetState().step)
      env.server.level = 2                                   -- the player fixes the server setting
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(Auto(env).IsRunning(), "the next Start is accepted at once")
      r:check(not chat_has(env, "still being stopped"), "no 'still being stopped' message")
   end)

-- Fix: in Auto.AbortShutdown use  if ( st.ownsBot or st.restore ) and st.step ~= "awaiton" then SavePending(st.ownsBot, st.restore) end
-- (any step that still owes the bot a cleanup, not only "remove").
scenario("auto-double-reload-pending",
   "a second /reload within the ~0.2-18 s the cleanup probe is outstanding must not forget the cleanup",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env)
      env:fire("PLAYER_LOGOUT")
      env:advance(3, 0.1)
      -- session 2: the first removal was lost, the bot still has the strategy
      local env2 = boot{ bom = "strip", saved = saved_of(env),
         server = { active = true, persisted = { "nc", "chat", "follow", "default", "master fishing" } } }
      r.env = env2
      local g = 0
      while not Auto(env2).GetState().stopping and g < 2000 do env2:advance(0.01, 0.01); g = g + 1 end
      env2:advance(0.03, 0.01)                               -- the cleanup probe is out, its answer is not in yet
      r:check(Auto(env2).GetState().stopping and Auto(env2).GetState().step == "stopping", "precondition: cleanup probe outstanding")
      env2:fire("PLAYER_LOGOUT")                             -- the player reloads again
      local pend = env2.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(pend) == "table" and pend.ownsBot == true, "the cleanup is saved for the next session again")
   end)

-- Fix: in SessionTick, probe branch, after  s.sawOn  re-probe wait at least as long as the deaf window of a fresh bot:
--     s.due = now + 12;     instead of     s.due = now + ProbeWait();
scenario("auto-foreign-on-during-probe",
   "somebody else (Botpad, AutoTravel) switches the bot on while the probe is outstanding: the addon asks again and does NOT toggle (no off/on pair)",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(0.5, 0.1)
      srv:toggle()                                           -- a foreign "SelfBot is now active."
      env:advance(60, 0.1)
      r:check(Auto(env).IsRunning() and srv.casts >= 1, "running, the bot casts")
      r:check(srv.toggles == 1, "the addon did not toggle the bot that somebody else had just switched on", "toggles: " .. srv.toggles)
      r:check(not Auto(env).GetState().ownsBot, "and does not claim it")
   end)



-- ---------------------------------------------------------------------------
-- scenarios for the defects the independent review confirmed (each one fails on the code before the fixes)
-- ---------------------------------------------------------------------------

-- Stop between the corrective second toggle and its answer: the bot was on before Start, so it stays on.
scenario("auto-stop-during-retoggle",
   "Stop between the corrective second toggle and its answer: the bot was on before Start and stays on (no third toggle)",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      local g = 0
      while srv.toggles < 2 and g < 3000 do env:advance(0.01, 0.01); g = g + 1 end
      r:check(srv.toggles == 2, "precondition: the corrective toggle is out", "toggles: " .. srv.toggles)
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(30, 0.1)
      r:check(srv.active, "the bot is on again, as it was before Start", "toggles: " .. srv.toggles)
      r:check(srv.toggles == 2, "no third toggle", "toggles: " .. srv.toggles)
      no_errors(r, env)
   end)

-- A reply to the apply command that arrives after Stop must not count as the confirmation of the removal.
scenario("auto-stop-sweep",
   "Stop at any moment of a cold start leaves the bot clean ('master fishing' gone, 'mount' back, bot off), for a fast and a slow link",
   function(r)
      local bad = {}
      for _, latency in ipairs{ 0.08, 0.5 } do
         for k = 0, 44 do
            local t = k * 0.7
            local env = boot{ bom = "strip", server = { latency = latency } }
            r.env = env
            local srv = env.server
            env:call("Auto.Toggle", Auto(env).Toggle)
            env:advance(t, 0.05)
            env:call("Auto.Stop", Auto(env).Stop)
            env:advance(60, 0.1)
            local clean = (not srv.active) and srv.persisted ~= nil and not srv.persisted["master fishing"] and srv.persisted["mount"]
            if srv.persisted == nil then clean = not srv.active end       -- never activated: nothing stored
            if not clean then bad[#bad + 1] = ("lat %.2f stop@%.1f active=%s master=%s mount=%s"):format(
               latency, t, tostring(srv.active), tostring(srv.persisted and srv.persisted["master fishing"]), tostring(srv.persisted and srv.persisted["mount"])) end
            if #env.errors > 0 then bad[#bad + 1] = "Lua error at " .. t .. ": " .. env.errors[1].message end
         end
      end
      r:check(#bad == 0, "every Stop time ends clean", table.concat(bad, " | "))
   end)

-- Several stop times with the link slow enough that the first list of the apply command arrives after Stop.
scenario("auto-stop-stale-list",
   "a list that answers the start command and arrives after Stop is not taken as the confirmation of the removal",
   function(r)
      local env = boot{ bom = "strip", server = { latency = 0.5 } }
      r.env = env
      local srv = env.server
      env:call("Auto.Toggle", Auto(env).Toggle)
      -- run until the apply command has been drained by the (awake) bot, its two answers are still on the way
      local g = 0
      while #srv.executed == 0 and g < 6000 do env:advance(0.01, 0.01); g = g + 1 end
      r:check(#srv.executed == 1, "precondition: the apply command was executed", "executed: " .. #srv.executed)
      env:advance(0.1, 0.01)
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(60, 0.1)
      r:check(not srv.active and not srv.persisted["master fishing"] and srv.persisted["mount"],
              "the bot is clean and off", table.concat(srv:strategies(), ", "))
      no_collapse(r, env)
   end)

-- A refused start must not leave the addon in a 5 s 'stopping' phase (covered by auto-refusal-restart too).

-- Logout while the bot sleeps on the bobber: the removal cannot reach it. The next session must still know that 'mount'
-- was taken away, and take 'master fishing' back as soon as the bot is on and listening.
scenario("auto-logout-asleep",
   "a real logout while the bot sleeps: the note stays, the next run puts 'mount' back, and the leftover strategy is gone afterwards",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env, 45)
      local srv = env.server
      env:fire("PLAYER_LOGOUT")
      srv:deactivate()                                  -- the player left: the AI (and its queue) is gone
      local left = {}
      for n in pairs(srv.persisted) do left[n] = true end
      r:check(not left["master fishing"] and not left["mount"], "precondition: the server lost 'mount' (the removal never reached the bot)")
      -- next login, the bot is off: the note stays
      local list = {}
      for n in pairs(left) do list[#list + 1] = n end
      local env2 = boot{ bom = "strip", saved = saved_of(env), server = { persisted = list } }
      r.env = env2
      env2:advance(30, 0.1)
      local note = env2.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(note) == "table" and note.restore == true and note.tries == 1, "the note survived an unanswered cleanup")
      -- a normal run: the leftover list has no 'mount', but the note says it was taken away
      start(env2, 45)
      local srv2 = env2.server
      r:check(srv2.casts >= 1 and not srv2:has("mount"), "running")
      r:check(env2.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "the run took the note over")
      stop(env2, 40)
      r:check(not srv2.active and srv2.persisted["mount"] and not srv2.persisted["master fishing"],
              "after Stop: 'mount' is back, 'master fishing' gone, bot off")
      no_errors(r, env2)
   end)

-- SelfBotLevel > 2: the bot is switched on silently at login and deaf for ~10 s; the cleanup probe waits long enough.
scenario("auto-resume-deaf-bot",
   "cleanup after a /reload when the bot was switched on silently at login (deaf for ~10 s): the probe waits for it and cleans up",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishPending = { ownsBot = false, restore = true } }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved,
         server = { selfbot_level = 3, login_auto = true, persisted = { "nc", "chat", "follow", "default", "master fishing" } } }
      r.env = env
      env:advance(40, 0.1)
      local srv = env.server
      r:check(not srv:has("master fishing") and srv:has("mount"), "leftover 'master fishing' removed, 'mount' back", table.concat(srv:strategies(), ", "))
      r:check(srv.active and srv.toggles == 0, "the bot (not ours) was not touched otherwise")
      r:check(env.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "the note is gone")
      no_errors(r, env)
   end)

-- Start while the post-login cleanup is still waiting for the bot: no 'still being stopped', the run takes the note over.
scenario("auto-start-during-resume",
   "Start while the post-login cleanup probe is outstanding (bot off): the run starts, takes the note over and restores 'mount' at the end",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = { AutoFishPending = { ownsBot = false, restore = true } }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved, server = { persisted = { "nc", "chat", "follow", "default", "master fishing" } } }
      r.env = env
      env:advance(7, 0.1)
      r:check(Auto(env).GetState().stopping, "precondition: the cleanup probe is outstanding")
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(Auto(env).IsRunning(), "Start is accepted")
      r:check(not chat_has(env, "still being stopped"), "no 'still being stopped'")
      env:advance(45, 0.1)
      local srv = env.server
      r:check(srv.casts >= 1 and not srv:has("mount"), "running")
      stop(env, 40)
      r:check(not srv.active and srv.persisted["mount"] and not srv.persisted["master fishing"], "clean afterwards")
      no_errors(r, env)
   end)

-- Somebody else switches the bot off while the strategy is set: the strategy may stay stored. The note makes the next
-- activation (by anybody) clean it up as soon as the bot listens.
scenario("auto-foreign-off-leftover",
   "somebody switches the bot off during the run: a note is saved; when the bot is switched on again the leftover strategy is removed",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      start(env, 45)
      srv:toggle()                                       -- foreign switch-off ("deactivated")
      env:advance(5, 0.1)
      r:check(not Auto(env).IsRunning(), "the run ended")
      local note = env.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(note) == "table", "a note was saved")
      r:check(srv.persisted and not srv.persisted["mount"], "precondition: 'mount' is still missing on the server")
      srv:toggle()                                       -- somebody (Botpad, AutoTravel, the player) switches the bot on again
      env:advance(40, 0.1)
      r:check(srv.active and not srv:has("master fishing"), "the leftover strategy was removed, the bot (not ours) stays on")
      r:check(srv:has("mount"), "and 'mount' is back")
      r:check(env.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "note cleared")
      no_errors(r, env)
   end)

-- The bot's answers to the stop command are hidden too, also after a long quiet run.
scenario("auto-echo-stop",
   "the bot's answer to the stop command (long after the last probe) does not show up in the chat window",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env, 90)
      env:advance(60, 0.5)
      env.chat_display = env.chat_display or {}
      local before = #env.chat_display
      stop(env, 40)
      local leaked = {}
      for i = before + 1, #env.chat_display do
         local l = env.chat_display[i]
         if tostring(l):lower():find("strategies:", 1, true) then leaked[#leaked + 1] = l end
      end
      r:check(#leaked == 0, "no 'Strategies:' line in the chat window after Stop", table.concat(leaked, " | "))
   end)

-- The first automatic lure attempt must not be wasted on a bot that is not active yet.
scenario("auto-lure-during-start",
   "an expired lure at Start: the bot lure command is not sent before the start is confirmed",
   function(r)
      local env = boot{ bom = "strip", world = { bags_have_lure = true, lure_seconds = 0 } }
      r.env = env
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(12, 0.1)                               -- probe, toggle, settle, apply: not confirmed yet
      local early = 0
      for _, e in ipairs(env.sent) do if e.text:find("^u ") then early = early + 1 end end
      r:check(early == 0, "no lure line before the start is confirmed", "sent: " .. early)
      env:advance(60, 0.1)
      local lines = 0
      for _, e in ipairs(env.sent) do if e.text:find("^u ") then lines = lines + 1 end end
      r:check(lines >= 1, "but later it is tried", "sent: " .. lines)
   end)

-- Non-nc lines of a custom block run once; only the merged nc command is repeated.
scenario("auto-stop-others-once",
   "a custom stop block with a /s line: the line is spoken once although the removal is repeated while the bot does not answer",
   function(r)
      local env = boot{ bom = "strip",
         server = { active = true, persisted = { "nc", "chat", "follow", "default", "mount" } } }
      r.env = env
      env.G.FishingBuddy_Player.Settings.AutoFishStopCommands = "/w %p nc -master fishing\n/s fishing is over"
      start(env, 40)
      env.server.ready_at = env.now + 100                     -- the bot stops reading chat
      env:clear_sent()
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(40, 0.1)
      local said, nc = 0, 0
      for _, e in ipairs(env.sent) do
         if e.text == "fishing is over" then said = said + 1 end
         if e.text:find("^nc ") then nc = nc + 1 end
      end
      r:check(nc >= 2, "precondition: the removal was repeated", "nc sends: " .. nc)
      r:check(said == 1, "the /s line went out once", "said: " .. said)
   end)

-- The bot already has the wanted strategies: the reply to the apply command is suppressed by the server (same text).
scenario("auto-already-fishing",
   "the bot already fishes by strategy ('master fishing' set, no 'mount'): the leftover is taken away once, without a failed retry, and the loop takes over",
   function(r)
      local env = boot{ bom = "strip",
         server = { active = true, persisted = { "nc", "chat", "follow", "default", "master fishing" } } }
      r.env = env
      env:advance(15, 0.5)
      start(env, 40)
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run", "running", Auto(env).GetState().step)
      r:check(env.server.toggles == 0, "no toggle")
      local applies = count_sent(env, "nc -master fishing,?")
      r:check(applies == 1, "the leftover strategy was removed once, no retry", "applies: " .. applies)
      r:check(not env.server:has("master fishing") and env.server.casts >= 1, "and the loop fishes instead")
      r:check(chat_has(env, "Auto fishing started"), "started message")
      no_errors(r, env)
   end)

-- Stop and Start in quick succession on a bot that is not ours: the probe reply equals the stop reply (suppressed by the server).
scenario("auto-restart-quick",
   "Stop, then Start again within a second on a bot that was on before: the suppressed duplicate reply does not make the addon toggle the bot",
   function(r)
      local env = boot{ bom = "strip", server = { active = true } }
      r.env = env
      env:advance(15, 0.5)
      start(env, 40)
      local srv = env.server
      env:call("Auto.Stop", Auto(env).Stop)
      local g = 0
      while Auto(env).GetState().stopping and g < 3000 do env:advance(0.05, 0.05); g = g + 1 end
      env:advance(0.3, 0.05)
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(45, 0.1)
      r:check(srv.toggles == 0, "the bot was never toggled", "toggles: " .. srv.toggles)
      r:check(Auto(env).IsRunning() and srv.casts >= 1, "and fishes again")
      no_errors(r, env)
   end)

-- Somebody else switches the bot on while the probe is outstanding: re-ask after the deaf window (one toggle fewer).
-- (auto-foreign-on-during-probe above)

-- ---------------------------------------------------------------------------
-- the loop (the player parks the character at the water; the addon casts by 'do' whispers)
-- ---------------------------------------------------------------------------

scenario("auto-loop-basic",
   "the loop: before every cast 'do move near water' then 'do go fishing'; the next pair only after the fish; no strategy is set, "
   .. "no nc command goes out while fishing; the whispers are hidden; Stop ends the loop",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      start(env, 120)
      local seq = {}
      for _, e in ipairs(env.sent) do
         if e.text == "do move near water" or e.text == "do go fishing" then seq[#seq + 1] = e.text end
      end
      local ok = (#seq >= 10 and #seq % 2 == 0)
      for i = 1, #seq do
         local want = (i % 2 == 1) and "do move near water" or "do go fishing"
         if seq[i] ~= want then ok = false end
      end
      r:check(ok, "the whispers come in pairs: 'do move near water', then 'do go fishing'", #seq .. " whispers")
      r:check(#seq == srv.casts * 2, "every pair produced one cast: nothing is sent while a fish is awaited", #seq .. " whispers, " .. srv.casts .. " casts")
      r:check(srv.casts >= 6 and srv.casts <= 9, "about one cast per bite (12 s in the model) plus the pauses", "casts: " .. srv.casts)
      r:check(not srv:has("master fishing") and count_sent_matching(env, "+master fishing") == 0, "the strategy 'master fishing' is never set")
      local ncs = 0
      for _, e in ipairs(env.sent) do if e.text:find("^nc ") then ncs = ncs + 1 end end
      r:check(ncs == 2, "only the probe and the preparation are nc commands", "nc commands: " .. ncs)
      local stats = env.G.FishingBuddy.Stats and env.G.FishingBuddy.Stats.Get and env.G.FishingBuddy.Stats.Get()
      r:check(stats and stats.catches >= srv.casts - 1, "the catches were counted", stats and ("catches=" .. stats.catches) or "no stats")
      r:check(not table.concat(env.chat_display, "\n"):find("do go fishing", 1, true), "the whispers to oneself are not shown in the chat")
      local st = Auto(env).GetState()
      r:check(st.running and st.step == "run" and st.loop ~= nil, "state: running, step 'run', a loop phase", tostring(st.loop))
      no_collapse(r, env)
      local before = count_sent(env, "do go fishing")
      stop(env)
      env:advance(60, 0.5)
      r:check(count_sent(env, "do go fishing") == before, "after Stop no further cast is sent")
      r:check(not srv.active and srv.persisted and srv.persisted["mount"], "bot off again, 'mount' restored")
      no_errors(r, env)
   end)

scenario("auto-loop-no-water",
   "no water within reach: five attempts, then the run ends with an explanation and the bot we switched on is switched off again",
   function(r)
      local env = boot{ bom = "strip", server = { water = false } }
      r.env = env
      start(env, 150)
      r:check(not Auto(env).IsRunning(), "the run gave up")
      r:check(chat_has(env, "The bot does not cast"), "the player is told what to check")
      r:check(count_sent(env, "do go fishing") == 5, "after exactly five attempts", count_sent(env, "do go fishing") .. " attempts")
      r:check(env.server.casts == 0, "nothing was cast")
      r:check(not env.server.active, "the bot we switched on is switched off again")
      no_errors(r, env)
   end)

scenario("auto-loop-walk",
   "the bot has to walk to the shore first: the wait is not a failed attempt, the next pair follows once it arrived",
   function(r)
      local env = boot{ bom = "strip", server = { walk = 6 } }
      r.env = env
      start(env, 90)
      r:check(Auto(env).IsRunning(), "still running")
      r:check(env.server.casts >= 1, "it cast after the walk", "casts: " .. env.server.casts)
      r:check(not chat_has(env, "The bot does not cast"), "no complaint")
      r:check(Auto(env).GetState().fails == 0, "no failed attempts are left over", "fails: " .. Auto(env).GetState().fails)
      no_errors(r, env)
   end)

scenario("auto-loop-fish-got-away",
   "the fish gets away (the channel ends without loot): the loop does not stall, it casts again after a short wait",
   function(r)
      local env = boot{ bom = "strip", server = { catch = false } }
      r.env = env
      start(env, 120)
      r:check(Auto(env).IsRunning(), "still running")
      r:check(env.server.casts >= 5, "casts keep coming", "casts: " .. env.server.casts)
      local stats = env.G.FishingBuddy.Stats and env.G.FishingBuddy.Stats.Get and env.G.FishingBuddy.Stats.Get()
      r:check(not stats or (stats.catches or 0) == 0, "and nothing is counted as caught")
      no_errors(r, env)
   end)

scenario("auto-loop-mounted",
   "the character mounts in the middle of a run: nothing is cast while mounted, the loop goes on after the dismount",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env, 45)
      r:check(env.server.casts >= 1, "precondition: fishing")
      env.world.mounted = true
      env:advance(40, 0.5)                                    -- the cast under way ends
      env:clear_sent()
      env:advance(40, 0.5)
      r:check(count_sent_matching(env, "do ") == 0, "nothing is sent while mounted", table.concat(sent_texts(env), " | "))
      env.world.mounted = false
      env:advance(10, 0.5)
      r:check(count_sent(env, "do go fishing") >= 1, "the loop goes on after the dismount")
      no_errors(r, env)
   end)

scenario("auto-loop-stop-fast",
   "a bot that is not ours and had no 'mount': nothing was prepared, so Stop is immediate and sends no nc command",
   function(r)
      local env = boot{ bom = "strip", server = { active = true, persisted = { "nc", "chat", "follow", "default" } } }
      r.env = env
      start(env, 30)
      r:check(env.server.casts >= 1, "precondition: fishing")
      env:clear_sent()
      env:call("Auto.Stop", Auto(env).Stop)
      r:check(not Auto(env).GetState().stopping and not Auto(env).IsRunning(), "stopped at once, no waiting for the bot")
      env:advance(5, 0.1)
      r:check(count_sent_matching(env, "nc ") == 0, "no nc command on Stop", table.concat(sent_texts(env), " | "))
      r:check(env.server.active and env.server.toggles == 0, "the bot (not ours) stays on")
      no_errors(r, env)
   end)

scenario("auto-loop-afk",
   "the client marked the character AFK (5 min without input): the server answers every whisper to oneself with a system message; "
   .. "the loop's two whispers per cast must not flood the chat, and other system messages stay visible",
   function(r)
      local function shown(e, needle)
         local n = 0
         for _, l in ipairs(e.chat_display) do if l:find(needle, 1, true) then n = n + 1 end end
         return n
      end
      local env = boot{ bom = "strip", world = { afk = true } }
      r.env = env
      start(env, 90)
      r:check(Auto(env).IsRunning() and env.server.casts >= 3, "the loop runs", "casts: " .. env.server.casts)
      r:check(shown(env, "Away from Keyboard") == 0, "the AFK auto-replies are hidden", shown(env, "Away from Keyboard") .. " shown")
      -- a system message that is not the reply to our own whisper is untouched
      env:advance(10, 0.5)
      env:chat_event("CHAT_MSG_SYSTEM", "Testchar has reached a milestone.")
      r:check(shown(env, "has reached a milestone") == 1, "other system messages stay visible")
      -- option off: the replies are shown
      local env2 = boot{ bom = "strip", world = { afk = true } }
      env2.G.FishingBuddy.SetSetting("AutoFishHideEcho", 0)
      start(env2, 60)
      r:check(shown(env2, "Away from Keyboard") >= 2, "[option 'hide bot whispers' off] they are shown", shown(env2, "Away from Keyboard") .. " shown")
      -- not AFK: nothing to hide, the filter lets everything through
      local env3 = boot{ bom = "strip" }
      start(env3, 30)
      env3.G.SendChatMessage("x", "WHISPER", nil, env3.G.UnitName("player"))
      env3:chat_event("CHAT_MSG_SYSTEM", "Testchar is Away from Keyboard: test")
      r:check(shown(env3, "Away from Keyboard") == 1, "without AFK the filter hides nothing")
      no_errors(r, env)
   end)

-- Hand-written block that resets with "nc !" before setting: the server applies '!' last; the warning/hint is in the docs.

-- ---------------------------------------------------------------------------
-- run
-- ---------------------------------------------------------------------------

if list_only then
   for _, s in ipairs(scenarios) do print(("%-18s %s"):format(s.name, s.descr)) end
   os.exit(0)
end

local function summarize_errors(env)
   local counts, order = {}, {}
   for _, e in ipairs(env.errors) do
      local key = e.message
      if not counts[key] then counts[key] = { n = 0, context = e.context, trace = e.trace }; order[#order + 1] = key end
      counts[key].n = counts[key].n + 1
   end
   return counts, order
end

local total_fail, results = 0, {}
for _, s in ipairs(scenarios) do
   if not only or only[s.name] then
      local r = new_result(s.name, s.descr)
      local ok, err = xpcall(function() s.fn(r) end, debug.traceback)
      if not ok then r:check(false, "scenario driver crashed (harness bug or unexpected addon state)", tostring(err)) end
      results[#results + 1] = r
   end
end

print("Fishing Buddy offline boot harness  --  repo: " .. repo)
print("(offline Lua 5.1 against stubs; NOT a real 3.3.5a client -- see README.txt, 'Honest boundary')")
local xfail_unexpected_pass = {}
for _, r in ipairs(results) do
   local xf = expect_fail[r.name]
   local status = (r.failed == 0) and "PASS" or (xf and "XFAIL" or "FAIL")
   if r.failed == 0 and xf then status = "XPASS"; xfail_unexpected_pass[#xfail_unexpected_pass + 1] = r.name end
   if r.skipped and r.failed == 0 then status = "SKIP" end
   print(("\n=== [%s] %s -- %s"):format(status, r.name, r.descr))
   for _, c in ipairs(r.checks) do
      if verbose or not c.ok then
         print(("    %s %s%s"):format(c.ok and "ok  " or "FAIL", c.what, c.detail and ("   <" .. c.detail .. ">") or ""))
      end
   end
   if not verbose and r.failed == 0 then print(("    %d checks ok"):format(#r.checks)) end
   if r.env and show_trace and r.failed > 0 then
      local env = r.env
      local FBt = env.G.FishingBuddy
      print("    --- trace (Auto.GetTrace) ---")
      for _, line in ipairs((FBt and FBt.Auto and FBt.Auto.GetTrace and FBt.Auto.GetTrace()) or {}) do print(("      %7.2f  %s"):format(tonumber(line.t) or 0, tostring(line.text))) end
      print("    --- sent ---")
      for _, e in ipairs(env.sent) do print(("      %s: %s"):format(tostring(e.chattype), tostring(e.text))) end
   end
   if r.env then
      local env = r.env
      local counts, order = summarize_errors(env)
      if #order > 0 then
         print(("    Lua errors recorded: %d (%d distinct)"):format(#env.errors, #order))
         for _, key in ipairs(order) do
            print(("      x%d  [%s]  %s"):format(counts[key].n, counts[key].context, key))
         end
      end
      local failed = {}
      for f, why in pairs(env.files_failed) do failed[#failed + 1] = f .. " (" .. why .. ")" end
      table.sort(failed)
      if #failed > 0 then print("    files that did not load: " .. table.concat(failed, ", ")) end
   end
   if r.failed > 0 and not xf then total_fail = total_fail + 1 end
end

-- compact summary table
do
   print("\nsummary:")
   print(("  %-26s %-6s %6s %8s  %s"):format("scenario", "status", "errors", "notload", "checks failed"))
   for _, r in ipairs(results) do
      local xf = expect_fail[r.name]
      local status = (r.failed == 0) and (xf and "XPASS" or "PASS") or (xf and "XFAIL" or "FAIL")
      local nerr, nload = "-", "-"
      if r.env then
         nerr = tostring(#r.env.errors)
         local c = 0 for _ in pairs(r.env.files_failed) do c = c + 1 end
         nload = tostring(c + (r.env.toc_dropped and 1 or 0))
      end
      print(("  %-26s %-6s %6s %8s  %d"):format(r.name, status, nerr, nload, r.failed))
   end
end

-- harness gaps (methods the stub accepted but ignored)
do
   local seen = {}
   for _, r in ipairs(results) do
      if r.env then for k, n in pairs(r.env.unmodelled) do seen[k] = (seen[k] or 0) + n end end
   end
   local names = {}
   for k in pairs(seen) do names[#names + 1] = k end
   table.sort(names)
   print(("\nharness gap report: %d widget methods were called but are not modelled (accepted and ignored)"):format(#names))
   if verbose and #names > 0 then print("  " .. table.concat(names, ", ")) end
end

if #xfail_unexpected_pass > 0 then
   print("\nnote: scenarios expected to fail but passing: " .. table.concat(xfail_unexpected_pass, ", "))
end
print(("\n%d scenario(s), %d unexpected failure(s)"):format(#results, total_fail))
os.exit(total_fail > 0 and 1 or 0)
