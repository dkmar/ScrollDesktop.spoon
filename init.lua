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
  self.gestureActive = false   -- true while we are consuming scroll events
  self.exemptWindow  = nil     -- window id to leave stationary   (⇧)
  self.onlyWindow    = nil     -- window object to move exclusively (⌥)
  self.onlyRightOf   = nil     -- x-coordinate column lock        (⌃)
  self.currentWindows = nil    -- cached window list for this gesture
  self.positions      = {}     -- virtual positions for off-screen windows
  self.xmax           = hs.screen.mainScreen():fullFrame().w

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
      self.gestureActive = false
      return false
    end

    -----------------------------------------------------------------------
    --  Only act while the cmd key is depressed
    -----------------------------------------------------------------------
    local mod = hs.eventtap.checkKeyboardModifiers()
    if not mod.cmd then
      self.gestureActive = false
      return false           -- let macOS / the app handle the scroll
    end

    -----------------------------------------------------------------------
    --  First horizontal event with RMB held → initialise gesture
    -----------------------------------------------------------------------
    local beginEvent = not self.gestureActive
    if beginEvent then
      self.gestureActive = true

      local dy     = event:getProperty(axis1)
      -- cheap filter: abort if vertical intent seems stronger
      if math.abs(dy) > math.abs(dx) then
        self.gestureActive = false
        return false
      end

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

      -------------------------------------------------------------------
      --  If no ⌥ override, capture the full ordered window list
      -------------------------------------------------------------------
      if not self.onlyWindow then
        self.currentWindows = hs.window.orderedWindows()
      end
    end

    -----------------------------------------------------------------------
    --  Perform the actual scrolling
    -----------------------------------------------------------------------
    self:scrollWindows(dx)
    return true -- swallow the event

  end):start()
end


---------------------------------------------------------------------------
--  Move windows horizontally by dx
---------------------------------------------------------------------------
function ScrollDesktop:scrollWindows(dx)
  for _, window in ipairs(self.currentWindows or {}) do
    local id = window:id()

    -- ⇧  exempt window
    if id ~= self.exemptWindow then

      ---------------------------------------------------------------------
      --  Determine the logical origin (real frame or virtual off-screen)
      ---------------------------------------------------------------------
      local origin = self.positions[id] or window:topLeft()

      ---------------------------------------------------------------------
      --  ⌃  column-lock logic
      ---------------------------------------------------------------------
      local x = origin.x + dx
      if self.onlyRightOf then
        local isRight = origin.x > self.onlyRightOf
                     or (origin.x == self.onlyRightOf and dx > 0)
        if not isRight then goto continue end
        if x <= self.onlyRightOf then x = self.onlyRightOf + 1 end
      end

      ---------------------------------------------------------------------
      --  Clamp to edges, maintain virtual position when outside
      ---------------------------------------------------------------------
      local outside = false
      local minx    = -window:size().w
      if     x > self.xmax - 1 then
        outside = true; x = self.xmax - 1
      elseif x < minx + 1 then
        outside = true; x = minx + 1
      end

      if outside then
        self.positions[id] = { x = origin.x + dx, y = origin.y }
      else
        self.positions[id] = nil
      end

      ---------------------------------------------------------------------
      --  ⌥ → move cursor with the window
      ---------------------------------------------------------------------
      if self.onlyWindow then
        local pos = hs.mouse.getRelativePosition()
        pos.x = pos.x + x - window:topLeft().x
        hs.mouse.setRelativePosition(pos)
      end

      ---------------------------------------------------------------------
      --  Finally set the new window position
      ---------------------------------------------------------------------
      window:setTopLeft(x, origin.y)
    end
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
