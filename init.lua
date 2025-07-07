---------------------------------------------------------------------------
--  ScrollDesktop.spoon
--  Horizontal “infinite desktop” panning activated while RIGHT mouse
--  button is held down.
--
-- original credit: John Ankarström @ https://github.com/jocap/ScrollDesktop.spoon
---------------------------------------------------------------------------

---------------------------------------------------------------------------
--  Helpers
---------------------------------------------------------------------------
local function get_window_under_mouse()
  -- make sure hs.application cache is populated (a quirk of Hammerspoon)
  local _ = hs.application

  local pt      = hs.geometry.new(hs.mouse.absolutePosition())
  local screen  = hs.mouse.getCurrentScreen()

  return hs.fnutils.find(hs.window.orderedWindows(), function(w)
    return w:screen() == screen and pt:inside(w:frame())
  end)
end

---------------------------------------------------------------------------
--  Local aliases for EventTap constants
---------------------------------------------------------------------------
local scrollWheel <const> = hs.eventtap.event.types.scrollWheel
local axis1 <const> = hs.eventtap.event.properties.scrollWheelEventPointDeltaAxis1 -- vertical
local axis2 <const> = hs.eventtap.event.properties.scrollWheelEventPointDeltaAxis2 -- horizontal
local checkKeyboardModifiers <const> = hs.eventtap.checkKeyboardModifiers


---------------------------------------------------------------------------
--  Spoon metadata
---------------------------------------------------------------------------
local ScrollDesktop       = {}
ScrollDesktop.__index     = ScrollDesktop
ScrollDesktop.name        = "ScrollDesktop"
ScrollDesktop.version     = "0.2"
ScrollDesktop.author      = "John Ankarström x dkmar"
ScrollDesktop.homepage    = "https://github.com/dkmar/ScrollDesktop.spoon"
ScrollDesktop.license     = "MIT - https://opensource.org/licenses/MIT"

---------------------------------------------------------------------------
--  Start
---------------------------------------------------------------------------
function ScrollDesktop:start(opt)
  opt = opt or {}

  -------------------------------------------------------------------------
  --  State
  -------------------------------------------------------------------------
  self.exemptWindow  = nil     -- window id to leave stationary   (⇧)
  self.onlyWindow    = nil     -- window object to move exclusively (⌥)
  self.onlyRightOf   = nil     -- x-coordinate column lock        (⌃)
  self.currentWindows = {}    -- cached window list for this gesture
  self.positions      = {}     -- virtual positions for off-screen windows
  self.xmax           = 0

  local active = false   -- true while we are consuming scroll events
  -------------------------------------------------------------------------
  --  Event-tap
  -------------------------------------------------------------------------
  self.tap = hs.eventtap.new({ scrollWheel }, function(event)
    -----------------------------------------------------------------------
    --  Ignore scroll events that have no horizontal component
    -----------------------------------------------------------------------
    local dx = event:getProperty(axis2)
    if dx == 0 then
      -- reset if we were active but user switched to vertical scrolling
      active = false
      return false
    end

    -----------------------------------------------------------------------
    --  Only act while the cmd key is depressed
    -----------------------------------------------------------------------
    local mod = checkKeyboardModifiers()
    if not mod.cmd then
      active = false
      return false           -- let macOS / the app handle the scroll
    end

    -----------------------------------------------------------------------
    --  First horizontal event with RMB held → initialise gesture
    -----------------------------------------------------------------------
    if not active then
      active = true

      local dy     = event:getProperty(axis1)
      -- cheap filter: abort if vertical intent seems stronger
      if math.abs(dy) > math.abs(dx) then
        active = false
        return false
      end

      -- additional modifiers held
      if #mod > 1 then
        local window = get_window_under_mouse()
        -------------------------------------------------------------------
        --  ⇧  Don’t move window under pointer
        -------------------------------------------------------------------
        if window and mod.shift then
            self.exemptWindow = window:id()
        else
            self.exemptWindow = nil
        end

        -------------------------------------------------------------------
        --  ⌥  Move only window under pointer (cursor “sticks” to it)
        -------------------------------------------------------------------
        if window and mod.alt then
            window:focus()
            self.onlyWindow    = window
            self.currentWindows = { window }
        else
            self.onlyWindow     = nil
        end

        -------------------------------------------------------------------
        --  ⌃  Only windows to the right of the pointer
        -------------------------------------------------------------------
        if mod.ctrl then
            self.onlyRightOf = hs.mouse:getRelativePosition().x
        else
            self.onlyRightOf = nil
        end
      end

      local gestureScreen = hs.mouse.getCurrentScreen()
      local screenFrame = gestureScreen:fullFrame()
      self.xmin, self.xmax = screenFrame.x, screenFrame.x + screenFrame.w
      -------------------------------------------------------------------
      --  If no ⌥ override, capture the full ordered window list
      -------------------------------------------------------------------
      if not self.onlyWindow then
        -- current screen only
        self.currentWindows = hs.fnutils.filter(
            hs.window.orderedWindows(),
            function(w) return w:screen() == gestureScreen end
        )
      end
    end

    -----------------------------------------------------------------------
    --  Perform the actual scrolling
    -----------------------------------------------------------------------
    self:scrollWindows(dx)
    return true -- swallow the event

  end):start()
end


local function resolve_position(cachedPos, currPos)
  -- if y differs, the cache is stale and the user has moved the window manually
  if cachedPos == nil or cachedPos.y ~= currPos.y then
    return currPos
  else
    return cachedPos
  end
end

---------------------------------------------------------------------------
--  Move windows horizontally by dx
---------------------------------------------------------------------------
function ScrollDesktop:scrollWindows(dx)
  for _, window in ipairs(self.currentWindows) do
    local id = window:id()

    -- Skip exempt window (⇧ modifier)
    if id == self.exemptWindow then goto continue end

    -- Get current logical position (virtual or real)
    local curr = resolve_position(self.positions[id],window:topLeft())
    local newX = curr.x + dx

    -- Apply column lock constraint (⌃ modifier)
    if self.onlyRightOf then
      local isRightOfColumn = curr.x > self.onlyRightOf or
      (curr.x == self.onlyRightOf and dx > 0)
      if not isRightOfColumn then goto continue end

      newX = math.max(newX, self.onlyRightOf + 1)
    end

    -- Calculate clamped position and track if window goes off-screen
    local windowWidth = window:frame().w
    local minX = self.xmin - windowWidth + 1
    local maxX = self.xmax - 1
    local clampedX = math.max(minX, math.min(newX, maxX))
    local isOffScreen = clampedX ~= newX

    -- Update virtual position tracking
    if isOffScreen then
      self.positions[id] = { x = newX, y = curr.y }
    else
      self.positions[id] = nil
    end

    -- Move cursor with window (⌥ modifier)
    if self.onlyWindow then
      local mousePos = hs.mouse.getRelativePosition()
      mousePos.x = mousePos.x + clampedX - window:topLeft().x
      hs.mouse.setRelativePosition(mousePos)
    end

    -- Apply the movement
    window:setTopLeft(clampedX, curr.y)

    ::continue::
  end
end


---------------------------------------------------------------------------
--  Stop
---------------------------------------------------------------------------
function ScrollDesktop:stop()
  if self.tap then
    self.tap:stop()
    self.tap = nil
  end
end

return ScrollDesktop
