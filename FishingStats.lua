-- FishingStats.lua
-- ---------------------------------------------------------------------------
-- Sitzungs-Statistik fuer Fishing Buddy
--
-- Sammelt waehrend einer Angel-Sitzung Kennzahlen (Fische, Wurfquote,
-- Haendlerwert, Skillanstieg, Rohgold) und zeigt sie kompakt im
-- Watcher-Fenster sowie ausfuehrlich per "/fb stats" im Chat.
-- ---------------------------------------------------------------------------

local FL = LibStub("LibFishing-1.0");
local Crayon = LibStub("LibCrayon-3.0");

FishingBuddy.Stats = {};
local Stats = FishingBuddy.Stats;

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local session = nil;

local function NewSession()
   local skill = FL:GetCurrentSkill();
   return {
      started = GetTime(),
      fishing = 0,            -- tatsaechliche Angelzeit in Sekunden
      lastTick = GetTime(),
      catches = 0,            -- erfolgreiche Fange (Einzelstueck)
      events = 0,             -- Fang-Ereignisse
      misses = 0,             -- "Der Fisch ist entkommen"
      value = 0,              -- geschaetzter Haendlerwert in Kupfer
      money = 0,              -- direkt erbeutetes Gold in Kupfer
      startMoney = GetMoney(),
      startSkill = skill or 0,
      skill = skill or 0,
      best = nil,             -- bestes Item der Sitzung
      bestQuality = -1,
      fish = {},              -- [id] = anzahl
   };
end

local function EnsureSession()
   if ( not session ) then
      session = NewSession();
   end
   return session;
end

local function ResetSession()
   session = NewSession();
end
Stats.Reset = ResetSession;
Stats.Get = function() return session; end

-- ---------------------------------------------------------------------------
-- Formatierung
-- ---------------------------------------------------------------------------

local function FormatDuration(elapsed)
   elapsed = math.floor(elapsed or 0);
   local s = math.fmod(elapsed, 60);
   local m = math.fmod(math.floor(elapsed / 60), 60);
   local h = math.floor(elapsed / 3600);
   if ( h > 0 ) then
      return string.format("%dh %02dm", h, m);
   elseif ( m > 0 ) then
      return string.format("%dm %02ds", m, s);
   end
   return string.format("%ds", s);
end
Stats.FormatDuration = FormatDuration;

-- Kupfer -> "12g 34s 56k" (nur die noetigen Einheiten)
local function FormatMoney(copper)
   copper = math.floor(copper or 0);
   if ( copper <= 0 ) then
      return "0"..FBConstants.STATS_COPPER;
   end
   local g = math.floor(copper / 10000);
   local s = math.floor(math.fmod(copper, 10000) / 100);
   local c = math.fmod(copper, 100);
   local out = "";
   if ( g > 0 ) then
      out = out..Crayon:Yellow(g..FBConstants.STATS_GOLD).." ";
   end
   if ( g > 0 or s > 0 ) then
      out = out..Crayon:Silver(s..FBConstants.STATS_SILVER).." ";
   end
   out = out..Crayon:Copper(c..FBConstants.STATS_COPPER);
   return out;
end
Stats.FormatMoney = FormatMoney;

-- Aktive Angelzeit: bevorzugt die Zeit, die FB als "Angelmodus" zaehlt
local function ActiveSeconds()
   local s = EnsureSession();
   local base = s.fishing;
   if ( FishingBuddy.StartedFishing ) then
      base = base + (GetTime() - s.lastTick);
   end
   if ( base < 1 ) then
      base = GetTime() - s.started;
   end
   if ( base < 1 ) then
      base = 1;
   end
   return base;
end
Stats.ActiveSeconds = ActiveSeconds;

local function PerHour(amount)
   return amount / (ActiveSeconds() / 3600);
end

-- ---------------------------------------------------------------------------
-- Datensammlung
-- ---------------------------------------------------------------------------

local function RecordCatch(id, name, zone, subzone, texture, quantity, quality)
   local s = EnsureSession();
   quantity = quantity or 1;

   if ( FL:IsMissedFish(id) ) then
      s.misses = s.misses + quantity;
      return;
   end

   s.events = s.events + 1;
   s.catches = s.catches + quantity;
   s.fish[id] = (s.fish[id] or 0) + quantity;

   -- Haendlerwert schaetzen (11. Rueckgabewert von GetItemInfo)
   local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(id);
   if ( price and price > 0 ) then
      s.value = s.value + price * quantity;
   end

   -- bestes Stueck merken
   quality = quality or 0;
   if ( quality > s.bestQuality ) then
      s.bestQuality = quality;
      s.best = name;
   end
end

-- ---------------------------------------------------------------------------
-- Watcher-Zusatzzeilen
-- ---------------------------------------------------------------------------

local function BuildWatcherLines(lines)
   if ( not FishingBuddy.GetSettingBool("StatsInWatcher") ) then
      return;
   end
   local s = EnsureSession();
   if ( s.catches == 0 and s.misses == 0 ) then
      return;
   end

   local white = "|cff"..Crayon.COLOR_HEX_WHITE;

   if ( FishingBuddy.GetSettingBool("StatsShowRate") ) then
      local rate = PerHour(s.catches);
      local line = string.format("%s: %s%d/h|r", FBConstants.STATS_RATE,
                                 white, math.floor(rate + 0.5));
      -- Trefferquote
      local total = s.catches + s.misses;
      if ( total > 0 ) then
         local hit = (s.catches / total) * 100;
         line = line..Crayon:White(" | ")..
                string.format("%s: %.1f%%", FBConstants.STATS_HITRATE, hit);
      end
      tinsert(lines, line);
   end

   if ( FishingBuddy.GetSettingBool("StatsShowValue") ) then
      local total = s.value + s.money;
      tinsert(lines, string.format("%s: %s (%s/h)", FBConstants.STATS_VALUE,
                                   FormatMoney(total),
                                   FormatMoney(PerHour(total))));
   end

   if ( FishingBuddy.GetSettingBool("StatsShowLure") ) then
      local has, expiration = GetWeaponEnchantInfo();
      local text;
      if ( has ) then
         local left = math.floor((expiration or 0) / 1000);
         local color = Crayon.COLOR_HEX_GREEN;
         if ( left < 60 ) then
            color = Crayon.COLOR_HEX_RED;
         elseif ( left < 180 ) then
            color = Crayon.COLOR_HEX_ORANGE;
         end
         text = string.format("%s: |cff%s%s|r", FBConstants.STATS_LURE, color,
                              FormatDuration(left));
      else
         text = FBConstants.STATS_LURE..": "..Crayon:Red(FBConstants.STATS_NOLURE);
      end
      tinsert(lines, text);
   end
end

-- ---------------------------------------------------------------------------
-- Chat-Bericht
-- ---------------------------------------------------------------------------

local function PrintReport()
   local s = EnsureSession();
   local elapsed = ActiveSeconds();
   local out = FishingBuddy.Output;

   out(Crayon:Green("--- "..FBConstants.STATS_TITLE.." ---"));

   out(string.format("  %s: %s", FBConstants.STATS_DURATION, FormatDuration(elapsed)));

   local total = s.catches + s.misses;
   local hit = 0;
   if ( total > 0 ) then
      hit = (s.catches / total) * 100;
   end
   out(string.format("  %s: %s%d|r  (%s: %d, %s: %.1f%%)",
                     FBConstants.STATS_CATCHES,
                     "|cff"..Crayon.COLOR_HEX_WHITE, s.catches,
                     FBConstants.STATS_MISSES, s.misses,
                     FBConstants.STATS_HITRATE, hit));

   out(string.format("  %s: %d/h", FBConstants.STATS_RATE,
                     math.floor(PerHour(s.catches) + 0.5)));

   out(string.format("  %s: %s   (%s/h)", FBConstants.STATS_VENDORVALUE,
                     FormatMoney(s.value), FormatMoney(PerHour(s.value))));

   if ( s.money > 0 ) then
      out(string.format("  %s: %s", FBConstants.STATS_LOOTEDMONEY, FormatMoney(s.money)));
   end

   local skillnow = FL:GetCurrentSkill() or s.startSkill;
   local gained = skillnow - s.startSkill;
   if ( gained > 0 ) then
      out(string.format("  %s: +%d  (%d)", FBConstants.STATS_SKILLUP, gained, skillnow));
   end

   if ( s.best ) then
      out(string.format("  %s: %s", FBConstants.STATS_BEST,
                        (ITEM_QUALITY_COLORS[s.bestQuality] and
                         ITEM_QUALITY_COLORS[s.bestQuality].hex or "")..s.best.."|r"));
   end

   -- Top 5 Fische
   local sorted = {};
   for id, count in pairs(s.fish) do
      tinsert(sorted, { id = id, count = count });
   end
   table.sort(sorted, function(a, b) return a.count > b.count; end);

   local shown = math.min(5, #sorted);
   if ( shown > 0 ) then
      out("  "..FBConstants.STATS_TOP..":");
      for i = 1, shown do
         local entry = sorted[i];
         local info = FishingBuddy_Info["Fishies"][entry.id];
         local name = info and info[GetLocale()] or ("item:"..entry.id);
         local percent = (entry.count / s.catches) * 100;
         out(string.format("    %d. %s  %s(%d - %.1f%%)|r", i,
                           FishingBuddy.StripRaw(name),
                           "|cff"..Crayon.COLOR_HEX_SILVER, entry.count, percent));
      end
   end
end
Stats.PrintReport = PrintReport;

-- ---------------------------------------------------------------------------
-- Optionen
-- ---------------------------------------------------------------------------

local StatsOptions = {
   ["StatsInWatcher"] = {
      ["text"] = FBConstants.CONFIG_STATSWATCHER_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_STATSWATCHER_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["StatsShowRate"] = {
      ["text"] = FBConstants.CONFIG_STATSRATE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_STATSRATE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1,
      ["deps"] = { ["StatsInWatcher"] = "d" } },
   ["StatsShowValue"] = {
      ["text"] = FBConstants.CONFIG_STATSVALUE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_STATSVALUE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1,
      ["deps"] = { ["StatsInWatcher"] = "d" } },
   ["StatsShowLure"] = {
      ["text"] = FBConstants.CONFIG_STATSLURE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_STATSLURE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1,
      ["deps"] = { ["StatsInWatcher"] = "d" } },
   ["StatsAutoReport"] = {
      ["text"] = FBConstants.CONFIG_STATSREPORT_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_STATSREPORT_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 0 },
};

-- ---------------------------------------------------------------------------
-- Slash-Kommando
-- ---------------------------------------------------------------------------

FishingBuddy.Commands[FBConstants.STATS] = {};
FishingBuddy.Commands[FBConstants.STATS].help = FBConstants.STATS_HELP;
FishingBuddy.Commands[FBConstants.STATS].func =
   function(what)
      if ( what and (string.lower(what) == "reset" or string.lower(what) == FBConstants.RESET) ) then
         ResetSession();
         FishingBuddy.Message(FBConstants.STATS_RESET);
         return true;
      end
      PrintReport();
      return true;
   end;

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local StatsEvents = {};

StatsEvents[FBConstants.ADD_FISHIE_EVT] = function(id, name, zone, subzone, texture, quantity, quality)
   RecordCatch(id, name, zone, subzone, texture, quantity, quality);
end;

StatsEvents[FBConstants.WATCHER_LINES_EVT] = BuildWatcherLines;

StatsEvents["PLAYER_MONEY"] = function()
   local s = EnsureSession();
   local now = GetMoney();
   local diff = now - s.startMoney;
   if ( diff > 0 and FishingBuddy.StartedFishing ) then
      s.money = s.money + diff;
   end
   s.startMoney = now;
end;

StatsEvents[FBConstants.FISHING_ENABLED_EVT] = function()
   local s = EnsureSession();
   s.lastTick = GetTime();
end;

StatsEvents[FBConstants.FISHING_DISABLED_EVT] = function()
   local s = EnsureSession();
   s.fishing = s.fishing + (GetTime() - s.lastTick);
   s.lastTick = GetTime();
   if ( FishingBuddy.GetSettingBool("StatsAutoReport") and s.catches > 0 ) then
      PrintReport();
   end
end;

StatsEvents[FBConstants.AUTO_STOP_EVT] = function()
   if ( FishingBuddy.GetSettingBool("StatsAutoReport") ) then
      PrintReport();
   end
end;

StatsEvents["VARIABLES_LOADED"] = function()
   ResetSession();
   FishingBuddy.OptionsFrame.HandleOptions("Watcher", nil, StatsOptions);
end;

FishingBuddy.API.RegisterHandlers(StatsEvents);
