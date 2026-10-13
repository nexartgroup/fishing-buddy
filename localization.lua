-- default to American English

FishingTranslations = {};
FishingTranslations["enUS"] = {
   NAME = "Fishing Buddy",
   
   -- these are translated automatically when loaded
   DESCRIPTION = "#DESCRIPTION1# #DESCRIPTION2#",
   WINDOW_TITLE = "#NAME# v#VERSION#",

   -- we can (should?) translate everything below here
   DESCRIPTION1 = "Keep track of the fish you've caught",
   DESCRIPTION2 = "and manage your fishing gear.",

   -- Tab labels and tooltips
   LOCATIONS_INFO = "Shows where you've caught fish by either Area or Fish Type",
   LOCATIONS_TAB = "Locations",
   OPTIONS_INFO = "Set #NAME# options",
   OPTIONS_TAB = "Options",

   POINT = "point",
   POINTS = "points",

   RAW = "Raw",
   FISH = "Fish",
   RANDOM = "Random",

   BOBBER_NAME = "Fishing Bobber",
   FISHINGSKILL = "Fishing",
   HELP = "help",
   SWITCH = "switch",
   UPDATEDB = "updatedb",
   FORCE = "force",

   OUTFITS = "Outfits",
   ELAPSED = "Elapsed",
   TOTAL = "Total",
   TOTALS = "Totals",

   SCHOOL = "School",  -- e.g. 'Oily Blackmouth School'
   FLOATING_WRECKAGE = "Floating Wreckage",
   FLOATING_DEBRIS = "Floating Debris",
   ELEM_WATER = "Elemental Water",
   OIL_SPILL = "Oil Spill",

   GOLD_COIN = "Gold coin",
   SILVER_COIN = "Silver coin",
   COPPER_COIN = "Copper coin",

   LAGER = "Captain Rumsey's Lager",
   
   ADD = "add",
   REPLACE = "replace",
   UPDATE = "update",
   CURRENT = "current",
   RESET = "reset",
   CLEANUP = "cleanup",
   CHECK = "check",
   NOW = "now",
   TIMER = "timer",
   CAST = "cast",

   NOREALM = "unknown realm",

   WATCHER = "watcher",
   WATCHER_LOCK = "lock",
   WATCHER_UNLOCK = "unlock",

   WEEKLY = "weekly",
   HOURLY = "hourly",

   OFFSET_LABEL_TEXT = "Offset:";

   KEYS_LABEL_TEXT = "Modifiers:",
   KEYS_NONE_TEXT = "None",
   KEYS_SHIFT_TEXT = "Shift",
   KEYS_CTRL_TEXT = "Control",
   KEYS_ALT_TEXT = "Alt",

   SHOWFISHIES = "Show fish",
   SHOWFISHIES_INFO = "Display fishing history grouped by fish type.",

   SHOWLOCATIONS = "Locations",
   SHOWLOCATIONS_INFO = "Display fishing history grouped by area caught.",

   ALLZOMGPETS = "Include all pets",

   -- Option names and tooltips
   CONFIG_SHOWNEWFISHIES_ONOFF   = "Show new fish",
   CONFIG_SHOWNEWFISHIES_INFO    = "Display a message in the chat area when a new fish for the current location is caught.",
   CONFIG_FISHWATCH_ONOFF        = "Fish watcher",
   CONFIG_FISHWATCH_INFO	 	 = "Display a text overlay with the fish caught in the current location.",
   CONFIG_FISHWATCHTIME_ONOFF    = "Show elapsed time",
   CONFIG_FISHWATCHTIME_INFO     = "Display the amount of time since you last equipped a fishing pole",
   CONFIG_FISHWATCHONLY_ONOFF    = "Only while fishing",
   CONFIG_FISHWATCHONLY_INFO	 = "Only show the Fish Watcher when we're actually fishing",
   CONFIG_FISHWATCHSKILL_ONOFF   = "Current skill",
   CONFIG_FISHWATCHSKILL_INFO	 = "Display the current fishing skill and mods in the fish watch area.",
   CONFIG_FISHWATCHZONE_ONOFF    = "Current zone",
   CONFIG_FISHWATCHZONE_INFO	 = "Display the current zone in the fish watch area.",
   CONFIG_FISHWATCHPERCENT_ONOFF = "Show percentages",
   CONFIG_FISHWATCHPERCENT_INFO	 = "Display the percentage of each kind of fish on the watch display",
   CONFIG_EASYCAST_ONOFF	 = "Easy Cast",
   CONFIG_EASYCAST_INFO		 = "Enable double-right-click casting.",
   CONFIG_AUTOLOOT_ONOFF	 = "Auto Loot",
   CONFIG_AUTOLOOT_INFO	     = "If enabled, automatic looting is turned on while fishing.",
   CONFIG_USEACTION_ONOFF	 = "Use Action",
   CONFIG_USEACTION_INFO	 = "If enabled, #NAME# will look for an action bar button to use for casting.",
   CONFIG_EASYLURES_ONOFF	 = "Easy Lures",
   CONFIG_EASYLURES_INFO	 = "If enabled, a lure will applied to your fishing pole before you start fishing, whenever you need one.",
   CONFIG_ALWAYSLURE_ONOFF   = "Always Lure",
   CONFIG_ALWAYSLURE_INFO    = "If enabled, put a lure on every time the pole doesn't have one",
   CONFIG_SHOWLOCATIONZONES_ONOFF	= "Show Zones",
   CONFIG_SHOWLOCATIONZONES_INFO	= "Display both zones and subzones.",
   CONFIG_SORTBYPERCENT_ONOFF = "Sort by number caught",
   CONFIG_SORTBYPERCENT_INFO  = "Order displays by the number of fish caught instead of by name.",
   CONFIG_TOOLTIPS_ONOFF     = "Show fishing info in tooltips",
   CONFIG_TOOLTIPS_INFO      = "If enabled, information about caught fish will be displayed in item tooltips.",
   CONFIG_ONLYMINE_ONOFF     = "Outfit Pole Only",
   CONFIG_ONLYMINE_INFO	     = "If enabled, easy cast will only check for your outfit's fishing pole (i.e. it won't search all possible poles for a match).",
   CONFIG_TURNOFFPVP_ONOFF   = "Turn off PVP",
   CONFIG_TURNOFFPVP_INFO    = "If enabled, PVP will be turned off while a fishing pole is equipped.",
   CONFIG_BGSOUNDS_ONOFF     = "Background sound",
   CONFIG_BGSOUNDS_INFO      = "If enabled, sound will be enabled while WoW is in the background",

   CONFIG_FISHINGFLUFF_ONOFF = "Fishing Fun",
   CONFIG_FISHINGFLUFF_INFO  = "Enable all sorts of fun while you fish",
   CONFIG_FINDFISH_ONOFF     = "Find Fish",
   CONFIG_FINDFISH_INFO      = "Turn on the 'Find Fish' ability when dressed to fish",
   CONFIG_DRINKHEAVILY_ONOFF = "Drink Lager",
   CONFIG_DRINKHEAVILY_INFO  = "If enabled, drink #LAGER# whenever you're fishing and 'dry'.",
   CONFIG_FISHINGBUDDY_ONOFF = "Fishing Buddy",
   CONFIG_FISHINGBUDDY_INFO  = "Bring out that special buddy while you fish.",
   
   CONFIG_WATCHBOBBER_ONOFF  = "Watch bobber",
   CONFIG_WATCHBOBBER_INFO   = "If enabled, #NAME# will not cast if the cursor is over the Fishing Bobber",
   
   CONFIG_CONTESTS_ONOFF     = "Fishing contest support",
   CONFIG_CONTESTS_INFO      = "Display timers for fishing contests",
   
   CONFIG_STVTIMER_ONOFF     = "Extravaganza timer",
   CONFIG_STVTIMER_INFO	     = "If enabled, display a countdown timer for the start of the Fishing Extravaganza and a countdown of the time left.",
   CONFIG_STVPOOLSONLY_ONOFF = "Only cast in pools",
   CONFIG_STVPOOLSONLY_INFO	 = "If enabled, easy cast will only be enabled if the cursor is over a fishing hole.",
   CONFIG_DERBYTIMER_ONOFF   = "Derby timer",
   CONFIG_DERBYTIMER_INFO	 = "If enabled, display a countdown timer for the start of the Kalu'ak Fishing Derby and a countdown of the time left.",
   CONFIG_SHOWPOOLS_ONOFF    = "Show pools",
   CONFIG_SHOWPOOLS_INFO     = "If enabled, known pool locations will be displaye don the minimap",
   
   CONFIG_OUTFITTER_TEXT     = "Outfit skill bonus: %s\r\nDraznar's style score: %d ",

   CLICKTOSWITCH_ONOFF	        = "Click to switch",
   CLICKTOSWITCH_INFO	        = "If enabled, a left click switches outfits, otherwise it brings up the Fishing Buddy window.",

   LEFTCLICKTODRAG = "Left-click to drag",
   RIGHTCLICKFORMENU = "Right-click for menu",
   WATCHERCLICKHELP = "#LEFTCLICKTODRAG#\n#RIGHTCLICKFORMENU#",

   MINIMAPBUTTONPLACEMENT = "Placement",
   MINIMAPBUTTONPLACEMENTTOOLTIP = "Allows you to move the #NAME# icon around the minimap",
   MINIMAPBUTTONRADIUS = "Distance",
   MINIMAPBUTTONRADIUSTOOLTIP = "Determines how far from the minimap the #NAME# icon should be",
   CONFIG_MINIMAPBUTTON_ONOFF	= "Display minimap icon",
   CONFIG_MINIMAPBUTTON_INFO	= "Display a #NAME# icon on the minimap.",

   CONFIG_ENHANCESOUNDS_ONOFF      = "Enhance fishing sounds",
   CONFIG_ENHANCESOUNDS_INFO       = "When enabled, maximize sound volume and minimize ambient volume to make the bobber noise more noticeable while fishing.",

   HIDEINWATCHER = "Display this fish in the watcher",

   -- messages
   COMPATIBLE_SWITCHER = "No compatible outfit switcher found.",
   TOOMANYFISHERMEN = "You have more than one easy cast mod installed.",
   FAILEDINIT = "Did not initialize correctly.",
   ADDFISHIEMSG = "Adding %s to location %s.",
   ADDSCHOOLMSG = "Adding '%s' to location %s.",
   NODATAMSG = "No fishing data available.",
   CLEANUP_NONEMSG = "No old settings remain.",
   CLEANUP_WILLMSG = "Old settings remaining for |c#RED#%s|r: %s.",
   CLEANUP_DONEMSG = "Old settings removed for |c#RED#%s|r: %s.",
   CLEANUP_NOOLDMSG = "There are no old settings for player |c#GREEN#%s|r.",
   NONEAVAILABLE_MSG = "None available",
   UPDATEDB_MSG = "Updated %d fish names.",

   MINIMUMSKILL = "Minimum skill: %d",
   NOTLINKABLE = "<Item is not linkable>",
   CAUGHTTHISMANY = "Caught:",
   CAUGHTTHISTOTAL = "Total:",
   FISHTYPES = "Fish types: %d",
   CAUGHT_IN_ZONES = "Caught in: %s",

   DASH = " -- ",
   FISHCAUGHT = "%d %s",
   
   EXTRAVAGANZA = "Extravaganza",
   DERBY = "Derby",
   
   TIMETOGO = "%s starts in %d:%02d",
   TIMELEFT = "%s ends in %d:%02d",
   
   FATLADYSINGS = "|c#RED#Extravaganza is over|r (%d:%02d left)",
   -- Figgle Bassbait yells: We have a winner! NAME is the Master Angler!
   RIGGLE_BASSBAIT = "^Riggle Bassbait yells: We have a winner!\s+(%a+)\s+is the Master Angler!",

   STVZONENAME = "Stranglethorn Vale",

   TOOLTIP_HINT = "Hint:",
   TOOLTIP_HINTSWITCH = "click to switch outfits",
   TOOLTIP_HINTTOGGLE = "click to show the #NAME# window.",

   -- Key binding support
   BINDING_HEADER_FISHINGBUDDY_BINDINGS = "#NAME#",
   BINDING_NAME_FISHINGBUDDY_TOGGLE = "Toggle #NAME# Window",
   BINDING_NAME_FISHINGBUDDY_SWITCH = "Switch Fishing Outfit",
   BINDING_NAME_FISHINGBUDDY_GOFISHING = "Suit up and go fishing",

   BINDING_NAME_TOGGLEFISHINGBUDDY_LOC = "Toggle #NAME# Locations Pane",
   BINDING_NAME_TOGGLEFISHINGBUDDY_OPT = "Toggle #NAME# Options Pane",
};

FishingTranslations["enUS"].SWITCH_HELP = {
      "|c#GREEN#/fb #SWITCH#|r",
      "    swap outfits (if OutfitDisplayFrame or Outfitter is available)",
};
FishingTranslations["enUS"].WATCHER_HELP = {
      "|c#GREEN#/fb #WATCHER#|r [|c#GREEN##WATCHER_LOCK#|r or |c#GREEN##WATCHER_UNLOCK#|r or |c#GREEN##RESET#|r]",
      "    Unlock the watcher to move the window,",
      "    lock to stop, reset to reset",
};
FishingTranslations["enUS"].CURRENT_HELP = {
   "|c#GREEN#/fb #CURRENT# #RESET#|r",
   "    Reset the fish caught during the current session.",
};
FishingTranslations["enUS"].UPDATEDB_HELP = {
   "|c#GREEN#/fb #UPDATEDB# [#FORCE#]|r",
   "    Try and find the names of all the fish we don't know already.",
   "    An attempt is made to skip 'rare' fish that may disconnect you",
   "    from the server -- use the '#FORCE#' option to override the check.",
};
FishingTranslations["enUS"].CLEANUP_HELP = {
      "|c#GREEN#/fb #CLEANUP#|r [|c#GREEN##CHECK#|r or |c#GREEN##NOW#|r]",
      "    Clean up old settings. |c#GREEN##CHECK#|r lists which",
      "    settings will be removed by |c#GREEN##NOW#|r.",
};
FishingTranslations["enUS"].TIMERRESET_HELP = {
      "|c#GREEN#/fb #TIMER# #RESET#|r",
      "    Reset the location of the Extravaganza timer by moving it to",
      "    the middle of the screen.",
};
FishingTranslations["enUS"].CASTHELP = {
      "|c#GREEN#/fb #CAST#|r",
      "    Scriptable cast, just like a double-click, usable from a macro.",
};

FishingTranslations["enUS"].PRE_HELP = {
      "You can use |c#GREEN#/fishingbuddy|r or |c#GREEN#/fb|r for all commands",
      "|c#GREEN#/fb|r: by itself, toggle the Fishing Buddy window",
      "|c#GREEN#/fb #HELP#|r: display this message",
};
FishingTranslations["enUS"].POST_HELP = {
      "You can bind both the window toggle and the outfit",
      " switch command to keys in the \"Key Bindings\" window.",
};

-- ------------------------------------------------------------------------
-- Fishing Buddy Enhanced -- auto fishing and statistics
-- ------------------------------------------------------------------------

FishingTranslations["enUS"].AUTO = "auto";
FishingTranslations["enUS"].STATS = "stats";
FishingTranslations["enUS"].AUTO_TAB = "Auto";
FishingTranslations["enUS"].AUTO_TITLE = "Auto Fishing (Playerbot)";
FishingTranslations["enUS"].AUTO_ON = "Auto Fishing: ON";
FishingTranslations["enUS"].AUTO_OFF = "Auto Fishing: OFF";
FishingTranslations["enUS"].AUTO_STARTED = "Auto fishing started.";
FishingTranslations["enUS"].AUTO_STOPPED = "Auto fishing stopped.";
FishingTranslations["enUS"].AUTO_SUMMARY = "Ran for %s, caught %d.";
FishingTranslations["enUS"].AUTO_NEEDPOLE = "Equip a fishing pole first.";
FishingTranslations["enUS"].AUTO_KEEPALIVE = "No catch for a while and the bot lost the strategy -- setting it again.";
FishingTranslations["enUS"].AUTO_BAGSLOW = "Only %d free bag slots left!";
FishingTranslations["enUS"].AUTO_LUREGONE = "Your lure has expired -- %s is ready in your bags.";
FishingTranslations["enUS"].AUTO_LURESOON = "Lure expires in %d seconds -- %s is ready in your bags.";
FishingTranslations["enUS"].AUTO_REASON_TIMEUP = "time limit reached";
FishingTranslations["enUS"].AUTO_REASON_NOPOLE = "no fishing pole";
FishingTranslations["enUS"].AUTO_REASON_DEAD = "you died";
FishingTranslations["enUS"].AUTO_REASON_COMBAT = "combat";
FishingTranslations["enUS"].AUTO_REASON_BAGS = "bags full";
FishingTranslations["enUS"].AUTO_LURE = "Lure";
FishingTranslations["enUS"].AUTO_NOLURE = "no lure";
FishingTranslations["enUS"].AUTO_SLOTS = "slots";
FishingTranslations["enUS"].AUTO_LUREBUTTON = "Apply best lure";
FishingTranslations["enUS"].AUTO_NOLUREINBAG = "No usable lure in your bags.";
FishingTranslations["enUS"].AUTO_TIP_START = "Left click: start auto fishing";
FishingTranslations["enUS"].AUTO_TIP_STOP = "Left click: stop auto fishing";
FishingTranslations["enUS"].AUTO_TIP_RIGHT = "Right click: open options";
FishingTranslations["enUS"].AUTO_TIP_DRAG = "Drag the panel to move it.";
FishingTranslations["enUS"].AUTO_EDITOR_TITLE = "Playerbot commands";
FishingTranslations["enUS"].AUTO_EDITOR_HINT = "One command per line. '/w %p ...' reaches your own self bot; several 'nc' lines are merged into one command. A leading dot sends a server command. The self-bot toggle is handled by the addon. %p = name, %z = zone, %s = subzone. Details: README.";
FishingTranslations["enUS"].AUTO_EDITOR_START = "On start:";
FishingTranslations["enUS"].AUTO_EDITOR_KEEP = "Re-set (used when the check finds the strategy gone):";
FishingTranslations["enUS"].AUTO_EDITOR_STOP = "On stop:";
FishingTranslations["enUS"].AUTO_EDITOR_SAVE = "Save";
FishingTranslations["enUS"].AUTO_EDITOR_RESET = "Defaults";
FishingTranslations["enUS"].AUTO_EDITOR_SAVED = "Commands saved.";
FishingTranslations["enUS"].AUTO_EDITOR_BUTTON = "Edit playerbot commands";
FishingTranslations["enUS"].AUTO_IDLELABEL = "Idle time";
FishingTranslations["enUS"].AUTO_MAXLABEL = "Time limit";
FishingTranslations["enUS"].CONFIG_AUTOPANEL_ONOFF = "Show auto fishing panel";
FishingTranslations["enUS"].CONFIG_AUTOPANEL_INFO = "Show the movable panel with the auto fishing toggle.";
FishingTranslations["enUS"].CONFIG_AUTOPANELPOLE_ONOFF = "Only with a pole equipped";
FishingTranslations["enUS"].CONFIG_AUTOPANELPOLE_INFO = "Hide the panel unless a fishing pole is equipped.";
FishingTranslations["enUS"].CONFIG_AUTOKEEPALIVE_ONOFF = "Check the bot when idle";
FishingTranslations["enUS"].CONFIG_AUTOKEEPALIVE_INFO = "If nothing is caught for a while, ask the bot for its strategies and set 'master fishing' again if it is gone.";
FishingTranslations["enUS"].CONFIG_AUTOBAGS_ONOFF = "Stop when bags are full";
FishingTranslations["enUS"].CONFIG_AUTOBAGS_INFO = "Automatically stop auto fishing when your bags run out of space.";
FishingTranslations["enUS"].CONFIG_AUTOCOMBAT_ONOFF = "Stop on combat";
FishingTranslations["enUS"].CONFIG_AUTOCOMBAT_INFO = "Automatically stop auto fishing when you enter combat.";
FishingTranslations["enUS"].CONFIG_AUTOLURE_ONOFF = "Warn when the lure expires";
FishingTranslations["enUS"].CONFIG_AUTOLURE_INFO = "Print a warning when your lure is about to run out.";
FishingTranslations["enUS"].CONFIG_AUTOSOUND_ONOFF = "Play a sound on alerts";
FishingTranslations["enUS"].CONFIG_AUTOSOUND_INFO = "Play a sound when auto fishing starts, stops or warns you.";
FishingTranslations["enUS"].CONFIG_AUTOVERBOSE_ONOFF = "Verbose messages";
FishingTranslations["enUS"].CONFIG_AUTOVERBOSE_INFO = "Also report when the bot lost its strategy and when the bot is asked to apply a lure.";
FishingTranslations["enUS"].CONFIG_AUTOIDLE_INFO = "How long to wait without a catch before checking the bot.";
FishingTranslations["enUS"].CONFIG_AUTOMAX_INFO = "Stop automatically after this many minutes (0 = no limit).";
FishingTranslations["enUS"].CONFIG_AUTOEDITOR_INFO = "Open the editor for the playerbot commands.";
FishingTranslations["enUS"].STATS_TITLE = "Session statistics";
FishingTranslations["enUS"].STATS_DURATION = "Fishing time";
FishingTranslations["enUS"].STATS_CATCHES = "Caught";
FishingTranslations["enUS"].STATS_MISSES = "escaped";
FishingTranslations["enUS"].STATS_HITRATE = "Hit rate";
FishingTranslations["enUS"].STATS_RATE = "Rate";
FishingTranslations["enUS"].STATS_VALUE = "Value";
FishingTranslations["enUS"].STATS_VENDORVALUE = "Vendor value";
FishingTranslations["enUS"].STATS_LOOTEDMONEY = "Looted coin";
FishingTranslations["enUS"].STATS_SKILLUP = "Skill gained";
FishingTranslations["enUS"].STATS_BEST = "Best catch";
FishingTranslations["enUS"].STATS_TOP = "Most caught";
FishingTranslations["enUS"].STATS_RESET = "Session statistics reset.";
FishingTranslations["enUS"].STATS_LURE = "Lure";
FishingTranslations["enUS"].STATS_NOLURE = "none";
FishingTranslations["enUS"].STATS_GOLD = "g";
FishingTranslations["enUS"].STATS_SILVER = "s";
FishingTranslations["enUS"].STATS_COPPER = "c";
FishingTranslations["enUS"].CONFIG_STATSWATCHER_ONOFF = "Show statistics in the watcher";
FishingTranslations["enUS"].CONFIG_STATSWATCHER_INFO = "Add session statistics to the fish watcher display.";
FishingTranslations["enUS"].CONFIG_STATSRATE_ONOFF = "Catch rate and hit rate";
FishingTranslations["enUS"].CONFIG_STATSRATE_INFO = "Show catches per hour and the percentage of successful casts.";
FishingTranslations["enUS"].CONFIG_STATSVALUE_ONOFF = "Value per hour";
FishingTranslations["enUS"].CONFIG_STATSVALUE_INFO = "Show the estimated vendor value of everything you caught.";
FishingTranslations["enUS"].CONFIG_STATSLURE_ONOFF = "Remaining lure time";
FishingTranslations["enUS"].CONFIG_STATSLURE_INFO = "Show how long your current lure will last.";
FishingTranslations["enUS"].CONFIG_STATSREPORT_ONOFF = "Report when you stop fishing";
FishingTranslations["enUS"].CONFIG_STATSREPORT_INFO = "Print the session report automatically when you stop fishing.";
FishingTranslations["enUS"].BINDING_NAME_FISHINGBUDDY_AUTOFISH = "Toggle Auto Fishing";
FishingTranslations["enUS"].BINDING_NAME_FISHINGBUDDY_AUTOPANEL = "Toggle Auto Fishing Panel";

FishingTranslations["enUS"].AUTO_HELP = {
      "|c#GREEN#/fb #AUTO#|r [|c#GREEN#on|r | |c#GREEN#off|r | |c#GREEN#lure|r | |c#GREEN#edit|r | |c#GREEN#panel|r | |c#GREEN#status|r | |c#GREEN#diag|r | |c#GREEN#probe|r]",
      "    Toggle playerbot auto fishing. |c#GREEN#edit|r opens the command editor,",
      "    |c#GREEN#panel|r shows or hides the on-screen panel,",
      "    |c#GREEN#diag|r prints what the bot is doing (for troubleshooting).",
};
FishingTranslations["enUS"].STATS_HELP = {
      "|c#GREEN#/fb #STATS#|r [|c#GREEN##RESET#|r]",
      "    Print the statistics for the current fishing session.",
};

-- Auto-Koeder / automatische Koederanwendung

FishingTranslations["enUS"].AUTO_ONWORD = "on";
FishingTranslations["enUS"].AUTO_OFFWORD = "off";
FishingTranslations["enUS"].AUTO_LUREWORD = "lure";
FishingTranslations["enUS"].AUTO_LURETRY = "Asking the bot to apply %s.";
FishingTranslations["enUS"].AUTO_LUREFAILED = "The bot did not apply the lure. Your server may not support the command -- use the lure button on the panel, or edit the command under /fb auto edit.";
FishingTranslations["enUS"].AUTO_LUREKEY = "Key: %s";
FishingTranslations["enUS"].AUTO_EDITOR_LURE = "Apply lure (%l = link, %i = id, %n = name):";
FishingTranslations["enUS"].CONFIG_AUTOAUTOLURE_ONOFF = "Let the bot apply lures";
FishingTranslations["enUS"].CONFIG_AUTOAUTOLURE_INFO = "When the lure runs out, send the configured command so the playerbot applies a new one by itself.";
FishingTranslations["enUS"].BINDING_NAME_FISHINGBUDDY_APPLYLURE = "Apply Best Fishing Lure";

-- Auto-Angeln 0.9.10: Zustandsverfolgung, Pruefung, Diagnose
FishingTranslations["enUS"].AUTO_STATE_STOPPING = "Auto Fishing: stopping ...";
FishingTranslations["enUS"].AUTO_TRIP_ACTIVE = "An AutoTravel trip is running -- start auto fishing after you arrive.";
FishingTranslations["enUS"].AUTO_WARN_BOTPAD_OLD = "Botpad before 1.3 in mode 'Minimal' takes away the bot's chat strategy: the bot will not hear Fishing Buddy. Update Botpad or pick another mode.";
FishingTranslations["enUS"].AUTO_WORD_YES = "yes";
FishingTranslations["enUS"].AUTO_WORD_NO = "no";
FishingTranslations["enUS"].AUTO_WORD_UNKNOWN = "unknown";
FishingTranslations["enUS"].AUTO_DIAG_STATE = "Auto fishing: %s, step %s, self bot %s, switched on by us: %s";
FishingTranslations["enUS"].AUTO_DIAG_STRATEGIES = "Bot strategies (%d s ago): %s";
FishingTranslations["enUS"].AUTO_DIAG_NOLIST = "No strategy list from the bot yet. If the self bot is off that is normal; /fb auto probe asks again.";
FishingTranslations["enUS"].AUTO_DIAG_ENV = "Fishing pole: %s, mounted: %s, group: %s, in combat: %s";
FishingTranslations["enUS"].AUTO_DIAG_ADDONS = "Botpad: %s%s, held by us: %s, AutoTravel: %s, AutoTravel trip running: %s";
FishingTranslations["enUS"].AUTO_DIAG_TRACE = "Last messages (seconds ago; -> sent, <- received):";
FishingTranslations["enUS"].AUTO_PROBE_SENT = "Asked the bot for its strategies. The answer (if any) shows up in /fb auto diag; no answer usually means the self bot is off.";
FishingTranslations["enUS"].AUTO_PROBE_BUSY = "Auto fishing is busy talking to the bot -- try again in a moment.";
FishingTranslations["enUS"].AUTO_STARTING = "Starting auto fishing -- checking the bot ...";
FishingTranslations["enUS"].AUTO_STATE_STARTING = "Auto Fishing: starting ...";
FishingTranslations["enUS"].AUTO_UNVERIFIED = "The bot did not answer the strategy check, so the start could not be confirmed. If nothing is cast: /fb auto diag";
FishingTranslations["enUS"].AUTO_STOPPING = "The bot is still being stopped, please wait a moment.";
FishingTranslations["enUS"].AUTO_DISMOUNT = "Dismount first -- the bot cannot fish while you are mounted.";
FishingTranslations["enUS"].AUTO_WARN_MOUNTED = "You are mounted -- the bot cannot fish like this. Dismount; with the option 'Keep the bot from mounting' it will not climb up again by itself.";
FishingTranslations["enUS"].AUTO_WARN_CLASH = "Other bot strategies are active (%s); the bot may walk away or fight instead of fishing.";
FishingTranslations["enUS"].AUTO_WARN_BOTPOLE = "The bot reports that it has no fishing pole.";
FishingTranslations["enUS"].AUTO_ERR_REFUSED = "The server refuses the self bot: %s (server setting AiPlayerbot.SelfBotLevel: 0 = off, 1 = game masters only)";
FishingTranslations["enUS"].AUTO_ERR_NOANSWER = "No answer to '.playerbots bot self'. Is mod-playerbots installed, and is the command allowed for your account?";
FishingTranslations["enUS"].AUTO_ERR_TOGGLE = "The self bot did not stay switched on.";
FishingTranslations["enUS"].AUTO_ERR_WHISPER = "Whispers to yourself are blocked. Game master accounts need '.whispers on' once.";
FishingTranslations["enUS"].AUTO_ERR_STRATEGY = "The bot did not accept the strategy 'master fishing' after %d tries. Another addon (Botpad, AutoTravel), a stored strategy set, your own command lists (/fb auto edit) or the bot itself (no water within reach?) may be removing it -- see /fb auto diag.";
FishingTranslations["enUS"].AUTO_REASON_ENDED = "the bot ended fishing by itself -- no water within reach?";
FishingTranslations["enUS"].AUTO_REASON_BOTOFF = "the self bot was switched off";
FishingTranslations["enUS"].AUTO_NOTE_PARTYLINE = "'%s' goes to the party chat, but you are not in a group, so the server would drop it. It is sent to your own bot instead (/w %%p ...).";
FishingTranslations["enUS"].AUTO_NOTE_TOGGLELINE = "Removed '.playerbots bot self' from your command list: Fishing Buddy now switches the self bot by itself, and only when needed.";
FishingTranslations["enUS"].CONFIG_AUTONOMOUNT_ONOFF = "Keep the bot from mounting";
FishingTranslations["enUS"].CONFIG_AUTONOMOUNT_INFO = "A self bot with a mount climbs into the saddle on its own, and nobody can fish while mounted. Turns the bot strategy 'mount' off while fishing and back on afterwards.";
FishingTranslations["enUS"].CONFIG_AUTOHIDEECHO_ONOFF = "Hide bot whispers in chat";
FishingTranslations["enUS"].CONFIG_AUTOHIDEECHO_INFO = "Hides the whispers Fishing Buddy sends to your own bot, and the bot's answers.";
