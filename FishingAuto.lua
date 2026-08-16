-- FishingAuto.lua
-- ---------------------------------------------------------------------------
-- Auto-Angeln ueber die Playerbot-Funktion (AzerothCore / mod-playerbots)
--
-- Der Client darf in 3.3.5 keine Zauber per Timer wirken (geschuetzte API).
-- Deshalb macht dieses Modul das, was erlaubt ist: es schickt die
-- Server-/Chat-Kommandos, die den Playerbot das Angeln uebernehmen lassen,
-- und ueberwacht danach den Ablauf (Koeder, Taschen, Kampf, Stillstand).
--
-- Alle Kommandos sind frei konfigurierbar (siehe Kommando-Editor),
-- damit das Modul auch mit abweichenden Playerbot-Builds funktioniert.
--
-- ACHTUNG: ".playerbots bot self" ist ein Umschalter. Es gehoert deshalb in
-- den Start- UND in den Stopp-Block, aber NICHT in den Nachfass-Block --
-- sonst wuerde das Nachfassen den Self-Bot wieder abschalten.
-- ---------------------------------------------------------------------------

local FL = LibStub("LibFishing-1.0");
local Crayon = LibStub("LibCrayon-3.0");

FishingBuddy.Auto = {};
local Auto = FishingBuddy.Auto;

-- ---------------------------------------------------------------------------
-- Voreinstellungen
-- ---------------------------------------------------------------------------

-- %p = eigener Charaktername, %z = Zone, %s = Unterzone
local DEFAULT_START = ".playerbots bot self\n/p nc +master fishing";
local DEFAULT_KEEP  = "/p nc +master fishing";
local DEFAULT_STOP  = "/p nc -master fishing\n.playerbots bot self";
-- Koeder auftragen lassen. %l = Itemlink, %i = Item-ID, %n = Itemname
local DEFAULT_LURE  = "/p u %l";

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
local lastKeepAliveAt = 0;
local lastWatchdogAt = 0;
local lastPanelAt = 0;
local fishCount = 0;
local lureWarnedAt = 0;
local bagWarnedAt = 0;
local lureTriedAt = 0;
local lureTries = 0;
local lureGaveUp = false;
local lureNeeded = false;

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

-- Fuehrt eine einzelne Zeile aus.
--  ".befehl"       -> Server-Kommando (wird als SAY geschickt, AzerothCore
--                     faengt Nachrichten mit fuehrendem Punkt ab)
--  "/p text"       -> Chatnachricht im entsprechenden Kanal
--  "/irgendwas"    -> normaler Slashbefehl (Fallback ueber die Chatbox)
--  alles andere    -> als SAY
local function ExecuteLine(line, extra)
   line = trim(Substitute(line, extra));
   if ( line == "" or string.sub(line, 1, 2) == "--" ) then
      return;
   end

   if ( string.sub(line, 1, 1) ~= "/" ) then
      -- Server-Kommando oder einfacher Text
      SendChatMessage(line, "SAY");
      return;
   end

   local _, _, slash, rest = string.find(line, "^/([%a%d]+)%s*(.*)$");
   if ( slash ) then
      slash = string.lower(slash);
      local chattype = CHATTYPES[slash];
      if ( chattype ) then
         if ( rest and rest ~= "" ) then
            SendChatMessage(rest, chattype);
         end
         return;
      end
      if ( WHISPERTYPES[slash] ) then
         local _, _, target, text = string.find(rest or "", "^(%S+)%s+(.*)$");
         if ( target and text and text ~= "" ) then
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

local function GetBlock(setting, fallback)
   local value = FishingBuddy.GetSetting(setting);
   if ( value == nil or trim(value) == "" ) then
      return fallback;
   end
   return value;
end

-- ---------------------------------------------------------------------------
-- Start / Stop
-- ---------------------------------------------------------------------------

local UpdatePanel;   -- vorwaerts deklariert

local function ResetCounters()
   startedAt = GetTime();
   lastFishAt = GetTime();
   lastKeepAliveAt = GetTime();
   fishCount = 0;
   lureWarnedAt = 0;
   bagWarnedAt = 0;
   lureTriedAt = 0;
   lureTries = 0;
   lureGaveUp = false;
   pausedReason = nil;
end

local function Start(silent)
   if ( running ) then
      return;
   end

   if ( not FL:IsFishingPole() ) then
      Warn(FBConstants.AUTO_NEEDPOLE);
      PlayAlert();
      return;
   end

   running = true;
   ResetCounters();
   ExecuteBlock(GetBlock("AutoFishStartCommands", DEFAULT_START));

   if ( not silent ) then
      Say(Crayon:Green(FBConstants.AUTO_STARTED));
   end
   PlayAlert();
   FishingBuddy.RunHandlers(FBConstants.AUTO_START_EVT);
   UpdatePanel(true);
end

local function Stop(silent, reason)
   if ( not running ) then
      return;
   end
   running = false;
   ExecuteBlock(GetBlock("AutoFishStopCommands", DEFAULT_STOP));

   if ( not silent ) then
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

   -- 7) Stillstand -> Kommandos nachschieben
   if ( FishingBuddy.GetSettingBool("AutoFishKeepAlive") ) then
      local idle = FishingBuddy.GetSetting("AutoFishIdleSeconds") or 45;
      if ( (now - lastFishAt) > idle and (now - lastKeepAliveAt) > idle ) then
         lastKeepAliveAt = now;
         ExecuteBlock(GetBlock("AutoFishKeepAliveCommands", DEFAULT_KEEP));
         if ( FishingBuddy.GetSettingBool("AutoFishVerbose") ) then
            Say(FBConstants.AUTO_KEEPALIVE);
         end
      end
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
      statusText:SetText(Crayon:Green(FBConstants.AUTO_ON));
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
      box:SetText(GetBlock(box.info.setting, box.info.default));
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
      Stop(true);
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
