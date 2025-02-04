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

local component = require("component")
local fs = require("filesystem")
local term = require("term")
local unicode = require("unicode")
local event = require("event")
local computer = require("computer")

local gpu = component.gpu
local dataCard = component.data

-- predefine the functions as local variables
local decodePNG
local display

local function main()
  local filenames = {}
  
  for filename in fs.list("/mnt/3fa/frames/") do
    table.insert(filenames, filename)
  end
  
  -- filenames are in the format "out_ABCD.png" where ABCD is a four digit integer
  table.sort(filenames, function(a, b)
    return tonumber(a:sub(5, 8)) < tonumber(b:sub(5, 8))
  end)
  
  term.setCursor(1, 1)
  
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(0, 0, 160, 50, " ")
  gpu.freeAllBuffers()
  
  local buffer = gpu.allocateBuffer(160, 50)
  
  gpu.setActiveBuffer(buffer)
  
  local interrupted = false
  
  event.listen("interrupted", function()
    interrupted = true
    
    return false -- unregister this listener
  end)
  
  local startTime = computer.uptime()
  
  for index, filename in ipairs(filenames) do
    if interrupted then
      break
    end
    
    local targetTime = startTime + index / 10
    
    if computer.uptime() < targetTime - 0.1 then -- we're early, wait
      os.sleep((targetTime - 0.1) - computer.uptime())
    end
    
    if computer.uptime() < targetTime then -- if this condition fails we've overshot our target time and need to skip this frame
      local handle = io.open("/mnt/3fa/frames/" .. filename, "rb")
      local contents = handle:read("*a")
      handle:close()
      
      local image = decodePNG(contents)
      display(image)
      
      if computer.pullSignal(0) == "interrupted" then -- yield to give the OS a chance to handle events and eliminate the "too long without yielding" error
        interrupted = true
      end
    end
  end
  
  gpu.freeAllBuffers()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, 160, 50, " ")
end

-- decodePNG(string) -> table

-- converts a PNG file to a two dimensional array of color values, with the first
-- index specifying the row and the second index specifying the column within
-- that row

-- predefined as local at the top of the file

function decodePNG(file)
  if file:sub(1, 8) ~= "\x89PNG\r\n\x1A\n" then
    print(file:sub(1, 8))
    error("attempt to decode a PNG with an invalid magic number", 2)
  end
  
  local headerFound = false
  local width = nil
  local height = nil
  local bitDepth = nil
  local colorType = nil
  local compressionMethod = nil
  local filterMethod = nil
  local interlaceMethod = nil
  
  local palette = {}
  local data = ""
  
  local i = 9
  while i <= #file do
    local chunkLength = string.unpack(">I4", file, i)
    local chunkType = file:sub(i + 4, i + 7)
    local chunkContent = file:sub(8, chunkLength + 7)
    
    if not headerFound and chunkType ~= "IHDR" then
        error("IHDR not first chunk in file, got chunk " .. chunkType .. " instead")
    end
    
    if chunkType == "IHDR" then
      assert(chunkLength == 13, "IHDR chunk with length " .. chunkLength .. " instead of 13")
      
      headerFound = true
      
      width, height, bitDepth, colorType, compressionMethod, filterMethod, interlaceMethod = string.unpack(">I4I4BBBBB", file, i + 8)
      
      if colorType ~= 3 then
        error("color types other than indexed color are not supported")
      end
      
      if bitDepth ~= 8 then
        error("bit depths other than 8 are not supported")
      end
      
      if compressionMethod ~= 0 then
        error("invalid PNG with specified compression method other than 0")
      end
      
      if filterMethod ~= 0 then
        error("invalid PNG with specified filter method other than 0")
      end
      
      if interlaceMethod ~= 0 then
        error("interlaced PNG files are not supported")
      end
    elseif chunkType == "PLTE" then
      if chunkLength % 3 ~= 0 then
        error("invalid PNG with PLTE chunk length not divisible by 3")
      end
      
      for k = 1, chunkLength, 3 do
        table.insert(palette, (string.unpack(">I3", file, i + k + 7)))
      end
    elseif chunkType == "IDAT" then
      data = data .. file:sub(i + 8, i + chunkLength + 7)
    elseif chunkType == "IEND" then
      if chunkLength ~= 0 then
        error("invalid PNG with IEND chunk length other than 0")
      end
      
      if #file - i ~= 11 then
        error("invalid PNG with IEND chunk not at end of file")
      end
    elseif chunkType:sub(1, 1):match("%l") ~= nil then
      -- do nothing, this chunk is ancillary and can be safely skipped
    else
      error("unrecognized critical chunk of type " .. chunkType)
    end
    
    i = i + chunkLength + 12
  end
  
  data = dataCard.inflate(data)
  
  local image = {}
  
  for y = 1, height do
    table.insert(image, {})
    
    for x = 1, width do
      local scanlineStart = 1 + (y - 1) * (width + 1)
      
      if data:sub(scanlineStart, scanlineStart):byte() ~= 0 then
        error("filter type " .. data:sub(scanlineStart, scanlineStart:byte()) .. " not supported")
      end
      
      local pixelLocation = scanlineStart + x - 1
      local paletteIndex = data:sub(pixelLocation, pixelLocation):byte()
      
      if paletteIndex == nil then
        error("attempt to access byte " .. pixelLocation .. " of data while data only has length " .. #data)
      end
      
      local color = palette[paletteIndex + 1]
      
      table.insert(image[y], color)
    end
  end
  
  return image
end

-- getBraille(table) -> string

-- returns the braille character corresponding to the supplied
-- 2D boolean array of dimensions arr[4][2] (4 vertical, 2
-- horizontal)

local function getBraille(arr)
  return unicode.char(
    0x2800 +
    (arr[1][1] and 1 or 0) +
    (arr[1][2] and 8 or 0) +
    (arr[2][1] and 2 or 0) +
    (arr[2][2] and 16 or 0) +
    (arr[3][1] and 4 or 0) +
    (arr[3][2] and 32 or 0) +
    (arr[4][1] and 64 or 0) +
    (arr[4][2] and 128 or 0)
  )
end

-- display(table) -> nil

-- draws to the screen

-- predefined as local at the top of the file

function display(image)
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  
  local bgColor = 0x000000
  local fgColor = 0xFFFFFF
  local str = ""
  
  for y = 1, 50 do
    for x = 1, 134 do
      local colorsMap = {}
      local colorsArr = {}
      
      for y1 = 1, 4 do
        for x1 = 1, 2 do
          local color = image[(y - 1) * 4 + y1][(x - 1) * 2 + x1]
          
          if color == nil then
            color = 0x000000
          end
          
          if colorsMap[color] == nil then
            local obj = {color = color, count = 0}
            colorsMap[color] = obj
            table.insert(colorsArr, obj)
          end
          
          colorsMap[color].count = colorsMap[color].count + 1
        end
      end
      
      table.sort(colorsArr, function(a, b)
        return a.count > b.count
      end)
      
      local colorMin = 0xFFFFFF
      local colorMax = 0x000000
      
      local colors = colorsArr
      
      if #colorsArr >= 2 then
        if colors[1].count == colors[2].count or (colors[3] ~= nil and colors[2].count == colors[3].count) then
          local count = colors[2].count
          
          for index, color in ipairs(colors) do
            if color.count < count then
              break
            end
            
            colorMin = math.min(colorMin, color.color)
            colorMax = math.max(colorMax, color.color)
          end
        else
          colorMin = math.min(colors[1].color, colors[2].color)
          colorMax = math.max(colors[1].color, colors[2].color)
        end
      else
        colorMin = colors[1].color
        colorMax = colors[1].color
      end
      
      local arr = {{}, {}, {}, {}}
      
      for y1 = 1, 4 do
        for x1 = 1, 2 do
          local color = image[(y - 1) * 4 + y1][(x - 1) * 2 + x1]
          
          if color == nil then
            color = 0x000000
          end
          
          local minColorDist = math.abs(color - colorMin)
          local maxColorDist = math.abs(color - colorMax)
          
          if minColorDist > maxColorDist then
            arr[y1][x1] = true
          else
            arr[y1][x1] = false
          end
        end
      end
      
      --if getBraille(arr) == unicode.char(0x2800) then
      if not (colorMin == bgColor and colorMax == fgColor) then
        if #str > 0 then
          gpu.set(x + 13 - unicode.len(str), y, str)
          str = ""
        end
        
        gpu.setBackground(colorMin)
        gpu.setForeground(colorMax)
        bgColor = colorMin
        fgColor = colorMax
      end
      
      str = str .. getBraille(arr)
    end
    
    if #str > 0 then
      gpu.set(135 + 13 - unicode.len(str), y, str)
      str = ""
    end
  end
  
  gpu.bitblt()
  
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, 160, 50, " ")
end

local status, result = xpcall(main, function(msg)
  gpu.freeAllBuffers() -- very important in order to restore drawing to the screen since OpenOS doesn't reset GPU state on program exit
  
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fil(1, 1, 160, 50, " ")
  
  if type(msg) == "table" and msg.reason == "terminated" then
    return msg
  end
  
  io.stderr:write(tostring(msg) .. "\n" .. debug.traceback(nil, 5))
end)

if not status and result then
  error(result) -- rethrow the os.exit error object
end