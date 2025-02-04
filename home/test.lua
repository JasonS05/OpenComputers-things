local x = 0
local y = 0

xpcall(error, function()
  x = x + 1
  y = 0
  xpcall(error, function()
    y = y + 1
    
    error()
  end)
  print("x: ", x)
  --print("y: ", y)
  error()
end)

print(x)
print(y)