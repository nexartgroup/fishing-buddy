Fishing Buddy -- offline load-integrity and boot harness
=========================================================

Purpose
-------
Answer, without a WoW client: "does the addon load completely, does it initialise,
and does Auto-Angeln start and stop?"  It loads the addon the way the 3.3.5a client
does (TOC order, XML <Script>/<Include>, XML-created frames and their handlers,
SavedVariables assigned after the files ran), fires the login events, drives
FishingBuddy.Auto.Toggle(), advances time, and records
  * every Lua error (with traceback; nothing is swallowed) and
  * every SendChatMessage call.

It is meant to become the repo's offline test suite (copy this directory to
<repo>/tests/ ; the scripts find their own location, the repo path is an argument).

NOTHING HERE HAS BEEN RUN AGAINST A REAL CLIENT OR SERVER.  Every statement the
harness makes is "offline Lua 5.1 against hand-written stubs" -- never "tested in game".


Requirements
------------
  lua5.1            the interpreter (WoW 3.3.5a embeds Lua 5.1; do not use 5.2+)
  luac5.1           only for the static audit (luac -p)
  ls, sh            for the static audit's exact-case path check
  luacheck          optional (static audit section 7); found in PATH or ~/.luarocks/bin


How to run
----------
  ./run.sh /path/to/fishing-buddy                  # everything: static audit + all scenarios
  ./run.sh /path/to/fishing-buddy --verbose        # list every individual check
  lua5.1 static_audit.lua /path/to/fishing-buddy --name FishingBuddy
  lua5.1 scenarios.lua   /path/to/fishing-buddy
  lua5.1 scenarios.lua   /path/to/fishing-buddy --list
  lua5.1 scenarios.lua   /path/to/fishing-buddy --only lenient-client,late-equip --verbose
  lua5.1 scenarios.lua   /path/to/fishing-buddy --expect-fail strict-client,bom-rejected

Run from anywhere; the repo path may be relative ("." from inside the repo).
The scripts never write into the repo (they only read it; a temp file in /tmp is used
for the BOM-stripped luac check).

Exit status
  static_audit.lua : 1 if any "[FAIL]" line was printed
  scenarios.lua    : 1 if a scenario fails that is not listed in --expect-fail
  run.sh           : 1 if either of them returned 1
expected_failures.txt lists the scenarios that are KNOWN to fail today (they model
pessimistic client assumptions or known defects); when a fix makes one pass it is
reported as XPASS -- delete its line then.


Files
-----
  run.sh                   runs both parts; reads expected_failures.txt
  static_audit.lua         part 1: file-level checks (see below)
  scenarios.lua            part 2: the boot scenarios and their assertions
  harness/wowenv.lua       the WoW 3.3.5a stand-in (API stubs, widgets, XML frame loader, TOC loader)
  harness/xmlparse.lua     minimal XML reader
  luacheckrc               luacheck config with a WoW 3.3.5a global whitelist
  expected_failures.txt    see above


Auto fishing against a server model (new in 0.9.10)
---------------------------------------------------
harness/botserver.lua models what AzerothCore + mod-playerbots do with the chat lines the Auto module
sends (written from the C++ sources, rule by rule with file/line comments; NOT measured on a server):
  * '.playerbots bot self' is a TOGGLE and is refused for SelfBotLevel 0 / 1-without-GM; level > 2 switches it on at login
  * party chat from a player without a group is dropped by the core before any module sees it
  * a whisper to oneself reaches the bot (unless the GM whisper filter is on); the line comes back as
    CHAT_MSG_WHISPER_INFORM and CHAT_MSG_WHISPER; the bot answers 'nc ?' with 'Strategies: a, b, c'
    (the same text again within RepeatDelay is not repeated)
  * 'nc +x,-y,~z,!' change the strategy set; it is stored and restored at the next activation; without the
    strategy 'chat' the bot ignores every command
  * options: latency, AI tick, a bot that drops 'master fishing' by itself, a mount that makes the bot mount,
    a client that never shows the bot's answer, a missing module, ...
The scenarios named auto-* (see --list) drive the Auto module against it: solo player, bot already on, refusals,
deaf bot, Botpad with and without the Hold interface, vanishing strategy, mount, chat echoes, saved-settings
migration, AutoTravel trip, logout, diag command.  auto-real-botpad loads a real Botpad checkout when
BOTPAD_DIR (or ../BotPad) points to one.

What the model cannot tell you: whether the real 3.3.5a client shows a whisper from yourself, whether the bot
casts on the real terrain, or anything about timing on a real server.  '/fb auto diag' in the game answers those.


Part 1: static_audit.lua  (reads files, runs luac/luacheck)
-----------------------------------------------------------
  1  folder name == TOC name (the client only loads <Folder>/<Folder>.toc); TOC ends with a
     line terminator; every TOC entry exists with EXACTLY the case written in the TOC;
     <Script>/<Include> targets of every XML exist
  3  per loaded file: UTF-8 BOM, invalid UTF-8, NUL bytes, mixed line endings
  4  luac5.1 -p on every loaded .lua, raw and (for BOM files) with the BOM removed
  5  all inline XML handlers compile; all <Binding> bodies in Bindings.xml compile
  6  FBConstants.NAME references vs. the localization tables: undefined names, whether a later
     locale file modifies the enUS base table, format-specifier parity per locale (a mismatch
     in a string that goes through string.format is a FAIL), fallback coverage per locale
  7  luacheck global-variable findings with a WoW whitelist (luacheckrc); '_' ignored

Part 2: scenarios.lua
---------------------
Boot sequence used by every scenario (the real client's order, approximated):
  load TOC files -> assign SavedVariables -> ADDON_LOADED("FishingBuddy") -> VARIABLES_LOADED
  -> SPELLS_CHANGED -> PLAYER_LOGIN -> PLAYER_ENTERING_WORLD   (pole in the main hand)

  lenient-client       BOM tolerated, legacy this/arg1 present: the reference run. Also opens /fb,
                       every options tab, /fb auto edit|status|on|off, /fb stats, /fb help, the
                       FISHINGBUDDY_AUTOFISH key-binding body, a simulated catch, PLAYER_LOGOUT
  strict-client        most defensive reading: BOM rejected + unterminated last TOC line ignored +
                       no legacy this/arg1  (all three UNVERIFIED client behaviours)
  bom-rejected         only: client rejects a UTF-8 BOM in .lua files
  toc-last-line-dropped only: client ignores a final TOC line without line terminator
  no-legacy-globals    only: client has no global this/event/arg1..9 in script handlers
  second-session       SavedVariables round-tripped through Lua source, changed settings persisted
  old-savedvars        five older/odd SavedVariables layouts (flat pre-0.9.7, per-realm, empty, ...)
  deDE, esES-zhCN-ruRU other locales boot; Auto strings fall back to enUS where untranslated
  pole-not-cached      GetItemInfo(6256) returns nil (item not in the client cache)
  late-equip           no pole at login, equip later, remove pole during a run (watchdog stop)
  easycast             the ORIGINAL feature: option off by default; with it on, a double right click
                       arms FB_FishingButton (BUTTON2 override + spell attribute)
  lure-in-bags         lure branch of the watchdog (command, 20 s retry, give-up after 3)
  whatif-*             WHAT-IF only: a library/file fails to load -> how far does one failure reach?
  no-NONE_KEY          the client does not define the global NONE_KEY

Reading the output: per scenario "[PASS|FAIL|XFAIL|XPASS]", failed checks with detail, the
distinct Lua errors with count and context ("load FishingAuto.lua", "OnLoad of FishingBuddyRoot",
"OnEvent of X (EVENT)"), files that did not load, and a summary table.  The last lines report the
"harness gap": widget methods the code called that the stub accepts but ignores.


Options of harness/wowenv.lua (Wow.new{ ... })
----------------------------------------------
  repo            path of the addon folder (required)
  locale          "enUS" (default), "deDE", ...
  bom             "strip" (client tolerates a BOM) | "reject" (syntax error at line 1, file not run)
  legacy_globals  true (default): this/event/arg1..arg9 are set around every script handler
  toc_last_line   "read" (default) | "drop": ignore a final TOC line that has no line terminator
  fail_files      { ["Libs/Astrolabe/Astrolabe.lua"] = true }  inject a load failure (what-if)
  no_none_key     true: do not define the global NONE_KEY
  saved           { FishingBuddy_Info = {...}, FishingBuddy_Player = {...} }  SavedVariables
  world           overrides for the fake game state: pole_equipped, pole_item_cached, lure_seconds,
                  bags_have_lure, free_slots, fishing_skill, zone, subzone, dead, combat, loot ...
Useful methods: env:load_addon(), env:fire(event, ...), env:advance(seconds, step), env:slash("/fb auto"),
env:run_script(frame, "OnClick", ...), env:call(label, fn, ...) (records errors), env.errors, env.sent,
env.chat, env.files_failed, env.G (the addon's global table, for assertions).

To add a scenario: copy one in scenarios.lua (function scenario(name, descr, fn)); build the env with
boot{...}; use r:check(cond, "what", "detail").  If the code calls a WoW API the stub lacks, the Lua
error names it (e.g. "attempt to call global 'UnitRace'"): add a stub in build_env() in harness/wowenv.lua,
or a method in the Widget table.  Unknown widget methods are accepted silently and counted in the gap report.


HONEST BOUNDARY -- what the harness cannot model
------------------------------------------------
  * It is not a WoW client.  All API stubs are written from memory of the 3.3.5a API; return values
    that matter for a conclusion are flagged in the report.  GlobalStrings values are placeholders.
  * Three client behaviours are switchable assumptions, not facts, and could not be verified offline:
      (1) a UTF-8 BOM at the start of a .lua file is a syntax error (modelled message:
          "unexpected symbol near '<\239>'"),
      (2) the last TOC line is ignored when it has no line terminator,
      (3) script handlers still see the legacy globals this/event/arg1..arg9.
    The global NONE_KEY is assumed to exist (also unverified).
  * Layout, rendering, textures, fonts, tooltips' content, sounds: not modelled (SetPoint & co. are
    accepted and forgotten).  A panel being "visible" only means Show() was called on it and its parents.
  * Secure/protected-function rules and taint are not modelled (SetAttribute in combat, protected
    frames, SecureActionButton click behaviour, SetOverrideBindingClick semantics).
  * SendChatMessage is a recorder.  It does not model client-side rejection (e.g. PARTY chat while not
    in a group), chat throttling, the 255-byte limit, language/channel validity, or what any server does.
    "Sent" in this harness never means "delivered" or "acted upon".
  * Event order and timing at login are approximated; OnUpdate is driven in fixed steps.
  * Saved variables are round-tripped through Lua source, but real files can contain anything the
    player's older versions wrote; only five synthetic layouts are tried.
  * Other addons are not loaded (no interaction with BotPad, AutoTravel, Carbonite, Outfitter, ...).
  * Map data is empty (Astrolabe/LibTourist see no continents), item database is tiny.


Self-test (does the harness actually catch defects?)
----------------------------------------------------
Done once by hand on a scratch copy (never on the repo): replacing the call
  ExecuteBlock(GetBlock("AutoFishStartCommands", DEFAULT_START))   in FishingAuto.lua by ExecuteBlockX(...)
and FBConstants.AUTO_STARTED by FBConstants.AUTO_STARTD made scenarios.lua report
  "FishingAuto.lua:277: attempt to call global 'ExecuteBlockX' (a nil value)" (5 failed checks) and
static_audit.lua report "FBConstants.AUTO_STARTD is referenced ... defined nowhere" and
"global 'ExecuteBlockX'".  Repeat it with:  cp -r REPO /tmp/x/FishingBuddy; edit; ./run.sh /tmp/x/FishingBuddy
