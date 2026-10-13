-- FishingAuto.lua
-- ---------------------------------------------------------------------------
-- Auto-Angeln ueber die Playerbot-Funktion (AzerothCore / mod-playerbots)
--
-- Der Client darf in 3.3.5 keine Zauber per Timer wirken (geschuetzte API).
-- Deshalb macht dieses Modul das, was erlaubt ist: es schickt die
-- Server-/Chat-Kommandos, die den Playerbot das Angeln uebernehmen lassen,
-- und ueberwacht danach den Ablauf (Koeder, Taschen, Kampf, Stillstand).
--
-- Die Strategiebefehle sind frei konfigurierbar (siehe Kommando-Editor),
-- damit das Modul auch mit abweichenden Playerbot-Builds funktioniert.
--
-- Wie der Selbstbot erreicht wird (aus dem Quelltext von AzerothCore und
-- mod-playerbots, nicht aus einem Spieltest):
--  * ".playerbots bot self" ist ein UMSCHALTER. Das Modul kennt deshalb den
--    Zustand: es liest die Systemmeldungen des Servers ("SelfBot is now
--    active." / "... deactivated." / Verweigerungen) und fragt den Bot mit
--    "nc ?" nach seinen Strategien, bevor es schaltet. Es schaltet nur, wenn
--    der Bot nicht schon an ist, und am Ende nur aus, was es selbst eingeschaltet
--    hat.
--  * Gruppenchat ("/p ...") erreicht den Selbstbot nur in einer Gruppe: der
--    Server verwirft die Nachricht eines Spielers ohne Gruppe stillschweigend.
--    Strategiebefehle gehen deshalb als Fluestern an den eigenen Charakter
--    ("/w %p ..."), das funktioniert mit und ohne Gruppe.
--  * Nach dem Setzen prueft das Modul per "nc ?", ob "master fishing" wirklich
--    uebernommen wurde, und meldet es, wenn nicht.
-- ---------------------------------------------------------------------------

local FL = LibStub("LibFishing-1.0");
local Crayon = LibStub("LibCrayon-3.0");

FishingBuddy.Auto = {};
local Auto = FishingBuddy.Auto;

-- ---------------------------------------------------------------------------
-- Voreinstellungen
-- ---------------------------------------------------------------------------

-- %p = eigener Charaktername, %z = Zone, %s = Unterzone
local DEFAULT_START = "/w %p nc +master fishing";
local DEFAULT_KEEP  = "/w %p nc +master fishing";
local DEFAULT_STOP  = "/w %p nc -master fishing";
-- Koeder auftragen lassen. %l = Itemlink, %i = Item-ID, %n = Itemname
local DEFAULT_LURE  = "/w %p u %l";

-- Standardwerte fruehere Fassungen (0.9.9-enhanced). Wer sie nie geaendert hat,
-- bekommt die neuen; geaenderte Bloecke bleiben unangetastet.
local OLD_DEFAULTS = {
   AutoFishStartCommands     = { ".playerbots bot self\n/p nc +master fishing" },
   AutoFishKeepAliveCommands = { "/p nc +master fishing" },
   AutoFishStopCommands      = { "/p nc -master fishing\n.playerbots bot self" },
   AutoFishLureCommands      = { "/p u %l" },
};

-- Zeiten (Sekunden)
local PROBE_WAIT    = 2.5;    -- Antwort auf "nc ?" abwarten
local TOGGLE_WAIT   = 5.0;    -- Bestaetigung von ".playerbots bot self" abwarten
local SETTLE_PLAIN  = 1.0;    -- Pause nach dem Einschalten
local SETTLE_BOTPAD = 3.5;    -- ... wenn Botpad ohne Hold-Schnittstelle laeuft (Salve ~2 s)
local VERIFY_DELAY  = 2.5;    -- zwischen Setzen der Strategie und Pruefung
local RETRY_DELAY   = 3.0;    -- vor einem erneuten Setzen
local MAX_TRIES     = 3;      -- Versuche, "master fishing" zu setzen
local MAX_VANISH    = 3;      -- so oft darf die Strategie verschwinden, dann gilt das Angeln als beendet
local STOP_WAIT     = 20;     -- so lange auf die Rueckname der Strategie warten, bevor ausgeschaltet wird
local ECHO_WINDOW   = 30;     -- so lange gelten eigene Fluesterbefehle als "eigene" (Echo ausblenden)
local TRACE_MAX     = 40;

local UPDATE_INTERVAL = 0.5;      -- Panel-Refresh
local WATCHDOG_INTERVAL = 2.0;    -- Ueberwachung

-- Panel-Layout. Die Breite waechst mit dem Text mit, damit die Zeile
-- "03:29 | 14 Fische | 241/h" nie an den Koeder-Knopf stoesst.
local PANEL_PAD      = 10;   -- Rand links und rechts
local PANEL_TOGGLE   = 32;   -- Groesse des Hauptschalters
local PANEL_TEXTGAP  = 8;    -- Schalter -> Text
local PANEL_LUREGAP  = 16;   -- Text -> Koeder-Knopf
local PANEL_LURE     = 26;   -- Groesse des Koeder-Knopfs
local PANEL_MINWIDTH = 210;

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local running = false;
local startedAt = 0;
local pausedReason = nil;
local lastFishAt = 0;
local lastWatchdogAt = 0;
local lastPanelAt = 0;
local fishCount = 0;
local lureWarnedAt = 0;
local bagWarnedAt = 0;
local lureTriedAt = 0;
local lureTries = 0;
local lureGaveUp = false;
local lureNeeded = false;

-- Selbstbot: nil = unbekannt, true = an, false = aus (letzte Meldung des Servers)
local selfState = nil;
local session = nil;          -- laufende Sitzung (Start bis Stopp), siehe Start()
local stopping = nil;         -- laufende Abschaltung, siehe Stop()
local trace = {};             -- Ringpuffer fuer "/fb auto diag"
local recent = {};            -- eigene Fluesterbefehle: Text -> Zeit (Echos ausblenden)
local lastProbeAt = 0;
local lastStrategies = nil;   -- letzte Strategieliste des Bots (Rohtext)
local lastStrategiesAt = 0;
local botpadHeld = false;
local mountWarnedAt = 0;

local panel, statusText, detailText, toggleButton, lureButton;

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

local function trim(s)
   if ( not s ) then
      return "";
   end
   return (string.gsub(s, "^%s*(.-)%s*$", "%1"));
end

local function Say(msg)
   FishingBuddy.Message(msg);
end

local function Warn(msg)
   FishingBuddy.Output(Crayon:Orange(FBConstants.NAME)..": "..msg);
end

local function PlayAlert()
   if ( FishingBuddy.GetSettingBool("AutoFishSound") ) then
      PlaySound("RaidWarning");
   end
end

local function FormatTime(elapsed)
   elapsed = math.floor(elapsed or 0);
   local s = math.fmod(elapsed, 60);
   local m = math.fmod(math.floor(elapsed / 60), 60);
   local h = math.floor(elapsed / 3600);
   if ( h > 0 ) then
      return string.format("%d:%02d:%02d", h, m, s);
   end
   return string.format("%02d:%02d", m, s);
end

-- Freie Taschenplaetze zaehlen (nur normale Taschen, keine Spezialtaschen)
local function FreeBagSlots()
   local free = 0;
   for bag = 0, NUM_BAG_SLOTS do
      local slots, bagType = GetContainerNumFreeSlots(bag);
      if ( slots and (not bagType or bagType == 0) ) then
         free = free + slots;
      end
   end
   return free;
end
Auto.FreeBagSlots = FreeBagSlots;

-- Restlaufzeit des Koeders (Waffenverzauberung der Haupthand) in Sekunden
local function LureSecondsLeft()
   local has, expiration = GetWeaponEnchantInfo();
   if ( not has ) then
      return 0;
   end
   return math.floor((expiration or 0) / 1000);
end
Auto.LureSecondsLeft = LureSecondsLeft;

-- ---------------------------------------------------------------------------
-- Protokoll und Erkennung eigener Befehle
-- ---------------------------------------------------------------------------

local function Trace(text)
   trace[#trace + 1] = string.format("%.1f  %s", GetTime(), text);
   if ( #trace > TRACE_MAX ) then
      table.remove(trace, 1);
   end
end

-- Gleicher Spieler? (Fluestern an/von sich selbst; ein "-Realm" wird abgeschnitten)
local function IsMe(name)
   local me = UnitName("player");
   if ( type(name) ~= "string" or not me ) then
      return false;
   end
   name = (string.gsub(name, "%-.*$", ""));
   return string.lower(name) == string.lower(me);
end

-- Merkt sich einen eigenen Fluesterbefehl. Der Server liefert ihn als "An <Name>"
-- und als "<Name> fluestert" zurueck; beide Echos filtert EchoFilter aus dem Chat.
local function RememberOwn(text)
   local now = GetTime();
   recent[text] = now;
   for k, t in pairs(recent) do
      if ( now - t > ECHO_WINDOW ) then
         recent[k] = nil;
      end
   end
end

local function IsGrouped()
   return ((GetNumPartyMembers() or 0) > 0) or ((GetNumRaidMembers() or 0) > 0);
end

-- ---------------------------------------------------------------------------
-- Kommando-Ausfuehrung
-- ---------------------------------------------------------------------------

-- Chat-Slashbefehle, die wir direkt (und ohne Taint) selbst umsetzen koennen
local CHATTYPES = {
   ["s"] = "SAY",       ["say"] = "SAY",
   ["y"] = "YELL",      ["yell"] = "YELL",
   ["p"] = "PARTY",     ["party"] = "PARTY",
   ["g"] = "GUILD",     ["guild"] = "GUILD",
   ["o"] = "OFFICER",   ["officer"] = "OFFICER",
   ["ra"] = "RAID",     ["raid"] = "RAID",
   ["rw"] = "RAID_WARNING", ["raidwarning"] = "RAID_WARNING",
   ["bg"] = "BATTLEGROUND", ["battleground"] = "BATTLEGROUND",
};

local WHISPERTYPES = {
   ["w"] = true, ["whisper"] = true, ["t"] = true, ["tell"] = true, ["send"] = true,
};

-- Ersetzt die Platzhalter. Die Ersetzung laeuft ueber Funktionen, damit
-- ein "%" im eingesetzten Text (z.B. in einem Itemlink) nicht als
-- Rueckverweis interpretiert wird.
local function Substitute(line, extra)
   local values = {
      ["%%p"] = UnitName("player") or "",
      ["%%z"] = GetRealZoneText() or "",
      ["%%s"] = GetSubZoneText() or "",
   };
   if ( extra ) then
      for k, v in pairs(extra) do
         values[k] = v;
      end
   end
   for pattern, value in pairs(values) do
      line = string.gsub(line, pattern, function() return value; end);
   end
   return line;
end

local partyNoted = false;     -- Hinweis auf Gruppenchat ohne Gruppe nur einmal je Sitzung

-- Fuehrt eine einzelne Zeile aus.
--  ".befehl"       -> Server-Kommando (wird als SAY geschickt, AzerothCore
--                     faengt Nachrichten mit fuehrendem Punkt ab)
--  "/w NAME text"  -> Fluestern (an sich selbst: so erreicht man den Selbstbot)
--  "/p text"       -> Chatnachricht im entsprechenden Kanal (ohne Gruppe verworfen)
--  "/irgendwas"    -> normaler Slashbefehl (Fallback ueber die Chatbox)
--  alles andere    -> als SAY
local function ExecuteLine(line, extra)
   line = trim(Substitute(line, extra));
   if ( line == "" or string.sub(line, 1, 2) == "--" ) then
      return;
   end

   if ( string.sub(line, 1, 1) ~= "/" ) then
      -- Server-Kommando oder einfacher Text
      Trace("-> say: "..line);
      SendChatMessage(line, "SAY");
      return;
   end

   local _, _, slash, rest = string.find(line, "^/([%a%d]+)%s*(.*)$");
   if ( slash ) then
      slash = string.lower(slash);
      local chattype = CHATTYPES[slash];
      if ( chattype ) then
         if ( rest and rest ~= "" ) then
            if ( chattype == "PARTY" and not IsGrouped() ) then
               -- Der Server verwirft Gruppenchat von einem Spieler ohne Gruppe
               -- stillschweigend; der Selbstbot bekaeme ihn nie zu sehen.
               if ( not partyNoted ) then
                  partyNoted = true;
                  Warn(string.format(FBConstants.AUTO_NOTE_PARTYLINE, line));
               end
               Trace("skipped (not in a group): "..line);
               return;
            end
            Trace("-> "..string.lower(chattype)..": "..rest);
            SendChatMessage(rest, chattype);
         end
         return;
      end
      if ( WHISPERTYPES[slash] ) then
         local _, _, target, text = string.find(rest or "", "^(%S+)%s+(.*)$");
         if ( target and text and text ~= "" ) then
            if ( IsMe(target) ) then
               RememberOwn(text);
            end
            Trace("-> /w "..target..": "..text);
            SendChatMessage(text, "WHISPER", nil, target);
         end
         return;
      end
      -- Zahlenkanaele: /1 hallo
      if ( string.find(slash, "^%d+$") ) then
         if ( rest and rest ~= "" ) then
            SendChatMessage(rest, "CHANNEL", nil, tonumber(slash));
         end
         return;
      end
   end

   -- Fallback: ueber die Chat-Eingabezeile ausfuehren
   local edit = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox or ChatFrame1EditBox;
   if ( edit and ChatEdit_SendText ) then
      edit:SetText(line);
      ChatEdit_SendText(edit, 0);
      edit:SetText("");
   end
end
Auto.ExecuteLine = ExecuteLine;

-- Fuehrt einen mehrzeiligen Kommandoblock aus
local function ExecuteBlock(block, extra)
   if ( not block ) then
      return 0;
   end
   local count = 0;
   for line in string.gmatch(block.."\n", "([^\r\n]*)\r?\n") do
      if ( trim(line) ~= "" ) then
         ExecuteLine(line, extra);
         count = count + 1;
      end
   end
   return count;
end
Auto.ExecuteBlock = ExecuteBlock;

-- Ein einzelner Fluesterbefehl an den eigenen Charakter (= an den Selbstbot)
local function WhisperSelf(text)
   ExecuteLine("/w %p "..text);
end

-- ".playerbots bot self" gehoert nicht mehr in die Bloecke: das Modul schaltet
-- selbst und nur bei Bedarf. Alte, gespeicherte Bloecke enthalten die Zeile noch.
local function IsToggleLine(line)
   return string.find(string.lower(trim(line)), "^%.playerbots?%s+bot%s+self$") ~= nil;
end

local toggleNoted = false;

local function RemoveToggleLines(block)
   local out, removed = {}, 0;
   for line in string.gmatch(block.."\n", "([^\r\n]*)\r?\n") do
      if ( IsToggleLine(line) ) then
         removed = removed + 1;
      else
         out[#out + 1] = line;
      end
   end
   if ( removed > 0 and not toggleNoted ) then
      toggleNoted = true;
      Warn(FBConstants.AUTO_NOTE_TOGGLELINE);
   end
   return table.concat(out, "\n");
end

-- Rohtext des gespeicherten Blocks (oder der Standard), unveraendert
local function GetBlockRaw(setting, fallback)
   local value = FishingBuddy.GetSetting(setting);
   if ( value == nil or trim(value) == "" ) then
      return fallback;
   end
   return value;
end

-- Block, wie er ausgefuehrt wird
local function GetBlock(setting, fallback)
   local block = RemoveToggleLines(GetBlockRaw(setting, fallback));
   if ( trim(block) == "" ) then
      return fallback;
   end
   return block;
end

-- Gleicher Inhalt ohne Leerzeilen und Zeilenenden-Unterschiede
local function NormalizeBlock(text)
   local lines = {};
   for line in string.gmatch((text or "").."\n", "([^\r\n]*)\r?\n") do
      line = trim(line);
      if ( line ~= "" ) then
         lines[#lines + 1] = line;
      end
   end
   return table.concat(lines, "\n");
end

-- Gespeicherte Bloecke, die noch den alten Standard enthalten, werden verworfen,
-- damit der neue Standard gilt. Selbst geaenderte bleiben unangetastet.
local function MigrateBlocks()
   for setting, olds in pairs(OLD_DEFAULTS) do
      local saved = FishingBuddy.GetSetting(setting);
      if ( type(saved) == "string" and trim(saved) ~= "" ) then
         local norm = NormalizeBlock(saved);
         for _, old in ipairs(olds) do
            if ( norm == old ) then
               FishingBuddy.SetSetting(setting, nil);
               break;
            end
         end
      end
   end
end
Auto.MigrateBlocks = MigrateBlocks;

-- ---------------------------------------------------------------------------
-- Antworten des Servers lesen
-- ---------------------------------------------------------------------------

-- Meldungen von mod-playerbots ("self", PlayerbotMgr.cpp):
--     "SelfBot is now active."                       eingeschaltet
--     "SelfBot is now deactivated."                  ausgeschaltet
--     "SelfBot is disabled server-wide."             AiPlayerbot.SelfBotLevel = 0
--     "SelfBot is restricted for this account."      SelfBotLevel = 1, kein Spielleiter
-- Aeltere Staende: "Enable/Disable player botAI". Dieselben Muster nutzen Botpad
-- und AutoTravel.
local ON_PATTERNS     = { "selfbot is now active", "enable player botai", "playerbot ai enabled" };
local OFF_PATTERNS    = { "selfbot is now deactivated", "disable player botai", "playerbot ai disabled" };
local REFUSE_PATTERNS = { "selfbot is disabled server-wide", "selfbot is restricted for this account",
                          "playerbot system is currently disabled", "you cannot control bots yet" };

local function MatchAny(low, list)
   for _, p in ipairs(list) do
      if ( string.find(low, p, 1, true) ) then
         return true;
      end
   end
   return false;
end

-- "Strategies: a, b, c" -> { a = true, b = true, c = true }, Rohliste
local function ParseStrategies(msg)
   local list = string.match(msg, "^[Ss]trategies:%s*(.-)%s*$");
   if ( not list ) then
      return nil;
   end
   local set = {};
   for name in string.gmatch(list, "[^,]+") do
      name = string.lower(trim(name));
      if ( name ~= "" ) then
         set[name] = true;
      end
   end
   return set, list;
end
Auto.ParseStrategies = ParseStrategies;

-- Der Server meldet "Kein Spieler namens X" fuer Fluestern an Konten mit
-- abgeschalteten Fluesternachrichten (Spielleiter: ".whispers on").
local function IsWhisperRefused(low)
   local me = UnitName("player");
   if ( not me ) then
      return false;
   end
   if ( ERR_CHAT_PLAYER_NOT_FOUND_S and
        low == string.lower(string.format(ERR_CHAT_PLAYER_NOT_FOUND_S, me)) ) then
      return true;
   end
   return false;
end

local SessionEvent;           -- unten definiert

local function OnSystemMessage(msg)
   if ( type(msg) ~= "string" ) then
      return;
   end
   local low = string.lower(msg);
   if ( MatchAny(low, REFUSE_PATTERNS) ) then
      selfState = false;
      Trace("<- system: "..msg);
      SessionEvent("refused", msg);
   elseif ( MatchAny(low, ON_PATTERNS) ) then
      selfState = true;
      Trace("<- system: "..msg);
      SessionEvent("on", msg);
   elseif ( MatchAny(low, OFF_PATTERNS) ) then
      selfState = false;
      Trace("<- system: "..msg);
      SessionEvent("off", msg);
   elseif ( IsWhisperRefused(low) ) then
      Trace("<- system: "..msg);
      SessionEvent("whisperrefused", msg);
   end
end

local noPoleNoted = false;

local function OnWhisper(msg, author)
   if ( type(msg) ~= "string" or not IsMe(author) ) then
      return;
   end
   local set, raw = ParseStrategies(msg);
   if ( set ) then
      lastStrategies = raw;
      lastStrategiesAt = GetTime();
      selfState = true;
      Trace("<- strategies: "..raw);
      SessionEvent("strategies", set);
   elseif ( (session or stopping) and not noPoleNoted
            and string.find(string.lower(msg), "fishing pole", 1, true) ) then
      -- "I don't have a Fishing Pole" (FishingAction.cpp)
      noPoleNoted = true;
      Trace("<- bot: "..msg);
      Warn(FBConstants.AUTO_WARN_BOTPOLE);
   end
end

-- Chatfilter: die Echos der eigenen Fluesterbefehle und die Antwort auf "nc ?"
-- sind Technik und gehoeren nicht in den Chat.
local function EchoFilter(self, event, msg, author)
   if ( type(self) == "string" ) then
      -- aeltere Aufrufform ohne self
      event, msg, author = self, event, msg;
   end
   if ( type(msg) ~= "string" ) then
      return false;
   end
   local ok, hide = pcall(FishingBuddy.GetSettingBool, "AutoFishHideEcho");
   if ( ok and not hide ) then
      return false;
   end
   local now = GetTime();
   if ( event == "CHAT_MSG_WHISPER_INFORM" ) then
      local t = recent[msg];
      return (t and (now - t) < ECHO_WINDOW) and true or false;
   elseif ( event == "CHAT_MSG_WHISPER" and IsMe(author) ) then
      local t = recent[msg];
      if ( t and (now - t) < ECHO_WINDOW ) then
         return true;
      end
      if ( string.find(string.lower(msg), "^strategies:") and (now - lastProbeAt) < 15 ) then
         return true;
      end
   end
   return false;
end

if ( ChatFrame_AddMessageEventFilter ) then
   ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", EchoFilter);
   ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", EchoFilter);
end

local chatEvents = CreateFrame("Frame");
chatEvents:RegisterEvent("CHAT_MSG_SYSTEM");
chatEvents:RegisterEvent("CHAT_MSG_WHISPER");
chatEvents:SetScript("OnEvent", function(self, event, msg, author)
   if ( event == "CHAT_MSG_SYSTEM" ) then
      OnSystemMessage(msg);
   elseif ( event == "CHAT_MSG_WHISPER" ) then
      OnWhisper(msg, author);
   end
end);

-- ---------------------------------------------------------------------------
-- Zusammenspiel mit Botpad und AutoTravel
-- ---------------------------------------------------------------------------

-- Botpad setzt bei JEDER Einschaltmeldung seinen Modus (nc !, co !, ...) und
-- wuerde "master fishing" wieder entfernen. Ab Botpad 1.3 kann man es bitten, die
-- Finger von den Strategien zu lassen.
local function HoldBotpad()
   local bp = rawget(_G, "Botpad");
   if ( not botpadHeld and bp and bp.Bot and bp.Bot.Hold ) then
      bp.Bot.Hold("Fishing Buddy");
      botpadHeld = true;
      Trace("botpad: hold");
   end
end

local function ReleaseBotpad()
   local bp = rawget(_G, "Botpad");
   if ( botpadHeld and bp and bp.Bot and bp.Bot.Release ) then
      bp.Bot.Release("Fishing Buddy");
      Trace("botpad: release");
   end
   botpadHeld = false;
end

-- Pause nach dem Einschalten: eine aeltere Botpad-Fassung (ohne Hold) schickt
-- danach rund 2 s lang ihre eigenen Strategien.
local function SettleDelay()
   local bp = rawget(_G, "Botpad");
   if ( bp and bp.Bot and not bp.Bot.Hold ) then
      return SETTLE_BOTPAD;
   end
   return SETTLE_PLAIN;
end

-- Waehrend einer AutoTravel-Reise setzt AutoTravel selbst Strategien (nc !) und
-- bewegt den Charakter; dazwischen nichts nachschieben.
local function TripActive()
   local at = rawget(_G, "AutoTravel");
   return at and at.active and true or false;
end

-- ---------------------------------------------------------------------------
-- Start / Stop
-- ---------------------------------------------------------------------------

local UpdatePanel;   -- vorwaerts deklariert
local Start, Stop;

local function ResetCounters()
   startedAt = GetTime();
   lastFishAt = GetTime();
   fishCount = 0;
   lureWarnedAt = 0;
   bagWarnedAt = 0;
   lureTriedAt = 0;
   lureTries = 0;
   lureGaveUp = false;
   pausedReason = nil;
end

local function SendProbe()
   lastProbeAt = GetTime();
   WhisperSelf("nc ?");
end

local function Fail(text)
   Warn(text);
   PlayAlert();
   Stop(true, nil, true);
end

-- "master fishing" (und bei Bedarf "-mount") an den Bot schicken
local function Prepare(s)
   if ( FishingBuddy.GetSettingBool("AutoFishNoMount") and s.strategies
        and s.strategies["mount"] and not s.mountRemoved ) then
      -- Ein Selbstbot mit Reittier setzt sich von selbst auf (Strategie "mount"),
      -- und im Sattel laesst sich nicht angeln.
      WhisperSelf("nc -mount");
      s.mountRemoved = true;
   end
   ExecuteBlock(GetBlock("AutoFishStartCommands", DEFAULT_START));
   s.prepared = true;
   s.step = "verifywait";
   s.due = GetTime() + VERIFY_DELAY;
end

local function Confirm(s, unverified)
   local now = GetTime();
   s.step = "run";
   s.due = nil;
   s.lastCheck = now;
   lastFishAt = now;
   if ( unverified ) then
      Warn(FBConstants.AUTO_UNVERIFIED);
   else
      Say(Crayon:Green(FBConstants.AUTO_STARTED));
   end
   local set = s.strategies;
   if ( set ) then
      local clash = {};
      for _, name in ipairs({ "grind", "rpg", "new rpg", "travel" }) do
         if ( set[name] ) then
            clash[#clash + 1] = name;
         end
      end
      if ( #clash > 0 ) then
         Warn(string.format(FBConstants.AUTO_WARN_CLASH, table.concat(clash, ", ")));
      end
   end
   PlayAlert();
   UpdatePanel(true);
end

-- Die Strategie ist nach einer Pruefung nicht da: erneut versuchen oder aufgeben
local function Missing(s)
   s.tries = s.tries + 1;
   if ( s.tries >= MAX_TRIES ) then
      Fail(string.format(FBConstants.AUTO_ERR_STRATEGY, s.tries));
      return;
   end
   s.step = "settle";
   s.due = GetTime() + RETRY_DELAY;
end

local function ToggleOn(s)
   s.step = "toggle";
   s.due = GetTime() + TOGGLE_WAIT;
   Trace("-> say: .playerbots bot self");
   SendChatMessage(".playerbots bot self", "SAY");
end

-- Ergebnis der regelmaessigen Kontrolle im Betrieb
local function HealthResult(s, set)
   s.step = "run";
   s.due = nil;
   if ( set["master fishing"] ) then
      s.present = (s.present or 0) + 1;
      if ( s.present >= 3 ) then
         s.vanish = 0;
      end
      return;
   end
   s.present = 0;
   s.vanish = s.vanish + 1;
   Trace("health: master fishing missing ("..s.vanish..")");
   if ( s.vanish >= MAX_VANISH ) then
      -- Der Bot nimmt die Strategie selbst zurueck ("end master fishing"), wenn
      -- im Umkreis kein Wasser liegt.
      Stop(nil, FBConstants.AUTO_REASON_ENDED);
      return;
   end
   if ( FishingBuddy.GetSettingBool("AutoFishVerbose") ) then
      Say(FBConstants.AUTO_KEEPALIVE);
   end
   ExecuteBlock(GetBlock("AutoFishKeepAliveCommands", DEFAULT_KEEP));
end

-- Wird von den Chatereignissen aufgerufen
SessionEvent = function(kind, arg)
   if ( not session ) then
      if ( stopping and kind == "strategies" and not arg["master fishing"] ) then
         Auto.FinishShutdown();
      end
      return;
   end
   local s = session;
   local step = s.step;
   local now = GetTime();

   if ( kind == "refused" ) then
      if ( step == "probe" or step == "toggle" ) then
         Fail(string.format(FBConstants.AUTO_ERR_REFUSED, arg or ""));
      end
   elseif ( kind == "whisperrefused" ) then
      if ( step == "probe" or step == "verify" or step == "verifywait" or step == "settle" ) then
         Fail(FBConstants.AUTO_ERR_WHISPER);
      end
   elseif ( kind == "on" ) then
      if ( step == "toggle" ) then
         -- After a corrective second toggle the bot is back in the state it was
         -- in before: it was on already (and deaf), so it is not ours to switch off.
         s.ownsBot = not s.retoggled;
         s.step = "settle";
         s.due = now + SettleDelay();
      end
   elseif ( kind == "off" ) then
      if ( step == "toggle" ) then
         -- Der Bot war doch schon an (und hat auf "nc ?" nicht geantwortet).
         if ( not s.retoggled ) then
            s.retoggled = true;
            ToggleOn(s);
         else
            Fail(FBConstants.AUTO_ERR_TOGGLE);
         end
      elseif ( step ~= "probe" ) then
         -- Jemand hat den Selbstmodus ausgeschaltet.
         Stop(nil, FBConstants.AUTO_REASON_BOTOFF);
      end
   elseif ( kind == "strategies" ) then
      s.strategies = arg;
      s.sawReply = true;
      if ( step == "probe" ) then
         -- Der Bot lebt und hoert zu: nicht umschalten.
         s.step = "settle";
         s.due = now + SettleDelay();
      elseif ( step == "preprobe" ) then
         Prepare(s);
      elseif ( step == "verify" ) then
         if ( arg["master fishing"] ) then
            Confirm(s);
         else
            Missing(s);
         end
      elseif ( step == "check" ) then
         HealthResult(s, arg);
      end
   end
end

local function SessionTick(now)
   local s = session;
   if ( not s or not s.due or now < s.due ) then
      return;
   end
   local step = s.step;
   if ( step == "probe" ) then
      -- keine Antwort auf "nc ?": der Bot ist aus -- einschalten
      ToggleOn(s);
   elseif ( step == "toggle" ) then
      Fail(FBConstants.AUTO_ERR_NOANSWER);
   elseif ( step == "settle" ) then
      if ( s.strategies and (now - lastStrategiesAt) < 15 ) then
         Prepare(s);
      else
         -- Die Liste der Strategien kennen wir noch nicht (der Bot war aus oder hat
         -- nicht geantwortet): jetzt fragen, bevor etwas veraendert wird.
         s.step = "preprobe";
         s.due = now + PROBE_WAIT;
         SendProbe();
      end
   elseif ( step == "preprobe" ) then
      Prepare(s);                -- keine Antwort: ohne Liste weitermachen
   elseif ( step == "verifywait" ) then
      s.step = "verify";
      s.due = now + PROBE_WAIT;
      SendProbe();
   elseif ( step == "verify" ) then
      if ( s.sawReply ) then
         Missing(s);
      else
         -- Der Bot antwortet nie auf "nc ?" (der Client zeigt keine Fluesternachricht
         -- von sich selbst, oder die Antwort wurde unterdrueckt). Nicht aufgeben.
         Confirm(s, true);
      end
   elseif ( step == "check" ) then
      s.step = "run";       -- keine Antwort: unklar, nichts unternehmen
      s.due = nil;
   end
end

-- Abschalten: erst die Strategie zuruecknehmen, DANN den Bot ausschalten. Ein
-- ausgeschalteter Bot fuehrt eine noch wartende Anweisung nicht mehr aus, und
-- die Strategie bliebe in der Datenbank stehen (sie wird beim naechsten
-- Einschalten wieder geladen).
function Auto.FinishShutdown()
   local st = stopping;
   if ( not st ) then
      return;
   end
   stopping = nil;
   if ( st.ownsBot and selfState ~= false ) then
      Trace("-> say: .playerbots bot self (off)");
      SendChatMessage(".playerbots bot self", "SAY");
   end
   ReleaseBotpad();
end

local function StopTick(now)
   local st = stopping;
   if ( not st or now < st.due ) then
      return;
   end
   if ( now - st.started >= STOP_WAIT ) then
      Trace("shutdown: timed out waiting for the strategy to go");
      Auto.FinishShutdown();
      return;
   end
   if ( st.step == "wait" ) then
      st.step = "probe";
      st.due = now + PROBE_WAIT;
      SendProbe();
   else
      st.step = "wait";
      st.due = now + 0.5;
   end
end

local driver = CreateFrame("Frame");
driver:SetScript("OnUpdate", function()
   if ( session or stopping ) then
      local now = GetTime();
      SessionTick(now);
      StopTick(now);
   end
end);

Start = function(silent)
   if ( running ) then
      return;
   end
   if ( stopping ) then
      Warn(FBConstants.AUTO_STOPPING);
      return;
   end

   if ( not FL:IsFishingPole() ) then
      Warn(FBConstants.AUTO_NEEDPOLE);
      PlayAlert();
      return;
   end
   if ( IsMounted and IsMounted() ) then
      Warn(FBConstants.AUTO_DISMOUNT);
      PlayAlert();
      return;
   end

   running = true;
   ResetCounters();
   partyNoted = false;
   noPoleNoted = false;
   session = {
      step = "probe", due = GetTime() + PROBE_WAIT,
      tries = 0, vanish = 0, lastCheck = 0,
      ownsBot = false, retoggled = false, sawReply = false,
      mountRemoved = false, prepared = false, strategies = nil,
   };
   Trace("start");
   HoldBotpad();
   if ( not silent ) then
      Say(Crayon:Green(FBConstants.AUTO_STARTING));
   end
   FishingBuddy.RunHandlers(FBConstants.AUTO_START_EVT);
   SendProbe();
   UpdatePanel(true);
end

-- silent: keine Meldung; failed: Abbruch beim Start (keine Zusammenfassung);
-- quick: sofort ausschalten (Abmelden, /reload), ohne auf den Bot zu warten
Stop = function(silent, reason, failed, quick)
   if ( not running ) then
      return;
   end
   local s = session;
   running = false;
   session = nil;
   Trace("stop"..(reason and (": "..reason) or ""));

   if ( not silent and not failed ) then
      local elapsed = GetTime() - startedAt;
      local text = Crayon:Red(FBConstants.AUTO_STOPPED);
      if ( reason ) then
         text = text.." ("..reason..")";
      end
      Say(text);
      Say(string.format(FBConstants.AUTO_SUMMARY, FormatTime(elapsed), fishCount));
   end
   PlayAlert();
   FishingBuddy.RunHandlers(FBConstants.AUTO_STOP_EVT);

   if ( s and s.prepared and selfState ~= false ) then
      ExecuteBlock(GetBlock("AutoFishStopCommands", DEFAULT_STOP));
      if ( s.mountRemoved ) then
         WhisperSelf("nc +mount");
      end
   end
   if ( s and s.ownsBot and selfState ~= false ) then
      stopping = { ownsBot = true, started = GetTime(), due = GetTime() + 1.0, step = "wait" };
      if ( quick or not s.prepared ) then
         Auto.FinishShutdown();
      end
   else
      ReleaseBotpad();
   end
   UpdatePanel(true);
end

local function Toggle()
   if ( running ) then
      Stop();
   else
      Start();
   end
end

Auto.Start = Start;
Auto.Stop = Stop;
Auto.Toggle = Toggle;
Auto.IsRunning = function() return running; end

-- Zustand fuer Anzeige, Diagnose und Tests
function Auto.GetState()
   return {
      running = running,
      starting = (running and session and session.step ~= "run") and true or false,
      step = session and session.step or (stopping and "stopping") or "idle",
      selfState = selfState,
      ownsBot = (session and session.ownsBot) or (stopping and stopping.ownsBot) or false,
      strategies = lastStrategies,
      holdingBotpad = botpadHeld,
   };
end

function Auto.GetTrace()
   return trace;
end

-- ---------------------------------------------------------------------------
-- Watchdog
-- ---------------------------------------------------------------------------

-- Baut die Ersetzungstabelle fuer einen konkreten Koeder auf
local function LureTokens(lure)
   local link = select(2, GetItemInfo(lure.id));
   if ( not link ) then
      link = "item:"..lure.id;
   end
   return {
      ["%%l"] = link,
      ["%%i"] = tostring(lure.id),
      ["%%n"] = lure.n or "",
   };
end

-- Koeder-Behandlung: erst versuchen, den Bot den Koeder auftragen zu lassen,
-- sonst warnen und den Schnellbutton hervorheben.
local function HandleLure(now)
   local left = LureSecondsLeft();
   local threshold = 30;
   local lure = FishingBuddy.API.GetBestLure and FishingBuddy.API.GetBestLure();

   lureNeeded = (left <= threshold) and (lure ~= nil);

   if ( not lureNeeded ) then
      -- Koeder sitzt wieder: Versuchszaehler zuruecksetzen
      if ( left > threshold ) then
         lureTries = 0;
         lureGaveUp = false;
      end
      return;
   end

   -- a) Automatisch ueber den Bot auftragen lassen
   if ( FishingBuddy.GetSettingBool("AutoFishAutoLure") and not lureGaveUp ) then
      local retry = FishingBuddy.GetSetting("AutoFishLureRetry") or 20;
      if ( (now - lureTriedAt) >= retry ) then
         lureTriedAt = now;
         lureTries = lureTries + 1;
         ExecuteBlock(GetBlock("AutoFishLureCommands", DEFAULT_LURE), LureTokens(lure));
         if ( FishingBuddy.GetSettingBool("AutoFishVerbose") ) then
            Say(string.format(FBConstants.AUTO_LURETRY, lure.n));
         end
         -- Nach mehreren erfolglosen Versuchen aufgeben: der Server
         -- unterstuetzt den Befehl offenbar nicht.
         if ( lureTries >= 3 ) then
            lureGaveUp = true;
            Warn(FBConstants.AUTO_LUREFAILED);
            PlayAlert();
         end
         return;
      end
      return;
   end

   -- b) Fallback: warnen und den Button blinken lassen
   if ( FishingBuddy.GetSettingBool("AutoFishLureAlert") and (now - lureWarnedAt) > 60 ) then
      lureWarnedAt = now;
      if ( left == 0 ) then
         Warn(string.format(FBConstants.AUTO_LUREGONE, lure.n));
      else
         Warn(string.format(FBConstants.AUTO_LURESOON, left, lure.n));
      end
      PlayAlert();
   end
end

local function RunWatchdog()
   if ( not running ) then
      return;
   end

   local now = GetTime();

   -- 1) Maximale Laufzeit
   local maxmin = FishingBuddy.GetSetting("AutoFishMaxMinutes") or 0;
   if ( maxmin and maxmin > 0 and (now - startedAt) >= maxmin * 60 ) then
      Stop(nil, FBConstants.AUTO_REASON_TIMEUP);
      return;
   end

   -- 2) Angel noch angelegt?
   if ( not FL:IsFishingPole() ) then
      Stop(nil, FBConstants.AUTO_REASON_NOPOLE);
      return;
   end

   -- 3) Tot / Geistgestalt
   if ( UnitIsDeadOrGhost("player") ) then
      Stop(nil, FBConstants.AUTO_REASON_DEAD);
      return;
   end

   -- 4) Kampf
   if ( FishingBuddy.GetSettingBool("AutoFishStopInCombat") and InCombatLockdown() ) then
      Stop(nil, FBConstants.AUTO_REASON_COMBAT);
      return;
   end

   -- 5) Taschen
   local free = FreeBagSlots();
   local limit = FishingBuddy.GetSetting("AutoFishBagLimit") or 2;
   if ( free <= limit ) then
      if ( FishingBuddy.GetSettingBool("AutoFishStopBagsFull") ) then
         Stop(nil, FBConstants.AUTO_REASON_BAGS);
         return;
      elseif ( now - bagWarnedAt > 30 ) then
         bagWarnedAt = now;
         Warn(string.format(FBConstants.AUTO_BAGSLOW, free));
         PlayAlert();
      end
   end

   -- 6) Koeder abgelaufen
   HandleLure(now);

   -- 7) Stillstand: pruefen, ob der Bot noch angelt, und die Strategie bei Bedarf
   --    erneut setzen. Nicht blind senden -- der Bot antwortet auf "nc ?" mit
   --    seiner Strategieliste.
   if ( session and session.step == "run" and FishingBuddy.GetSettingBool("AutoFishKeepAlive") ) then
      local idle = FishingBuddy.GetSetting("AutoFishIdleSeconds") or 45;
      if ( (now - lastFishAt) > idle and (now - session.lastCheck) > idle and not TripActive() ) then
         session.lastCheck = now;
         session.step = "check";
         session.due = now + PROBE_WAIT;
         SendProbe();
      end
   end

   -- 8) Im Sattel kann der Bot nicht angeln
   if ( session and session.step == "run" and IsMounted and IsMounted() and (now - mountWarnedAt) > 60 ) then
      mountWarnedAt = now;
      Warn(FBConstants.AUTO_WARN_MOUNTED);
   end
end

-- ---------------------------------------------------------------------------
-- Panel / Buttons
-- ---------------------------------------------------------------------------

local function ApplyLureToButton()
   if ( not lureButton or InCombatLockdown() ) then
      return;
   end
   local lure = FishingBuddy.API.GetBestLure and FishingBuddy.API.GetBestLure();
   if ( lure ) then
      lureButton:SetAttribute("type", "item");
      lureButton:SetAttribute("item", "item:"..lure.id);
      lureButton:SetAttribute("target-slot", GetInventorySlotInfo("MainHandSlot"));
      lureButton.lure = lure;
      lureButton:Enable();
      lureButton.icon:SetDesaturated(false);
   else
      lureButton:SetAttribute("type", nil);
      lureButton:SetAttribute("item", nil);
      lureButton.lure = nil;
      lureButton:Disable();
      lureButton.icon:SetDesaturated(true);
   end

   -- Blinken, wenn ein Koeder faellig ist
   local needed = (lure ~= nil) and (LureSecondsLeft() <= 30);
   if ( needed ) then
      local pulse = 0.35 + 0.45 * math.abs(math.sin(GetTime() * 2));
      lureButton.glow:SetAlpha(pulse);
      lureButton.glow:Show();
   else
      lureButton.glow:Hide();
   end
end

-- Die per Tastaturbelegung gewaehlte Taste direkt auf den sicheren Button
-- legen. Nur so laesst sich der Koeder per Tastendruck auftragen -- ein
-- normales Keybinding darf geschuetzte Aktionen nicht ausloesen.
local function SetupLureBinding()
   if ( not lureButton or InCombatLockdown() ) then
      return;
   end
   ClearOverrideBindings(lureButton);
   local key1, key2 = GetBindingKey("FISHINGBUDDY_APPLYLURE");
   if ( key1 ) then
      SetOverrideBindingClick(lureButton, false, key1, "FishingAutoLureButton");
   end
   if ( key2 ) then
      SetOverrideBindingClick(lureButton, false, key2, "FishingAutoLureButton");
   end
end
Auto.SetupLureBinding = SetupLureBinding;

-- Panelbreite an den laengsten Text anpassen. Ohne das laeuft die
-- Detailzeile bei hohen Zahlen in den Koeder-Knopf hinein.
local lastWidth = 0;
local function ResizePanel()
   if ( not panel ) then
      return;
   end
   local textwidth = math.max(statusText:GetStringWidth(),
                              detailText:GetStringWidth());
   local width = PANEL_PAD + PANEL_TOGGLE + PANEL_TEXTGAP + textwidth
                 + PANEL_LUREGAP + PANEL_LURE + PANEL_PAD;
   if ( width < PANEL_MINWIDTH ) then
      width = PANEL_MINWIDTH;
   end
   -- auf 2 Pixel runden, damit die Breite bei wechselnden Zahlen
   -- nicht sichtbar zappelt
   width = math.floor(width / 2 + 0.5) * 2;
   if ( math.abs(width - lastWidth) >= 2 ) then
      lastWidth = width;
      panel:SetWidth(width);
   end
end

UpdatePanel = function(force)
   if ( not panel ) then
      return;
   end

   local show = FishingBuddy.GetSettingBool("AutoFishPanelVisible");
   if ( show and FishingBuddy.GetSettingBool("AutoFishPanelOnlyWithPole") and not FL:IsFishingPole() ) then
      show = false;
   end
   if ( not show ) then
      panel:Hide();
      return;
   end
   panel:Show();

   if ( running ) then
      local elapsed = GetTime() - startedAt;
      local rate = 0;
      if ( elapsed > 30 ) then
         rate = fishCount / (elapsed / 3600);
      end
      if ( session and session.step ~= "run" ) then
         statusText:SetText(Crayon:Orange(FBConstants.AUTO_STATE_STARTING));
      else
         statusText:SetText(Crayon:Green(FBConstants.AUTO_ON));
      end
      detailText:SetText(string.format("%s  |  %d %s  |  %d/h",
                                       FormatTime(elapsed), fishCount,
                                       FBConstants.FISH, math.floor(rate + 0.5)));
      toggleButton.icon:SetVertexColor(0.4, 1.0, 0.4);
   else
      statusText:SetText(Crayon:Red(FBConstants.AUTO_OFF));
      local free = FreeBagSlots();
      local left = LureSecondsLeft();
      local lurepart;
      if ( left > 0 ) then
         lurepart = string.format("%s %s", FBConstants.AUTO_LURE, FormatTime(left));
      else
         lurepart = FBConstants.AUTO_NOLURE;
      end
      detailText:SetText(string.format("%s  |  %d %s", lurepart, free, FBConstants.AUTO_SLOTS));
      toggleButton.icon:SetVertexColor(1.0, 1.0, 1.0);
   end

   ApplyLureToButton();
   ResizePanel();
end
Auto.UpdatePanel = UpdatePanel;

local function PanelTooltip(self)
   GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT");
   GameTooltip:AddLine(FBConstants.AUTO_TITLE);
   if ( running ) then
      GameTooltip:AddLine(FBConstants.AUTO_TIP_STOP, 0.9, 0.9, 0.9, 1);
   else
      GameTooltip:AddLine(FBConstants.AUTO_TIP_START, 0.9, 0.9, 0.9, 1);
   end
   GameTooltip:AddLine(FBConstants.AUTO_TIP_RIGHT, 0.6, 0.8, 1.0, 1);
   GameTooltip:AddLine(FBConstants.AUTO_TIP_DRAG, 0.6, 0.6, 0.6, 1);
   GameTooltip:Show();
end

local function SavePanelPosition()
   local point, _, relPoint, x, y = panel:GetPoint();
   FishingBuddy.SetSetting("AutoFishPanelPosition",
      { point = point, relPoint = relPoint, x = x, y = y });
end

local function RestorePanelPosition()
   local pos = FishingBuddy.GetSetting("AutoFishPanelPosition");
   panel:ClearAllPoints();
   if ( type(pos) == "table" and pos.point ) then
      panel:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0);
   else
      panel:SetPoint("CENTER", UIParent, "CENTER", 0, -180);
   end
end

local function CreatePanel()
   panel = CreateFrame("Frame", "FishingAutoPanel", UIParent);
   panel:SetWidth(PANEL_MINWIDTH);
   panel:SetHeight(52);
   panel:SetMovable(true);
   panel:EnableMouse(true);
   panel:RegisterForDrag("LeftButton");
   panel:SetClampedToScreen(true);
   panel:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 16,
      insets = { left = 5, right = 5, top = 5, bottom = 5 },
   });
   panel:SetBackdropColor(0, 0, 0, 0.75);
   panel:SetScript("OnDragStart", function(self) self:StartMoving(); end);
   panel:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing();
      SavePanelPosition();
   end);
   panel:Hide();

   -- Hauptschalter
   toggleButton = CreateFrame("Button", "FishingAutoToggleButton", panel);
   toggleButton:SetWidth(PANEL_TOGGLE);
   toggleButton:SetHeight(PANEL_TOGGLE);
   toggleButton:SetPoint("LEFT", panel, "LEFT", PANEL_PAD, 0);
   toggleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp");

   local icon = toggleButton:CreateTexture(nil, "ARTWORK");
   icon:SetAllPoints(toggleButton);
   icon:SetTexture(FBConstants.FISHINGTEXTURE);
   icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
   toggleButton.icon = icon;

   local border = toggleButton:CreateTexture(nil, "OVERLAY");
   border:SetTexture("Interface\\Buttons\\UI-Quickslot2");
   border:SetWidth(56);
   border:SetHeight(56);
   border:SetPoint("CENTER", toggleButton, "CENTER", 0, -1);
   toggleButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");

   toggleButton:SetScript("OnClick", function(self, button)
      if ( button == "RightButton" ) then
         ToggleFishingBuddyFrame("FishingOptionsFrame");
      else
         Toggle();
      end
   end);
   toggleButton:SetScript("OnEnter", PanelTooltip);
   toggleButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

   -- Texte
   statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal");
   statusText:SetPoint("TOPLEFT", toggleButton, "TOPRIGHT", PANEL_TEXTGAP, -2);
   statusText:SetJustifyH("LEFT");

   detailText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
   detailText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -3);
   detailText:SetJustifyH("LEFT");

   -- Koeder-Schnellbutton (sicherer Button -- braucht echten Mausklick)
   lureButton = CreateFrame("Button", "FishingAutoLureButton", panel,
                            "SecureActionButtonTemplate");
   lureButton:SetWidth(PANEL_LURE);
   lureButton:SetHeight(PANEL_LURE);
   lureButton:SetPoint("RIGHT", panel, "RIGHT", -PANEL_PAD, 0);
   lureButton:RegisterForClicks("LeftButtonUp");

   local licon = lureButton:CreateTexture(nil, "ARTWORK");
   licon:SetAllPoints(lureButton);
   licon:SetTexture("Interface\\Icons\\INV_Misc_Fish_20");
   licon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
   lureButton.icon = licon;
   lureButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");

   local glow = lureButton:CreateTexture(nil, "OVERLAY");
   glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");
   glow:SetBlendMode("ADD");
   glow:SetVertexColor(0.2, 1.0, 0.4);
   glow:SetWidth(PANEL_LURE * 1.6);
   glow:SetHeight(PANEL_LURE * 1.6);
   glow:SetPoint("CENTER", lureButton, "CENTER", 0, 0);
   glow:Hide();
   lureButton.glow = glow;

   lureButton:SetScript("OnEnter", function(self)
      ApplyLureToButton();
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT");
      if ( self.lure ) then
         GameTooltip:AddLine(FBConstants.AUTO_LUREBUTTON);
         GameTooltip:AddLine(self.lure.n, 1, 1, 1, 1);
         GameTooltip:AddLine(string.format("+%d %s", self.lure.b, FBConstants.FISHINGSKILL), 0.6, 1, 0.6, 1);
         local key = GetBindingKey("FISHINGBUDDY_APPLYLURE");
         if ( key ) then
            GameTooltip:AddLine(string.format(FBConstants.AUTO_LUREKEY, GetBindingText(key, "KEY_")), 0.6, 0.8, 1.0, 1);
         end
      else
         GameTooltip:AddLine(FBConstants.AUTO_NOLUREINBAG);
      end
      GameTooltip:Show();
   end);
   lureButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

   RestorePanelPosition();

   -- Takt-Frame
   local ticker = CreateFrame("Frame", nil, UIParent);
   ticker:SetScript("OnUpdate", function(self, elapsed)
      local now = GetTime();
      if ( now - lastPanelAt >= UPDATE_INTERVAL ) then
         lastPanelAt = now;
         UpdatePanel();
      end
      if ( now - lastWatchdogAt >= WATCHDOG_INTERVAL ) then
         lastWatchdogAt = now;
         RunWatchdog();
      end
   end);
end

-- ---------------------------------------------------------------------------
-- Kommando-Editor
-- ---------------------------------------------------------------------------

local editor;
local function ShowEditor()
   if ( not editor ) then
      editor = CreateFrame("Frame", "FishingAutoEditor", UIParent);
      editor:SetWidth(480);
      editor:SetHeight(480);
      editor:SetPoint("CENTER");
      editor:SetMovable(true);
      editor:EnableMouse(true);
      editor:RegisterForDrag("LeftButton");
      editor:SetScript("OnDragStart", function(self) self:StartMoving(); end);
      editor:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
      editor:SetFrameStrata("DIALOG");
      editor:SetBackdrop({
         bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
         edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
         tile = true, tileSize = 32, edgeSize = 32,
         insets = { left = 11, right = 12, top = 12, bottom = 11 },
      });

      local title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
      title:SetPoint("TOP", editor, "TOP", 0, -16);
      title:SetText(FBConstants.AUTO_EDITOR_TITLE);

      local hint = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
      hint:SetPoint("TOPLEFT", editor, "TOPLEFT", 20, -40);
      hint:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -20, -40);
      hint:SetJustifyH("LEFT");
      hint:SetText(FBConstants.AUTO_EDITOR_HINT);

      local boxes = {
         { setting = "AutoFishStartCommands", label = FBConstants.AUTO_EDITOR_START, default = DEFAULT_START },
         { setting = "AutoFishKeepAliveCommands", label = FBConstants.AUTO_EDITOR_KEEP, default = DEFAULT_KEEP },
         { setting = "AutoFishStopCommands", label = FBConstants.AUTO_EDITOR_STOP, default = DEFAULT_STOP },
         { setting = "AutoFishLureCommands", label = FBConstants.AUTO_EDITOR_LURE, default = DEFAULT_LURE },
      };

      editor.boxes = {};
      local y = -92;
      for _, info in ipairs(boxes) do
         local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
         label:SetPoint("TOPLEFT", editor, "TOPLEFT", 22, y);
         label:SetText(info.label);

         local bg = CreateFrame("Frame", nil, editor);
         bg:SetPoint("TOPLEFT", editor, "TOPLEFT", 20, y - 16);
         bg:SetWidth(430);
         bg:SetHeight(62);
         bg:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
         });
         bg:SetBackdropColor(0, 0, 0, 0.6);

         local box = CreateFrame("EditBox", nil, bg);
         box:SetMultiLine(true);
         box:SetAutoFocus(false);
         box:SetPoint("TOPLEFT", bg, "TOPLEFT", 8, -6);
         box:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -8, 6);
         box:SetFontObject(ChatFontNormal);
         box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);
         box.info = info;
         tinsert(editor.boxes, box);

         y = y - 88;
      end

      local save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate");
      save:SetWidth(110);
      save:SetHeight(22);
      save:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -24, 20);
      save:SetText(SAVE or FBConstants.AUTO_EDITOR_SAVE);
      save:SetScript("OnClick", function()
         for _, box in ipairs(editor.boxes) do
            FishingBuddy.SetSetting(box.info.setting, box:GetText());
         end
         Say(FBConstants.AUTO_EDITOR_SAVED);
         editor:Hide();
      end);

      local reset = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate");
      reset:SetWidth(110);
      reset:SetHeight(22);
      reset:SetPoint("RIGHT", save, "LEFT", -8, 0);
      reset:SetText(RESET or FBConstants.AUTO_EDITOR_RESET);
      reset:SetScript("OnClick", function()
         for _, box in ipairs(editor.boxes) do
            box:SetText(box.info.default);
         end
      end);

      local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton");
      close:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -8, -8);
   end

   for _, box in ipairs(editor.boxes) do
      box:SetText(GetBlockRaw(box.info.setting, box.info.default));
      box:SetCursorPosition(0);
   end
   editor:Show();
end
Auto.ShowEditor = ShowEditor;

-- ---------------------------------------------------------------------------
-- Optionen
-- ---------------------------------------------------------------------------

local AutoOptions = {
   ["AutoFishPanelVisible"] = {
      ["text"] = FBConstants.CONFIG_AUTOPANEL_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOPANEL_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishPanelOnlyWithPole"] = {
      ["text"] = FBConstants.CONFIG_AUTOPANELPOLE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOPANELPOLE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1,
      ["deps"] = { ["AutoFishPanelVisible"] = "d" } },
   ["AutoFishKeepAlive"] = {
      ["text"] = FBConstants.CONFIG_AUTOKEEPALIVE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOKEEPALIVE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishNoMount"] = {
      ["text"] = FBConstants.CONFIG_AUTONOMOUNT_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTONOMOUNT_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishHideEcho"] = {
      ["text"] = FBConstants.CONFIG_AUTOHIDEECHO_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOHIDEECHO_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishStopBagsFull"] = {
      ["text"] = FBConstants.CONFIG_AUTOBAGS_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOBAGS_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishStopInCombat"] = {
      ["text"] = FBConstants.CONFIG_AUTOCOMBAT_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOCOMBAT_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishAutoLure"] = {
      ["text"] = FBConstants.CONFIG_AUTOAUTOLURE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOAUTOLURE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishLureAlert"] = {
      ["text"] = FBConstants.CONFIG_AUTOLURE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOLURE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishSound"] = {
      ["text"] = FBConstants.CONFIG_AUTOSOUND_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOSOUND_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 1 },
   ["AutoFishVerbose"] = {
      ["text"] = FBConstants.CONFIG_AUTOVERBOSE_ONOFF,
      ["tooltip"] = FBConstants.CONFIG_AUTOVERBOSE_INFO,
      ["v"] = 1, ["m"] = 1, ["default"] = 0 },
   ["AutoFishIdleSlider"] = {
      ["tooltip"] = FBConstants.CONFIG_AUTOIDLE_INFO,
      ["button"] = "FishingBuddyOption_AutoFishIdleSlider",
      ["deps"] = { ["AutoFishKeepAlive"] = "d" },
      ["margin"] = { 12, 8 }, },
   ["AutoFishMaxSlider"] = {
      ["tooltip"] = FBConstants.CONFIG_AUTOMAX_INFO,
      ["button"] = "FishingBuddyOption_AutoFishMaxSlider",
      ["margin"] = { 12, 8 }, },
   ["AutoFishEditorButton"] = {
      ["button"] = "FishingBuddyOption_AutoFishEditorButton",
      ["tooltip"] = FBConstants.CONFIG_AUTOEDITOR_INFO,
      ["margin"] = { 12, 8 }, },
};

local InvisibleOptions = {
   ["AutoFishStartCommands"] = { ["default"] = DEFAULT_START },
   ["AutoFishKeepAliveCommands"] = { ["default"] = DEFAULT_KEEP },
   ["AutoFishStopCommands"] = { ["default"] = DEFAULT_STOP },
   ["AutoFishIdleSeconds"] = { ["default"] = 45 },
   ["AutoFishMaxMinutes"] = { ["default"] = 0 },
   ["AutoFishBagLimit"] = { ["default"] = 2 },
   ["AutoFishLureCommands"] = { ["default"] = DEFAULT_LURE },
   ["AutoFishLureRetry"] = { ["default"] = 20 },
   ["AutoFishPanelPosition"] = { ["default"] = nil },
};

-- Slider und Button fuer die Optionsseite bauen
local function BuildOptionWidgets()
   local function MakeSlider(name, setting, min, max, fmt, step)
      local s = CreateFrame("Slider", "FishingBuddyOption_"..name, nil, "OptionsSliderTemplate");
      local textfield = getglobal(s:GetName().."Text");
      getglobal(s:GetName().."High"):SetText("");
      getglobal(s:GetName().."Low"):SetText("");
      s:SetWidth(150);
      s:SetHeight(17);
      s:SetMinMaxValues(min, max);
      s:SetValueStep(step or 5);
      s:SetScript("OnShow", function(self)
         local v = FishingBuddy.GetSetting(setting) or min;
         self:SetValue(v);
         textfield:SetText(string.format(fmt, v));
      end);
      s:SetScript("OnValueChanged", function(self)
         local v = math.floor(self:GetValue() + 0.5);
         textfield:SetText(string.format(fmt, v));
         FishingBuddy.SetSetting(setting, v);
      end);
      return s;
   end

   MakeSlider("AutoFishIdleSlider", "AutoFishIdleSeconds", 15, 180,
              FBConstants.AUTO_IDLELABEL.." - %d s", 5);
   MakeSlider("AutoFishMaxSlider", "AutoFishMaxMinutes", 0, 240,
              FBConstants.AUTO_MAXLABEL.." - %d min", 5);

   local b = CreateFrame("Button", "FishingBuddyOption_AutoFishEditorButton",
                         nil, "UIPanelButtonTemplate");
   b:SetWidth(180);
   b:SetHeight(22);
   b:SetText(FBConstants.AUTO_EDITOR_BUTTON);
   b:SetScript("OnClick", ShowEditor);
end

-- ---------------------------------------------------------------------------
-- Slash-Kommando
-- ---------------------------------------------------------------------------

-- Alles, was zur Fehlersuche gebraucht wird, in den Chat
local function YesNo(v) return v and "yes" or "no"; end

local function PrintDiagnosis()
   local st = Auto.GetState();
   local bp = rawget(_G, "Botpad");
   local at = rawget(_G, "AutoTravel");
   local sf = "unknown";
   if ( st.selfState == true ) then sf = "on"; elseif ( st.selfState == false ) then sf = "off"; end
   Say("Auto fishing: "..(st.running and "running" or "off")..", step "..st.step
       ..", self bot "..sf..", switched on by us: "..YesNo(st.ownsBot));
   if ( lastStrategies ) then
      Say(string.format("Bot strategies (%d s ago): %s", math.floor(GetTime() - lastStrategiesAt), lastStrategies));
   else
      Say("Bot strategies: no answer to 'nc ?' yet (/fb "..FBConstants.AUTO.." probe)");
   end
   Say("Pole: "..YesNo(FL:IsFishingPole())..", mounted: "..YesNo(IsMounted and IsMounted())
       ..", group: "..YesNo(IsGrouped())..", in combat: "..YesNo(InCombatLockdown()));
   Say("Botpad: "..YesNo(bp and bp.Bot)..(botpadHeld and " (held by us)" or "")
       ..", AutoTravel: "..YesNo(at and at.Start ~= nil)..(TripActive() and " (trip active)" or ""));
   for _, line in ipairs(trace) do
      Say("  "..line);
   end
end

FishingBuddy.Commands[FBConstants.AUTO] = {};
FishingBuddy.Commands[FBConstants.AUTO].help = FBConstants.AUTO_HELP;
FishingBuddy.Commands[FBConstants.AUTO].func =
   function(what)
      if ( not what ) then
         Toggle();
         return true;
      end
      what = string.lower(what);
      if ( what == "on" or what == "an" or what == "start" ) then
         Start();
      elseif ( what == "off" or what == "aus" or what == "stop" ) then
         Stop();
      elseif ( what == "edit" or what == "cmd" or what == "config" ) then
         ShowEditor();
      elseif ( what == "panel" or what == "show" ) then
         local v = FishingBuddy.GetSettingBool("AutoFishPanelVisible");
         FishingBuddy.SetSetting("AutoFishPanelVisible", v and 0 or 1);
         UpdatePanel(true);
      elseif ( what == "lure" or what == FBConstants.AUTO_LUREWORD ) then
         local v = FishingBuddy.GetSettingBool("AutoFishAutoLure");
         FishingBuddy.SetSetting("AutoFishAutoLure", v and 0 or 1);
         lureGaveUp = false;
         lureTries = 0;
         if ( v ) then
            Say(FBConstants.CONFIG_AUTOAUTOLURE_ONOFF.." "..FBConstants.AUTO_OFFWORD);
         else
            Say(FBConstants.CONFIG_AUTOAUTOLURE_ONOFF.." "..FBConstants.AUTO_ONWORD);
         end
      elseif ( what == "status" ) then
         if ( running ) then
            Say(string.format(FBConstants.AUTO_SUMMARY,
                              FormatTime(GetTime() - startedAt), fishCount));
         else
            Say(FBConstants.AUTO_OFF);
         end
      elseif ( what == "diag" ) then
         PrintDiagnosis();
      elseif ( what == "probe" ) then
         -- fragt den Bot nach seinen Strategien; die Antwort steht danach in "diag"
         SendProbe();
         Say("nc ? ...  /fb "..FBConstants.AUTO.." diag");
      else
         return false;
      end
      return true;
   end;

-- ---------------------------------------------------------------------------
-- Event-Anbindung
-- ---------------------------------------------------------------------------

local AutoEvents = {};

AutoEvents[FBConstants.ADD_FISHIE_EVT] = function(id, name, zone, subzone, texture, quantity)
   lastFishAt = GetTime();
   if ( running ) then
      fishCount = fishCount + (quantity or 1);
   end
end;

AutoEvents[FBConstants.FISHING_DISABLED_EVT] = function()
   if ( running ) then
      Stop(nil, FBConstants.AUTO_REASON_NOPOLE);
   end
   UpdatePanel(true);
end;

AutoEvents[FBConstants.FISHING_ENABLED_EVT] = function()
   UpdatePanel(true);
end;

AutoEvents[FBConstants.OPT_UPDATE_EVT] = function()
   UpdatePanel(true);
   SetupLureBinding();
end;

AutoEvents["UPDATE_BINDINGS"] = function()
   SetupLureBinding();
end;

AutoEvents[FBConstants.LOGOUT_EVT] = function()
   if ( running ) then
      Stop(true, nil, false, true);
   end
end;

AutoEvents["PLAYER_REGEN_DISABLED"] = function()
   if ( running and FishingBuddy.GetSettingBool("AutoFishStopInCombat") ) then
      Stop(nil, FBConstants.AUTO_REASON_COMBAT);
   end
end;

AutoEvents["PLAYER_DEAD"] = function()
   if ( running ) then
      Stop(nil, FBConstants.AUTO_REASON_DEAD);
   end
end;

AutoEvents["VARIABLES_LOADED"] = function()
   FishingBuddy.OptionsFrame.HandleOptions(FBConstants.AUTO_TAB,
                                           "Interface\\Icons\\Trade_Fishing",
                                           AutoOptions);
   FishingBuddy.OptionsFrame.HandleOptions(nil, nil, InvisibleOptions);
   MigrateBlocks();
   CreatePanel();
   UpdatePanel(true);
   SetupLureBinding();
end;

AutoEvents[FBConstants.LOGIN_EVT] = function()
   UpdatePanel(true);
   SetupLureBinding();
end;

-- Die Options-Widgets muessen existieren, bevor HandleOptions sie
-- per getglobal() sucht -- deshalb schon beim Laden anlegen.
BuildOptionWidgets();

FishingBuddy.API.RegisterHandlers(AutoEvents);

-- Globale Funktion fuer Makros: /run FishingBuddy_ToggleAutoFishing()
function FishingBuddy_ToggleAutoFishing()
   Toggle();
end
