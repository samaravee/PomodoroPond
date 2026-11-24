-- Goo Ripples: Node script for Rive.
--
-- Setup
--   1. In the Assets panel click +, choose Script, and pick the type "Shader" (it is called
--      "WGSL Shader" in some versions, and it is NOT "Blank"). Name it exactly
--      GooRipplesShader and paste in GooRipples.wgsl. Don't paste the WGSL into a Blank
--      script: Blank scripts expect Luau.
--   2. Create a script of type "Node" and paste this file in.
--   3. Add the Node script to your scene on a Node placed at the top-left corner of the
--      area you want covered, and set the width / height inputs to that area's size.
--      Put it ABOVE the things you want the water to sit over (top of the draw order).
--   4. Select Shader Targets for the runtimes you ship to (file-level option in the
--      Inspector when nothing is selected).
--
-- Pointer events: this script only WATCHES the pointer. It never calls event:hit(), so
-- every event keeps travelling to the hit targets, listeners and buttons underneath it.

local MAXC = 24            -- click ring slots (must match the shader)
local MAXT = 128           -- trail points (must match the shader)
local STEP = 1 / 240       -- the boat is simulated in small fixed steps
local STMAX = 4            -- highest wake strength the trail can carry (must match the shader)

-- Byte layout of the uniform buffer (must match `struct Uniforms` in the shader).
-- WGSL rules: vec2 aligns to 8, vec4 and array elements to 16.
local UBO_SIZE = 2480
local OFF_RES = 0          -- vec2  res
local OFF_TIME = 8         -- f32   time
local OFF_SHOWBG = 12      -- f32   showBg
local OFF_SLOSH = 16       -- vec4  slosh
local OFF_HEAD = 32        -- vec4  head (x, y, strength, unused)
local OFF_CLICKS = 48      -- 24 x vec4  (x, y, start time, strength)
local OFF_PT = 432         -- 128 x vec4 (x, y, spawn time, arc + strength)

type Spring = {
  axis: number, -- 1 = x, 2 = y
  w: number,    -- angular frequency
  z: number,    -- damping (low = a little bounce)
  amp: number,  -- push from a full-speed swipe
  x: number,
  v: number,
}

type GooRipples = {
  -- Script inputs (editor sidebar / data binding)
  width: Input<number>,
  height: Input<number>,
  renderScale: Input<number>, -- 1 = full resolution, 2 = half resolution (cheaper, softer)
  showBackground: Input<boolean>,
  hoverStrength: Input<number>, -- wake strength while just hovering (0 to 4, 1 = the original look)
  dragStrength: Input<number>,  -- wake strength while the button is held / finger is down (0 to 4)

  -- Diagnostics (each message is logged once to the Console)
  ctx: Context?,
  loggedDraw: boolean,
  loggedMove: boolean,
  loggedDown: boolean,

  -- GPU objects
  canvas: GPUCanvas?,
  pipeline: GPUPipeline?,
  bindGroup: GPUBindGroup?,
  ubo: GPUBuffer?,
  data: buffer?,
  sampler: ImageSampler?,
  cw: number, -- canvas size in pixels (width / renderScale)
  ch: number,

  -- Clock and fixed-step accumulator
  time: number,
  acc: number,

  -- Pointer and boat
  hasPointer: boolean,
  boatReady: boolean,
  curX: number,
  curY: number,
  tx: number,
  ty: number,
  bx: number,
  by: number,
  bvx: number,
  bvy: number,
  spf: number,
  headS: number,
  lastPx: number,
  lastPy: number,
  moving: boolean,
  pathLen: number,
  pressed: boolean, -- button held or finger down
  pressK: number,   -- 0 = hovering, 1 = pressing (eased, so the wake swells instead of jumping)

  -- Trail points (ring buffer; ptHead is the newest slot)
  ptX: { number },
  ptY: { number },
  ptT: { number },
  ptW: { number },
  ptHead: number,

  -- Click rings (ring buffer)
  clX: { number },
  clY: { number },
  clT: { number },
  clW: { number },
  clIdx: number,

  -- Whole-surface slosh springs
  sl: { Spring },
}

-- Canvas size in pixels. The shader always works in the full width x height space (the
-- "design" size), so a smaller canvas just means fewer pixels are shaded.
local function canvasSize(self: GooRipples): (number, number)
  local s = math.max(1, self.renderScale)
  return math.max(1, math.floor(self.width / s)), math.max(1, math.floor(self.height / s))
end

local function clamp(v: number, lo: number, hi: number): number
  return math.max(lo, math.min(hi, v))
end

local function smooth01(a: number, b: number, x: number): number
  local k = clamp((x - a) / (b - a), 0, 1)
  return k * k * (3 - 2 * k)
end

-- Newest point goes in the next slot of the ring
local function pushPoint(self: GooRipples, x: number, y: number, t: number, w: number)
  self.ptHead = (self.ptHead + 1) % MAXT
  local i = self.ptHead + 1
  self.ptX[i] = x
  self.ptY[i] = y
  self.ptT[i] = t
  self.ptW[i] = w
end

-- Each click spawns 1-3 rings a little apart in time, each a bit weaker than the last
local function addClick(self: GooRipples, x: number, y: number)
  -- a small kick so the whole surface answers the disturbance
  for i, m in ipairs(self.sl) do
    local sign = if math.random() < 0.5 then -1 else 1
    m.v += sign * (if i % 2 == 1 then 0.9 else 0.7)
  end

  local n = math.random(1, 3)
  local delay = 0
  for i = 0, n - 1 do
    local s = self.clIdx + 1
    self.clX[s] = x
    self.clY[s] = y
    self.clT[s] = self.time + delay
    self.clW[s] = 1 - 0.13 * i
    self.clIdx = (self.clIdx + 1) % MAXC
    delay += 0.10 + math.random() * 0.07
  end
end

local function stepSlosh(self: GooRipples, dt: number)
  local vn = {
    clamp(self.bvx / 1600, -1, 1),
    clamp(self.bvy / 1600, -1, 1),
  }
  for _, m in ipairs(self.sl) do
    local a = vn[m.axis] * m.amp * m.w * m.w - m.w * m.w * m.x - 2 * m.z * m.w * m.v
    m.v += a * dt
    m.x += m.v * dt
  end
end

-- Put the boat under the pointer and start a fresh trail
local function teleport(self: GooRipples, x: number, y: number)
  self.tx = x
  self.ty = y
  self.bx = x
  self.by = y
  self.lastPx = x
  self.lastPy = y
  self.bvx = 0
  self.bvy = 0
  self.spf = 0
  self.headS = 0
  self.moving = false
  for i = 1, MAXT do
    self.ptT[i] = -1000
  end
  self.boatReady = true
end

function init(self: GooRipples, context: Context): boolean
  self.ctx = context
  self.cw, self.ch = canvasSize(self)

  self.canvas = context:gpuCanvas({ width = self.cw, height = self.ch })
  local shader = context:shader('GooRipplesShader')

  local canvas = self.canvas
  if canvas and shader then
    -- Build into locals first: self.pipeline and self.ubo are optional fields, so the type
    -- checker won't accept them as plain values right after assigning.
    local pipeline = GPUPipeline.new({
      vertex = shader,
      fragment = shader,
      -- Positions come from vertex_index, so there is no vertex buffer.
      vertexLayout = {},
      colorTargets = { { format = canvas.format } },
    })
    local ubo = GPUBuffer.new({ size = UBO_SIZE, usage = 'uniform' })
    local bindGroup = GPUBindGroup.new({
      layout = pipeline:getBindGroupLayout(0),
      ubos = { { slot = 0, buffer = ubo } },
    })

    self.pipeline = pipeline
    self.ubo = ubo
    self.bindGroup = bindGroup
    print('GooRipples: init OK. canvas ' .. self.cw .. 'x' .. self.ch .. ', shader found')
  else
    print(
      'GooRipples: init FAILED. canvas created = '
        .. tostring(canvas ~= nil)
        .. ', shader asset named GooRipplesShader found = '
        .. tostring(shader ~= nil)
    )
  end

  self.data = buffer.create(UBO_SIZE)
  self.sampler = ImageSampler('clamp', 'clamp', 'bilinear')
  return true
end

function advance(self: GooRipples, seconds: number): boolean
  self.time += seconds
  local fdt = math.min(seconds, 0.05)

  -- Follow the size inputs
  if self.canvas then
    local w, h = canvasSize(self)
    if w ~= self.cw or h ~= self.ch then
      self.cw = w
      self.ch = h
      self.canvas:resize(w, h)
    end
  end

  if self.boatReady then
    self.acc += fdt
    while self.acc >= STEP do
      self.acc -= STEP

      -- Lightly smoothed cursor (hides event-timing noise)
      local follow = 1 - math.exp(-STEP * 30)
      self.tx += (self.curX - self.tx) * follow
      self.ty += (self.curY - self.ty) * follow

      -- Drag: damped spring toward the cursor (higher w = tighter, less lag)
      local w = 2 * math.pi * 3.2
      local z = 0.85
      self.bvx += (w * w * (self.tx - self.bx) - 2 * z * w * self.bvx) * STEP
      self.bvy += (w * w * (self.ty - self.by) - 2 * z * w * self.bvy) * STEP
      self.bx += self.bvx * STEP
      self.by += self.bvy * STEP

      -- Smoothed speed drives the blob and the trail
      local speed = math.sqrt(self.bvx * self.bvx + self.bvy * self.bvy)
      self.spf += (speed - self.spf) * (1 - math.exp(-STEP * 10))
      -- Press state eases over about 0.1 s, then scales the strength between hover and drag
      local pk = if self.pressed then 1 else 0
      self.pressK += (pk - self.pressK) * (1 - math.exp(-STEP * 12))
      local power = clamp(self.hoverStrength + (self.dragStrength - self.hoverStrength) * self.pressK, 0, STMAX)
      self.headS = math.min(1, 0.35 + self.spf / 800) * smooth01(8, 70, self.spf) * power -- can exceed 1 now

      -- Lay down trail points at an even spacing along the path
      if self.spf < 30 then
        self.lastPx = self.bx
        self.lastPy = self.by
        self.moving = false
      else
        if not self.moving then
          self.moving = true
          self.pathLen = math.random() * 4096 -- each stroke varies differently
        end
        local gap = math.min(14, math.max(6, self.spf * 0.02))
        local dx = self.bx - self.lastPx
        local dy = self.by - self.lastPy
        local dist = math.sqrt(dx * dx + dy * dy)
        while dist >= gap do
          local k = gap / dist
          self.lastPx += (self.bx - self.lastPx) * k
          self.lastPy += (self.by - self.lastPy) * k
          self.pathLen += gap
          -- Pack three things into one number: distance along the stroke (whole part, 2px steps,
          -- wraps at 4096px), and in the fraction the boat's speed (6 bits, 30px/s steps) and
          -- strength (7 bits, covering 0 to STMAX). Float32 holds this exactly.
          local arc2 = math.floor((self.pathLen % 4096) / 2)
          local stQ = math.min(127, math.floor(self.headS / STMAX * 127 + 0.5))
          local spdQ = math.min(63, math.floor(self.spf / 30 + 0.5))
          local packed = arc2 + (spdQ * 128 + stQ) / 8192
          pushPoint(self, self.lastPx, self.lastPy, self.time - self.acc, packed)
          dx = self.bx - self.lastPx
          dy = self.by - self.lastPy
          dist = math.sqrt(dx * dx + dy * dy)
        end
      end
    end
  end

  stepSlosh(self, math.min(fdt, 0.033))
  return true
end

-- Fill the uniform buffer from the current state
local function upload(self: GooRipples)
  local b = self.data
  local ubo = self.ubo
  if not b or not ubo then
    return
  end

  buffer.writef32(b, OFF_RES, self.width) -- design size, not canvas pixels
  buffer.writef32(b, OFF_RES + 4, self.height)
  buffer.writef32(b, OFF_TIME, self.time)
  buffer.writef32(b, OFF_SHOWBG, if self.showBackground then 1 else 0)

  for i = 1, 4 do
    buffer.writef32(b, OFF_SLOSH + (i - 1) * 4, self.sl[i].x)
  end

  local strength = self.headS
  buffer.writef32(b, OFF_HEAD, self.bx)
  buffer.writef32(b, OFF_HEAD + 4, self.by)
  buffer.writef32(b, OFF_HEAD + 8, strength)
  buffer.writef32(b, OFF_HEAD + 12, 0)

  for i = 1, MAXC do
    local o = OFF_CLICKS + (i - 1) * 16
    buffer.writef32(b, o, self.clX[i])
    buffer.writef32(b, o + 4, self.clY[i])
    buffer.writef32(b, o + 8, self.clT[i])
    buffer.writef32(b, o + 12, self.clW[i])
  end

  -- Trail points, newest first
  for i = 0, MAXT - 1 do
    local slot = (self.ptHead - i) % MAXT + 1
    local o = OFF_PT + i * 16
    buffer.writef32(b, o, self.ptX[slot])
    buffer.writef32(b, o + 4, self.ptY[slot])
    buffer.writef32(b, o + 8, self.ptT[slot])
    buffer.writef32(b, o + 12, self.ptW[slot])
  end

  ubo:write(b)
end

function draw(self: GooRipples, renderer: Renderer)
  local canvas = self.canvas
  local pipeline = self.pipeline
  local bindGroup = self.bindGroup
  if not canvas or not pipeline or not bindGroup then
    return
  end

  upload(self)
  if not self.loggedDraw then
    self.loggedDraw = true
    print('GooRipples: first draw, showBackground = ' .. tostring(self.showBackground))
  end

  -- Render the shader into the GPU canvas (transparent where the water has no effect)
  local pass = canvas:beginRenderPass({
    color = {
      { loadOp = 'clear', storeOp = 'store', clearColor = { 0, 0, 0, 0 } },
    },
  })
  pass:setPipeline(pipeline)
  pass:setBindGroup(0, bindGroup)
  pass:draw(3)
  pass:finish()

  -- Composite it into the scene, scaled back up to the full width x height
  if self.sampler then
    renderer:save()
    renderer:transform(Mat2D.withScale(self.width / self.cw, self.height / self.ch))
    renderer:drawImage(canvas.image, self.sampler, 'srcOver', 1)
    renderer:restore()
  end
end

-- Pointer handling. These only observe: none of them call event:hit(), so every pointer
-- event keeps going to the hit targets and listeners underneath this script.
function pointerMove(self: GooRipples, event: PointerEvent)
  local x = event.position.x
  local y = event.position.y
  self.curX = x
  self.curY = y
  if not self.loggedMove then
    self.loggedMove = true
    print('GooRipples: first pointerMove at ' .. math.floor(x) .. ', ' .. math.floor(y))
  end
  if not self.boatReady or not self.hasPointer then
    teleport(self, x, y) -- first move, or pointer just came back in
  end
  self.hasPointer = true
end

function pointerDown(self: GooRipples, event: PointerEvent)
  local x = event.position.x
  local y = event.position.y
  if not self.loggedDown then
    self.loggedDown = true
    print('GooRipples: first pointerDown at ' .. math.floor(x) .. ', ' .. math.floor(y))
  end
  if not self.boatReady then
    self.curX = x
    self.curY = y
    teleport(self, x, y)
  end
  self.hasPointer = true
  self.pressed = true
  addClick(self, x, y)
end

function pointerUp(self: GooRipples, event: PointerEvent)
  self.pressed = false
end

function pointerExit(self: GooRipples, event: PointerEvent)
  self.hasPointer = false -- next move starts a fresh trail
  self.pressed = false
end

return function(): Node<GooRipples>
  -- Fresh state for every instance of the script
  local ptX: { number } = {}
  local ptY: { number } = {}
  local ptT: { number } = {}
  local ptW: { number } = {}
  for i = 1, MAXT do
    ptX[i] = 0
    ptY[i] = 0
    ptT[i] = -1000
    ptW[i] = 0
  end

  local clX: { number } = {}
  local clY: { number } = {}
  local clT: { number } = {}
  local clW: { number } = {}
  for i = 1, MAXC do
    clX[i] = 0
    clY[i] = 0
    clT[i] = -1000
    clW[i] = 0
  end

  -- Whole-surface slosh: two modes per axis.
  -- w = angular frequency, z = damping (low = a little bounce), amp = push at full speed.
  local sl: { Spring } = {
    { axis = 1, w = 2 * math.pi * 0.55, z = 0.10, amp = 0.55, x = 0, v = 0 },
    { axis = 1, w = 2 * math.pi * 0.95, z = 0.14, amp = 0.30, x = 0, v = 0 },
    { axis = 2, w = 2 * math.pi * 0.55, z = 0.10, amp = 0.55, x = 0, v = 0 },
    { axis = 2, w = 2 * math.pi * 0.95, z = 0.14, amp = 0.30, x = 0, v = 0 },
  }

  return {
    -- Inputs
    width = 800,
    height = 600,
    renderScale = 1,
    showBackground = false, -- false = transparent overlay, true = draw the built-in backdrop
    hoverStrength = 1.0,    -- wake while hovering (1 = how it looked before)
    dragStrength = 2.0,     -- wake while click-dragging. Try 1.5 to 3. Max 4

    ctx = nil,
    loggedDraw = false,
    loggedMove = false,
    loggedDown = false,

    canvas = nil,
    pipeline = nil,
    bindGroup = nil,
    ubo = nil,
    data = nil,
    sampler = nil,
    cw = 800,
    ch = 600,

    time = 0,
    acc = 0,

    hasPointer = false,
    boatReady = false,
    curX = 0,
    curY = 0,
    tx = 0,
    ty = 0,
    bx = 0,
    by = 0,
    bvx = 0,
    bvy = 0,
    spf = 0,
    headS = 0,
    lastPx = 0,
    lastPy = 0,
    moving = false,
    pathLen = 0,
    pressed = false,
    pressK = 0,

    ptX = ptX,
    ptY = ptY,
    ptT = ptT,
    ptW = ptW,
    ptHead = -1,

    clX = clX,
    clY = clY,
    clT = clT,
    clW = clW,
    clIdx = 0,

    sl = sl,

    init = init,
    advance = advance,
    draw = draw,
    pointerMove = pointerMove,
    pointerDown = pointerDown,
    pointerUp = pointerUp,
    pointerExit = pointerExit,
  }
end
