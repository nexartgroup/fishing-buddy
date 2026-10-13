-- Deutsche
--            lower      upper
-- a umlaut   \195\164   \195\132
-- o umlaut   \195\192   \195\150
-- u umlaut   \195\188   \195\156
-- sharp s    \223

FishingTranslations["deDE"] = {
   NAME = "Fishing Buddy",
   DESCRIPTION1 = "\195\156bersicht, wo welche Fische gefangen wurden",
   DESCRIPTION2 = "und Handhabung deiner Fischereiausr\195\188stung.",

   -- Tab labels and tooltips
   LOCATIONS_INFO = "Anzeige von Fischen nach Fanggebieten",
   LOCATIONS_TAB = "Fische",
   OPTIONS_INFO = "#NAME#-Einstellungen",
   OPTIONS_TAB = "Einstellungen",

   POINT = "Punkt",
   POINTS = "Punkte",

   RAW = "Roher",
   FISH = "Fische",

   BOBBER_NAME = "Blinker",
   FISHINGSKILL = "Angeln",
   HELP = "Hilfe",
   SWITCH = "wechseln",

   GOLD_COIN = "Goldm\195\188nze",
   SILVER_COIN = "Silberm\195\188nze",
   COPPER_COIN = "Kupferm\195\188nze",
   
   LAGER = "Kapit\195\164n Rumseys Lagerbier",

   -- Thanks Maischter!
   SCHOOL = "schwarm",  -- e.g. '\195\150lige Schwarzmaul Schwarm'
   FLOATING_WRECKAGE = "Schwimmende Wrackteile",
   FLOATING_DEBRIS = "Schwimmende Tr\195\188mmer",
   ELEM_WATER = "Elementarwasser",

   ADD = "hinzuf\195\188gen",
   REPLACE = "ersetze",
   UPDATE = "update",
   CURRENT = "Session",
   RESET = "reset",
   CLEANUP = "cleanup",
   CHECK = "check",
   NOW = "now",
   
   NOREALM = "unbekannter Realm",

   WATCHER = "Watcher",
   WATCHER_LOCK = "fixieren",
   WATCHER_UNLOCK = "freigeben",

   WEEKLY = "w\195\182chentlich",
   HOURLY = "st\195\188ndlich",
   
   OFFSET_LABEL_TEXT = "Versatz:";

   KEYS_LABEL_TEXT = "Umschalter:",
   KEYS_NONE_TEXT = "Keiner",
   KEYS_SHIFT_TEXT = "Shift",
   KEYS_CTRL_TEXT = "Strg",
   KEYS_ALT_TEXT = "Alt",
   
   SHOWFISHIES = "Nach Fischnamen",
   SHOWFISHIES_INFO = "Fisch-Log nach Fischart gruppiert anzeigen.",
   SHOWLOCATIONS = "Nach Fanggebieten",
   SHOWLOCATIONS_INFO = "Fisch-Log nach Fanggebiet gruppiert anzeigen.",
   SWITCHOUTFIT = "Ausr\195\188stung wechseln",
   SWITCHOUTFIT_INFO = "Zwischen der Angelausr\195\188stung und der vorherigen umschalten.",

   -- Option names and tooltips
   CONFIG_SHOWNEWFISHIES_ONOFF = "Zeige neue Fische",
   CONFIG_SHOWNEWFISHIES_INFO  = "Zeigt im Chat-Log an, wenn ein neuer Fisch an der gegenw\195\164rtigen Position gefangen wird.",
   CONFIG_FISHWATCH_ONOFF      = "Fisch-W\195\164chter",
   CONFIG_FISHWATCH_INFO	 = "Zeigt in einer eigenen Chat-Anzeige die Fische an, die an der gegenw\195\164rtigen Position gefangen wurden.",
   CONFIG_FISHWATCHSKILL_ONOFF = "Zeige Angelskill an",
   CONFIG_FISHWATCHSKILL_INFO = "Zeigt deinen gegenw\195\164rtigen Angelskill in der \195\156bersicht an.",
   CONFIG_FISHWATCHZONE_ONOFF      = "Zone des Fanggebietes",
   CONFIG_FISHWATCHZONE_INFO	= "Zeigt die gegenw\195\164rtige Zone in der \195\156bersicht an.",
   CONFIG_FISHWATCHONLY_ONOFF   = "Nur beim Fischen",
   CONFIG_FISHWATCHONLY_INFO	 = "Anzeige nur beim Fischen",
   CONFIG_FISHWATCHPERCENT_ONOFF   = "Prozent je Fischart",
   CONFIG_FISHWATCHPERCENT_INFO	 = "Zeigt den Prozentsatz der gefangenen Fische je Fischart in der Anzeige.",
   CONFIG_SUITUPFIRST_ONOFF      = "Dress for success",
   CONFIG_SUITUPFIRST_INFO       = "Angelausrstung anlegen, wenn Du sie nicht tr\195\164gst, sobald die festgelegte Taste gedr\195\188ckt wird.",
   CONFIG_EASYCAST_ONOFF	 = "\"Einfaches Werfen\"",
   CONFIG_EASYCAST_INFO		 = "Wenn aktiviert, und eine Angel angelegt ist, wird bei einem Rechtsklick die Leine ausgeworfen.",
   CONFIG_ONLYMINE_ONOFF		 = "Nur die Angel anlegen",
   CONFIG_ONLYMINE_INFO		 = "Wenn aktiviert, wird \"Einfaches Werfen\" nur die Angel der aktuellen Fischereiausr\195\188stung checken (d.h. es sucht nicht nach weiteren/besseren Angeln).",
   CONFIG_EASYLURES_ONOFF		 = "Automatischer K\195\182der",
   CONFIG_EASYLURES_INFO		 = "Wenn aktiviert, wird (falls erforderlich) ein K\195\182der an der Angel angebracht, bevor man mit dem Angeln beginnt.",
   CONFIG_MOUSEFISHING_ONOFF	 = "Maus-Angeln",
   CONFIG_MOUSEFISHING_INFO	     = "Wenn aktiviert, wirft ein Linksklick die Leine aus und mit Rechtsklick wird der Fang eingeholt.",
   CONFIG_SHOWLOCATIONZONES_ONOFF	= "Zeige Zonen",
   CONFIG_SHOWLOCATIONZONES_INFO	= "Zeigt Zonen und Sub-Zonen an.",
   CONFIG_SORTBYPERCENT_ONOFF	= "Sortiere nach Anzahl gefangener Fische",
   CONFIG_SORTBYPERCENT_INFO	= "Anzeige sortiert nach Zahl der gefangenen Fische, anstelle von Fischnamen.",
   CONFIG_STVTIMER_ONOFF		= "Angelwettbewerb-Timer.",
   CONFIG_STVTIMER_INFO		= "Wenn aktiviert, wird je ein Countdown f\195\188r den Anfang und das Ende des Angelwettbewerbs angezeigt.",
   CONFIG_STVPOOLSONLY_ONOFF	= "Nur in Schw\195\164rme auswerfen",
   CONFIG_STVPOOLSONLY_INFO	= "Wenn aktiviert, wird \"Einfaches Werfen\" nur dann verwendet, wenn der Mauszeiger auf einen Schwarm zeigt.",
   CONFIG_SKILL_INFO	 = "Gesamtbonus durch Ausr\195\188stung.",
   CONFIG_SKILL_TEXT	 = "Angeln ",
   CONFIG_STYLISH_INFO		 = "Styling-Punkte, inspiriert durch die Draznars Fishing-FAQ in den (englischen) WoW-Foren.",
   CONFIG_STYLISH_TEXT		 = "Styling: ",

   TITAN_CLICKTOSWITCH_ONOFF	= "Zum Wechseln der Ausr\195\188stung klicken.",
   TITAN_CLICKTOSWITCH_INFO	= "Wenn aktiviert, wechselt ein Linksklick die Ausr\195\188stung, ansonsten \195\182ffnet sich das #NAME#-Fenster.",

   LEFTCLICKTODRAG = "Linksklick zum Ziehen",
   RIGHTCLICKFORMENU = "Rechtsklick \195\182ffnet das Men\195\188.",
   WATCHERCLICKHELP = "#LEFTCLICKTODRAG#\n#RIGHTCLICKFORMENU#",
   
   MINIMAPBUTTONPLACEMENT = "Plazierung des Icons",
   MINIMAPBUTTONPLACEMENTTOOLTIP = "Erlaubt Dir, das #NAME#-Icon um die Minimap zu verschieben.",
   CONFIG_MINIMAPBUTTON_ONOFF	= "Anzeigen des Minimap-Icons",
   CONFIG_MINIMAPBUTTON_INFO	= "Zeige das #NAME#-Icon an der Minimap an.",

   CONFIG_ENHANCESOUNDS_ONOFF = "Angel-Ger\195\164usche verst\195\164rken",
   CONFIG_ENHANCESOUNDS_INFO = "Maximiere Gesamtlautst\195\164rke und reduziere die Umgebungslautst\195\164rke, um das Pl\195\164tschern des K\195\182ders besser wahrnehmen zu k\195\182nnen.",
   
   -- messages
   COMPATIBLE_SWITCHER = "Kein kompatibles Ausr\195\188stungs-Wechsel-Addon gefunden.",
   FAILEDINIT = "Nicht richtig initialisiert.",
   ADDFISHIEMSG = "F\195\188ge %s an Position %s hinzu.",
   ADDSCHOOLMSG = "F\195\188ge '%s' an Position %s hinzu.",
   NODATAMSG = "Keine Fischdaten vorhanden.",
   TOOFASTMSG = "Kann Ausr\195\188stung nicht schnell wechseln.",
   CLEANUP_NONEMSG = "Keine alten Einstellungen zur\195\188ckbehalten.",
   CLEANUP_WILLMSG = "Alte Einstellungen verblieben f\195\188r |c#GREEN#%s|r: %s.",
   CLEANUP_DONEMSG = "Alte Einstellungen entfernt f\195\188r |c#GREEN#%s|r: %s.",
   CLEANUP_NOOLDMSG = "Es gibt keine alten Einstellungen f\195\188r Spieler |c#GREEN#%s|r.",
   NONEAVAILABLE_MSG = "Keine verf\195\188gbar",
   UPDATEDB_MSG = "%d Fischnamen aktualisiert.",
   
   NOTLINKABLE = "<Einzelteil ist nicht verbindbar>",

   EXTRAVAGANZA = "Angelwettbewerb",
   
   TIMETOGO = "%s beginnt in %d:%02d",
   TIMELEFT = "%s endet in %d:%02d",

   STVZONENAME = "Schlingendorntal",

   TOOLTIP_HINT = "Hinweis:";
   TOOLTIP_HINTSWITCH = "wechselt ein Linksklick die Ausr\195\188stung",
   TOOLTIP_HINTTOGGLE = "Linksklick \195\182ffnet das #NAME#-Fenster.",

   -- Key binding support
   BINDING_HEADER_FISHINGBUDDY_BINDINGS = "#NAME#",
   BINDING_NAME_FISHINGBUDDY_TOGGLE = "#NAME# anzeigen",
   BINDING_NAME_FISHINGBUDDY_SWITCH = "Ausr\195\188stung wechseln",

   BINDING_NAME_TOGGLEFISHINGBUDDY_LOC = "Zonen-Fenster anzeigen",
   BINDING_NAME_TOGGLEFISHINGBUDDY_OUT = "Outfit-Fenster anzeigen",
   BINDING_NAME_TOGGLEFISHINGBUDDY_OPT = "Optionen-Fenster anzeigen",
};

FishingTranslations["deDE"].SWITCH_HELP = {
   "|c#GREEN#/fb #SWITCH#|r",
   "    wechsle deine Angelausr\195\188stung und -kleidung.",
};

FishingTranslations["deDE"].WATCHER_HELP = {
   "|c#GREEN#/fb #WATCHER#|r [|c#GREEN##WATCHER_LOCK#|r oder |c#GREEN##WATCHER_UNLOCK#|r oder |c#GREEN##RESET#|r]",
   "    fixieren .. Fixieren der \195\156bersicht,",
   "    freigeben .. Entriegeln zum Verschieben,",
   "    reset .. Zur\195\188cksetzen",
};

FishingTranslations["deDE"].CURRENT_HELP = {
      "|c#GREEN#/fb #CURRENT# #RESET#|r",
      "   Zur\195\188cksetzen der w\195\164hrend der gegenw\195\164rtigen Session gefangenen Fische.",
   };
FishingTranslations["deDE"].CLEANUP_HELP = {
   "|c#GREEN#/fb #CLEANUP#|r [|c#GREEN##CHECK#|r or |c#GREEN##NOW#|r]",
   "    Alte Einstellungen aufr\195\164umen. |c#GREEN##CHECK#|r verzeichnet",
   "    die alten Einstellungen, die von |c#GREEN##NOW#|r entfernt werden.",
};

FishingTranslations["deDE"].PRE_HELP = {
   "Du kannst |c#GREEN#/fishingbuddy|r oder |c#GREEN#/fb|r f\195\188r alle Befehle benutzen",
   "|c#GREEN#/fb|r: schaltet das Fenster ein/aus.",
   "|c#GREEN#/fb #HELP#|r: zeigt diesen Hilfetext",
};
FishingTranslations["deDE"].POST_HELP = {
   "Du kannst die Fensteraktivierung und den",
   "Befehl zum Wechseln deiner Ausstattung in den",
   "\"Tastaturbelegungen\" festlegen.",
};

-- ------------------------------------------------------------------------
-- Fishing Buddy Enhanced -- Auto-Angeln und Statistik
-- ------------------------------------------------------------------------

FishingTranslations["deDE"].AUTO = "auto";
FishingTranslations["deDE"].STATS = "stats";
FishingTranslations["deDE"].AUTO_TAB = "Auto";
FishingTranslations["deDE"].AUTO_TITLE = "Auto-Angeln (Playerbot)";
FishingTranslations["deDE"].AUTO_ON = "Auto-Angeln: AN";
FishingTranslations["deDE"].AUTO_OFF = "Auto-Angeln: AUS";
FishingTranslations["deDE"].AUTO_STARTED = "Auto-Angeln gestartet.";
FishingTranslations["deDE"].AUTO_STOPPED = "Auto-Angeln beendet.";
FishingTranslations["deDE"].AUTO_SUMMARY = "Laufzeit %s, %d F\195\164nge.";
FishingTranslations["deDE"].AUTO_NEEDPOLE = "Du musst zuerst eine Angel anlegen.";
FishingTranslations["deDE"].AUTO_KEEPALIVE = "L\195\164ngere Zeit kein Fang und der Bot hat die Strategie verloren - sie wird erneut gesetzt.";
FishingTranslations["deDE"].AUTO_BAGSLOW = "Nur noch %d freie Taschenpl\195\164tze!";
FishingTranslations["deDE"].AUTO_LUREGONE = "Dein K\195\182der ist abgelaufen - %s liegt in deinen Taschen bereit.";
FishingTranslations["deDE"].AUTO_LURESOON = "K\195\182der l\195\164uft in %d Sekunden ab - %s liegt in deinen Taschen bereit.";
FishingTranslations["deDE"].AUTO_REASON_TIMEUP = "Zeitlimit erreicht";
FishingTranslations["deDE"].AUTO_REASON_NOPOLE = "keine Angel angelegt";
FishingTranslations["deDE"].AUTO_REASON_DEAD = "du bist gestorben";
FishingTranslations["deDE"].AUTO_REASON_COMBAT = "Kampf";
FishingTranslations["deDE"].AUTO_REASON_BAGS = "Taschen voll";
FishingTranslations["deDE"].AUTO_LURE = "K\195\182der";
FishingTranslations["deDE"].AUTO_NOLURE = "kein K\195\182der";
FishingTranslations["deDE"].AUTO_SLOTS = "Pl\195\164tze";
FishingTranslations["deDE"].AUTO_LUREBUTTON = "Besten K\195\182der auftragen";
FishingTranslations["deDE"].AUTO_NOLUREINBAG = "Kein passender K\195\182der in den Taschen.";
FishingTranslations["deDE"].AUTO_TIP_START = "Linksklick: Auto-Angeln starten";
FishingTranslations["deDE"].AUTO_TIP_STOP = "Linksklick: Auto-Angeln stoppen";
FishingTranslations["deDE"].AUTO_TIP_RIGHT = "Rechtsklick: Einstellungen \195\182ffnen";
FishingTranslations["deDE"].AUTO_TIP_DRAG = "Panel mit der Maus verschieben.";
FishingTranslations["deDE"].AUTO_EDITOR_TITLE = "Playerbot-Befehle";
FishingTranslations["deDE"].AUTO_EDITOR_HINT = "Ein Befehl pro Zeile. '/w %p text' fl\195\188stert deinem eigenen Selbstbot (so verwenden). '/p' erreicht ihn nur in einer Gruppe (ohne Gruppe geht die Zeile stattdessen an deinen eigenen Bot); Zeilen mit f\195\188hrendem Punkt gehen als Server-Befehl raus. Mehrere 'nc'-Zeilen werden zu EINEM Befehl zusammengefasst (der Bot beh\195\164lt je Takt nur das letzte 'nc'). Den Umschalter des Selbstbots erledigt das AddOn. %p = eigener Name, %z = Zone, %s = Unterzone.";
FishingTranslations["deDE"].AUTO_EDITOR_START = "Beim Start:";
FishingTranslations["deDE"].AUTO_EDITOR_KEEP = "Neu setzen (wenn die Pr\195\188fung die Strategie vermisst):";
FishingTranslations["deDE"].AUTO_EDITOR_STOP = "Beim Stoppen:";
FishingTranslations["deDE"].AUTO_EDITOR_SAVE = "Speichern";
FishingTranslations["deDE"].AUTO_EDITOR_RESET = "Standard";
FishingTranslations["deDE"].AUTO_EDITOR_SAVED = "Befehle gespeichert.";
FishingTranslations["deDE"].AUTO_EDITOR_BUTTON = "Playerbot-Befehle bearbeiten";
FishingTranslations["deDE"].AUTO_IDLELABEL = "Stillstand";
FishingTranslations["deDE"].AUTO_MAXLABEL = "Zeitlimit";
FishingTranslations["deDE"].CONFIG_AUTOPANEL_ONOFF = "Auto-Angeln-Panel anzeigen";
FishingTranslations["deDE"].CONFIG_AUTOPANEL_INFO = "Zeigt das verschiebbare Panel mit dem Auto-Angeln-Schalter.";
FishingTranslations["deDE"].CONFIG_AUTOPANELPOLE_ONOFF = "Nur mit angelegter Angel";
FishingTranslations["deDE"].CONFIG_AUTOPANELPOLE_INFO = "Panel nur einblenden, wenn eine Angel angelegt ist.";
FishingTranslations["deDE"].CONFIG_AUTOKEEPALIVE_ONOFF = "Bot bei Stillstand pr\195\188fen";
FishingTranslations["deDE"].CONFIG_AUTOKEEPALIVE_INFO = "Fragt den Bot nach seinen Strategien, wenn l\195\164ngere Zeit nichts gefangen wird, und setzt 'master fishing' neu, falls sie fehlt.";
FishingTranslations["deDE"].CONFIG_AUTOBAGS_ONOFF = "Bei vollen Taschen stoppen";
FishingTranslations["deDE"].CONFIG_AUTOBAGS_INFO = "Beendet das Auto-Angeln automatisch, wenn der Platz ausgeht.";
FishingTranslations["deDE"].CONFIG_AUTOCOMBAT_ONOFF = "Bei Kampf stoppen";
FishingTranslations["deDE"].CONFIG_AUTOCOMBAT_INFO = "Beendet das Auto-Angeln automatisch, sobald du in den Kampf ger\195\164tst.";
FishingTranslations["deDE"].CONFIG_AUTOLURE_ONOFF = "Warnen wenn der K\195\182der ausl\195\164uft";
FishingTranslations["deDE"].CONFIG_AUTOLURE_INFO = "Gibt eine Warnung aus, kurz bevor der K\195\182der abl\195\164uft.";
FishingTranslations["deDE"].CONFIG_AUTOSOUND_ONOFF = "Signalton bei Meldungen";
FishingTranslations["deDE"].CONFIG_AUTOSOUND_INFO = "Spielt einen Ton beim Starten, Stoppen und bei Warnungen.";
FishingTranslations["deDE"].CONFIG_AUTOVERBOSE_ONOFF = "Ausf\195\188hrliche Meldungen";
FishingTranslations["deDE"].CONFIG_AUTOVERBOSE_INFO = "Meldet auch die Nachfass-Befehle im Chatfenster.";
FishingTranslations["deDE"].CONFIG_AUTOIDLE_INFO = "Wie lange ohne Fang gewartet wird, bevor der Bot gepr\195\188ft wird.";
FishingTranslations["deDE"].CONFIG_AUTOMAX_INFO = "Automatisch nach so vielen Minuten stoppen (0 = kein Limit).";
FishingTranslations["deDE"].CONFIG_AUTOEDITOR_INFO = "\195\150ffnet den Editor f\195\188r die Playerbot-Befehle.";
FishingTranslations["deDE"].STATS_TITLE = "Sitzungs-Statistik";
FishingTranslations["deDE"].STATS_DURATION = "Angelzeit";
FishingTranslations["deDE"].STATS_CATCHES = "Gefangen";
FishingTranslations["deDE"].STATS_MISSES = "entkommen";
FishingTranslations["deDE"].STATS_HITRATE = "Trefferquote";
FishingTranslations["deDE"].STATS_RATE = "Rate";
FishingTranslations["deDE"].STATS_VALUE = "Wert";
FishingTranslations["deDE"].STATS_VENDORVALUE = "H\195\164ndlerwert";
FishingTranslations["deDE"].STATS_LOOTEDMONEY = "Erbeutetes Geld";
FishingTranslations["deDE"].STATS_SKILLUP = "Skillanstieg";
FishingTranslations["deDE"].STATS_BEST = "Bester Fang";
FishingTranslations["deDE"].STATS_TOP = "H\195\164ufigste F\195\164nge";
FishingTranslations["deDE"].STATS_RESET = "Sitzungs-Statistik zur\195\188ckgesetzt.";
FishingTranslations["deDE"].STATS_LURE = "K\195\182der";
FishingTranslations["deDE"].STATS_NOLURE = "keiner";
FishingTranslations["deDE"].STATS_GOLD = "g";
FishingTranslations["deDE"].STATS_SILVER = "s";
FishingTranslations["deDE"].STATS_COPPER = "k";
FishingTranslations["deDE"].CONFIG_STATSWATCHER_ONOFF = "Statistik im Watcher anzeigen";
FishingTranslations["deDE"].CONFIG_STATSWATCHER_INFO = "Erg\195\164nzt die Fischanzeige um Kennzahlen der laufenden Sitzung.";
FishingTranslations["deDE"].CONFIG_STATSRATE_ONOFF = "Fangrate und Trefferquote";
FishingTranslations["deDE"].CONFIG_STATSRATE_INFO = "Zeigt F\195\164nge pro Stunde und den Anteil erfolgreicher W\195\188rfe.";
FishingTranslations["deDE"].CONFIG_STATSVALUE_ONOFF = "Wert pro Stunde";
FishingTranslations["deDE"].CONFIG_STATSVALUE_INFO = "Zeigt den gesch\195\164tzten H\195\164ndlerwert des Fangs.";
FishingTranslations["deDE"].CONFIG_STATSLURE_ONOFF = "Restlaufzeit des K\195\182ders";
FishingTranslations["deDE"].CONFIG_STATSLURE_INFO = "Zeigt, wie lange der aktuelle K\195\182der noch h\195\164lt.";
FishingTranslations["deDE"].CONFIG_STATSREPORT_ONOFF = "Bericht beim Aufh\195\182ren";
FishingTranslations["deDE"].CONFIG_STATSREPORT_INFO = "Gibt den Sitzungsbericht automatisch aus, wenn du aufh\195\182rst zu angeln.";
FishingTranslations["deDE"].BINDING_NAME_FISHINGBUDDY_AUTOFISH = "Auto-Angeln umschalten";
FishingTranslations["deDE"].BINDING_NAME_FISHINGBUDDY_AUTOPANEL = "Auto-Angeln-Panel umschalten";

FishingTranslations["deDE"].AUTO_HELP = {
      "|c#GREEN#/fb #AUTO#|r [|c#GREEN#on|r | |c#GREEN#off|r | |c#GREEN#lure|r | |c#GREEN#edit|r | |c#GREEN#panel|r | |c#GREEN#status|r | |c#GREEN#diag|r | |c#GREEN#probe|r]",
      "    Schaltet das Playerbot-Auto-Angeln um. |c#GREEN#edit|r oeffnet den",
      "    Befehls-Editor, |c#GREEN#panel|r blendet das Panel ein oder aus,",
      "    |c#GREEN#diag|r zeigt, was der Bot gerade tut (Fehlersuche).",
};
FishingTranslations["deDE"].STATS_HELP = {
      "|c#GREEN#/fb #STATS#|r [|c#GREEN##RESET#|r]",
      "    Zeigt die Statistik der laufenden Angel-Sitzung.",
};

-- Auto-Koeder / automatische Koederanwendung

FishingTranslations["deDE"].AUTO_ONWORD = "an";
FishingTranslations["deDE"].AUTO_OFFWORD = "aus";
FishingTranslations["deDE"].AUTO_LUREWORD = "koeder";
FishingTranslations["deDE"].AUTO_LURETRY = "Bot soll %s auftragen.";
FishingTranslations["deDE"].AUTO_LUREFAILED = "Der Bot hat den K\195\182der nicht aufgetragen. Dein Server unterst\195\188tzt den Befehl vermutlich nicht -- nimm den K\195\182der-Knopf am Panel oder passe den Befehl unter /fb auto edit an.";
FishingTranslations["deDE"].AUTO_LUREKEY = "Taste: %s";
FishingTranslations["deDE"].AUTO_EDITOR_LURE = "K\195\182der auftragen (%l = Link, %i = ID, %n = Name):";
FishingTranslations["deDE"].CONFIG_AUTOAUTOLURE_ONOFF = "K\195\182der vom Bot auftragen lassen";
FishingTranslations["deDE"].CONFIG_AUTOAUTOLURE_INFO = "Sendet beim Ablaufen des K\195\182ders den eingestellten Befehl, damit der Playerbot selbst einen neuen auftr\195\164gt.";
FishingTranslations["deDE"].BINDING_NAME_FISHINGBUDDY_APPLYLURE = "Besten K\195\182der auftragen";

-- Auto-Angeln 0.9.10: Zustandsverfolgung, Pruefung, Diagnose
FishingTranslations["deDE"].AUTO_STATE_STOPPING = "Auto-Angeln: stoppt ...";
FishingTranslations["deDE"].AUTO_TRIP_ACTIVE = "Eine AutoTravel-Reise l\195\164uft - starte das Auto-Angeln nach der Ankunft.";
FishingTranslations["deDE"].AUTO_WARN_BOTPAD_OLD = "Botpad vor 1.3 im Modus 'Minimal' nimmt dem Bot die Chat-Strategie: der Bot h\195\182rt Fishing Buddy dann nicht. Aktualisiere Botpad oder w\195\164hle einen anderen Modus.";
FishingTranslations["deDE"].AUTO_WORD_YES = "ja";
FishingTranslations["deDE"].AUTO_WORD_NO = "nein";
FishingTranslations["deDE"].AUTO_WORD_UNKNOWN = "unbekannt";
FishingTranslations["deDE"].AUTO_DIAG_STATE = "Auto-Angeln: %s, Schritt %s, Selbstbot %s, von uns eingeschaltet: %s";
FishingTranslations["deDE"].AUTO_DIAG_STRATEGIES = "Strategien des Bots (vor %d s): %s";
FishingTranslations["deDE"].AUTO_DIAG_NOLIST = "Noch keine Strategieliste vom Bot. Ist der Selbstbot aus, ist das normal; /fb auto probe fragt erneut.";
FishingTranslations["deDE"].AUTO_DIAG_ENV = "Angel: %s, Reittier: %s, Gruppe: %s, im Kampf: %s";
FishingTranslations["deDE"].AUTO_DIAG_ADDONS = "Botpad: %s%s, von uns gehalten: %s, AutoTravel: %s, AutoTravel-Reise l\195\164uft: %s";
FishingTranslations["deDE"].AUTO_DIAG_TRACE = "Letzte Meldungen (Sekunden zuvor; -> gesendet, <- empfangen):";
FishingTranslations["deDE"].AUTO_PROBE_SENT = "Der Bot wurde nach seinen Strategien gefragt. Die Antwort (falls eine kommt) steht in /fb auto diag; keine Antwort hei\195\159t meist: der Selbstbot ist aus.";
FishingTranslations["deDE"].AUTO_PROBE_BUSY = "Das Auto-Angeln spricht gerade mit dem Bot - gleich noch einmal versuchen.";
FishingTranslations["deDE"].AUTO_STARTING = "Starte Auto-Angeln - der Bot wird gepr\195\188ft ...";
FishingTranslations["deDE"].AUTO_STATE_STARTING = "Auto-Angeln: startet ...";
FishingTranslations["deDE"].AUTO_UNVERIFIED = "Der Bot hat die Strategiepr\195\188fung nicht beantwortet, der Start ist daher unbest\195\164tigt. Wenn nichts ausgeworfen wird: /fb auto diag";
FishingTranslations["deDE"].AUTO_STOPPING = "Der Bot wird noch gestoppt, einen Moment bitte.";
FishingTranslations["deDE"].AUTO_DISMOUNT = "Steig zuerst ab - der Bot kann im Sattel nicht angeln.";
FishingTranslations["deDE"].AUTO_WARN_MOUNTED = "Du sitzt auf einem Reittier - so kann der Bot nicht angeln. Steig ab; mit der Option 'Bot nicht aufsitzen lassen' steigt er nicht von selbst wieder auf.";
FishingTranslations["deDE"].AUTO_WARN_CLASH = "Weitere Bot-Strategien sind aktiv (%s); der Bot l\195\164uft eventuell weg oder k\195\164mpft, statt zu angeln.";
FishingTranslations["deDE"].AUTO_WARN_BOTPOLE = "Der Bot meldet, dass er keine Angel hat.";
FishingTranslations["deDE"].AUTO_ERR_REFUSED = "Der Server verweigert den Selbstbot: %s (Servereinstellung AiPlayerbot.SelfBotLevel: 0 = aus, 1 = nur Spielleiter)";
FishingTranslations["deDE"].AUTO_ERR_NOANSWER = "Keine Antwort auf '.playerbots bot self'. Ist mod-playerbots installiert und der Befehl f\195\188r dein Konto erlaubt?";
FishingTranslations["deDE"].AUTO_ERR_TOGGLE = "Der Selbstbot blieb nicht eingeschaltet.";
FishingTranslations["deDE"].AUTO_ERR_WHISPER = "Fl\195\188stern an dich selbst ist gesperrt. Spielleiter-Konten brauchen einmal '.whispers on'.";
FishingTranslations["deDE"].AUTO_ERR_STRATEGY = "Der Bot hat die Strategie 'master fishing' nach %d Versuchen nicht \195\188bernommen. Ein anderes Addon (Botpad, AutoTravel), ein gespeicherter Strategiesatz, deine eigenen Befehlslisten (/fb auto edit) oder der Bot selbst (kein Wasser in Reichweite?) nimmt sie vielleicht zur\195\188ck - siehe /fb auto diag.";
FishingTranslations["deDE"].AUTO_REASON_ENDED = "der Bot hat das Angeln selbst beendet - kein Wasser in Reichweite?";
FishingTranslations["deDE"].AUTO_REASON_BOTOFF = "der Selbstbot wurde ausgeschaltet";
FishingTranslations["deDE"].AUTO_NOTE_PARTYLINE = "'%s' geht in den Gruppenchat, aber du bist in keiner Gruppe, der Server w\195\188rde sie verwerfen. Sie geht stattdessen an deinen eigenen Bot (/w %%p ...).";
FishingTranslations["deDE"].AUTO_NOTE_TOGGLELINE = "'.playerbots bot self' wurde aus deiner Befehlsliste entfernt: Fishing Buddy schaltet den Selbstbot jetzt selbst und nur bei Bedarf.";
FishingTranslations["deDE"].CONFIG_AUTONOMOUNT_ONOFF = "Bot nicht aufsitzen lassen";
FishingTranslations["deDE"].CONFIG_AUTONOMOUNT_INFO = "Ein Selbstbot mit Reittier steigt von selbst auf, und im Sattel kann niemand angeln. Schaltet die Bot-Strategie 'mount' w\195\164hrend des Angelns aus und danach wieder ein.";
FishingTranslations["deDE"].CONFIG_AUTOHIDEECHO_ONOFF = "Bot-Fl\195\188stern im Chat ausblenden";
FishingTranslations["deDE"].CONFIG_AUTOHIDEECHO_INFO = "Blendet die Fl\195\188sternachrichten aus, die Fishing Buddy an deinen eigenen Bot schickt, und die Antworten des Bots.";
