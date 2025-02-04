local process = require("process")
local thread = require("thread")
local event = require("event")
local component = require("component")

local gpu = component.gpu

local function main()
  local video = thread.create(loadfile("/home/video.lua"))
  
  local audio = thread.create(function()
    os.sleep(1.1)
    
    loadfile("/home/music.lua")("/home/Bad Apple!!.mus")
  end)
  
  event.listen("interrupted", function()
    audio:kill()
    
    return false -- unregister this listener
  end)
  
  thread.waitForAll({video, audio})
end

local status, result = xpcall(main, function(msg)
  gpu.freeAllBuffers() -- restore GPU to the screen in case the video thread crashes
  
  io.stderr:write(tostring(msg) .. "\n" .. debug.traceback())
end)

if not status then
  gpu.freeAllBuffers() -- just for good measure, really make sure the GPU is hooked to the screen and not virtual memory
end