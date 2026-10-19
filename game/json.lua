--[[
  json.lua -- just enough JSON for the party files the web app reads and
  writes. Plain Lua, no LOVE calls.

  decode(text) returns a value or nil plus a message. It is strict: one
  value, no trailing commas, no comments, strings must be valid UTF-8 after
  escapes are applied, and nesting and size are capped so a hostile file can
  only be refused. Objects become tables with string keys; arrays become
  sequences with a field `n` = length; null becomes json.null.

  encode(value, indent) writes what the web app's JSON.stringify(v, null, 2)
  writes, as long as objects say their key order: an object is a table with
  its keys listed, in order, in the field `__order`. Strings are escaped as
  JavaScript does: quote, backslash and control characters, nothing else.
--]]

local rules = require("rules")

local json = {}
json.null = setmetatable({}, { __tostring = function() return "null" end })

local MAX_DEPTH, MAX_LEN = 32, 2000000

-- ---------------------------------------------------------------- decode

local function decodeError(pos, msg) error({ json = true, msg = msg .. " at byte " .. pos }, 0) end

local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

function json.decode(text)
  if type(text) ~= "string" then return nil, "not text" end
  if #text > MAX_LEN then return nil, "too large" end
  local pos = 1
  if text:sub(1, 3) == "\239\187\191" then pos = 4 end         -- a byte-order mark

  local function ws()
    pos = text:find("[^ \t\r\n]", pos) or #text + 1
  end

  local value

  local function str()
    pos = pos + 1                                               -- the opening quote
    local out = {}
    while true do
      local c = text:sub(pos, pos)
      if c == "" then decodeError(pos, "unfinished string") end
      if c == '"' then pos = pos + 1 break end
      if c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        if e == "u" then
          local hex = text:sub(pos + 2, pos + 5)
          if not hex:match("^%x%x%x%x$") then decodeError(pos, "bad \\u escape") end
          local cp = tonumber(hex, 16)
          pos = pos + 6
          if cp >= 0xD800 and cp <= 0xDBFF then
            local lo = text:match("^\\u(%x%x%x%x)", pos)
            local lcp = lo and tonumber(lo, 16)
            if not lcp or lcp < 0xDC00 or lcp > 0xDFFF then decodeError(pos, "half a surrogate pair") end
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lcp - 0xDC00)
            pos = pos + 6
          elseif cp >= 0xDC00 and cp <= 0xDFFF then
            decodeError(pos, "half a surrogate pair")
          end
          out[#out + 1] = rules.encodeCodepoint(cp)
        elseif ESC[e] then
          out[#out + 1] = ESC[e]
          pos = pos + 2
        else
          decodeError(pos, "bad escape")
        end
      else
        if c:byte() < 32 then decodeError(pos, "control character in a string") end
        local run = text:match('^[^"\\%c]+', pos)
        out[#out + 1] = run
        pos = pos + #run
      end
    end
    local s = table.concat(out)
    -- Valid UTF-8 or nothing: a name with broken bytes would stop LOVE's
    -- text drawing.
    local check = {}
    for cp in rules.codepoints(s) do check[#check + 1] = rules.encodeCodepoint(cp) end
    if table.concat(check) ~= s then decodeError(pos, "invalid UTF-8 in a string") end
    return s
  end

  local function num()
    local s = text:match("^-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
    if not s or not s:match("^-?%d") then decodeError(pos, "bad number") end
    if s:match("^-?0%d") then decodeError(pos, "leading zero") end
    pos = pos + #s
    local n = tonumber(s)
    if not n then decodeError(pos, "bad number") end
    return n
  end

  value = function(depth)
    if depth > MAX_DEPTH then decodeError(pos, "nested too deeply") end
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1 return obj end
      while true do
        ws()
        if text:sub(pos, pos) ~= '"' then decodeError(pos, "expected a key") end
        local k = str()
        ws()
        if text:sub(pos, pos) ~= ":" then decodeError(pos, "expected :") end
        pos = pos + 1
        obj[k] = value(depth + 1)
        ws()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then decodeError(pos - 1, "expected , or }") end
      end
    elseif c == "[" then
      pos = pos + 1
      local arr = { n = 0 }
      ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1 return arr end
      while true do
        arr.n = arr.n + 1
        arr[arr.n] = value(depth + 1)
        ws()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then decodeError(pos - 1, "expected , or ]") end
      end
    elseif c == '"' then return str()
    elseif c == "-" or c:match("%d") then return num()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4 return json.null
    end
    decodeError(pos, c == "" and "unexpected end" or "unexpected character")
  end

  local okay, result = pcall(function()
    local v = value(1)
    ws()
    if pos <= #text then decodeError(pos, "text after the value") end
    return v
  end)
  if okay then return result end
  if type(result) == "table" and result.json then return nil, result.msg end
  return nil, tostring(result)
end

-- ---------------------------------------------------------------- encode

local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    if c == "\t" then return "\\t" end
    if c == "\b" then return "\\b" end
    if c == "\f" then return "\\f" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function enc(v, indent, depth, out)
  local t = type(v)
  if v == json.null or v == nil then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
    elseif v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.17g", v) end
  elseif t == "string" then out[#out + 1] = quote(v)
  elseif t == "table" then
    local pad = indent and ("\n" .. string.rep(" ", indent * (depth + 1))) or ""
    local close = indent and ("\n" .. string.rep(" ", indent * depth)) or ""
    local colon = indent and ": " or ":"
    if v.__order then
      if #v.__order == 0 then out[#out + 1] = "{}" return end
      out[#out + 1] = "{"
      for i, k in ipairs(v.__order) do
        out[#out + 1] = (i > 1 and "," or "") .. pad .. quote(k) .. colon
        enc(v[k], indent, depth + 1, out)
      end
      out[#out + 1] = close .. "}"
    else
      local n = v.n or #v
      if n == 0 then out[#out + 1] = "[]" return end
      out[#out + 1] = "["
      for i = 1, n do
        out[#out + 1] = (i > 1 and "," or "") .. pad
        enc(v[i], indent, depth + 1, out)
      end
      out[#out + 1] = close .. "]"
    end
  else
    error("cannot encode a " .. t)
  end
end

function json.encode(v, indent)
  local out = {}
  enc(v, indent, 0, out)
  return table.concat(out)
end

--- An object whose keys come out in the order given.
function json.object(order, fields)
  fields.__order = order
  return fields
end

return json
