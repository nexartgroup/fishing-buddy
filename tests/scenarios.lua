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
   r:check(srv:has("master fishing"), "auto: the bot has the strategy 'master fishing'", table.concat(srv:strategies(), ", "))
   r:check(srv.toggles == 1, "auto: '.playerbots bot self' was sent exactly once", "toggles: " .. srv.toggles)
   r:check(#srv.dropped == 0 and #srv.said == 0, "auto: nothing was dropped by the core and nothing was said aloud",
           "dropped: " .. #srv.dropped .. ", said: " .. #srv.said)
   r:check(#srv.collapsed == 0, "auto: no nc command was overwritten by a later one in the same AI update",
           #srv.collapsed .. " collapsed")
   r:check(chat_has(env, "Auto fishing started") or chat_has(env, "Auto-Angeln gestartet"), "auto: 'started' message printed (after the check)")
   r:check(FB.Auto.GetState().step == "run", "auto: session reached the 'run' step")
   -- time passes: panel refresh + watchdog (no catch for 100 s -> health check after 45 s idle)
   env:clear_sent()
   local n1 = #env.errors
   env:advance(100, 0.5)
   r:check(#env.errors == n1, "auto: 100 s of OnUpdate (panel refresh + watchdog) raised no Lua error")
   t = sent_texts(env)
   local probes, setters = 0, 0
   for _, x in ipairs(t) do
      if x == "WHISPER:nc ?" then probes = probes + 1 end
      if x:find("master fishing", 1, true) then setters = setters + 1 end
   end
   r:check(probes >= 1 and setters == 0, "auto: idle -> the bot is asked ('nc ?'), nothing is re-sent while the strategy is there",
           "sent: " .. table.concat(t, " | "))
   -- a simulated catch must be counted
   env.world.loot = { 13754 }
   env.world.loot_is_fishing = true
   local n2 = #env.errors
   env:fire("LOOT_OPENED")
   r:check(#env.errors == n2, "auto: LOOT_OPENED (simulated catch) raised no Lua error")
   local stats = FB.Stats and FB.Stats.Get and FB.Stats.Get()
   r:check(stats and stats.catches == 1, "auto: Stats module counted the simulated catch", stats and ("catches=" .. tostring(stats.catches)) or "no stats")
   -- stop
   env:clear_sent()
   env:call("FishingBuddy.Auto.Toggle() #2", FB.Auto.Toggle)
   r:check(not FB.Auto.IsRunning(), "auto: stopped after second Toggle()")
   r:check(chat_has(env, "caught 1") or chat_has(env, "1 F"), "auto: stop summary reports the 1 simulated catch")
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
      r:check(env.server:has("master fishing"), "slash: ... and the bot gets the strategy")
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
      env1.G.FishingBuddy.SetSetting("AutoFishKeepAlive", 0)
      env1.G.FishingBuddy.SetSetting("AutoFishStartCommands", ".playerbots bot self\n/w %p nc +master fishing\n/p co +loot\n/w %p co +loot")
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
      r:check(env.server:has("master fishing"), "custom start block: 'master fishing' arrived", joined)
      local gotloot = false
      for _, rcv in ipairs(env.server.received) do if rcv.text == "co +loot" then gotloot = true end end
      r:check(gotloot, "custom start block: the extra line 'co +loot' (whisper) reached the bot", joined)
      r:check(env.server.toggles == 1, "the legacy line '.playerbots bot self' in the saved block was NOT sent as an extra toggle", "toggles: " .. env.server.toggles)
      r:check(not joined:find("PARTY:", 1, true), "the '/p' line of the saved block is not sent while ungrouped", joined)
      r:check(chat_has(env, "Removed '.playerbots bot self'"), "the player is told that the toggle line was removed")
      r:check(chat_has(env, "not in a group"), "the player is told that a '/p' line cannot reach the bot while ungrouped")
      env:advance(120, 0.5)
      r:check(env.G.FishingBuddy.Auto.IsRunning(), "with keep-alive off and MaxMinutes=30 it is still running after 120 s")
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
            r:check(env.G.FishingBuddy.Auto.IsRunning() and env.server:has("master fishing"), "[" .. name .. "] Toggle() starts auto fishing and the bot has the strategy", table.concat(sent_texts(env), " | "))
         end
      end
   end)

scenario("lure-in-bags",
   "lures (Shiny Bauble) are in the bags and none is applied: exercises the watchdog's lure branch (command, retries, give-up) and the lure button",
   function(r)
      local env = boot{ bom = "strip", world = { bags_have_lure = true, lure_seconds = 0 } }
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
      r:check(#env.errors == 0, "2 minutes of watchdog with a missing lure: no Lua error", #env.errors > 0 and env.errors[1].message or nil)
      r:check(lurelines == 3, "lure command is sent 3 times (20 s retry) and then given up", "lure lines: " .. lurelines .. "; all: " .. table.concat(texts, " | "))
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
      r:check(env.server:has("master fishing"), "... and the bot has the strategy")
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
   "solo player, self bot off (the reported case): one combined command, the bot ends up with 'master fishing' and without 'mount'; Stop undoes it all",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      start(env)
      local st = Auto(env).GetState()
      r:check(st.running and st.step == "run", "running, step 'run'", st.step)
      r:check(srv:has("master fishing") and not srv:has("mount"), "the bot has 'master fishing' and no 'mount'")
      r:check(srv.toggles == 1 and st.ownsBot, "one toggle, and the addon knows it switched the bot on")
      r:check(sent_type(env, "PARTY") == 0, "no party chat is sent")
      r:check(count_sent(env, "nc ?,-mount,+master fishing,?") == 1, "the strategy went out as ONE command (before-list, -mount, +master fishing, after-list)")
      r:check(count_sent_matching(env, "nc +master fishing") == 0 and count_sent(env, "nc -mount") == 0, "... and not as separate nc lines")
      r:check(#srv.dropped == 0 and #srv.said == 0, "nothing dropped by the core, nothing said aloud")
      no_collapse(r, env)
      stop(env)
      r:check(not srv.active and srv.toggles == 2, "Stop switches the bot off again (we had switched it on)")
      r:check(srv.persisted and not srv.persisted["master fishing"] and srv.persisted["mount"], "the stored set is clean: no 'master fishing', 'mount' back")
      no_collapse(r, env, "after Stop")
      no_errors(r, env)
   end)

scenario("auto-bot-already-on",
   "the self bot is already on (BotPad / AutoTravel / SelfBotLevel > 2): Start must NOT toggle it off; Stop must leave it on",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      local srv = env.server
      r:check(srv.active, "precondition: the bot is on at login without any message")
      env:advance(15, 0.5)                    -- the first AI update is over: the bot hears chat commands
      start(env, 30)
      r:check(srv.toggles == 0, "Start did not send '.playerbots bot self'", "toggles: " .. srv.toggles)
      r:check(srv:has("master fishing") and not srv:has("mount"), "the strategy was set, 'mount' removed")
      r:check(not Auto(env).GetState().ownsBot, "the addon does not claim the bot")
      r:check(count_sent(env, "nc -mount,+master fishing,?") == 1, "warm start: the list was known, so no leading '?'")
      stop(env)
      r:check(srv.active and srv.toggles == 0, "Stop leaves the bot on (not ours) and sends no toggle")
      r:check(not srv:has("master fishing") and srv:has("mount"), "... but takes 'master fishing' back and restores 'mount'")
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
      r:check(srv.active and srv:has("master fishing"), "the bot is on and fishes")
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
      r:check(Auto(env).IsRunning() and env.server:has("master fishing"), "[level 1, GM] works")
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
      r:check(srv:has("master fishing"), "after that the strategy arrives")
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
      r:check(env.server:has("master fishing"), "'master fishing' survived the burst (ours was the last nc in the queue)")
      r:check(count_sent(env, "nc ?,-mount,+master fishing,?") == 1, "no retry was needed")
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
      r:check(env.server:has("master fishing"), "'master fishing' is set")
      stop(env)
      r:check(next(BP.Bot.holders) == nil, "hold released after the stop sequence")
      -- a second run in the same session takes the hold again
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(BP.Bot.holders["Fishing Buddy"], "second run: hold requested again")
      env:advance(45, 0.1)
      r:check(BP.Bot.bursts == 0 and env.server:has("master fishing"), "second run: still no burst, strategy set")
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
      r:check(Auto(env).IsRunning() and env.server:has("master fishing"), "start works although Hold raised")
      stop(env)
      r:check(not Auto(env).IsRunning() and not env.server.active, "stop works although Release raised")
   end)

scenario("auto-vanishing-strategy",
   "the bot drops 'master fishing' by itself (no water in range): re-set twice, then the addon stops and says why",
   function(r)
      local env = boot{ bom = "strip", server = { end_fishing_after = 6.0 } }
      r.env = env
      local srv = env.server
      env.G.FishingBuddy.SetSetting("AutoFishIdleSeconds", 15)
      start(env)
      env:advance(400, 0.5)
      r:check(not Auto(env).IsRunning(), "stopped by itself")
      r:check(chat_has(env, "ended fishing by itself"), "reason shown")
      r:check(count_sent_matching(env, "+master fishing") == 3, "the strategy was set at start and re-set twice", "sent: " .. count_sent_matching(env, "+master fishing"))
      r:check(not srv.active, "the bot we switched on is switched off again")
      no_collapse(r, env)
      no_errors(r, env)
   end)

scenario("auto-vanish-resets-on-catch",
   "three losses of the strategy far apart, each healed and followed by a catch, do not end the run",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      env.G.FishingBuddy.SetSetting("AutoFishIdleSeconds", 15)
      start(env)
      for round = 1, 4 do
         srv:run_nc("-master fishing")                        -- somebody else removes it
         env:advance(60, 0.5)                                 -- health check finds it missing and re-sets it
         r:check(Auto(env).IsRunning() and srv:has("master fishing"), "round " .. round .. ": healed and still running")
         env.world.loot = { 13754 }; env.world.loot_is_fishing = true
         env:fire("LOOT_OPENED")                               -- a catch proves the strategy works
      end
      r:check(Auto(env).IsRunning(), "four healed losses with catches in between: still running")
   end)

scenario("auto-strategy-refused-by-bot",
   "the bot never accepts 'master fishing' (unknown strategy name on that build): three tries, then a clear message and the bot is switched off",
   function(r)
      local env = boot{ bom = "strip", server = { ignore_fishing = true } }
      r.env = env
      start(env, 90)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(chat_has(env, "did not accept the strategy 'master fishing' after 3 tries"), "the message names the strategy and the number of tries")
      r:check(chat_has(env, "/fb auto edit"), "... and points at the command lists")
      r:check(count_sent(env, "nc ?,-mount,+master fishing,?") == 1 and count_sent(env, "nc +master fishing,?") == 2, "three attempts: the first with the leading '?', the retries without",
              "first " .. count_sent(env, "nc ?,-mount,+master fishing,?") .. ", retries " .. count_sent(env, "nc +master fishing,?"))
      r:check(not env.server.active, "the bot we switched on is off again")
      no_collapse(r, env)
      no_errors(r, env)
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
      r:check(count_sent(env3, "nc +master fishing,?") == 1, "warm start without 'mount' in the list: no -mount op")
   end)

scenario("auto-mount-recovery",
   "somebody else's 'nc !' brings 'mount' back during the run: the next check removes it again",
   function(r)
      local env = boot{ bom = "strip", server = { mount_owned = true } }
      r.env = env
      local srv = env.server
      env.G.FishingBuddy.SetSetting("AutoFishIdleSeconds", 15)
      start(env)
      srv:run_nc("!")                                       -- AutoTravel / Botpad style reset
      r:check(srv:has("mount") and not srv:has("master fishing"), "precondition: mount is back, fishing gone")
      env:advance(60, 0.5)
      r:check(srv:has("master fishing") and not srv:has("mount"), "healed: fishing set again AND mount removed again")
      no_collapse(r, env)
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
      r:check(env.server:has("master fishing") and not env.server:has("mount"), "the strategy was set and mount removed (blindly, in the first command)")
      r:check(chat_has(env, "did not answer the strategy check"), "the player is told that the start could not be confirmed")
      r:check(count_sent(env, "nc ?,-mount,+master fishing,?") == 1, "no pointless retries")
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
   "a fishing bot sleeps through the bobber wait and answers late: a started run on a busy bot is not toggled, checks and Stop wait for it",
   function(r)
      local env = boot{ bom = "strip", world = { channeling = true },
         server = { active = true, persisted = { "nc", "chat", "follow", "default", "master fishing", "mount" },
                    busy = { cycle = 40, sleep = 17 } } }
      r.env = env
      local srv = env.server
      srv.fish_since = env.now                              -- it just cast: asleep for the next 17 s
      start(env, 40)
      r:check(srv.toggles == 0, "no toggle: the probe wait was extended because the character is channelling", "toggles: " .. srv.toggles)
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run", "running")
      stop(env, 60)
      r:check(srv.active and not srv:has("master fishing"), "Stop waited for the bot to wake up and take the strategy back; the bot (not ours) stays on")
      no_collapse(r, env)
   end)

scenario("auto-late-answers",
   "a slow connection: replies take up to ~1 s each way; everything still works",
   function(r)
      local env = boot{ bom = "strip", server = { latency = 1.0 } }
      r.env = env
      start(env, 60)
      r:check(Auto(env).IsRunning() and env.server:has("master fishing"), "running with the strategy set")
      r:check(env.server.toggles == 1, "one toggle", "toggles: " .. env.server.toggles)
      stop(env, 40)
      r:check(not env.server.active and env.server.persisted and not env.server.persisted["master fishing"], "stopped cleanly")
   end)

scenario("auto-settings-migration",
   "saved command blocks that still hold the 0.9.9 defaults are replaced by the new defaults; edited blocks stay",
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
      r:check(S.AutoFishStartCommands == nil and S.AutoFishKeepAliveCommands == nil
              and S.AutoFishStopCommands == nil and S.AutoFishLureCommands == nil, "all four old defaults were cleared")
      start(env)
      r:check(env.server:has("master fishing") and #env.server.dropped == 0, "and the new defaults work")
      local saved2 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishStartCommands = "/w %p nc +master fishing\n/w %p co +loot" }, Outfit = {}, WasWearing = {} } }
      local env2 = boot{ bom = "strip", saved = saved2 }
      r:check(env2.G.FishingBuddy_Player.Settings.AutoFishStartCommands == "/w %p nc +master fishing\n/w %p co +loot", "an edited block is kept")
   end)

scenario("auto-custom-blocks",
   "edited blocks: a legacy toggle line is dropped from the STORED block (once, with a note); '/p nc' lines are merged into the single nc command, "
   .. "solo or grouped; other lines are sent as written",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishStartCommands = ".playerbots bot self\n/p nc +master fishing\n/p co +loot\n/w %p co +aoe" }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved }
      r.env = env
      start(env)
      local joined = table.concat(sent_texts(env), " | ")
      r:check(env.server:has("master fishing"), "the strategy arrived through the merged command", joined)
      r:check(env.server.toggles == 1, "the legacy toggle line did not cause a second toggle", "toggles: " .. env.server.toggles)
      r:check(count_sent_matching(env, "nc +master") == 0 and count_sent(env, "nc ?,-mount,+master fishing,?") == 1, "'/p nc ...' was merged, not sent as its own line", joined)
      local gotloot, gotaoe = false, false
      for _, rcv in ipairs(env.server.received) do
         if rcv.text == "co +loot" then gotloot = true end
         if rcv.text == "co +aoe" then gotaoe = true end
      end
      r:check(gotloot and gotaoe, "the 'co' lines (solo '/p' and '/w') reached the bot", joined)
      r:check(chat_has(env, "Removed '.playerbots bot self'"), "the player is told that the toggle line was removed")
      r:check(chat_has(env, "not in a group"), "and that a '/p' line goes to the own bot while ungrouped")
      local S = env.G.FishingBuddy_Player.Settings.AutoFishStartCommands
      r:check(S and not S:find("playerbots", 1, true), "the stored block no longer contains the toggle line", tostring(S))
      no_collapse(r, env)
      -- grouped: the nc line still goes to the own bot (whisper), a plain /p line goes to the party
      local saved2 = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishStartCommands = "/p nc +master fishing\n/p hello party" }, Outfit = {}, WasWearing = {} } }
      local env2 = boot{ bom = "strip", saved = saved2, world = { party = 2 } }
      start(env2)
      r:check(env2.server:has("master fishing"), "grouped: strategy set")
      r:check(count_sent(env2, "hello party") == 1 and sent_type(env2, "PARTY") == 1, "grouped: the plain /p line is real party chat")
      r:check(not chat_has(env2, "not in a group"), "no warning when grouped")
      no_collapse(r, env2, "grouped")
   end)

scenario("auto-trip",
   "AutoTravel: no Start during a trip; no health checks during a trip; a stop during a trip leaves the bot to AutoTravel",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      env.G.AutoTravel = { active = true }
      env:clear_sent()
      start(env, 5)
      r:check(not Auto(env).IsRunning() and #env.sent == 0, "Start refused while a trip is running, nothing sent")
      r:check(chat_has(env, "AutoTravel trip is running"), "with a hint")
      env.G.AutoTravel.active = false
      env.G.FishingBuddy.SetSetting("AutoFishIdleSeconds", 15)
      start(env)
      r:check(Auto(env).IsRunning(), "running after the trip")
      env.G.AutoTravel = { active = true }
      env:clear_sent()
      env:advance(120, 0.5)
      r:check(count_sent(env, "nc ?") == 0, "no health check during the trip", "probes: " .. count_sent(env, "nc ?"))
      env.G.AutoTravel.active = false
      env:advance(40, 0.5)
      r:check(count_sent(env, "nc ?") >= 1, "checks resume after the trip")
      -- stop in the middle of a trip that relies on the bot (supportOn)
      env.G.AutoTravel = { active = true, supportOn = true }
      stop(env)
      r:check(env.server.active, "the bot stays on: AutoTravel is using it")
      r:check(not env.server:has("master fishing"), "... but the fishing strategy is taken back")
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
      r:check(env3.G.FishingBuddy_Player.Settings.AutoFishPending == nil, "flag cleared anyway")
   end)

scenario("auto-logout-while-stopping",
   "/reload while the stop sequence is still waiting: the bot is not forgotten",
   function(r)
      local env = boot{ bom = "strip", server = { busy = { cycle = 40, sleep = 17 } } }
      r.env = env
      start(env, 55)                           -- the bot fishes and sleeps from ~1054 to ~1071
      env:call("Auto.Stop", Auto(env).Stop)
      env:advance(0.5, 0.1)
      r:check(Auto(env).GetState().stopping, "precondition: stop sequence pending (the sleeping bot has not answered)")
      env:fire("PLAYER_LOGOUT")
      local pend = env.G.FishingBuddy_Player.Settings.AutoFishPending
      r:check(type(pend) == "table" and pend.ownsBot == true, "pending cleanup saved")
      r:check(not Auto(env).GetState().stopping, "and the pending shutdown was dropped cleanly")
      -- /reload: the new session finds the bot still on and clean up
      local env2 = boot{ bom = "strip", saved = saved_of(env),
         server = { active = true, persisted = (function() local l = {} for n in pairs(env.server.persisted) do l[#l + 1] = n end return l end)() } }
      r.env = env2
      r:check(env2.server:has("master fishing"), "precondition: the left-over strategy is still on the bot")
      env2:advance(40, 0.1)
      r:check(not env2.server.active, "the next session switched the bot we had started off again")
      r:check(not env2.server.persisted["master fishing"] and env2.server.persisted["mount"], "... after taking the strategy back and restoring 'mount'")
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
      r:check(env.server:has("master fishing"), "'master fishing' is set and stayed")
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
