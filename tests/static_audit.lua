-- static_audit.lua
-- ---------------------------------------------------------------------------
-- Static load-integrity audit of a WoW 3.3.5a addon folder (written for Fishing
-- Buddy, usable for any addon with a <Name>.toc).  Pure Lua 5.1 plus `ls`,
-- `luac5.1` and (optional) `luacheck` via io.popen.
--
--   lua5.1 static_audit.lua /path/to/fishing-buddy [--name FishingBuddy] [--luacheck PATH]
--
-- Exit status 1 if any [FAIL] was printed.
--
-- What it checks (all by reading/executing offline, nothing is "tested in game"):
--   1  every file named in the TOC exists, with EXACTLY the case used in the TOC
--      (Windows clients are case-insensitive, but Linux checkouts/zip tools are not)
--   2  every <Script file=...>/<Include file=...> in the XMLs exists (exact case)
--   3  encoding of every loaded file: UTF-8 BOM, invalid UTF-8, NUL, CR/LF style
--   4  luac5.1 -p on every loaded .lua (raw, and with a BOM removed)
--   5  XML well-formedness, XML script handlers compile, Bindings.xml bodies compile
--   6  FBConstants.<NAME> references vs. the localization tables (base enUS table,
--      overwritten by other locale files?, format-specifier parity per locale)
--   7  luacheck global-variable findings with a WoW 3.3.5a whitelist (if installed)
-- ---------------------------------------------------------------------------

local here = (arg[0]:match("^(.*)/[^/]*$")) or "."
if not here:match("^/") then
   local p = io.popen("pwd"); local cwd = p:read("*l"); p:close()
   here = cwd .. "/" .. here
end
package.path = here .. "/harness/?.lua;" .. package.path
local xmlparse = require("xmlparse")

local repo, addon, luacheck_path
do
   local i = 1
   while i <= #arg do
      local a = arg[i]
      if a == "--name" then addon = arg[i + 1]; i = i + 2
      elseif a == "--luacheck" then luacheck_path = arg[i + 1]; i = i + 2
      else repo = repo or a; i = i + 1 end
   end
end
repo = (repo or "."):gsub("/+$", "")
if not addon then addon = repo:match("([^/]+)$"):gsub("[-_ ]", ""):gsub("^%l", string.upper) end

local nfail, nwarn = 0, 0
local function out(level, fmt, ...)
   local msg = (select("#", ...) > 0) and fmt:format(...) or fmt
   if level == "FAIL" then nfail = nfail + 1 elseif level == "WARN" then nwarn = nwarn + 1 end
   print(("[%-4s] %s"):format(level, msg))
end
local function section(t) print(("\n== %s"):format(t)) end

local function readfile(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
local function sh(cmd) local p = io.popen(cmd .. " 2>&1"); local s = p:read("*a"); local ok = p:close(); return s, ok end
local function norm(p) return (p:gsub("\\", "/")) end
local function lineno(s, off) local _, n = s:sub(1, off):gsub("\n", ""); return n + 1 end

-- ---------------------------------------------------------------------------
-- helpers: exact-case path check
-- ---------------------------------------------------------------------------

local dircache = {}
local function listdir(dir)
   if dircache[dir] then return dircache[dir] end
   local names = {}
   local s = sh(('ls -1A "%s"'):format(dir))
   for name in s:gmatch("[^\n]+") do names[name] = true end
   dircache[dir] = names
   return names
end

-- returns "ok", or "missing", or "case:<actual>"
local function check_path(base, rel)
   local cur = base
   local parts = {}
   for part in norm(rel):gmatch("[^/]+") do parts[#parts + 1] = part end
   for idx, part in ipairs(parts) do
      local names = listdir(cur)
      if not names[part] then
         for real in pairs(names) do
            if real:lower() == part:lower() then return "case:" .. real .. " (in " .. cur .. ")" end
         end
         return "missing"
      end
      cur = cur .. "/" .. part
   end
   return "ok"
end

-- ---------------------------------------------------------------------------
-- UTF-8 validation
-- ---------------------------------------------------------------------------

local function utf8_problems(s)
   local bad, i, n = {}, 1, #s
   local function cont(j) local b = s:byte(j); return b and b >= 0x80 and b <= 0xBF end
   while i <= n do
      local c = s:byte(i)
      if c < 0x80 then i = i + 1
      elseif c >= 0xC2 and c <= 0xDF then
         if cont(i + 1) then i = i + 2 else bad[#bad + 1] = i; i = i + 1 end
      elseif c >= 0xE0 and c <= 0xEF then
         local b2 = s:byte(i + 1)
         local lo, hi = 0x80, 0xBF
         if c == 0xE0 then lo = 0xA0 elseif c == 0xED then hi = 0x9F end
         if b2 and b2 >= lo and b2 <= hi and cont(i + 2) then i = i + 3 else bad[#bad + 1] = i; i = i + 1 end
      elseif c >= 0xF0 and c <= 0xF4 then
         local b2 = s:byte(i + 1)
         local lo, hi = 0x80, 0xBF
         if c == 0xF0 then lo = 0x90 elseif c == 0xF4 then hi = 0x8F end
         if b2 and b2 >= lo and b2 <= hi and cont(i + 2) and cont(i + 3) then i = i + 4 else bad[#bad + 1] = i; i = i + 1 end
      else
         bad[#bad + 1] = i; i = i + 1
      end
      if #bad >= 50 then break end
   end
   return bad
end

-- ---------------------------------------------------------------------------
-- 1. TOC
-- ---------------------------------------------------------------------------

section("1. TOC (" .. addon .. ".toc)")
local tocpath = repo .. "/" .. addon .. ".toc"
local toc = readfile(tocpath)
if not toc then
   out("FAIL", "cannot read %s", tocpath)
   os.exit(1)
end
local tocfiles, tocmeta = {}, {}
do
   local t = toc
   if t:sub(1, 3) == "\239\187\191" then out("WARN", "TOC starts with a UTF-8 BOM") t = t:sub(4) end
   for line in (t .. "\n"):gmatch("([^\r\n]*)\r?\n") do
      local k, v = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
      if k then tocmeta[k] = v
      elseif line:match("%S") and not line:match("^%s*#") then
         tocfiles[#tocfiles + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""))
      end
   end
end
do
   -- (a) the client only loads <Folder>/<Folder>.toc
   local abs = sh(('cd "%s" && pwd'):format(repo)):gsub("\n", "")
   local folder = abs:match("([^/]+)$") or repo
   if folder ~= addon then
      out("WARN", "folder is called '%s' but the TOC is '%s.toc': the 3.3.5a client only loads Interface/AddOns/<Folder>/<Folder>.toc, so " ..
          "this folder must be installed under the name '%s' (a plain 'git clone' or GitHub ZIP gives a different name)", folder, addon, addon)
   else
      out("OK", "folder name matches the TOC name")
   end
   -- (b) last TOC line without line terminator
   if toc:sub(-1) ~= "\n" then
      local last = toc:match("([^\r\n]*)$")
      out("FAIL", "%s.toc does not end with a line terminator; the last entry ('%s') may be ignored by the client " ..
          "(community-known gotcha; NOT verifiable offline) -- append a newline", addon, tostring(last))
   else
      out("OK", "TOC ends with a line terminator")
   end
   -- (c) mixed line endings inside the TOC
   local crlf = select(2, toc:gsub("\r\n", ""))
   local lf = select(2, toc:gsub("\n", "")) - crlf
   if crlf > 0 and lf > 0 then out("WARN", "TOC has mixed line endings (CRLF=%d, LF=%d)", crlf, lf) end
end
out("INFO", "Interface=%s Version=%s SavedVariables=%s SavedVariablesPerCharacter=%s",
    tostring(tocmeta.Interface), tostring(tocmeta.Version), tostring(tocmeta.SavedVariables), tostring(tocmeta.SavedVariablesPerCharacter))
if tocmeta.Interface ~= "30300" then out("WARN", "## Interface is %s (3.3.5a expects 30300)", tostring(tocmeta.Interface)) end
out("INFO", "%d files listed in the TOC", #tocfiles)

local loaded = {}      -- ordered list of repo-relative paths that the client will load
local seen = {}
local function add_loaded(rel, via)
   rel = norm(rel)
   if not seen[rel] then seen[rel] = via or "TOC"; loaded[#loaded + 1] = rel end
end

local function walk_xml(rel, via)
   local full = repo .. "/" .. rel
   local src = readfile(full)
   if not src then return end
   local ok, root = pcall(xmlparse.parse, src)
   if not ok then out("FAIL", "%s: XML parse error: %s", rel, tostring(root)) return end
   local dir = rel:match("^(.*)/[^/]*$")
   local function child(p) return dir and (dir .. "/" .. norm(p)) or norm(p) end
   local function rec(node)
      for _, ch in ipairs(node.children) do
         if ch.tag == "Script" and ch.attrs.file then
            local r = child(ch.attrs.file)
            local c = check_path(repo, r)
            if c ~= "ok" then out("FAIL", "%s: <Script file=\"%s\"> -> %s", rel, ch.attrs.file, c) end
            add_loaded(r, rel)
         elseif ch.tag == "Include" and ch.attrs.file then
            local r = child(ch.attrs.file)
            local c = check_path(repo, r)
            if c ~= "ok" then out("FAIL", "%s: <Include file=\"%s\"> -> %s", rel, ch.attrs.file, c) end
            add_loaded(r, rel)
            walk_xml(r, rel)
         end
         rec(ch)
      end
   end
   rec(root)
end

local nbad = 0
for _, f in ipairs(tocfiles) do
   local c = check_path(repo, f)
   if c ~= "ok" then out("FAIL", "TOC entry %s -> %s", f, c); nbad = nbad + 1 end
   add_loaded(f, "TOC")
   if f:lower():match("%.xml$") and c == "ok" then walk_xml(norm(f), f) end
end
if nbad == 0 then out("OK", "all TOC entries exist with exact case") end

-- files in the folder that nothing loads (INFO)
do
   local extra = {}
   local function scan(dir, relbase)
      for name in pairs(listdir(dir)) do
         local full = dir .. "/" .. name
         local rel = relbase and (relbase .. "/" .. name) or name
         local isdir = sh(('test -d "%s" && echo d'):format(full)):match("d")
         if name ~= ".git" then
            if isdir then scan(full, rel)
            elseif (rel:match("%.lua$") or rel:match("%.xml$")) and not seen[rel] and rel ~= "Bindings.xml" then extra[#extra + 1] = rel end
         end
      end
   end
   scan(repo, nil)
   table.sort(extra)
   if #extra > 0 then out("INFO", ".lua/.xml files present but not loaded by the TOC/XML chain: %s", table.concat(extra, ", ")) end
end

-- ---------------------------------------------------------------------------
-- 3/4. encoding + syntax
-- ---------------------------------------------------------------------------

section("3. encoding of loaded files + 4. luac -p")
local bomfiles, luafiles = {}, {}
local luac = "luac5.1"
local function has(cmd) return sh("command -v " .. cmd .. " >/dev/null && echo y"):match("y") end
if not has(luac) then luac = "luac" end

for _, rel in ipairs(loaded) do
   local full = repo .. "/" .. rel
   local s = readfile(full)
   if s then
      local isbom = (s:sub(1, 3) == "\239\187\191")
      local body = isbom and s:sub(4) or s
      local crlf = select(2, body:gsub("\r\n", ""))
      local lf = select(2, body:gsub("\n", "")) - crlf
      local cr = select(2, body:gsub("\r", "")) - crlf
      local tags = {}
      if isbom then tags[#tags + 1] = "BOM" end
      local bad = utf8_problems(body)
      if #bad > 0 then tags[#tags + 1] = ("invalid-UTF-8 x%d (first at line %d)"):format(#bad, lineno(body, bad[1])) end
      if body:find("%z") then tags[#tags + 1] = "NUL byte" end
      if crlf > 0 and lf > 0 then tags[#tags + 1] = ("mixed line endings CRLF=%d LF=%d"):format(crlf, lf) end
      if cr > 0 then tags[#tags + 1] = "lone CR x" .. cr end
      local isLua = rel:lower():match("%.lua$")
      if isLua then
         luafiles[#luafiles + 1] = rel
         local o1 = sh(('%s -p "%s"'):format(luac, full))
         local rawok = (o1 == "")
         local strippedok = rawok
         if not rawok and isbom then
            local tmp = os.tmpname()
            local f = io.open(tmp, "wb"); f:write(body); f:close()
            local o2 = sh(('%s -p "%s"'):format(luac, tmp))
            os.remove(tmp)
            strippedok = (o2 == "")
         end
         if not rawok then tags[#tags + 1] = ("luac -p FAILS raw: %s"):format((o1:gsub("\n.*", ""):gsub("^luac5?%.?1?:%s*", "")))
            if isbom and strippedok then tags[#tags + 1] = "(compiles once the BOM is removed)" end end
      end
      if isbom and isLua then bomfiles[#bomfiles + 1] = rel end
      local level = "OK"
      for _, t in ipairs(tags) do
         if t:find("BOM") and isLua then level = "FAIL"
         elseif t:find("luac") then level = "FAIL"
         elseif level ~= "FAIL" then level = "WARN" end
      end
      if #tags > 0 then out(level, "%-48s %s", rel, table.concat(tags, "; ")) end
   end
end
out("INFO", "%d loaded files checked (%d .lua)", #loaded, #luafiles)
if #bomfiles == 0 then
   out("OK", "no loaded .lua file starts with a UTF-8 BOM")
else
   out("FAIL", "%d loaded .lua file(s) start with a UTF-8 BOM (Lua 5.1's lexer does not skip it; luac5.1 rejects them): %s",
       #bomfiles, table.concat(bomfiles, ", "))
   out("INFO", "whether the 3.3.5a client tolerates the BOM could not be determined offline; stripping it is risk-free")
end

-- ---------------------------------------------------------------------------
-- 5. XML handlers / Bindings
-- ---------------------------------------------------------------------------

section("5. XML script handlers and key bindings compile")
local PARAMS = { OnEvent = "self, event, ...", OnUpdate = "self, elapsed", OnClick = "self, button, down", PostClick = "self, button, down",
                 OnEnter = "self, motion", OnLeave = "self, motion", OnDragStart = "self, button", OnDragStop = "self, button",
                 OnValueChanged = "self, value" }
local nhandlers, nhbad = 0, 0
for _, rel in ipairs(loaded) do
   if rel:lower():match("%.xml$") then
      local src = readfile(repo .. "/" .. rel)
      local ok, root = pcall(xmlparse.parse, src or "")
      if ok then
         local function rec(node, inscripts)
            for _, ch in ipairs(node.children) do
               if node.tag == "Scripts" then
                  if ch.text:find("%S") then
                     nhandlers = nhandlers + 1
                     local fn, err = loadstring("return function(" .. (PARAMS[ch.tag] or "self, ...") .. ") " .. ch.text .. "\n end", "=" .. rel .. ":" .. ch.tag)
                     if not fn then out("FAIL", "%s <%s>: %s", rel, ch.tag, err); nhbad = nhbad + 1 end
                  end
               end
               rec(ch)
            end
         end
         rec(root)
      end
   end
end
if nhbad == 0 then out("OK", "%d inline XML handlers compile", nhandlers) end

do
   local bpath = repo .. "/Bindings.xml"
   local src = readfile(bpath)
   if src then
      local ok, root = pcall(xmlparse.parse, src)
      if not ok then out("FAIL", "Bindings.xml: %s", tostring(root))
      else
         local n, bad = 0, 0
         for _, b in ipairs(root.children) do
            if b.tag == "Binding" then
               n = n + 1
               local fn, err = loadstring("return function(keystate) " .. b.text .. "\n end", "=Bindings.xml:" .. tostring(b.attrs.name))
               if not fn then out("FAIL", "Bindings.xml %s: %s", tostring(b.attrs.name), err); bad = bad + 1 end
            end
         end
         if bad == 0 then out("OK", "Bindings.xml: %d binding bodies compile", n) end
      end
   else
      out("INFO", "no Bindings.xml")
   end
end

-- ---------------------------------------------------------------------------
-- 6. localization / FBConstants
-- ---------------------------------------------------------------------------

section("6. FBConstants references vs localization tables")
local function deepcopy(t) if type(t) ~= "table" then return t end local r = {} for k, v in pairs(t) do r[k] = deepcopy(v) end return r end
local function deepeq(a, b)
   if type(a) ~= type(b) then return false end
   if type(a) ~= "table" then return a == b end
   for k, v in pairs(a) do if not deepeq(v, b[k]) then return false end end
   for k in pairs(b) do if a[k] == nil then return false end end
   return true
end

local env = setmetatable({}, { __index = _G })
local function load_into_env(rel)
   local s = readfile(repo .. "/" .. rel)
   if not s then return false, "missing" end
   if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end   -- reported in section 3 already
   local fn, err = loadstring(s, "@" .. rel)
   if not fn then return false, err end
   setfenv(fn, env)
   local ok, e = pcall(fn)
   return ok, e
end

local locfiles = {}
for _, rel in ipairs(tocfiles) do if rel:match("^localization[%w%.]*%.lua$") then locfiles[#locfiles + 1] = rel end end
if #locfiles == 0 then
   out("INFO", "no localization*.lua in the TOC; skipping section 6")
else
   local okb, eb = load_into_env(locfiles[1])
   if not okb or not env.FishingTranslations or not env.FishingTranslations.enUS then
      out("FAIL", "%s did not create FishingTranslations.enUS (%s)", locfiles[1], tostring(eb))
   else
      local base = deepcopy(env.FishingTranslations.enUS)
      local nb = 0 for _ in pairs(base) do nb = nb + 1 end
      out("INFO", "enUS base table: %d keys", nb)
      local lang_of = {}
      for i = 2, #locfiles do
         local ok, e = load_into_env(locfiles[i])
         if not ok then out("FAIL", "%s: %s", locfiles[i], tostring(e)) end
         if not deepeq(base, env.FishingTranslations.enUS) then
            out("FAIL", "%s modifies the enUS base table", locfiles[i])
            for k, v in pairs(env.FishingTranslations.enUS) do if not deepeq(v, base[k]) then out("FAIL", "   enUS.%s changed/added", k) end end
         end
      end
      -- every file of the TOC loaded; compare references
      local refs, refwhere = {}, {}
      for _, rel in ipairs(loaded) do
         if rel:lower():match("%.lua$") or rel:lower():match("%.xml$") then
            local s = readfile(repo .. "/" .. rel) or ""
            for name in s:gmatch("FBConstants%.([%a_][%w_]*)") do
               refs[name] = true
               refwhere[name] = refwhere[name] or rel
            end
         end
      end
      -- names assigned directly in code
      local direct = { VERSION = "FishLib:Translate" }
      for _, rel in ipairs(loaded) do
         if rel:lower():match("%.lua$") and not rel:match("^localization") then
            local s = readfile(repo .. "/" .. rel) or ""
            for name in s:gmatch("FBConstants%.([%a_][%w_]*)%s*=[^=]") do direct[name] = direct[name] or rel end
         end
      end
      local missing = {}
      for name in pairs(refs) do
         if base[name] == nil and not direct[name] then missing[#missing + 1] = name end
      end
      table.sort(missing)
      if #missing == 0 then out("OK", "every referenced FBConstants.* name is defined in enUS or assigned in code")
      else
         for _, n in ipairs(missing) do out("WARN", "FBConstants.%s is referenced (%s) but defined nowhere -> nil at runtime", n, refwhere[n]) end
      end

      -- per module: names used by the Auto/Stats modules
      for _, mod in ipairs{ "FishingAuto.lua", "FishingStats.lua" } do
         local s = readfile(repo .. "/" .. mod)
         if s then
            local m, tot = 0, 0
            for name in pairs((function() local r = {} for n in s:gmatch("FBConstants%.([%a_][%w_]*)") do r[n] = true end return r end)()) do
               tot = tot + 1
               if base[name] == nil and not direct[name] then m = m + 1 end
            end
            if m == 0 then out("OK", "%s: all %d FBConstants.* names resolve", mod, tot)
            else out("FAIL", "%s: %d of %d FBConstants.* names do not resolve", mod, m, tot) end
         end
      end

      -- format-specifier parity per locale
      local function specs(str)
         local r = {}
         for spec in str:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*([sdfgxXcioeEGuq])") do r[#r + 1] = spec end
         return table.concat(r)
      end
      local function flat(v)
         if type(v) == "string" then return { v } end
         if type(v) == "table" then local r = {} for i, x in ipairs(v) do r[i] = tostring(x) end return r end
         return {}
      end
      local usedformat = {}
      for _, rel in ipairs(loaded) do
         if rel:lower():match("%.lua$") and not rel:match("^localization") then
            local s = readfile(repo .. "/" .. rel) or ""
            for line in s:gmatch("[^\n]+") do
               if line:find("format") or line:find("Print%(") then
                  for name in line:gmatch("FBConstants%.([%a_][%w_]*)") do usedformat[name] = true end
               end
            end
         end
      end
      local mism = 0
      for lang, tbl in pairs(env.FishingTranslations) do
         if lang ~= "enUS" then
            for k, v in pairs(tbl) do
               local b = base[k]
               if b ~= nil then
                  if type(b) ~= type(v) then
                     out("WARN", "%s.%s has type %s, enUS has %s", lang, k, type(v), type(b)); mism = mism + 1
                  elseif type(b) == "string" and specs(b) ~= specs(v) then
                     local lvl = usedformat[k] and "FAIL" or "WARN"
                     out(lvl, "%s.%s format specifiers '%s' differ from enUS '%s'%s", lang, k, specs(v), specs(b),
                         usedformat[k] and " (used in string.format/Print -> runtime error or wrong output)" or "")
                     mism = mism + 1
                  end
               end
            end
         end
      end
      if mism == 0 then out("OK", "format-specifier / type parity of all locale tables vs enUS") end

      -- coverage summary
      for _, lang in ipairs{ "deDE", "esES", "frFR", "ruRU", "zhCN", "zhTW" } do
         local t = env.FishingTranslations[lang]
         if t then
            local miss, auto = 0, {}
            for k in pairs(base) do
               if t[k] == nil then miss = miss + 1; if k:match("^AUTO") or k:match("^CONFIG_AUTO") then auto[#auto + 1] = k end end
            end
            table.sort(auto)
            out("INFO", "%s: %d of %d keys fall back to enUS; %d of those belong to the Auto-fishing module%s", lang, miss, nb, #auto,
                (#auto > 0 and #auto <= 3) and (" (" .. table.concat(auto, ", ") .. ")") or "")
         end
      end
   end
end

-- ---------------------------------------------------------------------------
-- 7. luacheck
-- ---------------------------------------------------------------------------

section("7. luacheck (global variables only, WoW 3.3.5a whitelist: luacheckrc next to this script)")
do
   local lc = luacheck_path
   if not lc then
      for _, cand in ipairs{ "luacheck", "/root/.luarocks/bin/luacheck", (os.getenv("HOME") or "") .. "/.luarocks/bin/luacheck" } do
         if has(cand) or sh(('test -x "%s" && echo y'):format(cand)):match("y") then lc = cand; break end
      end
   end
   if not lc then
      out("INFO", "luacheck not installed; skipped")
   else
      local list = {}
      for _, rel in ipairs(luafiles) do list[#list + 1] = '"' .. rel .. '"' end
      local o = sh(('cd "%s" && %s --config "%s/luacheckrc" --no-color --codes --ranges --formatter plain %s'):format(repo, lc, here, table.concat(list, " ")))
      local hits, noise = {}, 0
      for line in o:gmatch("[^\n]+") do
         local file, ln, rest = line:match("^(%S+):(%d+):[%d%-]+: (.*)$")
         if file then
            local name = rest:match("'([^']+)'")
            if name == "_" then noise = noise + 1   -- throw-away variable idiom
            else hits[#hits + 1] = ("%s:%s %s"):format(file, ln, rest) end
         elseif line:match("E0%d%d") then
            hits[#hits + 1] = line
         end
      end
      -- fold repeated names
      local byname = {}
      local order = {}
      for _, h in ipairs(hits) do
         local name = h:match("'([^']+)'") or h
         if not byname[name] then byname[name] = {}; order[#order + 1] = name end
         table.insert(byname[name], (h:match("^(%S+:%d+)") or h))
      end
      for _, name in ipairs(order) do
         local locs = byname[name]
         local shown = {}
         for i = 1, math.min(4, #locs) do shown[i] = locs[i] end
         out("WARN", "global '%s' x%d: %s%s", name, #locs, table.concat(shown, ", "), #locs > 4 and ", ..." or "")
      end
      out("INFO", "%d findings folded into %d names; %d '_' throw-away globals ignored", #hits, #order, noise)
   end
end

print(("\nstatic audit finished: %d FAIL, %d WARN"):format(nfail, nwarn))
os.exit(nfail > 0 and 1 or 0)
