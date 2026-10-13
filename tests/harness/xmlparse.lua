-- harness/xmlparse.lua
-- Minimal XML reader, just enough for WoW UI XML (no DTD, no namespaces handling,
-- no processing of entities beyond the five predefined ones).
--
--   local node = xmlparse.parse(text)
--   node = { tag = "Ui", attrs = { name = ... }, children = { node, ... }, text = "..." }
--
-- `text` holds the concatenated character data of the element itself (XML
-- comments removed), which is what WoW feeds to the Lua compiler for script
-- handlers such as <OnLoad> ... </OnLoad>.

local M = {}

local ENT = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }
local function decode(s)
   return (s:gsub("&(#?%w+);", function(e)
      if ENT[e] then return ENT[e] end
      local n = e:match("^#(%d+)$")
      if n then return string.char(tonumber(n) % 256) end
      return "&" .. e .. ";"
   end))
end

local function parse_attrs(s)
   local attrs = {}
   for k, q, v in s:gmatch("([%w_:%.%-]+)%s*=%s*([\"'])(.-)%2") do
      attrs[k] = decode(v)
   end
   return attrs
end

function M.parse(xml)
   local root = { tag = "#root", attrs = {}, children = {}, text = "" }
   local stack = { root }
   local pos, len = 1, #xml
   -- skip a UTF-8 BOM: an XML parser must accept it
   if xml:sub(1, 3) == "\239\187\191" then pos = 4 end
   while pos <= len do
      local lt = xml:find("<", pos, true)
      if not lt then
         local cur = stack[#stack]
         cur.text = cur.text .. decode(xml:sub(pos))
         break
      end
      if lt > pos then
         local cur = stack[#stack]
         cur.text = cur.text .. decode(xml:sub(pos, lt - 1))
      end
      if xml:sub(lt, lt + 3) == "<!--" then
         local e = xml:find("-->", lt + 4, true)
         if not e then error("unterminated comment at byte " .. lt) end
         pos = e + 3
      elseif xml:sub(lt, lt + 8) == "<![CDATA[" then
         local e = xml:find("]]>", lt + 9, true)
         if not e then error("unterminated CDATA at byte " .. lt) end
         local cur = stack[#stack]
         cur.text = cur.text .. xml:sub(lt + 9, e - 1)
         pos = e + 3
      elseif xml:sub(lt, lt + 1) == "<?" then
         local e = xml:find("?>", lt + 2, true)
         if not e then error("unterminated processing instruction") end
         pos = e + 2
      elseif xml:sub(lt, lt + 1) == "</" then
         local e = xml:find(">", lt + 2, true)
         if not e then error("unterminated end tag") end
         local tag = xml:sub(lt + 2, e - 1):match("^%s*([^%s>]+)")
         local cur = table.remove(stack)
         if cur.tag ~= tag then
            error(("mismatched end tag </%s> (open: <%s>) near byte %d"):format(tostring(tag), tostring(cur.tag), lt))
         end
         pos = e + 1
      else
         -- start tag; find the closing '>' that is not inside quotes
         local i, q = lt + 1, nil
         while i <= len do
            local c = xml:sub(i, i)
            if q then
               if c == q then q = nil end
            elseif c == '"' or c == "'" then
               q = c
            elseif c == ">" then
               break
            end
            i = i + 1
         end
         if i > len then error("unterminated start tag at byte " .. lt) end
         local inner = xml:sub(lt + 1, i - 1)
         local selfclose = inner:sub(-1) == "/"
         if selfclose then inner = inner:sub(1, -2) end
         local tag, rest = inner:match("^([^%s/]+)%s*(.*)$")
         local node = { tag = tag, attrs = parse_attrs(rest or ""), children = {}, text = "" }
         local cur = stack[#stack]
         cur.children[#cur.children + 1] = node
         if not selfclose then stack[#stack + 1] = node end
         pos = i + 1
      end
   end
   if #stack ~= 1 then error("unclosed element <" .. stack[#stack].tag .. ">") end
   return root.children[1] or root
end

return M
