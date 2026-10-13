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
local only, expect_fail, verbose, list_only = nil, {}, false, false
do
   local i = 1
   while i <= #arg do
      local a = arg[i]
      if a == "--only" then only = {}; for n in arg[i + 1]:gmatch("[^,]+") do only[n] = true end; i = i + 2
      elseif a == "--expect-fail" then for n in arg[i + 1]:gmatch("[^,]+") do expect_fail[n] = true end; i = i + 2
      elseif a == "--verbose" then verbose = true; i = i + 1
      elseif a == "--list" then list_only = true; i = i + 1
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
   env:advance(15, 0.1)
   t = sent_texts(env)
   r:check(srv.active, "auto: the self bot was switched on (it was off)")
   r:check(srv:has("master fishing"), "auto: the bot has the strategy 'master fishing'", table.concat(srv:strategies(), ", "))
   r:check(srv.toggles == 1, "auto: '.playerbots bot self' was sent exactly once", "toggles: " .. srv.toggles)
   r:check(#srv.dropped == 0 and #srv.said == 0, "auto: nothing was dropped by the core and nothing was said aloud",
           "dropped: " .. #srv.dropped .. ", said: " .. #srv.said)
   r:check(chat_has(env, "Auto fishing started") or chat_has(env, "Auto-Angeln gestartet"), "auto: 'started' message printed (after the check)")
   r:check(FB.Auto.GetState().step == "run", "auto: session reached the 'run' step")
   -- time passes: panel refresh + watchdog (no catch for 100 s -> one health check after 45 s idle)
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
   env:advance(10, 0.1)
   t = sent_texts(env)
   r:check(t[1] == "WHISPER:nc -master fishing", "auto: stop first takes the strategy back (whisper)", "sent: " .. table.concat(t, " | "))
   r:check(not srv.active, "auto: after the strategy is gone the self bot is switched off again (we switched it on)")
   r:check(not srv.persisted or not srv.persisted["master fishing"], "auto: 'master fishing' is not left behind in the stored strategy set")
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
      r:check(texts[1] == "WHISPER:nc -master fishing", "stop commands were sent on that automatic stop", table.concat(texts, " | "))
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
   env:advance(secs or 15, 0.1)
end

local function stop(env, secs)
   env:call("Auto.Stop", Auto(env).Stop)
   env:advance(secs or 12, 0.1)
end

local function count_sent(env, text)
   local n = 0
   for _, e in ipairs(env.sent) do if e.text == text then n = n + 1 end end
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

scenario("auto-old-commands-fail-solo",
   "MODEL CHECK: the lines the 0.9.9 build sent ('.playerbots bot self' as SAY, '/p nc +master fishing' as PARTY) leave a solo player with an idle bot",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local G, srv = env.G, env.server
      G.SendChatMessage(".playerbots bot self", "SAY")
      G.SendChatMessage("nc +master fishing", "PARTY")
      env:advance(5, 0.1)
      r:check(srv.active, "the toggle works: the self bot is on")
      r:check(not srv:has("master fishing"), "... but the strategy never arrives (the party line is dropped)")
      r:check(#srv.dropped == 1 and srv.dropped[1].why == "no group", "the core dropped exactly the party line", #srv.dropped .. " dropped")
      -- the same player in a group: the old lines work
      local env2 = boot{ bom = "strip", world = { party = 1 } }
      env2.G.SendChatMessage(".playerbots bot self", "SAY")
      env2.G.SendChatMessage("nc +master fishing", "PARTY")
      env2:advance(5, 0.1)
      r:check(env2.server:has("master fishing"), "grouped: the old party line reaches the bot (why it 'worked' for some setups)")
   end)

scenario("auto-solo",
   "solo player, self bot off: Start switches it on once and the bot ends up with 'master fishing' (whisper to oneself)",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local srv = env.server
      start(env)
      local st = Auto(env).GetState()
      r:check(st.running and st.step == "run", "running, step 'run'", st.step)
      r:check(srv:has("master fishing"), "the bot has 'master fishing'")
      r:check(srv.toggles == 1 and st.ownsBot, "one toggle, and the addon knows it switched the bot on")
      r:check(sent_type(env, "PARTY") == 0, "no party chat is sent")
      r:check(#srv.dropped == 0 and #srv.said == 0, "nothing dropped by the core, nothing said aloud")
      stop(env)
      r:check(not srv.active and srv.toggles == 2, "Stop switches the bot off again (we had switched it on)")
      r:check(not srv.persisted or not srv.persisted["master fishing"], "the strategy is not left in the stored set")
      no_errors(r, env)
   end)

scenario("auto-bot-already-on",
   "the self bot is already on (BotPad / AutoTravel / SelfBotLevel > 2): Start must NOT toggle it off; Stop must leave it on",
   function(r)
      local env = boot{ bom = "strip", server = { selfbot_level = 3, login_auto = true } }
      r.env = env
      local srv = env.server
      r:check(srv.active, "precondition: the bot is on at login without any message")
      start(env)
      r:check(srv.toggles == 0, "Start did not send '.playerbots bot self'", "toggles: " .. srv.toggles)
      r:check(srv:has("master fishing"), "the strategy was set")
      r:check(not Auto(env).GetState().ownsBot, "the addon does not claim the bot")
      stop(env)
      r:check(srv.active and srv.toggles == 0, "Stop leaves the bot on (not ours) and sends no toggle")
      r:check(not srv:has("master fishing"), "... but takes 'master fishing' back")
      no_errors(r, env)
   end)

scenario("auto-refused",
   "the server refuses the self bot (SelfBotLevel 1 without GM rights, or 0): clear message, nothing else is sent, not 'running'",
   function(r)
      for _, case in ipairs{
         { name = "level 1, no GM", server = { selfbot_level = 1, gm = false }, text = "restricted for this account" },
         { name = "level 0",        server = { selfbot_level = 0 },             text = "disabled server-wide" },
      } do
         local env = boot{ bom = "strip", server = case.server }
         r.env = env
         start(env)
         r:check(not Auto(env).IsRunning(), "[" .. case.name .. "] not running")
         r:check(chat_has(env, case.text), "[" .. case.name .. "] the refusal text is shown")
         r:check(chat_has(env, "The server refuses the self bot"), "[" .. case.name .. "] the addon explains it")
         r:check(count_sent(env, "nc +master fishing") == 0, "[" .. case.name .. "] no strategy command was sent")
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
      start(env, 25)
      r:check(srv.toggles == 2, "two toggles (off, on): Load re-adds +chat", "toggles: " .. srv.toggles)
      r:check(srv:has("master fishing"), "after that the strategy arrives")
      r:check(not Auto(env).GetState().ownsBot, "the bot was on before, so it stays on after Stop")
      stop(env)
      r:check(srv.active, "Stop leaves it on")
   end)

scenario("auto-botpad-old",
   "Botpad without the Hold interface replays 'nc !' + a mode set after EVERY 'SelfBot is now active': the addon waits it out",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, false)
      start(env, 25)
      r:check(BP.Bot.bursts == 1, "Botpad did its burst once", "bursts: " .. BP.Bot.bursts)
      r:check(env.server:has("master fishing"), "'master fishing' survived the burst")
      r:check(count_sent(env, "nc +master fishing") == 1, "no retry was needed", "sent: " .. count_sent(env, "nc +master fishing"))
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run", "running")
   end)

scenario("auto-botpad-hold",
   "Botpad 1.3: the addon asks Botpad to hold its mode while running; Botpad skips its burst; released on stop",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      local BP = Server.install_botpad_stub(env, true)
      env:call("Auto.Toggle", Auto(env).Toggle)
      r:check(BP.Bot.holders["Fishing Buddy"], "hold is requested before the bot is switched on")
      env:advance(20, 0.1)
      r:check(BP.Bot.bursts == 0, "Botpad did not replay its mode", "bursts: " .. BP.Bot.bursts)
      r:check(env.server:has("master fishing"), "'master fishing' is set")
      stop(env)
      r:check(next(BP.Bot.holders) == nil, "hold released after the stop sequence")
      -- also released when the start fails
      local env2 = boot{ bom = "strip", server = { selfbot_level = 0 } }
      local BP2 = Server.install_botpad_stub(env2, true)
      start(env2)
      r:check(next(BP2.Bot.holders) == nil, "hold released when the server refuses")
   end)

scenario("auto-vanishing-strategy",
   "the bot drops 'master fishing' by itself (no water in range): re-set twice, then the addon stops and says why",
   function(r)
      local env = boot{ bom = "strip", server = { end_fishing_after = 6.0 } }
      r.env = env
      local srv = env.server
      env.G.FishingBuddy.SetSetting("AutoFishIdleSeconds", 15)
      start(env)
      env:advance(300, 0.5)
      r:check(not Auto(env).IsRunning(), "stopped by itself")
      r:check(chat_has(env, "ended fishing by itself"), "reason shown")
      r:check(count_sent(env, "nc +master fishing") == 3, "the strategy was set at start and re-set twice", "sent: " .. count_sent(env, "nc +master fishing"))
      r:check(not srv.active, "the bot we switched on is switched off again")
      no_errors(r, env)
   end)

scenario("auto-vanishing-at-once",
   "the bot takes 'master fishing' back right after it was set (nothing to fish): three tries, then a clear message and the bot is switched off",
   function(r)
      local env = boot{ bom = "strip", server = { end_fishing_after = 1.0 } }
      r.env = env
      start(env, 40)
      r:check(not Auto(env).IsRunning(), "not running")
      r:check(chat_has(env, "did not accept the strategy 'master fishing' after 3 tries"), "the message names the strategy and the number of tries")
      r:check(chat_has(env, "no water"), "... and the likely reason")
      r:check(count_sent(env, "nc +master fishing") == 3, "three attempts", "sent: " .. count_sent(env, "nc +master fishing"))
      r:check(not env.server.active, "the bot we switched on is off again")
      no_errors(r, env)
   end)

-- Optional: the REAL Botpad (needs a checkout; BOTPAD_DIR or ../../BotPad next to the repo)
local function botpad_dir()
   local d = os.getenv("BOTPAD_DIR") or (repo .. "/../BotPad")
   local f = io.open(d .. "/Botpad.toc", "r")
   if f then f:close() return d end
   return nil
end

scenario("auto-real-botpad",
   "the real Botpad (>= 1.3) loaded next to the addon: no mode burst, 'master fishing' stays (skipped when no Botpad checkout is found)",
   function(r)
      local dir = botpad_dir()
      if not dir then
         io.write("   (skipped: no Botpad checkout; set BOTPAD_DIR)\n")
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
      local mine = 0
      for _, e in ipairs(env.errors) do if not e.context:find("Botpad", 1, true) and not e.message:find("InputBoxTemplate", 1, true) then mine = mine + 1 end end
      r:check(mine == 0, "no Lua error from Fishing Buddy", mine .. " error(s)")
      if not env.G.Botpad.Bot.Hold then
         r:check(false, "this Botpad has no Hold interface (needs 1.3)")
         return
      end
      start(env, 25)
      local whispers = 0
      for _, e in ipairs(env.sent) do if e.chattype == "WHISPER" then whispers = whispers + 1 end end
      r:check(env.server:has("master fishing"), "'master fishing' is set and stayed")
      r:check(count_sent(env, "nc !") == 0 and count_sent(env, "co !") == 0, "Botpad did not send its reset")
      r:check(env.G.Botpad.Bot.IsHeld(), "Botpad is held while running")
      stop(env)
      r:check(not env.G.Botpad.Bot.IsHeld(), "... and released afterwards")
   end)

scenario("auto-mount",
   "a self bot with a mount mounts itself (strategy 'mount'): the addon turns it off while fishing and restores it afterwards",
   function(r)
      local env = boot{ bom = "strip", server = { mount_owned = true } }
      r.env = env
      local srv = env.server
      start(env)
      r:check(not srv:has("mount"), "'mount' is off while fishing")
      env:advance(60, 0.5)
      r:check(not env.world.mounted, "the character did not mount")
      stop(env)
      r:check(not srv.active, "bot off again")
      -- option off: the model mounts the character and the addon warns
      local env2 = boot{ bom = "strip", server = { mount_owned = true } }
      env2.G.FishingBuddy.SetSetting("AutoFishNoMount", 0)
      start(env2)
      env2:advance(30, 0.5)
      r:check(env2.world.mounted, "with the option off the model mounts the character")
      r:check(chat_has(env2, "You are mounted"), "... and the addon warns about it")
      -- strategy 'mount' is restored only if it was there
      local env3 = boot{ bom = "strip", server = { mount_owned = true, active = true,
         persisted = { "nc", "chat", "follow", "default" } } }
      start(env3)
      stop(env3)
      r:check(not env3.server:has("mount"), "a stored set without 'mount' does not get one added on Stop")
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
      r:check(not shown:find("nc +master fishing", 1, true) and not shown:find("Strategies:", 1, true) and not shown:find("nc ?", 1, true),
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
   "the client never shows the bot's answer (or it is suppressed): the start is accepted as UNVERIFIED with a warning",
   function(r)
      local env = boot{ bom = "strip", server = { reply_visible = false } }
      r.env = env
      start(env, 20)
      r:check(Auto(env).IsRunning() and Auto(env).GetState().step == "run", "running")
      r:check(env.server:has("master fishing"), "the strategy was set")
      r:check(chat_has(env, "did not answer the strategy check"), "the player is told that the start could not be confirmed")
      r:check(count_sent(env, "nc +master fishing") == 1, "no pointless retries", "sent: " .. count_sent(env, "nc +master fishing"))
   end)

scenario("auto-stop-early",
   "Stop right after the bot was switched on (before any strategy was set): the bot is switched off again, nothing left behind",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      env:call("Auto.Toggle", Auto(env).Toggle)
      env:advance(3.2, 0.1)
      r:check(env.server.active, "precondition: bot is on")
      r:check(count_sent(env, "nc +master fishing") == 0, "precondition: nothing set yet")
      stop(env)
      r:check(not env.server.active, "bot off")
      r:check(not env.server.persisted or not env.server.persisted["master fishing"], "no stored strategy")
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

scenario("auto-trip-active",
   "while an AutoTravel trip is running the addon does not poke the bot (AutoTravel resets strategies itself)",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      env.G.FishingBuddy.SetSetting("AutoFishIdleSeconds", 15)
      start(env)
      env.G.AutoTravel = { active = true }
      env:clear_sent()
      env:advance(120, 0.5)
      r:check(count_sent(env, "nc ?") == 0, "no health check during the trip", "probes: " .. count_sent(env, "nc ?"))
      env.G.AutoTravel.active = false
      env:advance(40, 0.5)
      r:check(count_sent(env, "nc ?") >= 1, "checks resume after the trip")
   end)

scenario("auto-logout",
   "PLAYER_LOGOUT (and /reload) while running: strategy taken back and the bot switched off at once",
   function(r)
      local env = boot{ bom = "strip" }
      r.env = env
      start(env)
      env:clear_sent()
      env:fire("PLAYER_LOGOUT")
      local t = sent_texts(env)
      r:check(t[1] == "WHISPER:nc -master fishing" and t[#t] == "SAY:.playerbots bot self", "strategy first, then the toggle, in the same frame", table.concat(t, " | "))
      env:advance(2, 0.1)
      r:check(not env.server.active, "bot off")
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
      env:slash("/fb auto probe")
      env:advance(3, 0.1)
      no_errors(r, env)
   end)

scenario("auto-warnings",
   "conflicting strategies and a bot without a pole are reported",
   function(r)
      local env = boot{ bom = "strip", server = { active = true, persisted = { "nc", "chat", "follow", "default", "grind", "mount" } } }
      r.env = env
      start(env)
      r:check(chat_has(env, "Other bot strategies are active (grind"), "grind warning")
      env.server:tell("I don't have a Fishing Pole")
      env:advance(2, 0.1)
      r:check(chat_has(env, "no fishing pole"), "the bot's complaint about the pole is shown")
   end)

scenario("auto-grouped-party-lines",
   "a custom block with '/p' lines still goes to the party when the player is in a group",
   function(r)
      local saved = { FishingBuddy_Info = {}, FishingBuddy_Player = { Settings = {
         AutoFishStartCommands = "/p nc +master fishing" }, Outfit = {}, WasWearing = {} } }
      local env = boot{ bom = "strip", saved = saved, world = { party = 2 } }
      r.env = env
      start(env)
      r:check(count_sent(env, "nc +master fishing") >= 1 and sent_type(env, "PARTY") >= 1, "party line sent")
      r:check(env.server:has("master fishing"), "and it reached the bot")
      r:check(not chat_has(env, "not in a group"), "no warning when grouped")
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
   print(("\n=== [%s] %s -- %s"):format(status, r.name, r.descr))
   for _, c in ipairs(r.checks) do
      if verbose or not c.ok then
         print(("    %s %s%s"):format(c.ok and "ok  " or "FAIL", c.what, c.detail and ("   <" .. c.detail .. ">") or ""))
      end
   end
   if not verbose and r.failed == 0 then print(("    %d checks ok"):format(#r.checks)) end
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
