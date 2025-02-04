-- global variable safety
local _ENV = setmetatable({}, {
  __index = function(self, key)
    local result = _ENV[key]
    
    if result == nil then
      error("attempted to read undefined global variable \"" .. tostring(key) .. "\"", 2)
    end
    
    return result
  end,
  __newindex = function(self, key, value)
    error("attempted to write global variable \"" .. tostring(key) .. "\"", 2)
  end
})

local args = {...}

local component = require("component")
local computer = require("computer")

local sound = component.sound

local notes = {C = 3, D = 5, E = 7, F = 8, G = 10, A = 12, B = 14}
local semitone = 2 ^ (1 / 12)

-- predefine the functions as local variables
local prettyPrint
local set
local tokenize
local processTokens
local parse
local execute
local playSong

local helpMessage =
  "USAGE:\n" ..
  "  music file\n" ..
  "  music [options] file\n" ..
  "  music file [options]\n" ..
  "  music [options] file [options]\n" ..
  "\n" ..
  "OPTIONS:\n" ..
  "  --wave=[sine, triangle, square, sawtooth]    default square      - the waveform to use\n" ..
  "  --A4=frequency                               default 440         - the frequency, in Hz, of A4\n" ..
  "  --offset=offset                              default 0           - number of semitones to offset the music\n" ..
  "  --skip=skip                                  default 0           - number of beats to skip in the beginning\n" ..
  "  --speed=speed                                default 1           - speed multiplier\n" ..
  "  --length                                                         - prints the duration it would play for and exits immediately\n" ..
  "  --help, -h                                                       - prints this message and exits immediately\n" ..
  "\n" ..
  "DESCRIPTION:\n" ..
  "  Plays a music file.\n\n"

local lines = {}

local function main()
  if not args[1] then
    io.stdout:write(helpMessage)
    return
  end
  
  local wave = "square"
  local A4 = 440
  local offset = 0
  local skip = 0
  local speed = 1
  local getLength = false
  local path = ""
  
  for i = 1, #args do
    if args[i]:match("^%-%-wave=.*$") then
      wave = args[i]:match("^%-%-wave=(.*)$")
      
      if not set{"sine", "triangle", "square", "sawtooth"}[wave] then
        io.stderr:write("error: invalid waveform \"" .. wave .. "\"\n\n" .. helpMessage)
        os.exit(1)
      end
    elseif args[i]:match("^%-%-A4=.*$") then
      A4 = args[i]:match("^%-%-A4=(.*)$")
      
      if type(tonumber(A4)) ~= "number" then
        io.stderr:write("error: invalid A4 frequency \"" .. A4 .. "\"\n\n" .. helpMessage)
        os.exit(1)
      end
      
      A4 = tonumber(A4)
      
      if A4 <= 0 then
        io.stderr:write("error: A4 frequency must be greater than zero\n\n" .. helpMessage)
        os.exit(1)
      end
    elseif args[i]:match("^%-%-offset=.*$") then
      offset = args[i]:match("^%-%-offset=(.*)$")
      
      if type(tonumber(offset)) ~= "number" then
        io.stderr:write("error: invalid offset \"" .. offset .. "\"\n\n" .. helpMessage)
        os.exit(1)
      end
      
      offset = tonumber(offset)
    elseif args[i]:match("^%-%-skip=.*$") then
      skip = args[i]:match("^%-%-skip=(.*)$")
      
      if type(tonumber(skip)) ~= "number" then
        io.stderr:write("error: invalid skip \"" .. skip .. "\"\n\n" .. helpMessage)
        os.exit(1)
      end
      
      skip = tonumber(skip)
      
      if skip < 0 then
        io.stderr:write("error: the number of beats skipped must not be negative\n\n" .. helpMessage)
        os.exit(1)
      end
    elseif args[i]:match("^%-%-speed=.*$") then
      speed = args[i]:match("^%-%-speed=(.*)$")
      
      if type(tonumber(speed)) ~= "number" then
        io.stderr:write("error: invalid speed \"" .. speed .. "\"\n\n" .. helpMessage)
        os.exit(1)
      end
      
      speed = tonumber(speed)
      
      if speed <= 0 then
        io.stderr:write("error: the speed must be greater than zero" .. helpMessage)
        os.exit(1)
      end
    elseif args[i] == "--length" then
      getLength = true
    elseif set{"--help", "-h"}[args[i]] then
      io.stdout:write(helpMessage)
      return
    else
      if path == "" then
        path = args[i]
      else
        io.stderr:write("error: only one music file may be specified\n\n" .. helpMessage)
        os.exit(1)
      end
    end
  end
  
  if path == "" then
    io.stderr:write("error: no file specified\n\n" .. helpMessage)
    os.exit(1)
  end
  
  local handle = io.open(path, "rb")
  
  if handle == nil then
    io.stderr:write(path .. ": file not found")
    os.exit(1)
  end
  
  local file = handle:read("*a")
  
  handle:close()
  
  for line in (file .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  
  local tokens = tokenize(file, path)
  local tokens2 = processTokens(tokens, path, A4 * semitone ^ offset, speed)
  local AST = parse(tokens2, path)  
  local schedule = execute(AST, path)
  local length = playSong(schedule, wave, skip / speed, getLength)
  
  if getLength then
    if length == 1 then
      print("1 second")
    else
      print(("%s seconds"):format(length))
    end
  end
end

-- prettyPrint(table, [number, table]) -> string

-- takes a table or other data type and turns it into a prettified string

-- predefined as local at the top of the file

function prettyPrint(data, depth, stack)
  depth = depth or 0
  stack = stack or {}
  
  for index, value in ipairs(stack) do
    if data == value then
      return "^" .. (depth - index) -- depth == #stack
    end
  end
  
  if type(data) ~= "table" then
    if type(data) == "string" then
      return "\"" .. data .. "\""
    else
     return tostring(data)
    end
  end
  
  if next(data) == nil then
    return tostring(data) .. " {}"
  end
  
  table.insert(stack, data)
  
  local out = "{\n"
  
  for key, value in pairs(data) do
    out = out .. ("  "):rep(depth + 1)
    
    if type(key) == "string" then
      out = out .. "\"" .. key .. "\" = "
    else
      out = out .. tostring(key) .. " = "
    end
    
    out = out .. prettyPrint(value, depth + 1, stack) .. (next(data, key) ~= nil and ",\n" or "\n")
  end
  
  table.remove(stack, #stack)
  
  return tostring(out .. ("  "):rep(depth) .. "}")
end

-- checkArg(any, number, string) -> error or nil

-- checks to make sure the argument is of the specified type, gives an informative error message otherwise

local function checkArg(argument, argNumber, expectedType)
  if type(argument) ~= expectedType then
    error(("bad argument #%s (%s expected, got %s)"):format(argNumber, expectedType, type(argument)), 3)
  end
end

-- terminalError(string, number, number, string) -> exits

-- reports a syntax error in a standardized way for ease of debugging and then exits

local function terminalError(path, line, column, message)
  checkArg(path, 1, "string")
  checkArg(line, 2, "number")
  checkArg(column, 3, "number")
  checkArg(message, 4, "string")
  
  io.stderr:write(path .. ":" .. line .. ":" .. column .. ": " .. message .. ":\n\n")
  io.stderr:write(lines[line] .. "\n")
  io.stderr:write((" "):rep(column - 1) .. "^\n")
  
  os.exit(1)
end

-- set(table) -> table

-- takes an array and turns it into a set

-- predefined as local at the top of the file

function set(arr)
  local set = {}
  
  for _, value in ipairs(arr) do
    set[value] = true
  end
  
  return set
end

-- tokenize(string, string) -> table

-- takes a file (i.e. a long string) and turns it into a stream of tokens, each of the following format:
--
-- {
--   content = string (the literal sequence of characters in the file that produced this token)
--   type = string (what sort of token this is)
--   line = number (what line in the file this token is from)
--   column = number (what column in the file this token is from)
-- }

-- predefined as local at the top of the file

function tokenize(file, path)
  local tokens = {}
  local currentToken = ""
  local currentTokenColumn = -1
  
  local function insertToken(content, type, line, column)
    table.insert(tokens, {content = content, type = type, line = line, column = column})
  end
  
  local i = 1
  local line = 1
  local column = 1
  while i <= #file do
    local char = file:sub(i, i)
    
    if char == " " or char == "\t" or char == "\n" or char == ";" then
      if currentToken ~= "" then
        insertToken(currentToken, "string", line, currentTokenColumn)
        currentToken = ""
      end
      
      if char == "\n" then
        line = line + 1
        column = 0
      end
      
      if char == ";" then
        while file:sub(i, i) ~= "\n" and i <= #file do -- stop when at newline or on last character of the file
          i = i + 1
          column = column + 1
        end
        
        i = i - 1
      end
    elseif char:match("[|!<%(%)&=]") then 
      if currentToken ~= "" then
        insertToken(currentToken, "string", line, currentTokenColumn)
        currentToken = ""
      end
      
      insertToken(char, "symbol", line, column)
    elseif char:match("[%w_%.#]") then
      if currentToken == "" then
        currentTokenColumn = column
      end
      
      currentToken = currentToken .. char
      
      if i == #file then
        insertToken(currentToken, "string", line, currentTokenColumn)
      end
    else
      terminalError(path, line, column, "invalid character \"" .. char .. "\"")
    end
    
    i = i + 1
    column = column + 1
  end
  
  table.insert(tokens, {type = "EOF"})
  
  return tokens
end

-- processTokens(table, string, number, number) -> table

-- does some further processing on tokens that could be done in tokenize(...) but
-- has been split off into this function in the name of keeping functions short
-- and simple
--
-- tokens of type "string" are differentiated into tokens of type "directive"
-- (i.e. BPM), "number" (a number), and "note", with some processing done to
-- determine the duration and frequency of the note, these values being placed
-- in the "duration" and "frequency" fields in units of beats and Hz, respectively

-- predefined as local at the top of the file

function processTokens(tokens, path, A4, speed)
  local function processDuration(token, duration)
    if duration == nil then
      error("nil duration", 2)
    end
    
    if duration == "." then
      terminalError(path, token.line, token.column, "\".\" is not a valid duration")
    end
    
    if duration == "" then
      duration = "1"
    end
    
    duration = tonumber(duration)
    
    if duration == 0 or duration == nil then -- it shouldn't be possible for duration to be nil but it can't hurt to check
      terminalError(path, token.line, token.column, "duration must be nonzero")
    end
    
    return duration
  end
  
  for _, token in ipairs(tokens) do
    if token.type == "string" then
      if token.content == "BPM" then
        token.type = "directive"
      elseif token.content == "TimeScale" then
        token.type = "directive"
      elseif token.content:match("^%d*%.?%d*$") and not set{"", "."}[token.content] then
        token.type = "number"
        token.content = tonumber(token.content)
      elseif token.content:match("^%d*%.?%d*Z$") then
        token.type = "sleep"
        token.duration = processDuration(token, token.content:match("%d*%.?%d*")) / speed
      elseif token.content:match("^%d*%.?%d*[ABCDEFG][#b]?%d$") then
        token.type = "note"
        
        local duration, note, octave = token.content:match("^(%d*%.?%d*)([ABCDEFG][#b]?)(%d)$")
        token.duration = processDuration(token, duration) / speed
        
        note = notes[note:sub(1, 1)] + (note:sub(2, 2) == "" and 0 or note:sub(2, 2) == "#" and 1 or note:sub(2, 2) == "b" and -1)
        note = note + (octave - 5) * 12
        token.frequency = A4 * semitone ^ note
        
        if token.frequency > 22000 then -- remove inaudibly high frequency notes to prevent Nyquist-Shannon aliasing down to audible frequencies
          token.frequency = 0
        end
      elseif token.content:match("^[_%a][_%w]*$") then
        token.type = "identifier"
      else
        terminalError(path, token.line, token.column, "invalid token \"" .. token.content .. "\"")
      end
    end
  end
  
  return tokens
end

-- unexpectedTokenError(table) -> error

local function unexpectedTokenError(token)
  error(("unexpected token with type %s and content %s at location %s:%s"):format(token.type, token.content, token.line, token.column), 2)
end

-- unexpectedNodeError(table) -> error

local function unexpectedNodeError(AST)
  error(("unexpected node with type %s and content %s with reported location %s:%s"):format(AST.token.type, AST.token.content, AST.token.line, AST.token.column), 2)
end

-- parse(table, string) -> table

-- parses the token stream into an abstract syntax tree (AST)
--
-- each node of the AST has a "token" field containing the unmodified
-- original of the token that the node was created from, a "parent"
-- field (except for the root node), and in the case of inner nodes,
-- a "children" field containing an array of children. Note that this
-- array is not necessarily populated at any point, so inner nodes
-- can also be leaf nodes (e.g. created by an empty pair of parentheses)
--
-- after each iteration of the for loop, the variable "AST" points to
-- the inner node nearest to the last created node. If that node was
-- itself an inner node, it simply points to that. Otherwise, it points
-- to its parent
--
-- some nodes will contain additional fields, such as "value" for a
-- node containing a directive token

-- predefined as local at the top of the file

function parse(tokens, path)
  local AST = {token = {type = "root"}, children = {}}
  local identifiers = {}
  
  for _, token in ipairs(tokens) do
    local latestNode = AST
    
    if latestNode.children ~= nil and #latestNode.children ~= 0 then
      latestNode = latestNode.children[#latestNode.children]
    end
    
    if latestNode.token.type == "symbol" and latestNode.token.content == "=" and latestNode.definition ~= nil then
      latestNode = latestNode.definition
    end
    
    if latestNode.token.type == "directive" and latestNode.value == nil then
      if token.type ~= "number" then
        terminalError(path, token.line, token.column, "unexpected " .. token.type .. " after directive, expected number instead")
      end
    end
    
    if latestNode.token.type == "identifier" then
      if not (token.type == "symbol" and token.content == "=") then
        if latestNode.definition == nil then
          terminalError(path, latestNode.token.line, latestNode.token.column, "identifer \"" .. latestNode.token.content .. "\" cannot be used before assignment")
        end
      end
    end
    
    if latestNode.token.type == "symbol" and latestNode.token.content == "=" then
      if not (token.type == "symbol" and token.content == "(") then
        terminalError(path, latestNode.token.line, latestNode.token.column, "assignment operator must be followed by parentheses")
      end
    end
    
    if token.type == "directive" then
      if token.content == "BPM" then
        local AST2 = AST
        
        while AST2.token.type ~= "root" do
          if AST2.token.type == "symbol" and AST2.token.content == "|" and not AST2.terminated then
            terminalError(path, token.line, token.column, "BPM directive not allowed at this location")
          end
          
          AST2 = AST2.parent
        end
        
        table.insert(AST.children, {token = token, parent = AST})
      elseif token.content == "TimeScale" then
        if AST.token.type ~= "root" then
          terminalError(path, token.line, token.column, "TimeScale directive must be at the beginning of the file")
        end
        
        for _, child in ipairs(AST.children) do
          if child.token.type ~= "directive" then
            terminalError(path, token.line, token.column, "TimeScale directive must be at the beginning of the file")
          end
          
          if child.token.content == "TimeScale" then
            terminalError(path, token.line, token.column, "TimeScale directive can only be used once in a given file")
          end
        end
        
        table.insert(AST.children, {token = token, parent = AST})
      else
        unexpectedTokenError(token)
      end
    elseif token.type == "number" then
      if not (latestNode.token.type == "directive" and set{"BPM", "TimeScale"}[latestNode.token.content]) then
        terminalError(path, token.line, token.column, "unexpected number, a number can only follow a BPM or TimeScale directive")
      end
      
      latestNode.value = token.content
    elseif set{"note", "sleep", "identifier"}[token.type] then
      if AST.token.type == "root" or set{"(", "|"}[AST.token.content] then
        if token.type == "note" then
          table.insert(AST.children, {token = token, parent = AST, blocking = true})
        elseif token.type == "sleep" then
          table.insert(AST.children, {token = token, parent = AST})
        elseif token.type == "identifier" then
          if identifiers[token.content] ~= nil then
            table.insert(AST.children, {token = token, parent = AST, blocking = true, definition = identifiers[token.content]})
          else
            table.insert(AST.children, {token = token, parent = AST, blocking = true})
          end
        else
          error("something went wrong")
        end
      else
        unexpectedNodeError(AST)
      end
    elseif token.type == "symbol" then
      if token.content == "|" then
        if AST.token.content == "|" then
          AST = AST.parent
        end
        
        AST = {token = token, parent = AST, children = {}, terminated = false, finalJump = -1}
        table.insert(AST.parent.children, AST)
      elseif set{"!", "<"}[token.content] then
        if AST.token.content ~= "|" then
          terminalError(path, token.line, token.column, "unexpected \"" .. token.content .. "\" without \"|\"")
        end
        
        if AST.terminated and token.content == "!" then
          terminalError(path, token.line, token.column, "unexpected \"!\", each \"|\" must only have one associated \"!\"")
        end
        
        if not AST.terminated then
          if token.content == "<" then
            terminalError(path, token.line, token.column, "unexpected \"<\", \"<\" must occur after a \"!\"")
          else
            if token.content ~= "!" then
              unexpectedTokenError(token)
            end
            
            AST.terminated = true
          end
        end
        
        table.insert(AST.children, {token = token, parent = AST})
        AST.finalJump = #AST.children
      elseif token.content == "(" then
        if latestNode.token.type == "symbol" and latestNode.token.content == "=" then
          AST = {token = token, parent = latestNode, children = {}, blocking = true}
          latestNode.definition = AST
        else
          AST = {token = token, parent = AST, children = {}, blocking = true}
          table.insert(AST.parent.children, AST)
        end
      elseif token.content == ")" then
        if AST.token.content == "|" then
          if not AST.terminated then
            terminalError(path, AST.token.line, AST.token.column, "\"|\" without corresponding \"!\"")
          end
          
          AST = AST.parent
        end
        
        if AST.token.type == "root" then
          terminalError(path, token.line, token.column, "unmatched closing parenthesis")
        end
        
        if AST.token.content ~= "(" then
          unexpectedNodeError(AST)
        end
        
        AST = AST.parent
        
        if AST.token.type == "symbol" and AST.token.content == "=" then
          identifiers[AST.identifier.token.content] = AST.definition
          
          AST = AST.parent
        end
      elseif token.content == "&" then
        if latestNode.token.type ~= "note" and latestNode.token.content ~= "(" and latestNode.token.type ~= "identifier" or latestNode.blocking == false then
          terminalError(path, token.line, token.column, "unexpected \"&\", \"&\" must follow either a note, a closing parenthesis, or an identifier")
        end
        
        latestNode.blocking = false
      elseif token.content == "=" then
        if latestNode.token.type ~= "identifier" or not latestNode.blocking then
          if latestNode.token.type == "note" then
            terminalError(path, latestNode.token.line, latestNode.token.column, "cannot assign to a note. Did you intend this to be an identifier? Rename it to something that's not a valid note")
          end
          
          terminalError(path, token.line, token.column, "assignment operator must follow an identifer")
        end
        
        if AST.token.type ~= "root" then
          if not (AST.token.type == "symbol" and AST.token.content == "|" and AST.terminated and AST.parent.token.type == "root") then
            terminalError(path, token.line, token.column, "assignment not allowed at this location")
          end
        end
        
        latestNode.parent = {token = token, parent = AST, identifier = latestNode}
        AST.children[#AST.children] = latestNode.parent
      else
        unexpectedTokenError(token)
      end
    elseif token.type == "EOF" then
      if AST.token.content == "|" then
        if not AST.terminated then
          terminalError(path, AST.token.line, AST.token.column, "\"|\" without corresponding \"!\"")
        end
        
        AST = AST.parent
      end
      
      if AST.token.content == "(" then
        terminalError(path, AST.token.line, AST.token.column, "unexpected EOF, unmatched opening parenthesis")
      end
      
      if AST.token.type ~= "root" then
        unexpectedNodeError(AST)
      end
    else
      unexpectedTokenError(token)
    end
  end
  
  return AST
end

-- execute(table, string, [number, [table, [boolean]]]) -> table, number

-- interprets the abstract syntax tree and executes it, producing
-- a schedule consisting of a sequence of timed actions. Each action
-- has a timestamp and says to start a note, stop a note, or change
-- the BPM

-- predefined as local at the top of the file

function execute(AST, path, currentTime, state, haltAtExclamation)
  local currentTime = currentTime or 0
  
  local state = state or {
    schedule = {{time = 0, token = {type = "directive", content = "BPM", line = -1, column = -1}, value = 120}},
    BPM = 120,
    timeScale = 1,
    id = 1
  }
  
  haltAtExclamation = haltAtExclamation or false
  
  local i = 1
  while i <= #AST.children do
    local child = AST.children[i]
    
    if child.token.type == "directive" then
      if child.token.content == "BPM" then
        local child2 = child
        while child2.parent.token.type ~= "root" do
          local position = -1
          
          for index in ipairs(child2.parent.children) do
            if child2.parent.children[index] == child2 then
              position = index
              break
            end
          end
          
          if position == -1 then
            unexpectedNodeError(child2)
          end
          
          if child2.parent.token.type == "symbol" and child2.parent.token.content == "|" and child2.parent.finalJump > position then
            terminalError(path, child.token.line, child.token.column, "BPM directive not allowed at this location")
          end
        end
        
        state.BPM = child.value
        
        table.insert(state.schedule, {time = currentTime, token = child.token, value = child.value})
      elseif child.token.content == "TimeScale" then
        state.timeScale = child.value
      else
        unexpectedNodeError(child)
      end
    elseif child.token.type == "sleep" then
      currentTime = currentTime + child.token.duration / state.BPM * 60 / state.timeScale
    elseif child.token.type == "note" then
      local endTime = currentTime + child.token.duration / state.BPM * 60 / state.timeScale
      
      table.insert(state.schedule, {time = currentTime, token = child.token, status = "starting", id = state.id})
      table.insert(state.schedule, {time = endTime, token = child.token, status = "ending", id = state.id})
      
      state.id = state.id + 1
      
      if child.blocking then
        currentTime = endTime
      end
    elseif child.token.type == "identifier" then
      if child.definition == nil then
        unexpectedNodeError(child)
      end
      
      local newCurrentTime = select(2, execute(child.definition, path, currentTime, state))
      
      if child.blocking then
        currentTime = newCurrentTime
      end
    elseif child.token.type == "symbol" then
      if child.token.content == "(" then
        local newCurrentTime = select(2, execute(child, path, currentTime, state))
        
        if child.blocking then
          currentTime = newCurrentTime
        end
      elseif child.token.content == "|" then
        currentTime = select(2, execute(child, path, currentTime, state))
      elseif child.token.content == "!" then
        if haltAtExclamation then
          return state.schedule, currentTime
        else
          -- do nothing
        end
      elseif child.token.content == "<" then
        currentTime = select(2, execute(AST, path, currentTime, state, true))
      elseif child.token.content == "=" then
        -- do nothing
      else
        unexpectedNodeError(child)
      end
    else
      unexpectedNodeError(child)
    end
    
    i = i + 1
  end
  
  -- higher priority gets sorted to an earlier position in the array
  local function getPriority(action)
    if action.token.type == "directive" then
      if action.token.content == "BPM" then
        return 1
      else
        unexpectedTokenError(action.token)
      end
    elseif action.token.type == "note" then
      if action.status == "starting" then
        return 0
      elseif action.status == "ending" then
        return 1
      else
        unexpectedTokenError(action.token)
      end
    else
      unexpectedTokenError(action.token)
    end
  end
  
  if AST.token.type == "root" then
    table.sort(state.schedule, function(a, b)
      if a == b then -- dunno why this is needed, table.sort is silly I guesss
        return false
      end
      
      if a.time ~= b.time then
        return a.time < b.time
      elseif getPriority(a) ~= getPriority(b) then
        return getPriority(a) > getPriority(b)
      elseif a.token.line ~= b.token.line then
        return a.token.line < b.token.line
      elseif a.token.column ~= b.token.column then
        return a.token.column < b.token.column
      else
        error("something went wrong")
      end
    end)
  end
  
  return state.schedule, currentTime
end

-- resetSound(table) -> nil

-- resets the sound card to a default state

local function resetSound(sound)
  if sound == nil then
    error("bad argument #1 to resetSound (sound component expected, got no value)", 2)
  end
  
  if type(sound) ~= "table" or sound.type ~= "sound" then
    error("bad argument #1 to resetSound (sound component expected, got " .. type(sound) .. ")", 2)
  end
  
  sound.clear()
  sound.setTotalVolume(1)
  
  for i = 1, sound.channel_count do
    sound.close(i)
    sound.setWave(i, sound.modes.square)
    sound.setVolume(i, 1)
    sound.setFrequency(i, 0)
    sound.resetEnvelope(i)
    sound.resetAM(i)
    sound.resetFM(i)
  end
end

-- soundProxy(table) -> table

-- takes a sound object and returns an object of
-- identical behavior, but tracks only the changes
-- of state so that extraneous instructions aren't
-- unnecessarily put into the queue

local function soundProxy(sound)
  local currentState = {}
  local desiredState = {}
  
  for i = 1, sound.channel_count do
    currentState[i] = {}
    desiredState[i] = {}
  end
  
  return {
    channel_count = sound.channel_count,
    modes = sound.modes,
    open = function(channel)
      desiredState[channel].open = true
    end,
    close = function(channel)
      desiredState[channel].open = false
    end,
    setWave = function(channel, wave)
      desiredState[channel].wave = wave
    end,
    setFrequency = function(channel, frequency)
      desiredState[channel].frequency = frequency
    end,
    delay = function(delay)
      if delay < 1 then
        return
      end
      
      for i = 1, sound.channel_count do
        if currentState[i].open ~= desiredState[i].open then
          currentState[i].open = desiredState[i].open
          
          if desiredState[i].open then
            assert(sound.open(i))
          else
            assert(sound.close(i))
          end
        end
        
        if currentState[i].wave ~= desiredState[i].wave then
          currentState[i].wave = desiredState[i].wave
          
          assert(sound.setWave(i, desiredState[i].wave))
        end
        
        if currentState[i].frequency ~= desiredState[i].frequency then
          currentState[i].frequency = desiredState[i].frequency
          
          assert(sound.setFrequency(i, desiredState[i].frequency))
        end
      end
      
      assert(sound.delay(delay))
    end,
    process = function()
      assert(sound.process())
    end
  }
end

-- playSong(table, string, number, boolean) -> number

-- takes a schedule and plays the song according to the
-- actions listed in the schedule. Can additionally skip
-- a requested number of beats to start forward in the
-- song. It returns the length of time played. The
-- dryRun option makes it return immediately with the
-- return value it would've outputted had the dryRun
-- option not been specified

-- predefined as local at the top of the file

function playSong(schedule, wave, skip, dryRun)
  resetSound(sound)
  
  local proxy = soundProxy(sound)
  
  local channelOccupation = {}
  local noteToChannel = {}
  
  for i = 1, proxy.channel_count do
    proxy.setWave(i, proxy.modes[wave])
    
    channelOccupation[i] = false
  end
  
  local function getFreeChannel()
    for index, value in ipairs(channelOccupation) do
      if not value then
        return index
      end
    end
    
    return -1
  end
  
  local function startNote(note, id)
    local channel = getFreeChannel()
    
    if channel == -1 then
      io.stderr:write("Insufficient free channels! Skipping a note.\n")
      return
    end
    
    channelOccupation[channel] = true
    noteToChannel[id] = channel
    
    proxy.setFrequency(channel, note.frequency)
    proxy.open(channel)
  end
  
  local function stopNote(note, id)
    local channel = noteToChannel[id]
    
    if channel == nil then
      return
    end
    
    proxy.close(channel)
    
    channelOccupation[channel] = false
    noteToChannel[id] = nil
  end
  
  local queueEndTime = computer.uptime()
  local length = 0
  
  local beats = 0
  local function play(duration, BPM)
    local duration = math.floor(duration * 1000) -- convert to milliseconds
    local remainingDuration = duration
    
    if skip > 0 then
      local durationInBeats = duration * BPM / 60 / 1000
      
      if durationInBeats <= skip then
        skip = skip - durationInBeats
        return duration / 1000 -- convert back to seconds
      else
        skip = 0
        remainingDuration = remainingDuration - skip / BPM * 60 * 1000
      end
    end
    
    if dryRun then
      length = length + remainingDuration / 1000
      return duration / 1000 -- convert back to seconds
    end
    
    while remainingDuration / 1000 + queueEndTime - computer.uptime() > 4 do
      local delay = math.floor((4 + computer.uptime() - queueEndTime) * 1000) -- convert to milliseconds
      proxy.delay(delay)
      queueEndTime = queueEndTime + delay / 1000
      remainingDuration = remainingDuration - delay
      
      proxy.process()
      os.sleep(3)
    end
    
    proxy.delay(remainingDuration)
    queueEndTime = queueEndTime + remainingDuration / 1000
    
    return duration / 1000 -- convert back to seconds
  end
  
  local discrepancy = 0
  local BPM = 0 -- this number is assigned by the first action in the schedule
  
  for index, action in ipairs(schedule) do
    if action.token.type == "directive" then
      if action.token.content == "BPM" then
        BPM = action.value
      else
        unexpectedTokenError(action.token)
      end
    elseif action.token.type == "note" then
      if action.status == "starting" then
        startNote(action.token, action.id)
      elseif action.status == "ending" then
        stopNote(action.token, action.id)
      else
        unexpectedTokenError(action.token)
      end
    else
      unexpectedTokenError(action.token)
    end
    
    if schedule[index + 1] ~= nil then
      local timeToNextAction = schedule[index + 1].time - action.time + discrepancy
      
      if timeToNextAction > 0.001 then
        discrepancy = timeToNextAction - play(timeToNextAction, BPM)
      else
        discrepancy = timeToNextAction
      end
    else
      -- we're processing the last action, which is necessarily to stop playing the last note, so nothing to do here
    end
  end
  
  proxy.process()
  os.sleep(queueEndTime - computer.uptime())
  
  resetSound(sound)
  sound.clear() -- dunno why this is necessary since resetSound(sound) should take care of that, but erroneous sounds get played if this line is removed
  sound.process()
  
  return length
end

main()