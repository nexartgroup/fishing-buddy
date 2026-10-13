-- harness/wowenv.lua
-- ---------------------------------------------------------------------------
-- An offline stand-in for the parts of the WoW 3.3.5a (build 12340) client that
-- Fishing Buddy touches, good enough to load the addon exactly as the client
-- would (TOC order, XML includes, XML-created frames, XML script handlers) and to
-- drive it with events and time.  Lua 5.1 only.
--
--   local Wow = require("wowenv")
--   local env = Wow.new{ repo = "/path/to/fishing-buddy", locale = "enUS", ... }
--   env:load_addon("FishingBuddy")
--   env:fire("ADDON_LOADED", "FishingBuddy")
--   env:advance(60)
--   print(#env.errors, #env.sent)
--
-- IMPORTANT, what this is NOT (see README.txt for the full list):
--   * It does not render anything and does not model layout (SetPoint & co. are
--     accepted and forgotten).
--   * Secure-frame / protected-function rules are not modelled.
--   * Every API function here is written from memory of the 3.3.5a API; where the
--     real return values matter for a conclusion the report says so.
--   * It has never been run against a real client.  Nothing it prints is
--     "tested in game".
-- ---------------------------------------------------------------------------

local xmlparse = require("xmlparse")

local M = {}
local make_widget_mt   -- defined below

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

local function readfile(path)
   local f, err = io.open(path, "rb")
   if not f then return nil, err end
   local s = f:read("*a")
   f:close()
   return s
end

local function dirname(path) return (path:match("^(.*)/[^/]*$")) or "." end
local function norm(path) return (path:gsub("\\", "/")) end

local function traceback(msg)
   return debug.traceback(tostring(msg), 2)
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ---------------------------------------------------------------------------
-- Env class
-- ---------------------------------------------------------------------------

local Env = {}
Env.__index = Env

local FRAME_TAGS = {
   Frame = true, Button = true, CheckButton = true, Slider = true, EditBox = true,
   GameTooltip = true, ScrollFrame = true, SimpleHTML = true, StatusBar = true, Model = true,
   MessageFrame = true, ScrollingMessageFrame = true, ColorSelect = true, Cooldown = true,
   Minimap = true, PlayerModel = true, DressUpModel = true, TabardModel = true, Browser = true,
   Checkbutton = true,
}
local REGION_TAGS = { Texture = true, FontString = true }
local TEXTURE_SLOT_TAGS = {
   NormalTexture = "Texture", PushedTexture = "Texture", DisabledTexture = "Texture",
   HighlightTexture = "Texture", CheckedTexture = "Texture", DisabledCheckedTexture = "Texture",
   ThumbTexture = "Texture", ButtonText = "FontString",
}
local SCRIPT_PARAMS = {
   OnEvent = "self, event, ...",
   OnUpdate = "self, elapsed",
   OnClick = "self, button, down",
   PostClick = "self, button, down",
   PreClick = "self, button, down",
   OnDoubleClick = "self, button",
   OnMouseDown = "self, button",
   OnMouseUp = "self, button",
   OnEnter = "self, motion",
   OnLeave = "self, motion",
   OnValueChanged = "self, value",
   OnDragStart = "self, button",
   OnDragStop = "self",
   OnTextChanged = "self, userInput",
   OnChar = "self, text",
   OnMouseWheel = "self, delta",
   OnAttributeChanged = "self, name, value",
   OnTooltipSetItem = "self",
}

-- Children that the Blizzard templates create (from memory of FrameXML 3.3.5a).
-- { type, "$parentSuffix" }
local BLIZZ_TEMPLATES = {
   OptionsSmallCheckButtonTemplate = { { "FontString", "$parentText" } },
   OptionsCheckButtonTemplate      = { { "FontString", "$parentText" } },
   UICheckButtonTemplate           = { { "FontString", "$parentText" } },
   OptionsBaseCheckButtonTemplate  = {},
   OptionsSliderTemplate = { { "FontString", "$parentText" }, { "FontString", "$parentLow" }, { "FontString", "$parentHigh" } },
   UIPanelButtonTemplate = { { "Texture", "$parentLeft" }, { "Texture", "$parentMiddle" }, { "Texture", "$parentRight" } },
   UIPanelCloseButton = {},
   UIDropDownMenuTemplate = { { "Texture", "$parentLeft" }, { "Texture", "$parentMiddle" }, { "Texture", "$parentRight" },
                              { "FontString", "$parentText" }, { "Button", "$parentButton" } },
   SpellBookSkillLineTabTemplate = {},
   SecureActionButtonTemplate = {},
   GameTooltipTemplate = (function()
      local t = {}
      for i = 1, 8 do
         t[#t + 1] = { "FontString", "$parentTextLeft" .. i }
         t[#t + 1] = { "FontString", "$parentTextRight" .. i }
      end
      return t
   end)(),
   FauxScrollFrameTemplate = { { "Slider", "$parentScrollBar" } },
   UIPanelScrollFrameTemplate = { { "Slider", "$parentScrollBar" } },
   -- font objects (used as inherits= on FontStrings)
   GameFontNormal = {}, GameFontNormalSmall = {}, GameFontNormalLarge = {}, GameFontHighlight = {},
   GameFontHighlightSmall = {}, GameFontDisableSmall = {}, GameFontRedSmall = {}, GameFontGreenSmall = {},
}

-- ---------------------------------------------------------------------------
-- creation
-- ---------------------------------------------------------------------------

function M.new(opts)
   opts = opts or {}
   local self = setmetatable({}, Env)
   self.opts = opts
   self.repo = assert(opts.repo, "opts.repo required")
   self.locale = opts.locale or "enUS"
   self.addon = opts.addon or "FishingBuddy"
   -- BOM policy for .lua files: "reject" mimics what I recall of the 3.3.5a
   -- client (syntax error at line 1, file not executed) -- UNVERIFIED --,
   -- "strip" mimics a client that tolerates a UTF-8 BOM.
   self.bom = opts.bom or "reject"
   -- the 3.3.5a client still provides the legacy globals this/event/arg1..arg9 in
   -- XML and Lua script handlers -- UNVERIFIED from here, hence switchable.
   self.legacy_globals = (opts.legacy_globals ~= false)
   self.now = opts.start_time or 1000.0
   self.errors = {}           -- { context=, message=, trace= }
   self.sent = {}             -- SendChatMessage calls { text, chattype, language, target, t }
   self.chat = {}             -- DEFAULT_CHAT_FRAME:AddMessage lines
   self.chat_filters = {}     -- event -> { filter functions }  (ChatFrame_AddMessageEventFilter)
   self.chat_display = {}     -- chat events that were shown (Env:chat_event)
   self.chat_hidden = {}      -- chat events a filter hid
   self.timers = {}
   self.log = {}              -- load log
   self.unmodelled = {}       -- [ "Frame:SetFoo" ] = n   widget methods the harness ignores
   self.undefined_reads = {}  -- [ name ] = n  reads of undefined globals (only if strict_globals)
   self.frames = {}           -- all frames in creation order
   self.templates = {}        -- XML virtual templates
   self.state = setmetatable({}, { __mode = "k" })
   self.files_loaded = {}
   self.files_failed = {}
   self.world = M.default_world(self)
   self.mt = make_widget_mt(self)
   if opts.world then for k, v in pairs(opts.world) do self.world[k] = v end end
   self:build_env()
   return self
end

function M.default_world(env)
   return {
      name = "Testchar", realm = "TestRealm", class = "WARRIOR", level = 80,
      zone = "Stranglethorn Vale", subzone = "Booty Bay",
      dead = false, combat = false, mounted = false,
      pole_equipped = true,            -- Fishing Pole (6256) in the main hand
      pole_item_cached = true,         -- does GetItemInfo(6256) work without a server round trip?
      lure_seconds = 0,                -- main hand enchant expiry in seconds (0 = none)
      free_slots = { [0] = 12, 12, 12, 12, 12 },   -- per bag 0..4
      fishing_skill = 300, fishing_mod = 0, fishing_max = 450,
      bags_have_lure = false,
      game_hour = 12, game_minute = 0,
      cvars = {},
      money = 12345,
   }
end

-- ---------------------------------------------------------------------------
-- errors
-- ---------------------------------------------------------------------------

function Env:record_error(context, message, trace)
   self.errors[#self.errors + 1] = { context = context, message = tostring(message), trace = trace }
end

-- run f(...) under xpcall; errors are recorded (never swallowed silently)
function Env:call(context, f, ...)
   -- Lua 5.1's xpcall passes no arguments, so close over them
   local n, args = select("#", ...), { ... }
   local ok, a, b, c, d = xpcall(function() return f(unpack(args, 1, n)) end, traceback)
   if not ok then
      local msg = tostring(a)
      local first = msg:match("^(.-)\nstack traceback:") or msg
      self:record_error(context, first, msg)
      return false
   end
   return true, a, b, c, d
end

-- ---------------------------------------------------------------------------
-- loading Lua
-- ---------------------------------------------------------------------------

local BOM = "\239\187\191"

-- Loads and runs one Lua file the way the client does.
function Env:load_lua(path, context)
   local rel = path:sub(#self.repo + 2)
   if self.opts.fail_files and self.opts.fail_files[rel] then
      self:record_error((context or rel) .. " [injected failure]", rel .. ": injected load failure (what-if: file missing/incompatible)")
      self.files_failed[rel] = "injected"
      return false
   end
   local src, err = readfile(path)
   if not src then
      self:record_error(context or rel, "cannot open file: " .. tostring(err))
      self.files_failed[rel] = "missing"
      return false
   end
   if src:sub(1, 3) == BOM then
      self.bom_files = self.bom_files or {}
      self.bom_files[rel] = true
      if self.bom == "reject" then
         local msg = rel .. ":1: unexpected symbol near '<\\239>'"
         self:record_error((context or rel) .. " [BOM, bom=reject]", msg)
         self.files_failed[rel] = "BOM"
         return false
      end
      src = src:sub(4)
   end
   local fn, serr = loadstring(src, "@" .. rel)
   if not fn then
      self:record_error(context or rel, serr)
      self.files_failed[rel] = "syntax"
      return false
   end
   setfenv(fn, self.G)
   self.files_loaded[#self.files_loaded + 1] = rel
   local ok = self:call("load " .. rel, fn, self.addon, self.addon_table)
   if not ok then self.files_failed[rel] = self.files_failed[rel] or "runtime" end
   return ok
end

-- ---------------------------------------------------------------------------
-- widgets
-- ---------------------------------------------------------------------------

local Widget = {}      -- methods (shared); every Env has its own metatable carrying `env`

local function E(o) return getmetatable(o).env end
local function S(o) return E(o).state[o] end

function Env:new_widget(kind, name, parent, opts)
   local o = {}
   setmetatable(o, self.mt)
   local st = {
      env = self, kind = kind, name = name, parent = parent, scripts = {}, hooks = {}, events = {},
      shown = true, text = "", checked = nil, value = 0, min = 0, max = 1, id = 0, enabled = true,
      width = 0, height = 0, level = 1, attrs = {}, children = {}, regions = {}, points = {}, alpha = 1,
      is_region = (kind == "Texture" or kind == "FontString"),
   }
   if kind == "FontString" then st.shown = true end
   self.state[o] = st
   if parent and self.state[parent] then
      local pst = self.state[parent]
      if st.is_region then pst.regions[#pst.regions + 1] = o else pst.children[#pst.children + 1] = o end
   end
   if name and name ~= "" then self.G[name] = o end
   if not st.is_region then self.frames[#self.frames + 1] = o end
   if kind == "Button" or kind == "CheckButton" then st.clicks = {} end
   return o
end

-- is this frame visible (shown and all parents shown)?
local function is_visible(env, o)
   local st = env.state[o]
   while st do
      if not st.shown then return false end
      local p = st.parent
      if not p then return true end
      st = env.state[p]
   end
   return true
end

-- run a script handler of frame `o` (if any), with the legacy globals if enabled
function Env:run_script(o, name, ...)
   local st = self.state[o]
   local fn = st.scripts[name]
   local hooks = st.hooks[name]
   if not fn and not hooks then return end
   local G = self.G
   local saved
   if self.legacy_globals then
      saved = { this = G.this, event = G.event, arg1 = G.arg1, arg2 = G.arg2, arg3 = G.arg3, arg4 = G.arg4, arg5 = G.arg5 }
      G.this = o
      if name == "OnEvent" then
         local ev, a1, a2, a3, a4, a5 = ...
         G.event = ev
         G.arg1, G.arg2, G.arg3, G.arg4, G.arg5 = a1, a2, a3, a4, a5
      elseif name == "OnUpdate" then
         G.arg1 = (...)
      elseif name == "OnClick" then
         G.arg1 = (...)
      else
         G.arg1 = (...)
      end
   end
   local ctx = ("%s of %s"):format(name, st.name or ("<anonymous " .. st.kind .. ">"))
   if name == "OnEvent" then ctx = ctx .. " (" .. tostring((...)) .. ")" end
   local result
   if fn then
      local _, r = self:call(ctx, fn, o, ...)
      result = r
   end
   if hooks then
      for _, h in ipairs(hooks) do self:call(ctx .. " [hook]", h, o, ...) end
   end
   if saved then
      for k, v in pairs(saved) do G[k] = v end
      G.this = saved.this
   end
   return result
end

local function unmodelled(env, kind, key)
   local k = kind .. ":" .. key
   env.unmodelled[k] = (env.unmodelled[k] or 0) + 1
end

make_widget_mt = function(env)
   local mt = { env = env }
   mt.__index = function(o, key)
      local m = Widget[key]
      if m ~= nil then return m end
      -- A WoW *method* name we do not model is accepted and forgotten (counted in the gap
      -- report).  Script-handler names (OnMouseDown, PostClick ...) are NOT methods: on a real
      -- frame `frame.OnMouseDown` is nil, and the addon tests for that (TrapWorldMouse).
      if type(key) == "string" and key:match("^%u") and not key:match("^On%u") and not key:match("^Pre%u") and not key:match("^Post%u") then
         return function(self, ...)
            local st = env.state[self]
            unmodelled(env, st and st.kind or "?", key)
            return nil
         end
      end
      return nil
   end
   mt.__tostring = function(o)
      local st = env.state[o]
      return ("<%s %s>"):format(st and st.kind or "widget", st and st.name or "?")
   end
   return mt
end

function Widget.GetName(o) return S(o).name end
function Widget.GetObjectType(o) return S(o).kind end
function Widget.IsObjectType(o, t) return S(o).kind == t end
function Widget.GetParent(o) return S(o).parent end
function Widget.SetParent(o, p) S(o).parent = p end
function Widget.SetID(o, i) S(o).id = i end
function Widget.GetID(o) return S(o).id end
function Widget.GetChildren(o) return unpack(S(o).children) end
function Widget.GetRegions(o) return unpack(S(o).regions) end
function Widget.SetScript(o, name, fn) S(o).scripts[name] = fn end
function Widget.GetScript(o, name) return S(o).scripts[name] end
function Widget.HookScript(o, name, fn) local st = S(o); st.hooks[name] = st.hooks[name] or {}; table.insert(st.hooks[name], fn) end
function Widget.HasScript(o, name) return S(o).scripts[name] ~= nil end
function Widget.RegisterEvent(o, e) S(o).events[e] = true end
function Widget.UnregisterEvent(o, e) S(o).events[e] = nil end
function Widget.UnregisterAllEvents(o) S(o).events = {} end
function Widget.IsEventRegistered(o, e) return S(o).events[e] and 1 or nil end

function Widget.Show(o)
   local st = S(o)
   if st.shown then return end
   st.shown = true
   if st.is_region then return end
   local env = E(o)
   if is_visible(env, o) then
      env:run_script(o, "OnShow")
      for _, c in ipairs(st.children) do
         local cst = env.state[c]
         if cst.shown and is_visible(env, c) then env:run_script(c, "OnShow") end
      end
   end
end
function Widget.Hide(o)
   local st = S(o)
   if not st.shown then return end
   local env = E(o)
   local was_visible = is_visible(env, o)
   st.shown = false
   if st.is_region then return end
   if was_visible then
      env:run_script(o, "OnHide")
      for _, c in ipairs(st.children) do
         local cst = env.state[c]
         if cst.shown then env:run_script(c, "OnHide") end
      end
   end
end
function Widget.IsShown(o) return S(o).shown and 1 or nil end
function Widget.IsVisible(o) return is_visible(E(o), o) and 1 or nil end
function Widget.SetShown(o, v) if v then o:Show() else o:Hide() end end

function Widget.SetText(o, t) S(o).text = (t == nil) and "" or tostring(t) end
function Widget.GetText(o) return S(o).text end
function Widget.SetFormattedText(o, fmt, ...) S(o).text = string.format(fmt, ...) end
function Widget.GetStringWidth(o) return #S(o).text * 6 end
function Widget.GetStringHeight(o) return 12 end
function Widget.GetNormalFontObject(o) return E(o):new_widget("FontString", nil, o) end
function Widget.GetHighlightFontObject(o) return E(o):new_widget("FontString", nil, o) end
function Widget.GetDisabledFontObject(o) return E(o):new_widget("FontString", nil, o) end
function Widget.GetFontString(o) local st = S(o); return st.fontstring end
function Widget.SetChecked(o, v) S(o).checked = v and 1 or nil end
function Widget.GetChecked(o) return S(o).checked end
function Widget.Enable(o) S(o).enabled = true end
function Widget.Disable(o) S(o).enabled = false end
function Widget.IsEnabled(o) return S(o).enabled and 1 or nil end
function Widget.SetValue(o, v)
   local st = S(o)
   local changed = (st.value ~= v)
   st.value = v
   if changed then E(o):run_script(o, "OnValueChanged", v) end
end
function Widget.GetValue(o) return S(o).value end
function Widget.SetMinMaxValues(o, a, b) local st = S(o); st.min, st.max = a, b end
function Widget.GetMinMaxValues(o) local st = S(o); return st.min, st.max end
function Widget.SetWidth(o, w) S(o).width = w end
function Widget.SetHeight(o, h) S(o).height = h end
function Widget.SetSize(o, w, h) local st = S(o); st.width, st.height = w, h end
function Widget.GetWidth(o) return S(o).width end
function Widget.GetHeight(o) return S(o).height end
function Widget.GetFrameLevel(o) return S(o).level end
function Widget.SetFrameLevel(o, l) S(o).level = l end
function Widget.GetScale(o) return 1 end
function Widget.GetEffectiveScale(o) return 1 end
function Widget.GetAlpha(o) return S(o).alpha end
function Widget.SetAlpha(o, a) S(o).alpha = a end
function Widget.GetLeft(o) return 0 end
function Widget.GetRight(o) return 100 end
function Widget.GetTop(o) return 100 end
function Widget.GetBottom(o) return 0 end
function Widget.GetCenter(o) return 50, 50 end
function Widget.GetNumPoints(o) return #S(o).points end
function Widget.SetPoint(o, ...) local st = S(o); st.points[#st.points + 1] = { ... } end
function Widget.ClearAllPoints(o) S(o).points = {} end
function Widget.GetPoint(o, i) local p = S(o).points[i or 1]; if p then return unpack(p) end return "CENTER", nil, "CENTER", 0, 0 end
function Widget.SetAttribute(o, k, v) S(o).attrs[k] = v end
function Widget.GetAttribute(o, k) return S(o).attrs[k] end
function Widget.CreateTexture(o, name, layer, inherits)
   local t = E(o):new_widget("Texture", name, o)
   return t
end
function Widget.CreateFontString(o, name, layer, inherits)
   local t = E(o):new_widget("FontString", name, o)
   return t
end
function Widget.SetNormalTexture(o, tex) S(o).normaltexture = tex end
function Widget.GetNormalTexture(o) return E(o):new_widget("Texture", nil, o) end
function Widget.SetTexture(o, tex) S(o).texture = tex end
function Widget.GetTexture(o) return S(o).texture end
function Widget.GetNumLetters(o) return #S(o).text end
function Widget.SetFontObject(o, f) S(o).fontobject = f end
function Widget.IsMovable(o) return S(o).movable end
function Widget.SetMovable(o, v) S(o).movable = v end
function Widget.EnableMouse(o, v) S(o).mouse = v end
function Widget.IsMouseEnabled(o) return S(o).mouse end
function Widget.RegisterForClicks(o, ...) S(o).clicks = { ... } end
function Widget.RegisterForDrag(o, ...) S(o).drag = { ... } end
function Widget.GetNumRegions(o) return #S(o).regions end
-- tooltips
function Widget.SetOwner(o, owner, anchor) local st = S(o); st.owner = owner; st.lines = {} ; st.shown = false end
function Widget.AddLine(o, text) local st = S(o); st.lines = st.lines or {}; table.insert(st.lines, text) end
function Widget.AddDoubleLine(o, a, b) local st = S(o); st.lines = st.lines or {}; table.insert(st.lines, a) end
function Widget.ClearLines(o) S(o).lines = {} end
function Widget.NumLines(o) return #(S(o).lines or {}) end
function Widget.SetHyperlink(o, link) local st = S(o); st.lines = { link }; end
-- message frames (UIErrorsFrame)
function Widget.AddMessage(o, msg, ...)
   local env = E(o)
   local st = S(o)
   if st.name == "DEFAULT_CHAT_FRAME" or st.is_chat then env.chat[#env.chat + 1] = tostring(msg) end
end
-- edit boxes
function Widget.SetCursorPosition(o, n) end
function Widget.Insert(o, text) local st = S(o); st.text = st.text .. text end

-- ---------------------------------------------------------------------------
-- XML loading
-- ---------------------------------------------------------------------------

local function subst_name(name, parent_name)
   if not name then return nil end
   if name:find("$parent", 1, true) then
      return (name:gsub("%$parent", function() return parent_name or "" end))
   end
   return name
end

-- compile an XML handler body
function Env:compile_handler(name, body, where)
   local params = SCRIPT_PARAMS[name] or "self, ..."
   local src = "return function(" .. params .. ") " .. body .. "\n end"
   local chunk, err = loadstring(src, "=" .. where .. ":" .. name)
   if not chunk then
      self:record_error(where, "XML handler " .. name .. " does not compile: " .. tostring(err))
      return nil
   end
   setfenv(chunk, self.G)
   return chunk()
end

-- collect everything that a node (frame element or template) contributes.
function Env:collect_template(tname, out, seen)
   seen = seen or {}
   if seen[tname] then return end
   seen[tname] = true
   local def = self.templates[tname]
   if def then
      if def.attrs.inherits then
         for t in def.attrs.inherits:gmatch("[^,%s]+") do self:collect_template(t, out, seen) end
      end
      out[#out + 1] = { node = def, xml = true }
      return
   end
   local blizz = BLIZZ_TEMPLATES[tname]
   if blizz then
      out[#out + 1] = { blizz = blizz, name = tname }
      return
   end
   -- unknown template: the real client raises an error while parsing
   out[#out + 1] = { unknown = tname }
end

function Env:apply_children(frame, node, xmlfile, parent_name, handlers)
   -- walk the children of `node`, creating named/unnamed child frames and regions
   local fst = self.state[frame]
   for _, ch in ipairs(node.children) do
      local tag = ch.tag
      if tag == "Scripts" then
         for _, h in ipairs(ch.children) do
            handlers[h.tag] = { node = h, file = xmlfile }
         end
      elseif tag == "Frames" or tag == "Layers" or tag == "Layer" or tag == "ScrollChild" then
         self:apply_children(frame, ch, xmlfile, parent_name, handlers)
      elseif FRAME_TAGS[tag] then
         if ch.attrs.virtual ~= "true" then
            self:create_from_node(ch, frame, xmlfile)
         else
            self:register_template(ch)
         end
      elseif REGION_TAGS[tag] then
         local nm = subst_name(ch.attrs.name, parent_name)
         local r = self:new_widget(tag, nm, frame)
         if ch.attrs.hidden == "true" then self.state[r].shown = false end
         if ch.attrs.inherits then
            -- inherited font objects need nothing here
         end
      elseif TEXTURE_SLOT_TAGS[tag] then
         local nm = subst_name(ch.attrs.name, parent_name)
         if nm then
            local r = self:new_widget(TEXTURE_SLOT_TAGS[tag], nm, frame)
            if tag == "ButtonText" then fst.fontstring = r end
         end
      end
   end
end

function Env:register_template(node)
   if node.attrs.name then self.templates[node.attrs.name] = node end
end

function Env:create_from_node(node, parent, xmlfile, override_parent)
   local attrs = node.attrs
   local pname = parent and self.state[parent] and self.state[parent].name or nil
   local name = subst_name(attrs.name, pname)
   local parent_frame = parent
   if attrs.parent then
      parent_frame = self.G[attrs.parent]
      if parent_frame == nil then
         self:record_error(xmlfile, ("frame '%s': parent '%s' does not exist at this point"):format(tostring(name), attrs.parent))
         parent_frame = self.G.UIParent
      end
   end
   local kind = node.tag
   if kind == "Checkbutton" then kind = "CheckButton" end
   local frame = self:new_widget(kind, name, parent_frame)
   local st = self.state[frame]
   if kind == "GameTooltip" then st.shown = false end

   local handlers = {}
   local hidden = (attrs.hidden == "true")

   -- templates first (in order), then the node's own contents
   local contribs = {}
   if attrs.inherits then
      for t in attrs.inherits:gmatch("[^,%s]+") do self:collect_template(t, contribs) end
   end
   for _, c in ipairs(contribs) do
      if c.unknown then
         self:record_error(xmlfile or "?", ("frame '%s': inherited template '%s' does not exist (client: 'Couldn't find inherited node')"):format(tostring(name), c.unknown))
      elseif c.blizz then
         for _, ch in ipairs(c.blizz) do
            local nm = subst_name(ch[2], name)
            local r = self:new_widget(ch[1], nm, frame)
         end
      else
         local tnode = c.node
         if tnode.attrs.hidden == "true" then hidden = true end
         self:apply_children(frame, tnode, xmlfile, name, handlers)
      end
   end
   self:apply_children(frame, node, xmlfile, name, handlers)

   if attrs.hidden == "false" then hidden = false end
   if hidden then st.shown = false end
   if kind == "GameTooltip" then st.shown = false end

   -- compile & install handlers (own overrides template)
   for hname, h in pairs(handlers) do
      local hn = h.node
      local fn
      if hn.attrs["function"] then
         local f = self.G[hn.attrs["function"]]
         if type(f) ~= "function" then
            self:record_error(h.file or xmlfile or "?", ("frame '%s': %s function=\"%s\" is not a function at load time (%s)"):format(
               tostring(name), hname, hn.attrs["function"], type(f)))
         else
            fn = f
         end
      elseif hn.attrs.method then
         local mname = hn.attrs.method
         fn = function(self_, ...) return self_[mname](self_, ...) end
      elseif hn.text and hn.text:find("%S") then
         fn = self:compile_handler(hname, hn.text, (h.file or xmlfile or "?") .. "#" .. tostring(name or "?"))
      end
      if fn then st.scripts[hname] = fn end
   end

   -- OnLoad fires after the frame (and its XML children) exist
   if st.scripts.OnLoad then self:run_script(frame, "OnLoad") end
   return frame
end

function Env:load_xml(path, context)
   local rel = path:sub(#self.repo + 2)
   local src, err = readfile(path)
   if not src then
      self:record_error(context or rel, "cannot open file: " .. tostring(err))
      self.files_failed[rel] = "missing"
      return false
   end
   local ok, root = pcall(xmlparse.parse, src)
   if not ok then
      self:record_error(context or rel, "XML parse error: " .. tostring(root))
      self.files_failed[rel] = "xml"
      return false
   end
   self.files_loaded[#self.files_loaded + 1] = rel
   local dir = dirname(path)
   local function walk(node)
      for _, ch in ipairs(node.children) do
         local tag = ch.tag
         if tag == "Script" then
            if ch.attrs.file then
               self:load_lua(dir .. "/" .. norm(ch.attrs.file), rel)
            elseif ch.text:find("%S") then
               local fn, serr = loadstring(ch.text, "=" .. rel .. ":inline")
               if fn then setfenv(fn, self.G); self:call(rel .. " inline <Script>", fn) else self:record_error(rel, serr) end
            end
         elseif tag == "Include" then
            self:load_xml(dir .. "/" .. norm(ch.attrs.file), rel)
         elseif FRAME_TAGS[tag] then
            if ch.attrs.virtual == "true" then
               self:register_template(ch)
            else
               self:create_from_node(ch, nil, rel)
            end
         elseif REGION_TAGS[tag] and ch.attrs.virtual == "true" then
            self:register_template(ch)
         end
      end
   end
   walk(root)
   return true
end

-- ---------------------------------------------------------------------------
-- TOC
-- ---------------------------------------------------------------------------

function Env:parse_toc(addon)
   local path = self.repo .. "/" .. addon .. ".toc"
   local src = readfile(path)
   assert(src, "cannot read " .. path)
   local meta, files = {}, {}
   local unterminated = (src:sub(-1) ~= "\n")
   if src:sub(1, 3) == BOM then src = src:sub(4) end
   for line in (src .. "\n"):gmatch("([^\r\n]*)\r?\n") do
      local k, v = line:match("^##%s*([%w%-]+)%s*:%s*(.-)%s*$")
      if k then
         meta[k] = v
      elseif not line:match("^%s*#") and line:match("%S") then
         files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""))
      end
   end
   -- Option toc_last_line="drop": model a client that ignores a final TOC line that has no line
   -- terminator.  UNVERIFIED -- I recall this gotcha from the modding community but could not
   -- confirm it for build 12340 offline.  Default "read" = the client processes it.
   if unterminated and #files > 0 then
      self.toc_unterminated_last = files[#files]
      if self.opts.toc_last_line == "drop" then
         self.toc_dropped = table.remove(files)
      end
   end
   return meta, files
end

function Env:load_addon(addon)
   addon = addon or self.addon
   local meta, files = self:parse_toc(addon)
   self.toc_meta = meta
   self.toc_files = files
   self.addon_table = {}
   self.loading = true
   for _, f in ipairs(files) do
      local p = self.repo .. "/" .. norm(f)
      local lower = f:lower()
      if lower:match("%.lua$") then
         self:load_lua(p, f)
      elseif lower:match("%.xml$") then
         self:load_xml(p, f)
      else
         self:record_error("TOC", "unknown file type in TOC: " .. f)
      end
   end
   self.loading = false
   self:apply_saved()
end

-- ---------------------------------------------------------------------------
-- event & time driving
-- ---------------------------------------------------------------------------

function Env:fire(event, ...)
   local snapshot = {}
   for i, f in ipairs(self.frames) do snapshot[i] = f end
   for _, f in ipairs(snapshot) do
      local st = self.state[f]
      if st.events[event] and st.scripts.OnEvent then
         self:run_script(f, "OnEvent", event, ...)
      end
   end
end

-- timers (used by the fake server to deliver replies after a latency)
function Env:after(delay, fn)
   self.timers = self.timers or {}
   self.timers[#self.timers + 1] = { at = self.now + delay, fn = fn }
end

local function run_timers(self)
   while true do
      local best
      for i, t in ipairs(self.timers or {}) do
         if t.at <= self.now + 1e-9 and (not best or t.at < self.timers[best].at) then best = i end
      end
      if not best then return end
      local t = table.remove(self.timers, best)
      self:call("timer", t.fn)
   end
end

-- A chat line arrives: the event reaches every frame (filters do not stop events), and
-- the chat window shows the line unless a message-event filter hides it.
-- Returns true when the line was displayed.
function Env:chat_event(event, ...)
   self:fire(event, ...)
   local hidden = false
   for _, fn in ipairs(self.chat_filters[event] or {}) do
      local ok, res = pcall(fn, self.G.ChatFrame1, event, ...)
      if not ok then self:record_error("chat filter " .. event, res, nil)
      elseif res then hidden = true; break end
   end
   local msg = select(1, ...)
   if hidden then
      self.chat_hidden[#self.chat_hidden + 1] = event .. ": " .. tostring(msg)
   else
      self.chat_display[#self.chat_display + 1] = event .. ": " .. tostring(msg)
   end
   return not hidden
end

function Env:advance(seconds, step)
   step = step or 0.1
   local done = 0
   while done < seconds - 1e-9 do
      local d = math.min(step, seconds - done)
      self.now = self.now + d
      done = done + d
      run_timers(self)
      local snapshot = {}
      for i, f in ipairs(self.frames) do snapshot[i] = f end
      for _, f in ipairs(snapshot) do
         local st = self.state[f]
         if st.scripts.OnUpdate and is_visible(self, f) then
            self:run_script(f, "OnUpdate", d)
         end
      end
   end
end

function Env:clear_sent() self.sent = {} end

-- convenience: run a slash command as the chat box would
function Env:slash(line)
   local cmd, rest = line:match("^(/%S+)%s*(.*)$")
   local G = self.G
   for key, fn in pairs(G.SlashCmdList) do
      local i = 1
      while G["SLASH_" .. key .. i] do
         if G["SLASH_" .. key .. i]:lower() == cmd:lower() then
            self:call("slash " .. line, fn, rest)
            return true
         end
         i = i + 1
      end
   end
   self.chat[#self.chat + 1] = "[harness] unknown slash command: " .. line
   return false
end

-- ---------------------------------------------------------------------------
-- the global environment (WoW API stubs)
-- ---------------------------------------------------------------------------

local ITEMS = {
   -- id = { name, rarity, ilvl, minlevel, type, subtype, stack, equiploc, texture, sellprice }
   [6256]  = { "Fishing Pole", 1, 5, 0, "Weapon", "Fishing Poles", 1, "INVTYPE_2HWEAPON", "Interface\\Icons\\INV_Fishingpole_01", 10 },
   [45858] = { "Nat's Lucky Fishing Pole", 3, 80, 0, "Weapon", "Fishing Poles", 1, "INVTYPE_2HWEAPON", "Interface\\Icons\\INV_Fishingpole_03", 10 },
   [6529]  = { "Shiny Bauble", 1, 5, 0, "Trade Goods", "Other", 20, "", "Interface\\Icons\\INV_Misc_Orb_03", 5 },
   [6532]  = { "Bright Baubles", 1, 5, 0, "Trade Goods", "Other", 20, "", "Interface\\Icons\\INV_Misc_Orb_03", 5 },
   [13754] = { "Raw Glossy Mightfish", 1, 40, 0, "Trade Goods", "Meat", 20, "", "Interface\\Icons\\INV_Misc_Fish_02", 50 },
   [6358]  = { "Oily Blackmouth", 1, 20, 0, "Trade Goods", "Meat", 20, "", "Interface\\Icons\\INV_Misc_Fish_06", 20 },
}
M.ITEMS = ITEMS

local function itemlink(id)
   local it = ITEMS[id]
   local name = it and it[1] or ("item" .. id)
   local color = ({ [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee" })[it and it[2] or 1] or "ffffffff"
   return ("|c%s|Hitem:%d:0:0:0:0:0:0:0:80|h[%s]|h|r"):format(color, id, name)
end

function Env:build_env()
   local env = self
   local W = self.world
   local G = {}
   self.G = G
   -- standard Lua 5.1 + WoW aliases ------------------------------------------------
   for _, k in ipairs{ "assert", "collectgarbage", "error", "getfenv", "getmetatable", "ipairs", "loadstring", "next", "pairs",
                       "pcall", "rawequal", "rawget", "rawset", "select", "setfenv", "setmetatable", "tonumber", "tostring",
                       "type", "unpack", "xpcall", "string", "table", "math", "os", "io", "debug", "coroutine", "loadfile", "dofile", "newproxy" } do
      G[k] = _G[k]
   end
   local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
   G.string, G.table, G.math = copy(string), copy(table), copy(math)
   G._G = G
   G.getfenv = function(f)
      if f == nil or f == 0 or f == 1 then return G end
      if type(f) == "function" then return getfenv(f) end
      return G
   end
   G._VERSION = _VERSION
   G.os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime }   -- no os.execute etc. for addons
   G.io = nil; G.debug = nil; G.dofile = nil; G.loadfile = nil
   G.format, G.gsub, G.strbyte, G.strchar, G.strfind, G.strlen = string.format, string.gsub, string.byte, string.char, string.find, string.len
   G.strlower, G.strmatch, G.strrep, G.strsub, G.strupper, G.strrev = string.lower, string.match, string.rep, string.sub, string.upper, string.reverse
   G.gmatch = string.gmatch
   G.tinsert, G.tremove, G.sort, G.getn, G.wipe = table.insert, table.remove, table.sort, table.getn, function(t) for k in pairs(t) do t[k] = nil end return t end
   G.table.wipe = G.wipe
   G.abs, G.ceil, G.floor, G.max, G.min, G.sqrt, G.sin, G.cos, G.tan = math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt, math.sin, math.cos, math.tan
   G.mod, G.random, G.randomseed, G.log, G.exp = math.fmod, math.random, math.randomseed, math.log, math.exp
   G.deg = math.deg; G.rad = math.rad; G.atan2 = math.atan2; G.atan = math.atan; G.asin = math.asin; G.acos = math.acos; G.log10 = math.log10
   G.date, G.time, G.difftime = os.date, os.time, os.difftime
   G.strtrim = function(s, chars) chars = chars or "%s"; return (s:gsub("^[" .. chars .. "]+", ""):gsub("[" .. chars .. "]+$", "")) end
   G.strsplit = function(delim, str, pieces)
      local out, pos = {}, 1
      while true do
         if pieces and #out >= pieces - 1 then out[#out + 1] = str:sub(pos) break end
         local s, e = str:find(delim, pos, true)
         if not s then out[#out + 1] = str:sub(pos) break end
         out[#out + 1] = str:sub(pos, s - 1); pos = e + 1
      end
      return unpack(out)
   end
   G.strjoin = function(delim, ...) return table.concat({ ... }, delim) end
   G.bit = { band = function(a, b) local r, p = 0, 1; while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2 end return r end,
             bor = function(a, b) local r, p = 0, 1; while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + p end a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2 end return r end,
             lshift = function(a, n) return a * 2 ^ n end, rshift = function(a, n) return math.floor(a / 2 ^ n) end }
   -- loadstring() chunks run in the global environment of the *client*, i.e. our G
   G.loadstring = function(src, name)
      local f, e = loadstring(src, name)
      if f then setfenv(f, G) end
      return f, e
   end
   G.getglobal = function(n) return G[n] end
   G.setglobal = function(n, v) G[n] = v end
   G.geterrorhandler = function() return function(e) env:record_error("errorhandler", e) end end
   G.seterrorhandler = function() end
   G.debugstack = function() return debug.traceback() end
   G.issecurevariable = function() return nil end
   G.securecall = function(f, ...) if type(f) == "string" then f = G[f] end return f(...) end
   G.hooksecurefunc = function(a, b, c)
      local tbl, name, fn
      if type(a) == "table" then tbl, name, fn = a, b, c else tbl, name, fn = G, a, b end
      local orig = tbl[name]
      if type(orig) ~= "function" then error("hooksecurefunc: hook failed: " .. tostring(name) .. " is not a function (" .. type(orig) .. ")") end
      tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
   end
   G.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end env.chat[#env.chat + 1] = table.concat(t, " ") end

   -- game constants / global strings ----------------------------------------------
   G.UNKNOWN = "Unknown"; G.UNKNOWNOBJECT = "Unknown"; G.UKNOWNBEING = "Unknown Being"
   G.NONE = "None"; G.GENERAL = "General"; G.SAVE = "Save"; G.RESET = "Reset"
   G.GUILD_BANK_TAB_INFO = "Tab Info"
   -- ASSUMPTION: the 3.3.5a client defines NONE_KEY (FishingOutfitManager.lua and LibFishing use it).
   -- Not verifiable offline; set opts.no_none_key = true to model its absence.
   if not self.opts.no_none_key then G.NONE_KEY = "None" end
   G.MAX_PLAYER_LEVEL = 80; G.EQUIPMENT_MANAGER = "Equipment Manager"
   G.NUM_BAG_SLOTS = 4; G.NUM_CHAT_WINDOWS = 10; G.BACKPACK_CONTAINER = 0
   G.BOOKTYPE_SPELL = "spell"
   G.SPELL_FAILED_FISHING_TOO_LOW = "Fishing skill not high enough. You need %d."
   G.SPELL_FAILED_LOW_CASTLEVEL = "Skill not high enough"
   G.ERR_FISH_ESCAPED = "Your fish got away."
   G.UIERRORS_HOLD_TIME = 5
   G.MYADDONS_CATEGORY_PROFESSIONS = "Professions"
   G.NORMAL_FONT_COLOR = { r = 1.0, g = 0.82, b = 0.0 }
   G.GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
   G.TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
   G.TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0.09, g = 0.09, b = 0.19 }
   G.ITEM_QUALITY_COLORS = {}
   for i = 0, 6 do G.ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
   G.ITEM_BIND_QUEST = "Quest Item"
   G.PET_TYPE_PET = "Pet"; G.SKILL = "Skill"
   G.UISpecialFrames = {}; G.UIPanelWindows = {}
   G.StaticPopupDialogs = {}
   G.SlashCmdList = {}
   G.CHAT_MSG_SKILL = "CHAT_MSG_SKILL"
   G.SPELL_FAILED_TRY_AGAIN = "Failed attempt. Try again."

   -- frames provided by FrameXML ---------------------------------------------------
   G.UIParent = self:new_widget("Frame", "UIParent", nil)
   G.WorldFrame = self:new_widget("Frame", "WorldFrame", nil)
   G.Minimap = self:new_widget("Minimap", "Minimap", G.UIParent)
   G.UIErrorsFrame = self:new_widget("MessageFrame", "UIErrorsFrame", G.UIParent)
   -- GameTooltip with its text lines
   G.GameTooltip = self:new_widget("GameTooltip", "GameTooltip", G.UIParent)
   self.state[G.GameTooltip].shown = false
   for i = 1, 8 do
      self:new_widget("FontString", "GameTooltipTextLeft" .. i, G.GameTooltip)
      self:new_widget("FontString", "GameTooltipTextRight" .. i, G.GameTooltip)
   end
   -- chat
   G.DEFAULT_CHAT_FRAME = self:new_widget("MessageFrame", "DEFAULT_CHAT_FRAME", G.UIParent)
   self.state[G.DEFAULT_CHAT_FRAME].is_chat = true
   G.ChatFrame1 = G.DEFAULT_CHAT_FRAME
   G.ChatFrameEditBox = self:new_widget("EditBox", "ChatFrameEditBox", G.UIParent)
   self.state[G.ChatFrameEditBox].shown = false
   G.DEFAULT_CHAT_FRAME.editBox = G.ChatFrameEditBox
   for i = 1, 10 do
      local t = self:new_widget("Button", "ChatFrame" .. i .. "Tab", G.UIParent)
      self.state[t].text = (i == 1) and "General" or ""
   end
   G.ChatEdit_SendText = function(edit, addHistory)
      env.sent_by_chatbox = env.sent_by_chatbox or {}
      table.insert(env.sent_by_chatbox, edit:GetText())
   end
   -- microbuttons & panel helpers
   G.UpdateMicroButtons = function() end
   G.ShowUIPanel = function(f) if f then f:Show() end end
   G.HideUIPanel = function(f) if f then f:Hide() end end
   G.PanelTemplates_SetNumTabs = function() end
   G.PanelTemplates_SetTab = function() end
   G.PanelTemplates_TabResize = function() end
   G.PanelTemplates_Tab_OnClick = function() end
   G.UIDropDownMenu_SetWidth = function() end
   G.UIDropDownMenu_SetSelectedValue = function() end
   G.UIDropDownMenu_SetText = function() end
   G.UIDropDownMenu_AddButton = function() end
   G.UIDropDownMenu_Initialize = function() end
   G.ToggleDropDownMenu = function() end
   G.UIFrameFadeIn = function() end; G.UIFrameFadeOut = function() end
   G.UIFrameIsFading = function() return false end
   G.FauxScrollFrame_GetOffset = function() return 0 end
   G.FauxScrollFrame_Update = function() end
   G.PlaySound = function(name) env.sounds = env.sounds or {}; table.insert(env.sounds, name) end
   G.GameTooltip_AddNewbieTip = function() end
   G.MouseIsOver = function() return false end
   G.StaticPopup_Show = function() end

   -- time -------------------------------------------------------------------------
   -- During addon loading, time creeps forward on every call: LibTourist busy-waits on
   -- GetTime() (repeat ... until finish < GetTime()) while probing the world map.
   G.GetTime = function()
      if env.loading then env.now = env.now + 0.001 end
      return env.now
   end
   G.GetGameTime = function() return W.game_hour, W.game_minute end
   G.CalendarGetDate = function() return 7, 10, 13, 2026 end

   -- client / addon info -----------------------------------------------------------
   G.GetLocale = function() return env.locale end
   G.GetBuildInfo = function() return "3.3.5", "12340", "Mar 15 2011", 30300 end
   G.GetRealmName = function() return W.realm end
   G.GetAddOnMetadata = function(addon, field)
      if addon == env.addon and env.toc_meta then
         return env.toc_meta[field]
      end
   end
   G.GetAddOnInfo = function(name)
      -- name, title, notes, enabled, loadable, reason, security
      if name == env.addon then return name, name, "", 1, 1, nil, "INSECURE" end
      return name, name, "", nil, nil, "MISSING", "INSECURE"
   end
   G.IsAddOnLoaded = function(name) return name == env.addon and true or nil end
   G.GetCVar = function(k) return W.cvars[k] or "0" end
   G.SetCVar = function(k, v) W.cvars[k] = tostring(v) end

   -- player / unit ----------------------------------------------------------------
   G.UnitName = function(u) if u == "player" then return W.name end return nil end
   G.UnitClass = function() return "Warrior", W.class end
   G.UnitRace = function() return "Human", "Human" end
   G.UnitFactionGroup = function() return "Alliance", "Alliance" end
   G.UnitSex = function() return 2 end
   G.UnitLevel = function() return W.level end
   G.UnitIsDeadOrGhost = function() return W.dead and 1 or nil end
   G.UnitAffectingCombat = function() return W.combat and 1 or nil end
   G.InCombatLockdown = function() return W.combat and 1 or nil end
   G.UnitCastingInfo = function() return nil end
   G.UnitBuff = function() return nil end
   G.IsMounted = function() return W.mounted end
   G.IsFlying = function() return false end
   G.IsMouselooking = function() return false end
   G.MouselookStop = function() end
   G.IsShiftKeyDown = function() return nil end
   G.IsControlKeyDown = function() return nil end
   G.IsAltKeyDown = function() return nil end
   G.GetCursorPosition = function() return 0, 0 end
   G.GetScreenWidth = function() return 1024 end
   G.GetPlayerFacing = function() return 0 end
   G.GetPlayerMapPosition = function() return 0, 0 end
   G.GetMoney = function() return W.money end
   G.GetRealZoneText = function() return W.zone end
   G.GetZoneText = function() return W.zone end
   G.GetSubZoneText = function() return W.subzone end
   G.GetPVPDesired = function() return nil end
   G.SetPVP = function() end

   -- map (Astrolabe / LibTourist need these, return a tiny but consistent world)
   G.GetMapContinents = function() return end   -- no map data: keeps Astrolabe/LibTourist from probing a fake world
   G.GetMapZones = function(c) return "Zone" .. c end
   G.SetMapZoom = function() end
   G.SetMapToCurrentZone = function() end
   G.GetCurrentMapContinent = function() return 2 end
   G.GetCurrentMapZone = function() return 1 end
   G.GetCurrentMapAreaID = function() return 0 end
   G.SetMapByID = function() end
   G.GetNumMapOverlays = function() return 0 end
   G.GetMapInfo = function() return "StranglethornVale" end
   G.UpdateMapHighlight = function() return nil end
   G.IsLoggedIn = function() return env.logged_in and true or false end
   G.GetNumMapLandmarks = function() return 0 end
   G.WorldMapFrame = self:new_widget("Frame", "WorldMapFrame", G.UIParent); self.state[G.WorldMapFrame].shown = false
   G.WorldMapButton = self:new_widget("Button", "WorldMapButton", G.WorldMapFrame)

   -- tracking (FishLib:GetTrackingID) ----------------------------------------------
   G.GetNumTrackingTypes = function() return 0 end
   G.GetTrackingInfo = function() return nil end
   G.GetTrackingTexture = function() return nil end
   G.SetTracking = function() end

   -- companions
   G.GetNumCompanions = function() return 0 end
   G.GetCompanionInfo = function() return nil end
   G.CallCompanion = function() end; G.DismissCompanion = function() end

   -- equipment sets / outfitter: absent (like a client without Outfitter)
   G.GetNumEquipmentSets = function() return 0 end
   G.GetEquipmentSetInfo = function() return nil end
   G.GetEquipmentSetInfoByName = function() return nil end
   G.GetEquipmentSetLocations = function() return nil end
   G.SaveEquipmentSet = function() end; G.DeleteEquipmentSet = function() end
   G.EquipmentManager_EquipSet = function() end
   G.EquipItemByName = function() end

   -- chat ---------------------------------------------------------------------------
   G.SendChatMessage = function(text, chattype, language, target)
      local entry = { text = text, chattype = chattype, language = language, target = target, t = env.now }
      env.sent[#env.sent + 1] = entry
      if env.on_send then env.on_send(entry) end
   end
   G.GetNumPartyMembers = function() return W.party or 0 end
   G.GetNumRaidMembers = function() return W.raid or 0 end
   G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
   G.ChatFrame_AddMessageEventFilter = function(event, fn)
      env.chat_filters[event] = env.chat_filters[event] or {}
      table.insert(env.chat_filters[event], fn)
   end
   G.ChatFrame_RemoveMessageEventFilter = function(event, fn)
      local list = env.chat_filters[event] or {}
      for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
   end

   -- items / inventory ------------------------------------------------------------
   local MAINHAND = 16
   G.GetInventorySlotInfo = function(slot)
      local ids = { MainHandSlot = 16, SecondaryHandSlot = 17, HeadSlot = 1 }
      return ids[slot] or 0, "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand"
   end
   G.GetInventoryItemLink = function(unit, slot)
      if unit == "player" and slot == MAINHAND and W.pole_equipped then
         return itemlink(W.pole_id or 6256)
      end
      return nil
   end
   G.GetItemInfo = function(x)
      local id
      if type(x) == "number" then id = x
      elseif type(x) == "string" then id = tonumber(x:match("item:(%d+)")) or tonumber(x:match("^(%d+)$")) end
      if not id then return nil end
      local it = ITEMS[id]
      if not it then return nil end
      if id == 6256 and not W.pole_item_cached and not (W.pole_equipped and type(x) == "string" and x:find("|H")) then
         return nil   -- not in the client cache
      end
      return it[1], itemlink(id), it[2], it[3], it[4], it[5], it[6], it[7], it[8], it[9], it[10]
   end
   G.GetItemQualityColor = function(q) return 1, 1, 1, "|cffffffff" end
   G.GetItemCount = function(id) if W.bags_have_lure and (id == 6529 or id == 6532) then return 5 end return 0 end
   G.GetItemCooldown = function() return 0, 0, 1 end
   G.GetContainerNumFreeSlots = function(bag) return W.free_slots[bag] or 0, 0 end
   G.GetContainerNumSlots = function(bag) return 16 end
   G.GetContainerItemLink = function() return nil end
   G.GetWeaponEnchantInfo = function()
      if W.lure_seconds and W.lure_seconds > 0 then return 1, W.lure_seconds * 1000, 0, nil, nil, nil end
      return nil
   end

   -- spells & skills -------------------------------------------------------------
   local function fishing_name() return ({ enUS = "Fishing", deDE = "Angeln" })[env.locale] or "Fishing" end
   G.GetSpellTexture = function(id, book) if id == 1 then return "Interface\\Icons\\Trade_Fishing" end return nil end
   G.GetSpellName = function(id, book) if id == 1 then return fishing_name(), "Apprentice" end return nil end
   G.GetNumSkillLines = function() return 2 end
   G.GetSkillLineInfo = function(i)
      if i == 1 then return "Professions", 1, 1, 0, 0, 0, 0, nil end
      if i == 2 then return fishing_name(), nil, nil, W.fishing_skill, 0, W.fishing_mod, W.fishing_max end
   end
   G.HasAction = function() return nil end
   G.IsAttackAction = function() return nil end
   G.GetActionInfo = function() return nil end
   G.GetActionTexture = function() return nil end

   -- loot (used by the simulated catch) -----------------------------------------
   G.IsFishingLoot = function() return env.world.loot_is_fishing and 1 or nil end
   G.GetNumLootItems = function() return env.world.loot and #env.world.loot or 0 end
   G.LootSlotIsItem = function(i) return env.world.loot and env.world.loot[i] and 1 or nil end
   G.GetLootSlotInfo = function(i) local it = env.world.loot[i]; return ITEMS[it][9], ITEMS[it][1], 1, ITEMS[it][2], nil end
   G.GetLootSlotLink = function(i) return itemlink(env.world.loot[i]) end

   -- key bindings (client side) ---------------------------------------------------
   G.GetBindingKey = function() return nil end
   G.GetBindingText = function(k) return k end
   G.ClearOverrideBindings = function() end
   G.SetOverrideBindingClick = function(owner, priority, key, button)
      env.override_bindings = env.override_bindings or {}
      table.insert(env.override_bindings, { key = key, button = button, priority = priority })
   end

   -- SecureActionButtonTemplate frames, CreateFrame --------------------------------
   G.CreateFrame = function(kind, name, parent, inherits)
      if type(kind) ~= "string" then error("CreateFrame: frame type must be a string", 2) end
      local k = kind:sub(1, 1):upper() .. kind:sub(2):lower()
      local canonical = { Frame = "Frame", Button = "Button", Checkbutton = "CheckButton", Slider = "Slider", Editbox = "EditBox",
                          Gametooltip = "GameTooltip", Scrollframe = "ScrollFrame", Simplehtml = "SimpleHTML", Statusbar = "StatusBar",
                          Model = "Model", Messageframe = "MessageFrame", Colorselect = "ColorSelect", Cooldown = "Cooldown" }
      local ck = canonical[k]
      if not ck then error("CreateFrame: Unknown frame type '" .. kind .. "'", 2) end
      local fr = env:new_widget(ck, name, parent ~= nil and parent or nil)
      local st = env.state[fr]
      st.parent = parent
      if inherits then
         local contribs = {}
         for t in tostring(inherits):gmatch("[^,%s]+") do env:collect_template(t, contribs) end
         local handlers = {}
         for _, c in ipairs(contribs) do
            if c.unknown then
               error("CreateFrame: Couldn't find inherited node '" .. c.unknown .. "'", 2)
            elseif c.blizz then
               for _, ch in ipairs(c.blizz) do env:new_widget(ch[1], subst_name(ch[2], name), fr) end
            else
               if c.node.attrs.hidden == "true" then st.shown = false end
               env:apply_children(fr, c.node, "CreateFrame(" .. tostring(name) .. ")", name, handlers)
            end
         end
         for hname, h in pairs(handlers) do
            local hn = h.node
            local fn
            if hn.attrs["function"] then fn = env.G[hn.attrs["function"]]
            elseif hn.text and hn.text:find("%S") then fn = env:compile_handler(hname, hn.text, "CreateFrame(" .. tostring(name) .. ")") end
            if type(fn) == "function" then st.scripts[hname] = fn end
         end
         -- virtual templates fire OnLoad too
         if st.scripts.OnLoad then env:run_script(fr, "OnLoad") end
      end
      return fr
   end

   -- strict global read tracking is done lazily by a metatable on G when asked
   if self.opts.strict_globals then
      setmetatable(G, { __index = function(t, k)
         if type(k) == "string" and not self.opts.allow_undefined or not (self.opts.allow_undefined or {})[k] then
            self.undefined_reads[k] = (self.undefined_reads[k] or 0) + 1
         end
         return nil
      end })
   end

end

-- SavedVariables are assigned by the client AFTER the addon's files have run and
-- BEFORE ADDON_LOADED fires; file-level code must therefore not read them.
function Env:apply_saved()
   if self.opts.saved then
      for k, v in pairs(self.opts.saved) do self.G[k] = v end
   end
end

M.Env = Env
return M
