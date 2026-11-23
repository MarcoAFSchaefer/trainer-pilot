-- Trainer Pilot: a training and hunting bot that plays through the game's own buttons.
--
-- It walks a route the player recorded (or stands on a marked spot), fights
-- with the battle menu, finds its way to the nearest Pokémon Center through a
-- map of how maps connect, and stops on the conditions the player chose. It
-- can hunt for Pokémon that match detailed targets and catch them, train EVs,
-- and hunt by resetting (save in front of a Pokémon, reload until it fits).
--
-- What it changes in the game is limited to what a player could do: button
-- presses, using an item from the bag, putting a party member in front, and,
-- for reset hunting, saving once and loading that save again (while such a hunt
-- exists, no other save may be written over it).
--
-- main.lua holds the bot; panel.lua draws its control panel for Trainer Desk.
-- See docs/ARCHITECTURE.md for a map of this file.
return function(mod)
  if mod.generation ~= 3 then return end

  -- The panel's language (lang/<code>.lua, read through i18n.lua).
  if mod.options and mod.options.define then
    pcall(mod.options.define, mod.options, {
      { key = "language", label = "LANGUAGE", type = "choice", default = "en",
        choices = { { "ENGLISH", "en" }, { "ESPANOL", "es" }, { "PORTUGUES", "pt" }, { "JAPANESE", "ja" } },
        description = "Language of the control panel. Names that come from the game (Pokemon, moves, items) stay in the game's language." },
    })
  end
  local function language()
    local ok, value = pcall(function() return mod.options:get("language") end)
    return ok and value or "en"
  end
  local I18n = assert(load(assert(mod:read("i18n.lua")), "@trainer_pilot/i18n.lua"))()(mod, language)
  local floor, max, min, abs = math.floor, math.max, math.min, math.abs

  local function req(name)
    local ok, m = pcall(require, name)
    if ok and type(m) == "table" then return m end
  end
  local function try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
  end

  -- Waiting is measured in game steps AND in real seconds: at high game speed
  -- hundreds of steps pass in a blink while a map is still loading.
  local Bot
  local function mark() return { tick = Bot.stats.ticks, clock = love.timer.getTime() } end
  local function late(since, ticks, seconds)
    return since ~= nil and Bot.stats.ticks - since.tick > ticks and love.timer.getTime() - since.clock > seconds
  end

  ---------------------------------------------------------------------------
  -- Saved data: routes and settings
  ---------------------------------------------------------------------------
  local ROUTES_KEY, CONFIG_KEY = "routes/v1", "config/v1"
  local KINDS = { grass = true, fish = true, seeker = true, heal = true, scent = true }
  Bot = {
    routes = {},                -- { name, kind, points = { { map, x, y, dir } } }
    config = {
      train = nil, heal = nil,  -- route names
      healOn = true, hpPct = 30, stopLevel = 0,
      stopShiny = true, stopLearn = true, stopEvolve = true,
      travelRun = true,         -- run from wild Pokémon met on the way to the Center or to the route
      stopNoPP = false,         -- stop when the one fighting runs out of PP (else: switch, then heal)
      species = {},             -- [species id] = true: stop when one appears
      policy = "selected",      -- who fights is always the marked slots
      selected = { [1] = true },-- [party slot] = true
      huntExp = false,          -- fight the ones that do not fit (else run from them)
      huntShiny = true,         -- a hunt also stops for any shiny
      huntScent = false,        -- on a grass route, call encounters with Sweet Scent instead of walking
      huntCatch = false,        -- try to catch a target (else only stop)
      catchContinue = true,     -- after a catch, go on hunting
      catchWeaken = true,       -- bring its HP down first, only with a move that cannot make it faint
      catchFalseSwipe = false,  -- ...and only with False Swipe
      catchStatus = true,       -- put it to sleep or paralyse it before the ball
      catchHeal = false,        -- go to the Center after every catch attempt
      useMaster = false,        -- the Master Ball may be thrown
      ballOrder = "2,3,4",      -- item ids, first choice first (2 Ultra, 3 Great, 4 Poké)
      safariBaits = 2,          -- in the Safari Zone: this many baits, then...
      safariBalls = 3,          -- ...this many balls, over and over until it is caught or flees
      evTargets = {},           -- ["<personality>"] = { hp, atk, def, spe, spa, spd }: EVs that Pokémon is training for
      itemHp = 0,               -- potions the bot may use in a run before going to the Center; -1 for no limit
      itemPp = 0,               -- the same for Ethers and Elixirs
      resetCatch = false,       -- reset hunting: try to catch the target (else only stop)
      safariReentries = 0,      -- how many times to pay and go back in when a visit ends; -1 for no limit
      targets = {},             -- { species, gender, ivTotal, ivs = { hp, atk, def, spe, spa, spd }, ability }
      banned = {},              -- ["<personality>:<move id>"] = true: a move the bot must not use
      speed = 0,                -- game speed while the bot runs; 0 leaves the game's own
      rod = 0,                  -- fishing rod item id (262 Old, 263 Good, 264 Super); 0 picks the best there is
    },
    running = false, status = "idle", reason = nil,
    stats = { battles = 0, heals = 0, seeker = 0, ticks = 0 },
    recording = nil,            -- { kind, points }
  }

  local IV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
  Bot.EV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
  function Bot.encodeEvTargets()
    local out = {}
    for who, t in pairs(Bot.config.evTargets) do
      local values, any = {}, false
      for index, key in ipairs(Bot.EV_KEYS) do
        values[index] = tostring(t[key] or 0)
        any = any or (t[key] or 0) > 0
      end
      if any then out[#out + 1] = who .. ":" .. table.concat(values, ".") end
    end
    table.sort(out)
    return table.concat(out, ";")
  end
  -- A target's name: letters, digits and spaces only, so it never breaks the saved settings.
  Bot.MAX_TARGETS = 30
  function Bot.cleanName(name)
    return (tostring(name or ""):gsub("[^%w ]", ""):gsub("^%s+", ""):sub(1, 20))
  end
  function Bot.encodeTargets()
    local out = {}
    for _, t in ipairs(Bot.config.targets) do
      out[#out + 1] = table.concat({ t.species, t.gender, t.ivTotal, t.ivs.hp, t.ivs.atk, t.ivs.def,
        t.ivs.spe, t.ivs.spa, t.ivs.spd, t.ability, -1, t.shiny and 1 or 0,
        t.levelMin or 0, t.levelMax or 0, t.hpType or -1, t.hpPower or 0, t.item and 1 or 0,
        (function()
          local list = {}
          for nature, on in pairs(t.natures or {}) do if on then list[#list + 1] = nature end end
          table.sort(list)
          return #list > 0 and table.concat(list, ".") or "-"
        end)(), Bot.cleanName(t.name) ~= "" and Bot.cleanName(t.name) or "-" }, ",")
    end
    return table.concat(out, ";")
  end
  local function cacheRead(key)
    return mod.cache and mod.cache.read and mod.cache:read(key) or nil
  end
  local function cacheWrite(key, text)
    if mod.cache and mod.cache.write then mod.cache:write(key, text) end
  end

  local function encodeRoutes()
    local lines = {}
    for _, route in ipairs(Bot.routes) do
      local points = {}
      for index, p in ipairs(route.points) do
        points[index] = ("%s,%d,%d,%s"):format(p.map, p.x, p.y, p.dir or "down")
      end
      lines[#lines + 1] = route.name .. "|" .. route.kind .. "|" .. table.concat(points, ";")
    end
    return table.concat(lines, "\n")
  end
  local function decodeRoutes(text)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\n]+") do
      local name, kind, body = line:match("^([^|]+)|(%a+)|(.*)$")
      if name and KINDS[kind] then
        local route = { name = name, kind = kind, points = {} }
        for map, x, y, dir in body:gmatch("([%w_]+),(-?%d+),(-?%d+),(%a+)") do
          route.points[#route.points + 1] = { map = map, x = tonumber(x), y = tonumber(y), dir = dir }
        end
        if #route.points > 0 then out[#out + 1] = route end
      end
    end
    return out
  end
  local function set(list)
    local keys = {}
    for key, on in pairs(list) do if on then keys[#keys + 1] = tostring(key) end end
    table.sort(keys)
    return table.concat(keys, ",")
  end
  local function encodeConfig()
    local c = Bot.config
    return table.concat({
      "train=" .. (c.train or ""), "heal=" .. (c.heal or ""), "healOn=" .. (c.healOn and 1 or 0),
      "hpPct=" .. c.hpPct, "stopLevel=" .. c.stopLevel, "stopShiny=" .. (c.stopShiny and 1 or 0),
      "stopLearn=" .. (c.stopLearn and 1 or 0), "stopEvolve=" .. (c.stopEvolve and 1 or 0),
      "travelRun=" .. (c.travelRun and 1 or 0), "stopNoPP=" .. (c.stopNoPP and 1 or 0),
      "species=" .. set(c.species), "selected=" .. set(c.selected), "speed=" .. c.speed, "rod=" .. c.rod,
      "banned=" .. set(c.banned), "huntExp=" .. (c.huntExp and 1 or 0), "huntShiny=" .. (c.huntShiny and 1 or 0), "huntScent=" .. (c.huntScent and 1 or 0),
      "huntCatch=" .. (c.huntCatch and 1 or 0), "catchContinue=" .. (c.catchContinue and 1 or 0),
      "catchWeaken=" .. (c.catchWeaken and 1 or 0), "catchFalseSwipe=" .. (c.catchFalseSwipe and 1 or 0),
      "catchStatus=" .. (c.catchStatus and 1 or 0), "catchHeal=" .. (c.catchHeal and 1 or 0),
      "useMaster=" .. (c.useMaster and 1 or 0), "ballOrder=" .. c.ballOrder, "safariBaits=" .. c.safariBaits, "safariBalls=" .. c.safariBalls, "safariReentries=" .. c.safariReentries, "resetCatch=" .. (c.resetCatch and 1 or 0), "itemHp=" .. c.itemHp, "itemPp=" .. c.itemPp,
      "targets=" .. Bot.encodeTargets(), "evTargets=" .. Bot.encodeEvTargets(),
    }, "\n")
  end
  local function decodeConfig(text)
    local c = Bot.config
    for key, value in tostring(text or ""):gmatch("([%a]+)=([^\n]*)") do
      if key == "train" or key == "heal" then c[key] = value ~= "" and value or nil
      elseif key == "healOn" or key == "stopShiny" or key == "stopLearn" or key == "stopEvolve"
          or key == "travelRun" or key == "stopNoPP" then c[key] = value == "1"
      elseif key == "hpPct" then c.hpPct = max(0, min(90, tonumber(value) or 30))
      elseif key == "stopLevel" then c.stopLevel = max(0, min(100, tonumber(value) or 0))
      elseif key == "huntExp" or key == "huntShiny" or key == "huntScent" or key == "huntCatch"
          or key == "catchContinue" or key == "catchWeaken" or key == "catchFalseSwipe" or key == "catchStatus"
          or key == "catchHeal" or key == "useMaster" or key == "resetCatch" then c[key] = value == "1"
      elseif key == "ballOrder" then if value:match("^[%d,]+$") then c.ballOrder = value end
      elseif key == "itemHp" or key == "itemPp" then c[key] = max(-1, min(99, floor(tonumber(value) or 0)))
      elseif key == "safariBaits" then c.safariBaits = max(0, min(5, tonumber(value) or 2))
      elseif key == "safariBalls" then c.safariBalls = max(1, min(9, tonumber(value) or 3))
      elseif key == "safariReentries" then c.safariReentries = max(-1, min(99, tonumber(value) or 0))
      elseif key == "evTargets" then
        c.evTargets = {}
        for who, values in value:gmatch("(%d+):([%d%.]+)") do
          local t, index = {}, 0
          for n in values:gmatch("%d+") do
            index = index + 1
            if Bot.EV_KEYS[index] then t[Bot.EV_KEYS[index]] = max(0, min(252, tonumber(n) or 0)) end
          end
          c.evTargets[who] = t
        end
      elseif key == "targets" then
        c.targets = {}
        for entry in value:gmatch("[^;]+") do
          local f = {}
          for field in entry:gmatch("[^,]+") do f[#f + 1] = field end
          if #f >= 10 then
            c.targets[#c.targets + 1] = { species = tonumber(f[1]) or 0, gender = (f[2] == "M" or f[2] == "F") and f[2] or "any",
              ivTotal = tonumber(f[3]) or 0, ability = tonumber(f[10]) or 0,
              shiny = f[12] == "1", levelMin = tonumber(f[13]) or 0, levelMax = tonumber(f[14]) or 0,
              hpType = tonumber(f[15]) or -1, hpPower = tonumber(f[16]) or 0, item = f[17] == "1",
              natures = (function()
                local out = {}
                -- one nature, as targets were saved before several could be chosen
                if (tonumber(f[11]) or -1) >= 0 then out[tonumber(f[11])] = true end
                for nature in tostring(f[18] or ""):gmatch("%d+") do out[tonumber(nature)] = true end
                return out
              end)(),
              name = (f[19] and f[19] ~= "-") and Bot.cleanName(f[19]) or nil,
              ivs = { hp = tonumber(f[4]) or 0, atk = tonumber(f[5]) or 0, def = tonumber(f[6]) or 0,
                spe = tonumber(f[7]) or 0, spa = tonumber(f[8]) or 0, spd = tonumber(f[9]) or 0 } }
          end
        end
      elseif key == "speed" then c.speed = max(0, min(200, tonumber(value) or 0))
      elseif key == "rod" then
        local rod = tonumber(value) or 0
        c.rod = (rod == 262 or rod == 263 or rod == 264) and rod or 0
      elseif key == "banned" then
        c.banned = {}
        for entry in value:gmatch("[^,]+") do c.banned[entry] = true end
      elseif key == "species" or key == "selected" then
        c[key] = {}
        for id in value:gmatch("%d+") do c[key][tonumber(id)] = true end
      end
    end
  end
  function Bot.save()
    cacheWrite(ROUTES_KEY, encodeRoutes())
    cacheWrite(CONFIG_KEY, encodeConfig())
  end
  Bot.routes = decodeRoutes(cacheRead(ROUTES_KEY))
  decodeConfig(cacheRead(CONFIG_KEY))
  function Bot.reloadConfig() decodeConfig(cacheRead(CONFIG_KEY)) end
  if not next(Bot.config.selected) then Bot.config.selected[1] = true end

  function Bot.route(name)
    for index, route in ipairs(Bot.routes) do
      if route.name == name then return route, index end
    end
  end
  function Bot.deleteRoute(name)
    local _, index = Bot.route(name)
    if not index then return end
    table.remove(Bot.routes, index)
    if Bot.config.train == name then Bot.config.train = nil end
    if Bot.config.heal == name then Bot.config.heal = nil end
    Bot.save()
  end

  ---------------------------------------------------------------------------
  -- The game, as the bot sees it
  ---------------------------------------------------------------------------
  local game
  local H                     -- host modules, loaded once the game is running
  local function host()
    if H then return H end
    local h = {
      Field = req("src.core.game3.field"), P = req("src.core.game3.player"),
      Map = req("src.core.game3.map"), Collision = req("src.core.game3.collision"),
      Objects = req("src.core.game3.objects"), Battle = req("src.core.game3.battle"),
      Pokemon = req("src.core.game3.pokemon"), Moves = req("src.core.game3.battle.moves"),
      Types = req("src.core.game3.battle.types"), Message = req("src.ui.game3.message"),
      Choice = req("src.ui.game3.choice"), PartyMenu = req("src.ui.game3.party_menu"),
      Evolution = req("src.ui.game3.evolution_scene"), ItemUse = req("src.core.game3.item_use"),
      Bag = req("src.core.game3.bag"), VsSeeker = req("src.core.game3.vs_seeker"),
      Safari = req("src.core.game3.safari"),
      Summary = req("src.core.game3.summary_data"), BattleUi = req("src.core.game3.battle.ui"),
      Compat = req("src.mods.Gen3Compat"), BattleAPI = req("src.battle.game3.BattleAPI"),
      BattleCore = req("src.core.game3.battle.init"),
      FieldMoves = req("src.core.game3.field_moves"), World = req("src.world.game3.WorldAPI"),
      Conn = req("src.core.game3.connections"), Space = req("src.core.game3.scripting.space"),
      Rng = req("src.core.game3.rng"), Ghosts = req("src.core.game3.ghosts"),
      Storage = req("src.core.game3.storage"),
    }
    if not (h.Field and h.P and h.Collision and h.Battle and h.Pokemon) then return nil end
    H = h
    return h
  end
  Bot.host = host
  local function session()
    return game and type(game.session) == "table" and game.session or nil
  end
  Bot.session = session

  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local DIRS = { "up", "down", "left", "right" }

  -- Where the player is, or is about to be once the current step ends.
  local function position()
    local h = host()
    local P = h.P
    local x, y = P.cellX or 0, P.cellY or 0
    if P.moving and P.targetX then x, y = P.targetX, P.targetY end
    return (h.Map and h.Map.current) or session().map, x, y
  end
  Bot.position = function()
    if not (host() and session()) then return nil end
    return position()
  end

  ---------------------------------------------------------------------------
  -- Buttons
  ---------------------------------------------------------------------------
  local held                  -- { dir, token }
  local lastTap = -100
  local function release()
    if held then
      pcall(mod.input.release, mod.input, held.token)
      held = nil
    end
  end
  local function hold(dir)
    if held and held.dir == dir then return end
    release()
    local ok, token = pcall(mod.input.press, mod.input, game, dir)
    if ok and token then held = { dir = dir, token = token } end
  end
  -- One press, no faster than every `gap` steps.
  local function tap(button, gap)
    local tick = Bot.stats.ticks
    if tick - lastTap < (gap or 8) then return false end
    lastTap = tick
    release()
    pcall(mod.input.tap, mod.input, game, button)
    return true
  end

  ---------------------------------------------------------------------------
  -- Walking: a breadth-first search over the cells the player may enter
  ---------------------------------------------------------------------------
  local function elevationOf(h, x, y, carried)
    local e = try(h.Collision.elevationAt, x, y)
    if e == nil or e == 0 or e == 15 then return carried end
    return e
  end
  local function isWarp(h, x, y)
    local behavior = try(h.Collision.behavior, x, y)
    return behavior ~= nil and try(h.Collision.isWarpMetatileBehavior, behavior) == true
  end
  -- The first direction of a shortest walk to (tx, ty), or to any cell next
  -- to it when `beside` is set. nil when there is no way.
  local pathCache = {}        -- the last walk worked out: { id, next = { [cell] = dir }, at }
  local function pathStep(tx, ty, beside, goal, goalId)
    local h = host()
    local C, P = h.Collision, h.P
    local map, sx, sy = position()
    local function done(x, y)
      if goal then return goal(x, y) end
      if beside then return abs(x - tx) + abs(y - ty) == 1 end
      return x == tx and y == ty
    end
    if done(sx, sy) then return "here" end
    local key = function(x, y) return x * 4096 + y end
    -- Returns the cell a step leads to, whether the player is on water there,
    -- and the field move the step needs ("surf" to get on the water, "cut"
    -- for a small tree), if the team can use it.
    local function enter(fx, fy, dir, elevation, surfing)
      local d = DELTA[dir]
      if not surfing then
        local lx, ly = try(C.ledgeLanding, game, fx, fy, dir)
        if lx then return lx, ly, false end
      end
      local nx, ny = fx + d[1], fy + d[2]
      if surfing and dir == "up" and Bot.isWaterfall(nx, ny) then
        -- a waterfall is climbed in one go, to the water above it
        if not Bot.canUse("WATERFALL") then return nil end
        local top = ny
        for _ = 1, 30 do
          if not Bot.isWaterfall(nx, top) then break end
          top = top - 1
        end
        if try(C.isWater, nx, top) ~= true then return nil end
        return nx, top, true, "waterfall"
      end
      local ok, why = try(C.canEnter, game, nx, ny, { fromX = fx, fromY = fy, dir = dir,
        surfing = surfing, elevation = elevation })
      local action
      if ok ~= true then
        -- the game may name the water's lower level as the reason, not the water itself
        if not surfing and why ~= "entity" and why ~= "bounds" and try(C.isWater, nx, ny) == true
            and Bot.canUse("SURF") then action = "surf"
        elseif why == "entity" then
          local kind = Bot.obstacleAt(nx, ny)
          if kind == "cut" and Bot.canUse("CUT") then action = "cut"
          elseif kind == "rock_smash" and Bot.canUse("ROCK_SMASH") then action = "rock_smash"
          elseif kind == "strength" and Bot.canUse("STRENGTH") then
            -- a boulder moves only if the cell behind it is free ground
            local bx, by = nx + d[1], ny + d[2]
            local free = try(C.canEnter, game, bx, by, { fromX = nx, fromY = ny, dir = dir,
              surfing = false, elevation = elevation }) == true
            if not free or isWarp(h, bx, by) or try(C.isWater, bx, by) == true then return nil end
            action = "strength"
          else return nil end
        else return nil end
      end
      -- a door or stair on the way would take the player somewhere else
      if isWarp(h, nx, ny) and not (nx == tx and ny == ty) and not (goal and goal(nx, ny)) then return nil end
      local onWater = (surfing or action == "surf") and try(C.isWater, nx, ny) == true
      return nx, ny, onWater, action
    end
    -- searching every step of the game would be slow on a big map: keep the
    -- walk and only search again when the player leaves it or it gets blocked
    local id = map .. "|" .. tostring(goalId or (tostring(tx) .. "," .. tostring(ty) .. "," .. tostring(beside)))
    local tick = Bot.stats.ticks
    if pathCache.id == id then
      local dir = pathCache.next and pathCache.next[key(sx, sy)]
      if dir then
        local nx, _, _, action = enter(sx, sy, dir, P.currentElevation, P.surfing == true)
        if nx then return dir, action end
      end
      -- "no way" is kept for a while in real time too: finding that out means
      -- searching the whole map, and at high game speed 12 steps are nothing
      if tick - pathCache.at < 12 then
        if pathCache.failed then return nil end
        return pathCache.last, pathCache.lastAction
      end
    end
    pathCache = { id = id, at = tick, clock = love.timer.getTime() }
    local seen = { [key(sx, sy)] = true }
    local queue = { { sx, sy, P.currentElevation, nil, nil, P.surfing == true } }
    local head = 1
    while queue[head] and head < 8000 do
      local node = queue[head]
      for _, dir in ipairs(DIRS) do
        local nx, ny, onWater, action = enter(node[1], node[2], dir, node[3], node[6])
        if nx and not seen[key(nx, ny)] then
          seen[key(nx, ny)] = true
          queue[#queue + 1] = { nx, ny, elevationOf(h, nx, ny, node[3]), head, dir, onWater, action }
          if done(nx, ny) then
            -- walk the chain back to the start, noting the way out of each cell
            local nextDir, at, firstAction = {}, #queue, nil
            while queue[at][4] do
              local parent = queue[queue[at][4]]
              nextDir[key(parent[1], parent[2])] = queue[at][5]
              firstAction = queue[at][7]
              at = queue[at][4]
            end
            pathCache.next, pathCache.last, pathCache.lastAction = nextDir, nextDir[key(sx, sy)], firstAction
            return pathCache.last, firstAction
          end
        end
      end
      head = head + 1
    end
    pathCache.failed = true
    return nil
  end
  -- What the team can do on the field, asked of the game at most twice a second.
  local abilityCache = {}
  function Bot.canUse(move)
    local entry = abilityCache[move]
    if entry and Bot.stats.ticks - entry.at < 30 then return entry.value end
    local h = host()
    local value = h.FieldMoves ~= nil and h.World ~= nil
      and try(h.FieldMoves.partyMoveUser, session().party, move, { game = game }) ~= nil
    abilityCache[move] = { at = Bot.stats.ticks, value = value }
    return value
  end
  -- What stands on a cell that a field move deals with: "cut" (small tree),
  -- "rock_smash" (cracked rock) or "strength" (boulder).
  function Bot.obstacleAt(x, y)
    local h = host()
    local object = h.Objects and try(h.Objects.at, x, y)
    if type(object) ~= "table" or not h.FieldMoves then return nil end
    local def = type(object.def) == "table" and object.def or {}
    local ids = h.FieldMoves.GFX_IDS
    for _, gfx in ipairs({ object.gfx or false, object.graphicsId or false, def.graphicsId or false, def.gfx or false }) do
      if gfx then
        if gfx == ids.CUT_TREE then return "cut" end
        if gfx == ids.ROCK_SMASH_ROCK then return "rock_smash" end
        if gfx == ids.PUSHABLE_BOULDER then return "strength" end
      end
    end
  end
  function Bot.isWaterfall(x, y)
    local h = host()
    local behavior = try(h.Collision.behavior, x, y)
    return behavior ~= nil and h.FieldMoves ~= nil and try(h.FieldMoves.isWaterfallBehavior, behavior) == true
  end
  function Bot.isCutTree(x, y)
    local h = host()
    local object = h.Objects and try(h.Objects.at, x, y)
    local def = type(object) == "table" and object.def or nil
    local tree = h.FieldMoves and h.FieldMoves.GFX_IDS and h.FieldMoves.GFX_IDS.CUT_TREE
    return def ~= nil and tree ~= nil and (def.graphicsId == tree or def.gfx == tree)
  end
  local face
  local worldApi, lastAction, actionFails = nil, -1000, 0
  local strengthMap            -- the map where Strength is already switched on
  -- Takes the next step of a walk; a step that needs Surf or Cut uses the move
  -- the way the party menu would, facing the water or the tree.
  local function advance(step, action)
    -- with Strength already on, a boulder is simply walked into
    if not action or (action == "strength" and strengthMap == (position())) then
      actionFails = 0
      hold(step)
      return true
    end
    release()
    local h = host()
    if h.P.moving or not face(step) then return true end
    if Bot.stats.ticks - lastAction < 90 or love.timer.getTime() - (Bot.actionClock or 0) < 1 then return true end
    lastAction, Bot.actionClock = Bot.stats.ticks, love.timer.getTime()
    worldApi = worldApi or h.World.new(game, "trainer_pilot")
    local ok = try(worldApi.useFieldAction, worldApi, action)
    if ok ~= true then actionFails = actionFails + 1
    elseif action == "strength" then strengthMap = (position()) end
    return actionFails < 6
  end
  -- Walks toward a cell. Returns "arrived", "walking" or "blocked".
  local blockedSince
  local function walkTo(tx, ty, beside)
    local h = host()
    local step, action = pathStep(tx, ty, beside)
    if step == "here" then
      if h.P.moving then return "walking" end
      release()
      blockedSince = nil
      return "arrived"
    end
    if not step then
      release()
      blockedSince = blockedSince or mark()
      -- someone walking by may be in the way for a moment
      if late(blockedSince, 300, 4) then return "blocked" end
      return "walking"
    end
    blockedSince = nil
    if not advance(step, action) then return "blocked" end
    return "walking"
  end
  function face(dir)
    local h = host()
    if h.P.facing == dir then return true end
    if not h.P.moving then tap(dir, 10) end
    return false
  end

  ---------------------------------------------------------------------------
  -- Travelling to a cell that may be on a neighbouring map: walk to the edge
  -- the map connection is on and step across, one map at a time
  ---------------------------------------------------------------------------
  local CARDINAL = { up = "north", down = "south", left = "west", right = "east" }
  local FROM_CARDINAL = { north = "up", south = "down", west = "left", east = "right" }
  local function mapDef(id)
    return game and game.data and type(game.data.maps) == "table" and game.data.maps[id] or nil
  end
  local function neighbours(id)
    local h = host()
    local def = mapDef(id)
    return def and h.Conn and try(h.Conn.each, def) or {}
  end
  -- The direction to leave `from` in to get nearer to `to`, over at most four maps.
  local function nextHop(from, to)
    local seen, queue, head = { [from] = true }, { { from, nil, 0 } }, 1
    while queue[head] do
      local node = queue[head]
      head = head + 1
      if node[3] < 4 then
        for _, c in ipairs(neighbours(node[1])) do
          if not seen[c.map] then
            seen[c.map] = true
            local first = node[2] or FROM_CARDINAL[c.dir]
            local via = node[4] or c.map
            if c.map == to then return first, via end
            queue[#queue + 1] = { c.map, first, node[3] + 1, via }
          end
        end
      end
    end
  end
  ---------------------------------------------------------------------------
  -- The map of links: every map is a point, and it is joined to others by
  -- its edges (map connections) and by its doors, caves and stairs (warps).
  -- A trip is first worked out here, map by map; the steps inside each map
  -- are worked out only when the player is on it.
  ---------------------------------------------------------------------------
  local AVOID = { "SAFARI", "LEAGUE", "INDIGO", "SS_ANNE", "SSANNE", "SEAGALLOP", "TRAINER_TOWER", "UNION_ROOM",
    "CABLE", "ELEVATOR", "GAME_CORNER", "ROCKET", "SILPH",
    -- caves with a puzzle the bot cannot work out: no way through them, for now
    "VICTORY_ROAD", "SEAFOAM", "ICEFALL", "MANSION", "LOST_CAVE" }
  local function avoided(id, goalKey)
    -- a trip into the Safari Zone goes through its own gate and areas
    local safariTrip = goalKey ~= nil and goalKey:find("SAFARI", 1, true) ~= nil
    for _, word in ipairs(AVOID) do
      if id:find(word, 1, true) and not (safariTrip and word == "SAFARI") then return true end
    end
    return false
  end
  local badLinks, planCache = {}, {}
  local function mapLinks(id)
    local out = {}
    for _, c in ipairs(neighbours(id)) do
      out[#out + 1] = { kind = "conn", to = c.map, dir = c.dir, cost = 1 }
    end
    local def, seen = mapDef(id), {}
    for _, w in ipairs(def and type(def.warps) == "table" and def.warps or {}) do
      local to = w.destMap or w.map
      if type(to) == "string" and to ~= id and not seen[to] and tonumber(w.x) and tonumber(w.y) then
        seen[to] = true
        -- going indoors costs more than walking on: a door is taken only when it shortens the way
        out[#out + 1] = { kind = "warp", to = to, cost = 3 }
      end
    end
    return out
  end
  -- The first link to take from `from` toward the nearest map that `isGoal`
  -- accepts, and that map. nil when none is within reach.
  local function planHop(from, isGoal, goalKey)
    local key = from .. "|" .. goalKey
    local cached = planCache[key]
    if cached and love.timer.getTime() - cached.at < 1 then return cached.hop, cached.goal end
    local dist, first, done = { [from] = 0 }, {}, {}
    local hop, found
    for _ = 1, 600 do
      local at, best
      for id, d in pairs(dist) do
        if not done[id] and (not best or d < best) then at, best = id, d end
      end
      if not at then break end
      done[at] = true
      if at ~= from and isGoal(at) then hop, found = first[at], at break end
      if best < 16 then
        for _, link in ipairs(mapLinks(at)) do
          if not badLinks[at .. ">" .. link.to] and not done[link.to] and (isGoal(link.to) or not avoided(link.to, goalKey)) then
            local d = best + link.cost
            if not dist[link.to] or d < dist[link.to] then
              dist[link.to], first[link.to] = d, first[at] or link
            end
          end
        end
      end
    end
    planCache[key] = { hop = hop, goal = found, at = love.timer.getTime() }
    return hop, found
  end
  Bot.planHop = planHop
  -- Cells where the player has crossed from one map to the next before: the
  -- place to cross again, rather than trying the whole edge cell by cell.
  local CROSS_KEY = "crossings/v1"
  local crossings = {}
  for key, x, y in tostring(cacheRead(CROSS_KEY) or ""):gmatch("([%w_>]+)=(-?%d+),(-?%d+)") do
    crossings[key] = { x = tonumber(x), y = tonumber(y) }
  end
  local lastMap, lastCell
  local function noteCrossing()
    local h = host()
    local map, x, y = (h.Map and h.Map.current) or session().map, h.P.cellX, h.P.cellY
    if try(h.Collision.inBounds, x, y) ~= true then return end
    -- only a step off the edge of a map counts: a door, Fly or Teleport also changes map
    local def = lastMap and game.data and type(game.data.maps) == "table" and game.data.maps[lastMap]
    local w, hgt
    if def and h.Conn then w, hgt = try(h.Conn.sizeOf, def) end
    local onEdge = lastCell and w and (lastCell.x == 0 or lastCell.y == 0 or lastCell.x == w - 1 or lastCell.y == hgt - 1)
    local here = game.data and type(game.data.maps) == "table" and game.data.maps[map]
    local w2, h2
    if here and h.Conn then w2, h2 = try(h.Conn.sizeOf, here) end
    onEdge = onEdge and w2 and (x == 0 or y == 0 or x == w2 - 1 or y == h2 - 1)
    if lastMap and map ~= lastMap and onEdge then
      crossings[lastMap .. ">" .. map], crossings[map .. ">" .. lastMap] = lastCell, { x = x, y = y }
      local lines = {}
      for key, cell in pairs(crossings) do lines[#lines + 1] = ("%s=%d,%d"):format(key, cell.x, cell.y) end
      cacheWrite(CROSS_KEY, table.concat(lines, "\n"))
    end
    lastMap, lastCell = map, { x = x, y = y }
  end
  Bot.noteCrossing = noteCrossing
  local travelState = { bad = {} }
  -- Whether a goal can be walked to from a cell the player is not on yet.
  local function reachable(sx, sy, goal)
    local h = host()
    local C = h.Collision
    if goal(sx, sy) then return true end
    local seen, queue, head = { [sx * 4096 + sy] = true }, { { sx, sy, elevationOf(h, sx, sy, 3) } }, 1
    while queue[head] and head < 8000 do
      local node = queue[head]
      head = head + 1
      for _, dir in ipairs(DIRS) do
        local d = DELTA[dir]
        local nx, ny = node[1] + d[1], node[2] + d[2]
        local lx, ly = try(C.ledgeLanding, game, node[1], node[2], dir)
        local ok = lx ~= nil
        if lx then nx, ny = lx, ly else
          ok = try(C.canEnter, game, nx, ny, { fromX = node[1], fromY = node[2], dir = dir,
            surfing = false, elevation = node[3] }) == true
        end
        if ok and not seen[nx * 4096 + ny] then
          seen[nx * 4096 + ny] = true
          if goal(nx, ny) then return true end
          if not isWarp(h, nx, ny) then queue[#queue + 1] = { nx, ny, elevationOf(h, nx, ny, node[3]) } end
        end
      end
    end
    return false
  end
  -- A building that is walked through to get past something: a gate house on
  -- a route, say. Looks for a door on this map that can be reached, whose
  -- inside has another door back to this map from where the goal can be reached.
  local function planPortal(goal)
    local map = position()
    local def = mapDef(map)
    local warps = def and type(def.warps) == "table" and def.warps or {}
    for _, w in ipairs(warps) do
      local inside = w.destMap or w.map
      local idef = type(inside) == "string" and inside ~= map and mapDef(inside) or nil
      local wx, wy = tonumber(w.x), tonumber(w.y)
      if idef and wx and wy and pathStep(wx, wy) then
        for _, iw in ipairs(type(idef.warps) == "table" and idef.warps or {}) do
          local index = tonumber(iw.destWarp) or 0
          if (iw.destMap or iw.map) == map and tonumber(iw.x) and tonumber(iw.y) then
            -- the game counts a map's doors from 1 (its own lookup reads warps[destWarp])
            for _, out in ipairs({ warps[index] or false }) do
              local ox, oy = out and tonumber(out.x), out and tonumber(out.y)
              if ox and oy and abs(ox - wx) + abs(oy - wy) > 2 and reachable(ox, oy, goal) then
                return { origin = map, ax = wx, ay = wy, inside = inside, ex = tonumber(iw.x), ey = tonumber(iw.y) }
              end
            end
          end
        end
      end
    end
  end
  -- Standing on a door that did not open by itself: lean each way in turn,
  -- starting with the sides the player cannot simply walk to (a wall, the
  -- building, the edge of the room), since that is where a door leads.
  -- A way already tried is not tried again, even if leaning moved the player off.
  local function push(portal)
    local h = host()
    local _, x, y = position()
    if not portal.order then
      local walls, open = {}, {}
      for _, dir in ipairs({ "down", "up", "left", "right" }) do
        local d = DELTA[dir]
        local free = try(h.Collision.canEnter, game, x + d[1], y + d[2], { fromX = x, fromY = y, dir = dir,
          surfing = false, elevation = h.P.currentElevation }) == true
        local list = free and open or walls
        list[#list + 1] = dir
      end
      for _, dir in ipairs(open) do walls[#walls + 1] = dir end
      -- the way the player was walking when reaching the door is nearly always
      -- the way through it, so that comes before everything else
      local order, facing = {}, h.P.facing
      if DELTA[facing] then order[1] = facing end
      for _, dir in ipairs(walls) do if dir ~= facing then order[#order + 1] = dir end end
      portal.order, portal.turn = order, 1
    end
    if portal.pushing and late(portal.pushing, 40, 1) then portal.turn, portal.pushing = portal.turn + 1, nil end
    local dir = portal.order[portal.turn]
    if not dir then return false end
    portal.pushing = portal.pushing or mark()
    hold(dir)
    return true
  end
  -- Leaning moved the player off the door: that way is done with.
  local function stepped(portal)
    if portal.pushing then portal.turn, portal.pushing = portal.turn + 1, nil end
  end
  local function throughPortal()
    local portal = travelState.portal
    if not portal then return nil end
    local map, x, y = position()
    if map == portal.inside then
      if not portal.entered then portal.entered, portal.order, portal.pushing = true, nil, nil end
      if x == portal.ex and y == portal.ey then
        if not push(portal) then travelState.portal = nil end
        return "walking"
      end
      if not portal.entered then portal.entered, portal.order, portal.pushing = true, nil, nil end
      stepped(portal)
      if walkTo(portal.ex, portal.ey) == "blocked" then travelState.portal = nil end
      return "walking"
    elseif map == portal.origin and not portal.entered then
      if x == portal.ax and y == portal.ay then
        if not push(portal) then travelState.portal = nil end
        return "walking"
      end
      stepped(portal)
      if walkTo(portal.ax, portal.ay) == "blocked" then travelState.portal = nil end
      return "walking"
    end
    travelState.portal = nil          -- out the other side
    return nil
  end
  -- No way on foot: once every couple of seconds, look for a building to go through.
  local portalMemo = {}       -- [map | goal] = the building that worked last time
  local function tryPortal(goal, key)
    local map = position()
    local memo = key and portalMemo[map .. "|" .. key]
    if memo and pathStep(memo.ax, memo.ay) then
      -- the same way through as before, without searching the map again
      travelState.portal = { origin = memo.origin, ax = memo.ax, ay = memo.ay, inside = memo.inside, ex = memo.ex, ey = memo.ey }
      pathCache, blockedSince = {}, nil
      return true
    end
    local clock = love.timer.getTime()
    if clock - (travelState.plannedAt or 0) < 2 then return false end
    travelState.plannedAt = clock
    local found = planPortal(goal)
    travelState.portal = found
    pathCache = {}
    if found then
      blockedSince = nil
      if key then
        portalMemo[map .. "|" .. key] = { origin = found.origin, ax = found.ax, ay = found.ay, inside = found.inside, ex = found.ex, ey = found.ey }
      end
    end
    return found ~= nil
  end
  local function travel(tmap, tx, ty, beside)
    local h = host()
    local viaPortal = throughPortal()
    if viaPortal then return viaPortal end
    local map, x, y = position()
    if map == tmap then
      travelState.since = nil
      if not pathStep(tx, ty, beside) then
        tryPortal(function(gx, gy)
          if beside then return abs(gx - tx) + abs(gy - ty) == 1 end
          return gx == tx and gy == ty
        end, "cell:" .. tx .. ":" .. ty)
      end
      return walkTo(tx, ty, beside)
    end
    local hop = planHop(map, function(id) return id == tmap end, tmap)
    if not hop then release() return "blocked" end
    if hop.kind == "warp" then
      -- through a door, a cave mouth, a stair: any of this map's warps that lead there
      local def = mapDef(map)
      local function door(dx, dy)
        if travelState.bad[map .. ":" .. dx .. ":" .. dy] then return false end
        for _, w in ipairs(def and type(def.warps) == "table" and def.warps or {}) do
          if (w.destMap or w.map) == hop.to and tonumber(w.x) == dx and tonumber(w.y) == dy then return true end
        end
        return false
      end
      if door(x, y) then
        -- standing on it and still here: lean on it, and give this cell up if nothing opens
        travelState.door = travelState.door or {}
        if travelState.doorCell ~= map .. ":" .. x .. ":" .. y then
          travelState.door, travelState.doorCell = {}, map .. ":" .. x .. ":" .. y
        end
        if not push(travelState.door) then
          travelState.bad[map .. ":" .. x .. ":" .. y], travelState.door, travelState.doorCell = true, nil, nil
        end
        return "walking"
      end
      if travelState.door then stepped(travelState.door) end
      local step, action = pathStep(nil, nil, false, door, "door:" .. hop.to)
      if not step or step == "here" then
        -- no door to that map can be walked to: this link is no use from here, plan around it
        release()
        travelState.doorSince = travelState.doorSince or mark()
        if late(travelState.doorSince, 60, 1) then
          badLinks[map .. ">" .. hop.to], planCache, travelState.doorSince = true, {}, nil
        end
        return "walking"
      end
      travelState.doorSince = nil
      if not advance(step, action) then return "blocked" end
      return "walking"
    end
    local dir, via = FROM_CARDINAL[hop.dir], hop.to
    local def = mapDef(map)
    if not (dir and def and h.Conn) then release() return "blocked" end
    local w, hgt = h.Conn.sizeOf(def)
    local known = via and crossings[map .. ">" .. via]
    if known and travelState.bad[map .. ":" .. known.x .. ":" .. known.y] then known = nil end
    local function edge(ex, ey)
      if travelState.bad[map .. ":" .. ex .. ":" .. ey] then return false end
      if known then return ex == known.x and ey == known.y end
      if (dir == "right" and ex ~= w - 1) or (dir == "left" and ex ~= 0)
          or (dir == "up" and ey ~= 0) or (dir == "down" and ey ~= hgt - 1) then return false end
      return try(h.Conn.incoming, def, CARDINAL[dir], ex, ey, mapDef) ~= nil
    end
    if edge(x, y) then
      -- on the edge: step off it; a landing that turns out blocked is not tried again.
      -- The wait is counted only while the player stands on this very cell, step after step.
      local here = map .. ":" .. x .. ":" .. y
      if travelState.cell ~= here or Bot.stats.ticks - (travelState.seen or 0) > 2 then travelState.since = nil end
      travelState.cell, travelState.seen = here, Bot.stats.ticks
      travelState.since = travelState.since or mark()
      if late(travelState.since, 60, 1) then
        travelState.bad[map .. ":" .. x .. ":" .. y], travelState.since = true, nil
      end
      hold(dir)
      return "walking"
    end
    travelState.since = nil
    local step, action = pathStep(nil, nil, false, edge, "edge:" .. dir .. (known and ":known" or ""))
    if not step and known then
      -- the usual crossing cannot be reached right now: look along the whole edge instead
      travelState.bad[map .. ":" .. known.x .. ":" .. known.y] = true
    end
    if not step and tryPortal(edge, "edge:" .. dir) then return "walking" end
    if not step or step == "here" then
      release()
      blockedSince = blockedSince or mark()
      if late(blockedSince, 300, 4) then return "blocked" end
      return "walking"
    end
    blockedSince = nil
    if not advance(step, action) then return "blocked" end
    return "walking"
  end

  ---------------------------------------------------------------------------
  -- Following a recorded route
  ---------------------------------------------------------------------------
  local function at(point, map, x, y)
    return point.map == map and point.x == x and point.y == y
  end
  -- cursor = { i = index being walked to, dir = 1 | -1 }
  -- Returns "end" past the last point, "walking", or "blocked".
  local changeSince
  local function follow(route, cursor)
    local h = host()
    local points = route.points
    local map, x, y = position()
    -- pick the route up from wherever the player is on it
    for k = 0, 8 do
      local j = cursor.i + k * cursor.dir
      -- a recording that comes back over the same cells must not be picked up on its return leg
      if cursor.max and j > cursor.max then break end
      if points[j] and at(points[j], map, x, y) then
        cursor.i = j + cursor.dir
        break
      end
    end
    -- a point recorded mid-step across a map connection lies just outside the
    -- map it names: there is nothing to walk to, the crossing itself covers it
    while points[cursor.i] and points[cursor.i].map == map
        and try(h.Collision.inBounds, points[cursor.i].x, points[cursor.i].y) == false do
      cursor.i = cursor.i + cursor.dir
    end
    local target = points[cursor.i]
    if not target then
      if h.P.moving then return "walking" end
      release()
      return "end"
    end
    if target.map == map then
      changeSince = nil
      local state = walkTo(target.x, target.y)
      if state == "blocked" then
        -- maybe only this point is unreachable now: try the ones after it
        for k = 1, 8 do
          local later = points[cursor.i + k * cursor.dir]
          if later and later.map == map and pathStep(later.x, later.y) then
            cursor.i = cursor.i + k * cursor.dir
            blockedSince = nil
            return "walking"
          end
        end
      end
      return state == "arrived" and "walking" or state
    end
    -- the next point is on another map
    if nextHop(map, target.map) then
      -- joined by a map connection: walk off the right edge
      local state = travel(target.map, target.x, target.y)
      return state == "arrived" and "walking" or state
    end
    -- through a door: the warp on this map that leads there, when the game lists it
    local from = points[cursor.i - cursor.dir]
    local recorded = cursor.dir == 1 and target.dir or (from and OPPOSITE[from.dir])
    local def, warp = mapDef(map), nil
    for _, w in ipairs(def and type(def.warps) == "table" and def.warps or {}) do
      if (w.destMap or w.map) == target.map and tonumber(w.x) and tonumber(w.y) then
        -- the one nearest to where the recording went through
        local near = from and from.map == map and abs(tonumber(w.x) - from.x) + abs(tonumber(w.y) - from.y) or 0
        -- a listed cell whose tile is not really a way through is a last choice
        if not isWarp(h, tonumber(w.x), tonumber(w.y)) then near = near + 1000 end
        if not warp or near < warp.near then warp = { x = tonumber(w.x), y = tonumber(w.y), near = near } end
      end
    end
    changeSince = changeSince or mark()
    -- how long the bot has stood here, in whichever of steps and seconds says less
    local waited = min(Bot.stats.ticks - changeSince.tick, floor((love.timer.getTime() - changeSince.clock) * 60))
    if waited > 900 then return "blocked" end
    if warp then
      if not (x == warp.x and y == warp.y) then
        changeSince = nil
        local state = walkTo(warp.x, warp.y)
        return state == "arrived" and "walking" or state
      end
      -- standing on it (the mat inside a building): step out, trying the recorded way first
      local order = { recorded or "down", "down", "up", "left", "right" }
      hold(order[min(#order, floor(waited / 120) + 1)])
      return "walking"
    end
    if from and from.map == map and not at(from, map, x, y) then
      changeSince = nil
      local state = walkTo(from.x, from.y)
      return state == "arrived" and "walking" or state
    end
    if not recorded then return "blocked" end
    hold(recorded)
    return "walking"
  end
  -- The index of the route point nearest to the player on this map.
  local function nearest(route)
    local map, x, y = position()
    local best, bestDistance
    for index, p in ipairs(route.points) do
      if p.map == map then
        local distance = abs(p.x - x) + abs(p.y - y)
        if not bestDistance or distance < bestDistance then best, bestDistance = index, distance end
      end
    end
    return best
  end

  ---------------------------------------------------------------------------
  -- Recording
  ---------------------------------------------------------------------------
  local function routeName(kind, map)
    local label = I18n.T("kinds")[kind] or kind
    local place = tostring(map or "?"):gsub("^MAP_", ""):gsub("_", " "):lower():gsub("^%l", string.upper)
    local base, n = label .. " " .. place, 1
    local name = base
    while Bot.route(name) do
      n = n + 1
      name = base .. " " .. n
    end
    return name
  end
  function Bot.startRecording(kind)
    if not (KINDS[kind] and host() and session()) or Bot.running then return false end
    local map, x, y = position()
    Bot.recording = { kind = kind, points = { { map = map, x = x, y = y, dir = host().P.facing or "down" } } }
    return true
  end
  function Bot.stopRecording(keep)
    local rec = Bot.recording
    Bot.recording = nil
    if not (rec and keep) then return nil end
    if not rec.spot and #rec.points < 2 then return nil end
    local route = { name = routeName(rec.kind, rec.points[1].map), kind = rec.kind, points = rec.points }
    Bot.routes[#Bot.routes + 1] = route
    if rec.kind == "heal" then Bot.config.heal = route.name else Bot.config.train = route.name end
    Bot.save()
    return route
  end
  -- A spot is one cell and the way the player faces there: where to fish,
  -- or where to use the VS Seeker.
  function Bot.markSpot(kind)
    if not Bot.startRecording(kind) then return nil end
    Bot.recording.spot = true
    return Bot.stopRecording(true)
  end
  function Bot.markFishingSpot() return Bot.markSpot("fish") end
  local function recordTick()
    local rec = Bot.recording
    if not rec or rec.spot then return end
    local h = host()
    if not (h and session() and h.Field.running) then return end
    local P = h.P
    local map, x, y = (h.Map and h.Map.current) or session().map, P.cellX, P.cellY
    local last = rec.points[#rec.points]
    if at(last, map, x, y) then return end
    -- half way across a map connection the cell is outside the new map: wait for the step to end
    if try(h.Collision.inBounds, x, y) == false then return end
    if #rec.points < 4000 then
      rec.points[#rec.points + 1] = { map = map, x = x, y = y, dir = P.facing or P.moveDir or "down" }
    end
  end

  ---------------------------------------------------------------------------
  -- The team
  ---------------------------------------------------------------------------
  function Bot.moveKey(mon, id) return tostring(mon.personality or 0) .. ":" .. tostring(id) end
  -- Hunting: whether a Pokémon fits a target.
  function Bot.genderOf(mon)
    local summary = req("src.core.game3.summary_data")
    local g = summary and try(summary.gender, mon) or mon.gender
    g = tostring(g or ""):upper():sub(1, 1)
    return (g == "M" or g == "F") and g or "N"
  end
  -- Hidden Power's type (0 Fighting … 15 Dark) and power (30–70), from the IVs.
  function Bot.hiddenPower(mon)
    local typeBits, powerBits, weight = 0, 0, 1
    for _, key in ipairs(IV_KEYS) do
      local iv = type(mon.ivs) == "table" and tonumber(mon.ivs[key]) or 0
      typeBits = typeBits + (iv % 2) * weight
      powerBits = powerBits + (floor(iv / 2) % 2) * weight
      weight = weight * 2
    end
    return floor(typeBits * 15 / 63), floor(powerBits * 40 / 63) + 30
  end
  function Bot.matches(mon, t)
    local h = host()
    local species = try(h.Pokemon.speciesOf, mon)
    if t.species ~= 0 and species ~= t.species then return false end
    if t.gender ~= "any" and Bot.genderOf(mon) ~= t.gender then return false end
    local total = 0
    for _, key in ipairs(IV_KEYS) do
      local iv = type(mon.ivs) == "table" and tonumber(mon.ivs[key]) or 0
      if iv < (t.ivs[key] or 0) then return false end
      total = total + iv
    end
    if total < t.ivTotal then return false end
    if t.ability ~= 0 and try(h.Pokemon.abilityId, species, mon.personality) ~= t.ability then return false end
    -- the nature is the personality value's remainder by 25, in the games' fixed order
    if t.natures and next(t.natures) and not t.natures[(tonumber(mon.personality) or 0) % 25] then return false end
    local level = tonumber(mon.level) or 0
    if (t.levelMin or 0) > 0 and level < t.levelMin then return false end
    if (t.levelMax or 0) > 0 and level > t.levelMax then return false end
    if t.item and (tonumber(mon.heldItem or mon.item) or 0) == 0 then return false end
    if (t.hpType or -1) >= 0 or (t.hpPower or 0) > 0 then
      local hpType, hpPower = Bot.hiddenPower(mon)
      if (t.hpType or -1) >= 0 and hpType ~= t.hpType then return false end
      if hpPower < (t.hpPower or 0) then return false end
    end
    if t.shiny and try(h.Pokemon.isShiny, mon) ~= true then return false end
    return true
  end
  local function allowed(slot)
    return Bot.config.selected[slot] == true
  end
  local function hpPct(mon)
    local maxHp = max(1, tonumber(mon.maxHp) or 1)
    return floor((tonumber(mon.hp) or 0) * 100 / maxHp)
  end
  -- Slots of the moves that can hurt and still have PP.
  local function attacks(mon)
    local h, out = host(), {}
    for slot = 1, 4 do
      local id = type(mon.moves) == "table" and mon.moves[slot]
      if type(id) == "table" then id = id.id end
      if id and id ~= 0 and id ~= "" then
        local def = try(h.Moves.get, id)
        local pp = type(mon.pp) == "table" and tonumber(mon.pp[slot]) or 0
        if def and (tonumber(def.power) or 0) > 0 and pp > 0 and not Bot.config.banned[Bot.moveKey(mon, id)] then
          out[#out + 1] = { slot = slot, def = def, id = id }
        end
      end
    end
    return out
  end
  local function isEgg(mon) return try(host().Pokemon.isEgg, mon) == true end
  ---------------------------------------------------------------------------
  -- EV training: each Pokémon may have the EVs it is after. On routes of wild
  -- Pokémon (not VS Seeker ones) the bot runs from what would give the wrong
  -- EVs, and that Pokémon is done when it has them.
  ---------------------------------------------------------------------------
  -- The targets of this Pokémon, or nil when it has none.
  function Bot.evTarget(mon)
    local t = Bot.config.evTargets[tostring(mon.personality or 0)]
    if not t then return nil end
    for _, key in ipairs(Bot.EV_KEYS) do
      if (t[key] or 0) > 0 then return t end
    end
  end
  function Bot.evsOf(mon)
    local h = host()
    local evs = h and try(h.Pokemon.evsOf, mon) or mon.evs
    return type(evs) == "table" and evs or {}
  end
  function Bot.evDone(mon)
    local t = Bot.evTarget(mon)
    if not t then return true end
    local evs, total = Bot.evsOf(mon), 0
    for _, key in ipairs(Bot.EV_KEYS) do total = total + (tonumber(evs[key]) or 0) end
    if total >= 510 then return true end                -- the game gives no more
    for _, key in ipairs(Bot.EV_KEYS) do
      if (t[key] or 0) > 0 and (tonumber(evs[key]) or 0) < t[key] then return false end
    end
    return true
  end
  -- Would beating this species put EVs where this Pokémon does not want them?
  function Bot.evWasted(mon, species)
    local t = Bot.evTarget(mon)
    if not t then return false end
    local yield = try(host().Pokemon.evYield, species)
    if type(yield) ~= "table" then return false end
    local evs = Bot.evsOf(mon)
    for _, key in ipairs(Bot.EV_KEYS) do
      if (tonumber(yield[key]) or 0) > 0 and ((t[key] or 0) <= 0 or (tonumber(evs[key]) or 0) >= t[key]) then return true end
    end
    return false
  end
  local function belowTarget(mon)
    local target = Bot.config.stopLevel
    -- the level target belongs to training; a hunt goes on whatever the levels
    local below = target <= 0 or Bot.mode == "hunt" or (tonumber(mon.level) or 0) < target
    -- with EV targets, that Pokémon is done as soon as it has them
    if Bot.evOn and Bot.evTarget(mon) then return below and not Bot.evDone(mon) end
    return below
  end
  local function fit(mon)
    return not isEgg(mon) and (tonumber(mon.hp) or 0) > 0 and hpPct(mon) >= Bot.config.hpPct and #attacks(mon) > 0
  end
  -- The slot that should lead now: nil and a reason when nobody can.
  local function pickLead(party)
    local anyBelow, anyAllowed = false, false
    for slot, mon in ipairs(party) do
      if allowed(slot) and not isEgg(mon) then
        anyAllowed = true
        if belowTarget(mon) then
          anyBelow = true
          if fit(mon) then return slot end
        end
      end
    end
    if not anyAllowed then return nil, "nobody" end
    if not anyBelow then return nil, "level" end
    return nil, "tired"
  end
  local function fullyHealed(party)
    for _, mon in ipairs(party) do
      if not isEgg(mon) then
        if (tonumber(mon.hp) or 0) < (tonumber(mon.maxHp) or 1) then return false end
        for slot = 1, 4 do
          local pp = type(mon.pp) == "table" and tonumber(mon.pp[slot])
          local maxPp = type(mon.maxPp) == "table" and tonumber(mon.maxPp[slot])
          if pp and maxPp and pp < maxPp then return false end
        end
      end
    end
    return true
  end

  ---------------------------------------------------------------------------
  -- Stopping and starting
  ---------------------------------------------------------------------------
  local run                   -- the running job's state
  local function applySpeed()
    local options = game and type(game.options) == "table" and game.options or nil
    local speed = Bot.config.speed
    if options and Bot.running and speed > 0 then options.speedOverworld, options.speedBattle = speed, speed end
  end
  function Bot.setSpeed(value)
    Bot.config.speed = value
    Bot.save()
    local saved, options = Bot.savedSpeed, game and game.options
    if value == 0 and saved and type(options) == "table" then
      options.speedOverworld, options.speedBattle = saved[1], saved[2]
    end
    applySpeed()
  end
  -- Every stop of a run, newest first, kept between sessions.
  local HISTORY_KEY, HISTORY_MAX = "log/history", 40
  Bot.history = {}
  local function historyField(value) return (tostring(value or ""):gsub("[|\n\r]", " ")) end
  local function historySave()
    local lines = {}
    for _, e in ipairs(Bot.history) do
      lines[#lines + 1] = table.concat({ e.at, historyField(e.reason), historyField(e.mode), historyField(e.route), historyField(e.map),
        e.x or 0, e.y or 0, e.battles or 0, e.seconds or 0, e.found or 0, e.caught or 0 }, "|")
    end
    cacheWrite(HISTORY_KEY, table.concat(lines, "\n"))
  end
  local function historyLoad()
    Bot.history = {}
    for row in tostring(cacheRead(HISTORY_KEY) or ""):gmatch("[^\n]+") do
      local f = {}
      for field in (row .. "|"):gmatch("([^|]*)|") do f[#f + 1] = field end
      if #f >= 9 then
        Bot.history[#Bot.history + 1] = { at = tonumber(f[1]) or 0, reason = f[2], mode = f[3], route = f[4], map = f[5],
          x = tonumber(f[6]), y = tonumber(f[7]), battles = tonumber(f[8]) or 0, seconds = tonumber(f[9]) or 0,
          found = tonumber(f[10]) or 0, caught = tonumber(f[11]) or 0 }
      end
    end
  end
  function Bot.clearHistory()
    Bot.history = {}
    historySave()
  end
  local function historyAdd(reason)
    local map, x, y
    pcall(function() map, x, y = position() end)
    local stats = Bot.stats
    local route = run and run.route
    table.insert(Bot.history, 1, { at = os.time(), reason = tostring(reason), mode = tostring(Bot.mode or ""),
      route = route and route.kind ~= "reset" and route.name or "", map = map or "", x = x, y = y,
      battles = stats.battles or 0, seconds = stats.startedAt and floor(love.timer.getTime() - stats.startedAt) or 0,
      found = stats.found or 0, caught = stats.caught or 0 })
    while #Bot.history > HISTORY_MAX do table.remove(Bot.history) end
    historySave()
  end
  Bot.historyLoad = historyLoad
  pcall(historyLoad)
  function Bot.stop(reason)
    release()
    if Bot.evOn and (reason == "level" or reason == "level_healed") then
      -- it was the EVs that were reached, not a level
      local s = session()
      for slot, mon in ipairs(s and s.party or {}) do
        if Bot.config.selected[slot] and Bot.evTarget(mon) and Bot.evDone(mon) then
          reason = reason == "level" and "ev_done" or "ev_healed"
          break
        end
      end
    end
    -- the stop goes into the history with the reason it ends up having
    if Bot.running and reason ~= "quit" then pcall(historyAdd, reason) end
    -- the game goes back to the speeds it had when the bot started
    if Bot.savedSpeed and game and type(game.options) == "table" then
      game.options.speedOverworld, game.options.speedBattle = Bot.savedSpeed[1], Bot.savedSpeed[2]
    end
    Bot.savedSpeed = nil
    -- with the target in hand the game may be saved again
    if reason == "hunt_found" or reason == "caught" or reason == "shiny" or reason == "no_balls" then Bot.resetLock = nil end
    if Bot.running then Bot.stats.endedAt = love.timer.getTime() end
    if Bot.running then
      Bot.reason = reason
      -- kept on disk so a stop can be looked into afterwards
      pcall(function()
        local map, x, y = position()
        cacheWrite("log/last", ("reason=%s\nphase=%s\nstatus=%s\nmap=%s\nx=%s\ny=%s\nbattles=%s\nerror=%s\n"):format(
          tostring(reason), tostring(run and run.phase), tostring(Bot.status), tostring(map), tostring(x), tostring(y),
          tostring(Bot.stats.battles), tostring(Bot.lastError)))
      end)
    end
    Bot.running, Bot.status, run = false, "idle", nil
  end
  -- Closes the stopped run: its numbers are cleared and there is nothing left to resume.
  function Bot.finish()
    if Bot.running then return false end
    Bot.mode, Bot.reason, Bot.resetLock, Bot.resetAt = nil, nil, nil, nil
    local stats = Bot.stats
    stats.resets, stats.itemsHp, stats.itemsPp = nil, 0, 0
    stats.battles, stats.heals, stats.seeker, stats.seen = 0, 0, 0, {}
    stats.caught, stats.lost, stats.found, stats.safariEntries = 0, 0, 0, nil
    stats.startedAt, stats.endedAt = nil, nil
    return true
  end
  -- Somewhere for a caught Pokémon to go: a free place in the team, or in a PC box.
  -- Only read: the PC is never touched.
  function Bot.roomForCatch()
    local s, h = session(), host()
    if not s then return true end
    if #(s.party or {}) < 6 then return true end
    local storage = s.storage
    if not (h and h.Storage and h.Storage.findOpenSlot and type(storage) == "table" and type(storage.boxes) == "table") then return true end
    return try(h.Storage.findOpenSlot, storage) ~= nil
  end
  -- Steps left on a Repel, as the game's own encounter check reads them. On
  -- routes that live off wild encounters a Repel makes the run pointless.
  local function repelLeft()
    local ok, Sem = pcall(require, "src.core.game3.field_semantics")
    local value = ok and type(Sem) == "table" and Sem.getVar and try(Sem.getVar, session(), "repelSteps")
    return tonumber(value) or tonumber(session() and session().repelSteps) or 0
  end
  local function repelMatters(route) return route ~= nil and (route.kind == "grass" or route.kind == "scent") end
  Bot.repelLeft = repelLeft
  -- mode: "train" or "hunt". resume: carry on the stopped run, keeping its numbers.
  function Bot.start(mode, resume)
    if Bot.running then return true end
    mode = (mode == "hunt" or mode == "reset") and mode or "train"
    if mode == "hunt" and #Bot.config.targets == 0 then Bot.reason = "no_targets" return false end
    -- a catch with nowhere to go: say so before the hunt rather than after a find
    if ((mode == "hunt" and Bot.config.huntCatch) or (mode == "reset" and Bot.config.resetCatch)) and not Bot.roomForCatch() then
      Bot.reason = "pc_full" return false
    end
    if mode == "reset" and #Bot.config.targets == 0 and not Bot.config.huntShiny then Bot.reason = "no_targets" return false end
    local h = host()
    if not (h and session() and h.Field.running) then Bot.reason = "no_game" return false end
    local route
    if mode == "reset" then
      if h.Battle.isActive() then Bot.reason = "no_game" return false end
      -- the save made here is the point every attempt goes back to; a paused
      -- reset hunt keeps the one it already has
      if not (resume and Bot.mode == "reset" and Bot.resetLock) then
        Bot.resetLock = nil
        local can = try(function() return game:quickSaveAllowed() end)
        local saved = can and try(function() return game:saveGame() end)
        if not can or saved == false or saved == nil then Bot.reason = "no_save" return false end
      end
      Bot.resetLock = true
      route = { kind = "reset", name = "reset", points = {} }
    else
      route = Bot.route(Bot.config.train)
      if not route or route.kind == "heal" then Bot.reason = "no_route" return false end
      if repelMatters(route) and repelLeft() > 0 then Bot.reason = "repel_on" return false end
    end
    Bot.recording = nil
    Bot.leadSlot = 1
    run = { phase = "train", route = route, cursor = { i = mode ~= "reset" and nearest(route) or 1, dir = 1 },
      sameSince = mark(), learn = 0 }
    if mode == "reset" then run.phase, run.reset = "reset", { state = "reload" } end
    travelState.bad, travelState.since, travelState.portal, travelState.plannedAt = {}, nil, nil, nil
    travelState.door, travelState.doorCell, travelState.doorSince = nil, nil, nil
    badLinks, planCache = {}, {}
    blockedSince, changeSince, pathCache, abilityCache, actionFails = nil, nil, {}, {}, 0
    strengthMap = nil
    if resume and Bot.stats.startedAt and Bot.mode == mode then
      -- the time spent stopped does not count
      Bot.stats.startedAt = Bot.stats.startedAt + (love.timer.getTime() - (Bot.stats.endedAt or love.timer.getTime()))
    else
      Bot.stats.battles, Bot.stats.heals, Bot.stats.seeker, Bot.stats.seen = 0, 0, 0, {}
      Bot.stats.caught, Bot.stats.lost, Bot.stats.found = 0, 0, 0
      Bot.stats.resets = mode == "reset" and 0 or nil
      Bot.stats.itemsHp, Bot.stats.itemsPp = 0, 0
      Bot.stats.startedAt = love.timer.getTime()
    end
    Bot.mode = mode
    -- EV training belongs to routes of wild Pokémon: a trainer cannot be run from
    Bot.evOn = mode == "train" and route.kind ~= "seeker"
    if not (resume and Bot.stats.evFled) then Bot.stats.evFled = 0 end
    Bot.running, Bot.status, Bot.reason = true, "train", nil
    if type(game.options) == "table" then
      Bot.savedSpeed = { game.options.speedOverworld, game.options.speedBattle }
      applySpeed()
    end
    return true
  end

  ---------------------------------------------------------------------------
  -- Reset hunting: starters, gifts, legendaries. The game is saved in front of
  -- the Pokémon; each attempt loads that save again (what the game's own quick
  -- load does) until what comes out fits a target.
  ---------------------------------------------------------------------------
  local function wanted(mon)
    local h, c = host(), Bot.config
    for _, target in ipairs(c.targets) do
      if Bot.matches(mon, target) then return true end
    end
    return c.huntShiny and try(h.Pokemon.isShiny, mon) == true
  end
  Bot.wanted = wanted
  local function partyCount()
    local s = session()
    return s and type(s.party) == "table" and #s.party or 0
  end
  -- The load itself happens outside the game's step (see core.update below).
  -- replay: { seed, delay, personality } to bring the very same Pokémon back.
  local function askReload(replay)
    release()
    run.reset.state, run.reset.replay = "reload", replay
  end
  -- A catch that did not work out: the same Pokémon is brought back a few times.
  local function resetFailed(foe)
    local r = run.reset
    run.catching, run.battle = nil, nil
    r.tries = (r.tries or 0) + 1
    if r.seed and foe and r.tries <= 10 then
      return askReload({ seed = r.seed, delay = r.delay, personality = foe.personality })
    end
    Bot.stats.lost = (Bot.stats.lost or 0) + 1
    r.tries = 0
    askReload()
  end
  function Bot.reloadNow()
    local r = Bot.running and run and run.reset
    if not (r and r.state == "reload") then return end
    local h = host()
    release()
    local ok, err = pcall(function()
      game:_tearDownField()
      if h.Ghosts and h.Ghosts.clear then pcall(h.Ghosts.clear) end
      game:_handleBootAction({ action = "continue" })
    end)
    if not ok or not session() then
      Bot.lastError = tostring(err)
      return Bot.stop("reset_load")
    end
    run.battle, run.catching = nil, nil
    if r.replay then
      -- the same luck and the same wait as the attempt being repeated
      if h.Rng then try(h.Rng.setState, r.replay.seed) end
      r.delay = r.replay.delay
    else
      r.seed = h.Rng and try(h.Rng.getState) or nil
      -- a different wait each time, so the attempts do not repeat one another
      r.delay = love.math.random(0, 120)
      r.tries = 0
      Bot.stats.resets = (Bot.stats.resets or 0) + 1
    end
    r.state, r.wait, r.base, r.since = "wait", r.delay, partyCount(), mark()
    lastTap = -100
  end
  local function resetTick()
    local r, h = run.reset, host()
    Bot.status = "reset"
    if run.catching and run.battle then
      -- the battle with a target is over
      local foe, result = run.catching.foe, run.battle.result
      local caught = result == "catch" or (result == nil and (tonumber(foe.hp) or 0) > 0)
      if caught then
        run.catching, run.battle = nil, nil
        Bot.stats.caught = (Bot.stats.caught or 0) + 1
        return Bot.stop("caught")
      end
      return resetFailed(foe)
    end
    run.battle = nil
    if not h.Field.running then return end
    if r.state == "wait" then
      r.wait = r.wait - 1
      if r.wait <= 0 then r.state = "press" end
      return
    end
    local count = partyCount()
    if count > r.base then
      -- a Pokémon was handed over: look at it before anything else is answered
      local mon = session().party[count]
      local species = try(h.Pokemon.speciesOf, mon)
      Bot.stats.seen = Bot.stats.seen or {}
      if species then Bot.stats.seen[species] = (Bot.stats.seen[species] or 0) + 1 end
      if wanted(mon) then
        Bot.stats.found = (Bot.stats.found or 0) + 1
        return Bot.stop("hunt_found")
      end
      return askReload()
    end
    if late(r.since, 6000, 90) then return Bot.stop("reset_nothing") end
    tap("a", 8)
  end

  ---------------------------------------------------------------------------
  -- Battle
  ---------------------------------------------------------------------------
  local battleApi, intentId = nil, 0
  local function submit(snap, intent)
    intentId = intentId + 1
    intent.id, intent.revision = intentId, snap.revision
    local ok, err = battleApi:submit(intent)
    if not ok then run.submitFails = (run.submitFails or 0) + 1 else run.submitFails = 0 end
    return ok, err
  end
  local function bestAttack(mon, foe)
    local h = host()
    local types = try(h.Pokemon.types, try(h.Pokemon.speciesOf, mon)) or {}
    local foeTypes = foe and try(h.Pokemon.types, try(h.Pokemon.speciesOf, foe)) or {}
    local best, bestScore
    for _, attack in ipairs(attacks(mon)) do
      local score = tonumber(attack.def.power) or 0
      local moveType = attack.def.type
      local effect = foeTypes[1] and try(h.Types.effectiveness, moveType, foeTypes[1], foeTypes[2])
      if tonumber(effect) then score = score * effect end
      if moveType ~= nil and (moveType == types[1] or moveType == types[2]) then score = score * 1.5 end
      score = score * (tonumber(attack.def.accuracy) or 100) / 100
      if not bestScore or score > bestScore then best, bestScore = attack.slot, score end
    end
    return best, bestScore or 0
  end
  -- Whether two records are the same Pokémon: the battle may hold its own copy
  -- of the one that is out, so comparing the tables themselves is not enough.
  local function same(a, b)
    if a == nil or b == nil then return false end
    if a == b then return true end
    return a.personality ~= nil and a.personality == b.personality
      and try(host().Pokemon.speciesOf, a) == try(host().Pokemon.speciesOf, b)
  end
  -- Out on the field right now: in a double battle that is two of them.
  local function inBattle(st, mon)
    if same(mon, st.player and st.player.mon) then return true end
    local partner = st.double and type(st.battlers) == "table" and st.battlers[2] or nil
    return partner ~= nil and same(mon, partner.mon)
  end
  -- Someone else who may fight and still has an attack with PP: the hardest hitter.
  local function substitute(st, anyone)
    local active = st.player and st.player.mon
    local foe = st.enemy and st.enemy.mon
    local best, bestScore
    for slot, mon in ipairs(session().party) do
      if not inBattle(st, mon) and (anyone or allowed(slot)) and not isEgg(mon) and (tonumber(mon.hp) or 0) > 0 and #attacks(mon) > 0 then
        local _, score = bestAttack(mon, foe)
        if not bestScore or score > bestScore then best, bestScore = mon, score end
      end
    end
    return best
  end
  local function battlePhase()
    local h = host()
    return (h.BattleCore and h.BattleCore._phase) or h.Battle._phase, h.BattleCore and h.BattleCore._phase and h.BattleCore or h.Battle
  end
  -- Who should face the trainer's next Pokémon: the one of those allowed to
  -- fight whose best attack hits it hardest. nil keeps the one that is out.
  local function betterAgainst(st, foe)
    local c = Bot.config
    local active = st.player and st.player.mon
    if c.policy == "lead" or not (foe and active) then return nil end
    local _, current = bestAttack(active, foe)
    if hpPct(active) < c.hpPct then current = 0 end
    local best, bestScore = nil, current
    for slot, mon in ipairs(session().party) do
      if not inBattle(st, mon) and allowed(slot) and not isEgg(mon) and (tonumber(mon.hp) or 0) > 0
          and hpPct(mon) >= c.hpPct then
        local _, score = bestAttack(mon, foe)
        if score > bestScore then best, bestScore = mon, score end
      end
    end
    return best
  end
  ---------------------------------------------------------------------------
  -- Catching a hunt target
  ---------------------------------------------------------------------------
  local MOVE_FALSE_SWIPE = 206
  local STATUS_MOVES = { [47] = true, [79] = true, [95] = true, [142] = true, [147] = true, [320] = true,   -- sleep
    [78] = true, [86] = true, [137] = true }                                                               -- paralysis
  local function hasStatus(mon)
    local h = host()
    local ailment = h.Summary and try(h.Summary.statusAilment, mon)
    if ailment ~= nil then return ailment ~= 0 end
    return mon.status ~= nil and mon.status ~= 0 and mon.status ~= ""
  end
  -- The most a move can take off the foe: top of the damage roll, a critical
  -- hit, and a margin on top. nil when the numbers needed are not there.
  local function maxDamage(mon, foe, def)
    local h = host()
    -- Gen 3 splits physical and special by the move's type
    local physical
    if type(h.Types.PHYSICAL) == "table" then physical = h.Types.PHYSICAL[def.type] == true end
    local attack = tonumber(physical and mon.attack or mon.spAtk)
    local defense = tonumber(physical and foe.defense or foe.spDef)
    if physical == nil then
      -- which side of the split the move is on is not known: assume the worse one
      attack = max(tonumber(mon.attack) or 0, tonumber(mon.spAtk) or 0)
      defense = min(tonumber(foe.defense) or 0, tonumber(foe.spDef) or 0)
    end
    local level, power = tonumber(mon.level), tonumber(def.power)
    if not (attack and defense and level and power) or defense <= 0 then return nil end
    local base = floor(floor(floor(2 * level / 5 + 2) * attack * power / defense) / 50) + 2
    local own = try(h.Pokemon.types, try(h.Pokemon.speciesOf, mon)) or {}
    local foeTypes = try(h.Pokemon.types, try(h.Pokemon.speciesOf, foe)) or {}
    local effect = foeTypes[1] and tonumber(try(h.Types.effectiveness, def.type, foeTypes[1], foeTypes[2])) or 100
    local stab = (def.type ~= nil and (def.type == own[1] or def.type == own[2])) and 1.5 or 1
    return base * stab * (effect / 100) * 2 * 1.2
  end
  -- A move that brings the foe's HP down and cannot make it faint.
  local function safeAttack(mon, foe)
    local best, bestDamage
    for _, attack in ipairs(attacks(mon)) do
      if attack.id == MOVE_FALSE_SWIPE then return attack.slot end
      if not Bot.config.catchFalseSwipe then
        local damage = maxDamage(mon, foe, attack.def)
        if damage and damage > 0 and damage < (tonumber(foe.hp) or 0) and (not bestDamage or damage > bestDamage) then
          best, bestDamage = attack.slot, damage
        end
      end
    end
    return best
  end
  local function statusMove(mon, foe)
    local h = host()
    local foeTypes = try(h.Pokemon.types, try(h.Pokemon.speciesOf, foe)) or {}
    for slot = 1, 4 do
      local id = type(mon.moves) == "table" and mon.moves[slot]
      if type(id) == "table" then id = id.id end
      if id and STATUS_MOVES[id] and (type(mon.pp) == "table" and tonumber(mon.pp[slot]) or 0) > 0 then
        local def = try(h.Moves.get, id)
        local effect = def and foeTypes[1] and tonumber(try(h.Types.effectiveness, def.type, foeTypes[1], foeTypes[2]))
        if effect ~= 0 then return slot end           -- a type the move cannot touch is skipped
      end
    end
  end
  function Bot.pickBall()
    local c = Bot.config
    if c.useMaster and Bot.hasItem(1) then return 1 end
    for id in c.ballOrder:gmatch("%d+") do
      id = tonumber(id)
      if id ~= 1 and Bot.hasItem(id) then return id end
    end
  end
  -- What to do at the battle menu while catching. Returns true when it acted.
  local function catchStep(snap, st, mon, submitFn)
    local h, c = host(), Bot.config
    local cat = run.catching
    local foe = st.enemy and st.enemy.mon
    if not (foe and mon) then return false end
    cat.slot = nil
    if c.catchWeaken and (tonumber(foe.hp) or 0) > 1 and hpPct(foe) > 20 then
      cat.slot = safeAttack(mon, foe)
    end
    if not cat.slot and c.catchStatus and not hasStatus(foe) and cat.statusTries < 3 then
      cat.slot = statusMove(mon, foe)
      if cat.slot then cat.statusTries = cat.statusTries + 1 end
    end
    if cat.slot then
      submitFn(snap, { kind = "menu", choice = "fight" })
      return true
    end
    local ball = Bot.pickBall()
    if not ball then Bot.stop("no_balls") return true end
    local ui = h.BattleUi
    if not ui then Bot.stop("battle_menu") return true end
    -- what the bag screen hands the battle when the player picks a ball there;
    -- the battle itself takes the ball out of the bag
    ui._pendingCommand = { kind = "bag", user = "player", itemId = ball }
    ui._mode = "none"
    cat.thrown = cat.thrown + 1
    return true
  end

  -- The Safari Zone has no fighting: its menu is BALL, BAIT, ROCK, RUN, in the
  -- places where FIGHT, BAG, POKéMON and RUN are in an ordinary battle.
  local function safariStep(snap, st)
    local cat = run.catching
    if not cat then
      submit(snap, { kind = "menu", choice = "run" })       -- not what is being hunted
      return
    end
    -- baits, then balls, then baits again... rocks are never thrown
    cat.turn = (cat.turn or 0) + 1
    local baits, balls = Bot.config.safariBaits, Bot.config.safariBalls
    local choice = ((cat.turn - 1) % (baits + balls)) < baits and "bag" or "fight"      -- BAIT or BALL
    if choice == "fight" then cat.thrown = cat.thrown + 1 end
    submit(snap, { kind = "menu", choice = choice })
  end
  local function battleTick()
    local h, c = host(), Bot.config
    release()
    battleApi = battleApi or (h.BattleAPI and h.BattleAPI.new(game))
    local st = h.Battle.getState()
    if not (battleApi and st) then return end
    if run.reset and run.reset.state == "reload" then return end
    if run.battle ~= st and run.reset then
      -- reset hunting: only what appeared matters
      local r = run.reset
      run.battle, run.learn, run.submitFails, run.switchTried, run.switchTo, run.anyone = st, 0, 0, nil, nil, nil
      run.huntRun = false
      local foe = st.enemy and st.enemy.mon
      if not (foe and st.wild) then return Bot.stop("reset_trainer") end
      local species = try(h.Pokemon.speciesOf, foe)
      Bot.stats.seen = Bot.stats.seen or {}
      local again = r.replay and r.replay.personality == foe.personality
      if r.replay and not again then
        -- the load did not bring the same one back: that target is gone
        Bot.stats.lost = (Bot.stats.lost or 0) + 1
        r.tries = 0
      end
      if species and not again then Bot.stats.seen[species] = (Bot.stats.seen[species] or 0) + 1 end
      if not wanted(foe) then return askReload() end
      if not again then Bot.stats.found = (Bot.stats.found or 0) + 1 end
      if not c.resetCatch then return Bot.stop("hunt_found") end
      -- a repeated attempt waits a little longer each time, so the battle does not play out the same
      run.catching = { foe = foe, statusTries = 0, thrown = 0, holdUntil = Bot.stats.ticks + (r.tries or 0) * 13 }
      return
    end
    if run.battle ~= st then
      -- a new battle: look at what appeared before touching anything
      run.battle, run.learn, run.submitFails, run.switchTried, run.switchTo, run.anyone = st, 0, 0, nil, nil, nil
      run.counted = nil
      Bot.stats.battles = Bot.stats.battles + 1
      local foe = st.enemy and st.enemy.mon
      run.huntRun = false
      if foe and st.wild then
        local species = try(h.Pokemon.speciesOf, foe)
        Bot.stats.seen = Bot.stats.seen or {}
        if species then Bot.stats.seen[species] = (Bot.stats.seen[species] or 0) + 1 end
      end
      if foe and st.wild and Bot.mode == "hunt" then
        for _, target in ipairs(c.targets) do
          if Bot.matches(foe, target) then
            if not run.counted then
              run.counted = true
              Bot.stats.found = (Bot.stats.found or 0) + 1
            end
            if not c.huntCatch then return Bot.stop("hunt_found") end
            run.catching = { foe = foe, statusTries = 0, thrown = 0 }
          end
        end
        if run.catching then return end
        if c.huntShiny and try(h.Pokemon.isShiny, foe) == true then return Bot.stop("shiny") end
        run.huntRun = not c.huntExp
      end
      -- the training stops (shiny, listed species) are not the hunt's: a hunt has its targets
      if foe and st.wild and Bot.mode ~= "hunt" then
        if c.stopShiny and try(h.Pokemon.isShiny, foe) == true then return Bot.stop("shiny") end
        local species = try(h.Pokemon.speciesOf, foe)
        if species and c.species[species] then return Bot.stop("species") end
        -- EV training: not this one, it would give EVs the one fighting does not want
        local fighter = st.player and st.player.mon
        if Bot.evOn and species and fighter and Bot.evWasted(fighter, species) then
          run.huntRun = true
          Bot.stats.evFled = (Bot.stats.evFled or 0) + 1
        end
      end
    end
    Bot.status = "battle"
    local phase, core = battlePhase()
    if phase == "shift_prompt" then
      -- "Will you switch your Pokémon?" before the trainer's next one
      if h.Choice and h.Choice.isOpen and h.Choice.isOpen() then
        local foe = type(st.foeParty) == "table" and st.foeParty[core._shiftEnemyIdx or 0] or nil
        if run.shiftFor ~= foe then
          -- EV training: whoever comes in shares the EVs, so no switching by choice
          local out = st.player and st.player.mon
          local training = Bot.evOn and out and Bot.evTarget(out) ~= nil
          run.shiftFor, run.switchTo = foe, not training and betterAgainst(st, foe) or nil
          local active = st.player and st.player.mon
          if not run.switchTo and active and #attacks(active) == 0 and not c.stopNoPP then
            -- the one out has no attack left: this is the moment to bring in someone who has
            run.switchTo = substitute(st) or substitute(st, true)
            run.anyone = run.switchTo ~= nil or nil
          end
        end
        tap(run.switchTo and "a" or "b", 15)
      elseif h.Message and h.Message.isWaiting and h.Message.isWaiting() then
        tap("a", 6)
      end
      return
    end
    if run.catching and h.Choice and h.Choice.isOpen and h.Choice.isOpen() then
      tap("b", 15)                 -- "give it a nickname?": no
      return
    end
    if h.Choice and h.Choice.isOpen and h.Choice.isOpen() then
      -- the only question a battle asks: whether to make room for a new move
      if c.stopLearn then return Bot.stop("learn") end
      -- "delete a move?" no, then "stop learning?" yes
      if tap(run.learn % 2 == 0 and "b" or "a", 20) then run.learn = run.learn + 1 end
      return
    end
    local menu = h.PartyMenu
    if menu and menu.open == true then
      -- the active one fainted: send the next one that may fight
      local party = type(menu._party) == "table" and menu._party or {}
      local choice
      for slot, mon in ipairs(party) do
        if run.switchTo and same(mon, run.switchTo) and (tonumber(mon.hp) or 0) > 0
            and not inBattle(st, mon) then choice = slot end
      end
      for slot, mon in ipairs(choice and {} or party) do
        local own
        for index, mine in ipairs(session().party) do if mine == mon then own = index end end
        if (tonumber(mon.hp) or 0) > 0 and not isEgg(mon) and (run.anyone or allowed(own or slot))
            and not inBattle(st, mon) then
          choice = slot
          break
        end
      end
      local active = st.player and st.player.mon
      if not choice and active and (tonumber(active.hp) or 0) > 0 then
        -- nobody to bring in and the one out can still stand: close the menu and carry on
        tap("b", 20)
        return
      end
      if not choice then
        -- the one out fainted: anyone alive, marked or not, rather than losing the battle
        for slot, mon in ipairs(party) do
          if (tonumber(mon.hp) or 0) > 0 and not isEgg(mon) and not inBattle(st, mon) then choice = choice or slot end
        end
      end
      if not choice and run.reset and run.catching then return resetFailed(run.catching.foe) end
      if not choice then return Bot.stop("fainted") end
      run.menuWasOpen = true
      run.partyTries = (run.partyTries or 0) + 1
      if run.partyTries > 400 then return Bot.stop("party_menu") end
      if menu.cursor ~= choice then menu.cursor = choice end
      tap("a", 20)
      return
    end
    run.partyTries = 0
    -- the menu has closed: whatever switch was planned is done with
    if run.menuWasOpen then run.menuWasOpen, run.switchTo = false, nil end
    if run.switchTo and st.player and same(st.player.mon, run.switchTo) then run.switchTo = nil end
    local snap = battleApi:snapshot()
    if not snap then return end
    if snap.prompt == "advance" then
      tap("a", 6)
    elseif snap.prompt == "menu" then
      if Bot.stats.ticks - (run.lastSubmit or -100) < 10 then return end
      run.lastSubmit = Bot.stats.ticks
      if st.safari then return safariStep(snap, st) end
      if run.catching and run.catching.holdUntil and Bot.stats.ticks < run.catching.holdUntil then return end
      local battler = st.player
      if st.double and snap.active == 2 and st.battlers then battler = st.battlers[2] or battler end
      local mon = battler and battler.mon
      local wild = st.wild == true
      local dry = mon and #attacks(mon) == 0
      local weak = mon and (hpPct(mon) < c.hpPct or dry)
      if (run.submitFails or 0) > 30 then return Bot.stop("battle_menu") end
      if run.catching and wild and catchStep(snap, st, mon, submit) then return end
      local choice = "fight"
      if wild and (weak or run.huntRun or (c.travelRun and (run.phase ~= "train" or run.away))) then
        choice = "run"
      elseif dry then
        -- out of PP against a trainer: stop if asked to, else bring in one that can still attack
        if c.stopNoPP then return Bot.stop("no_pp") end
        -- one of those marked to fight if any can; else anyone in the team, just to finish this battle
        local other = substitute(st) or substitute(st, true)
        if other and run.switchTried ~= other then
          run.switchTo, run.switchTried, run.anyone, choice = other, other, true, "party"
        end
      end
      submit(snap, { kind = "menu", choice = choice })
    elseif snap.prompt == "moves" then
      if Bot.stats.ticks - (run.lastSubmit or -100) < 10 then return end
      run.lastSubmit = Bot.stats.ticks
      local battler = st.player
      if st.double and snap.active == 2 and st.battlers then battler = st.battlers[2] or battler end
      local slot = battler and battler.mon and bestAttack(battler.mon, st.enemy and st.enemy.mon)
      if run.catching then
        -- only the move the catch plan chose; never an attack picked for damage
        if not run.catching.slot then submit(snap, { kind = "back" }) return end
        slot = run.catching.slot
      end
      if not slot and battler and battler.mon then
        -- nothing that hurts is left: any move that still has PP keeps the battle going
        local mon = battler.mon
        local lastResort
        for index = 1, 4 do
          local id = mon.moves and mon.moves[index]
          if type(id) == "table" then id = id.id end
          if type(mon.pp) == "table" and (tonumber(mon.pp[index]) or 0) > 0 and id and id ~= 0 then
            -- a forbidden move only when there is nothing else at all
            if Bot.config.banned[Bot.moveKey(mon, id)] then lastResort = lastResort or index
            else slot = slot or index end
          end
        end
        slot = slot or lastResort
      end
      if not slot then return Bot.stop("no_pp") end
      submit(snap, { kind = "move", slot = slot })
    elseif snap.prompt == "target" then
      if Bot.stats.ticks - (run.lastSubmit or -100) < 10 then return end
      run.lastSubmit = Bot.stats.ticks
      local target = 1
      for _, id in ipairs({ 1, 3 }) do
        local foe = id == 1 and st.enemy or (st.battlers and st.battlers[id])
        if foe and foe.mon and (tonumber(foe.mon.hp) or 0) > 0 and not (st.absent and st.absent[id]) then
          target = id
          break
        end
      end
      submit(snap, { kind = "target", target = target })
    elseif snap.prompt == "locked" then
      -- a window that waits for a button without being a message, such as
      -- the stats shown on a level up
      tap("a", 20)
    end
  end

  ---------------------------------------------------------------------------
  -- Field work: grass, fishing, VS Seeker, healing
  ---------------------------------------------------------------------------
  local RODS = { 264, 263, 262 }
  local ITEM_VS_SEEKER = 362
  local hasItem
  function Bot.hasItem(id) return hasItem(id) end
  function hasItem(id)
    local h, s = host(), session()
    if not (h.Bag and h.Bag.has and s.bag) then return false end
    return try(h.Bag.has, s.bag, id, 1) == true
  end
  -- Healing from the bag, where the Center would otherwise be the only way:
  -- the common drinks and potions, smallest that does the job first.
  local HP_ITEMS = { { 13, 20 }, { 22, 50 }, { 26, 50 }, { 27, 60 }, { 28, 80 }, { 29, 100 }, { 21, 200 } }
  local function useItem(id, slot, moveSlot)
    local s = session()
    return try(host().ItemUse.useField, s, s.bag, id, slot, moveSlot) == true
  end
  -- One item on one of those who fight. Returns true when something was used.
  local function itemHeal(party)
    local h, c, stats = host(), Bot.config, Bot.stats
    local hpLeft = c.itemHp == -1 or (stats.itemsHp or 0) < c.itemHp
    local ppLeft = c.itemPp == -1 or (stats.itemsPp or 0) < c.itemPp
    if not (hpLeft or ppLeft) or not (h.ItemUse and h.ItemUse.useField) then return false end
    for slot, mon in ipairs(party) do
      local hp, maxHp = tonumber(mon.hp) or 0, tonumber(mon.maxHp) or 1
      if allowed(slot) and not isEgg(mon) and belowTarget(mon) and hp > 0 then
        if hpLeft and hpPct(mon) < c.hpPct then
          local pick
          for _, item in ipairs(HP_ITEMS) do
            if hasItem(item[1]) then
              pick = item[1]
              if item[2] >= maxHp - hp then break end
            end
          end
          if pick and useItem(pick, slot) then
            stats.itemsHp = (stats.itemsHp or 0) + 1
            return true
          end
        elseif ppLeft and hpPct(mon) >= c.hpPct and #attacks(mon) == 0 then
          -- the attacks that are allowed and have run dry
          local empty = {}
          for index = 1, 4 do
            local id = type(mon.moves) == "table" and mon.moves[index]
            if type(id) == "table" then id = id.id end
            local def = id and id ~= 0 and id ~= "" and try(h.Moves.get, id)
            if def and (tonumber(def.power) or 0) > 0 and not c.banned[Bot.moveKey(mon, id)] then empty[#empty + 1] = index end
          end
          local one = (hasItem(34) and 34) or (hasItem(35) and 35)
          local all = (hasItem(36) and 36) or (hasItem(37) and 37)
          local pick = (#empty > 1 and all) or one or all
          if #empty > 0 and pick and useItem(pick, slot, (pick == 34 or pick == 35) and empty[1] or nil) then
            stats.itemsPp = (stats.itemsPp or 0) + 1
            return true
          end
        end
      end
    end
    return false
  end
  local function loopRoute()
    -- there and back, or round and round when the route closes on itself
    local points, cursor = run.route.points, run.cursor
    local first, last = points[1], points[#points]
    local closed = #points > 2 and first.map == last.map and abs(first.x - last.x) + abs(first.y - last.y) <= 1
    if closed then
      cursor.i, cursor.dir = 1, 1
    else
      cursor.dir = -cursor.dir
      cursor.i = cursor.dir == 1 and min(2, #points) or max(1, #points - 1)
    end
  end
  -- Sweet Scent: stand on a grass cell of the route and call the encounters,
  -- one PP each. Returns false when it is not to be used right now.
  local MOVE_SWEET_SCENT = 230
  local function scentPP()
    local total = 0
    for _, mon in ipairs(session().party) do
      if not isEgg(mon) and type(mon.moves) == "table" then
        for slot = 1, 4 do
          local id = mon.moves[slot]
          if type(id) == "table" then id = id.id end
          if id == MOVE_SWEET_SCENT then total = total + (type(mon.pp) == "table" and tonumber(mon.pp[slot]) or 0) end
        end
      end
    end
    return total
  end
  -- Leaves for the Center: by the recorded heal path when there is one, else finding it.
  local function startHeal()
    local route = Bot.route(Bot.config.heal)
    if not route then
      run.phase, run.auto = "to_heal", { deadExit = {} }
      return true
    end
    local start = nearest(route)
    if not start then Bot.stop("heal_far") return false end
    run.phase, run.healCursor, run.auto = "to_heal", { i = start, dir = 1 }, nil
    return true
  end
  -- A marked Sweet Scent spot: stand there and call the encounters, without
  -- taking a step. In the Safari Zone that spends none of the visit's steps.
  local function trainScent()
    local h, c = host(), Bot.config
    local spot = run.route.points[1]
    local state = travel(spot.map, spot.x, spot.y)
    if state == "blocked" then return Bot.stop("blocked") end
    run.away = state ~= "arrived"
    if state ~= "arrived" then return end
    Bot.status = "scent"
    if not Bot.canUse("SWEET_SCENT") then return Bot.stop("no_scent_move") end
    if scentPP() == 0 then
      local safari = h.Safari ~= nil and try(h.Safari.isActive, session()) == true
      if safari or not c.healOn then return Bot.stop("no_scent") end
      startHeal()
      return
    end
    local clock = love.timer.getTime()
    if Bot.stats.ticks - (run.lastScent or -1000) < 60 or clock - (run.scentClock or 0) < 0.3 then return end
    run.lastScent, run.scentClock = Bot.stats.ticks, clock
    worldApi = worldApi or h.World.new(game, "trainer_pilot")
    if try(worldApi.useFieldAction, worldApi, "sweet_scent") == true then
      run.scentFails = 0
    else
      run.scentFails = (run.scentFails or 0) + 1
      if run.scentFails > 8 then return Bot.stop("no_scent_here") end
    end
  end
  local function scentHunt()
    local h, c = host(), Bot.config
    if run.scentOff or not Bot.canUse("SWEET_SCENT") then return false end
    local index = nearest(run.route)
    if not index then return false end              -- not on the route's map yet: walk there first
    if scentPP() == 0 and h.Safari and try(h.Safari.isActive, session()) == true then return false end
    if scentPP() == 0 then
      -- the scent is spent: the Center gives it back
      if not c.healOn then Bot.stop("no_scent") return true end
      run.phase, run.auto = "to_heal", { deadExit = {} }
      return true
    end
    -- the route point to stand on: the nearest one that is tall grass
    local map, x, y = position()
    local spot, best
    for _, p in ipairs(run.route.points) do
      if p.map == map and try(h.Collision.isGrass, p.x, p.y) == true then
        local distance = abs(p.x - x) + abs(p.y - y)
        if not best or distance < best then spot, best = p, distance end
      end
    end
    if not spot then return false end
    run.away = best > 6
    Bot.status = "scent"
    local state = walkTo(spot.x, spot.y)
    if state == "blocked" then Bot.stop("blocked") return true end
    if state ~= "arrived" then return true end
    local clock = love.timer.getTime()
    if Bot.stats.ticks - (run.lastScent or -1000) < 60 or clock - (run.scentClock or 0) < 0.3 then return true end
    run.lastScent, run.scentClock = Bot.stats.ticks, clock
    worldApi = worldApi or h.World.new(game, "trainer_pilot")
    if try(worldApi.useFieldAction, worldApi, "sweet_scent") == true then
      run.scentFails = 0
    else
      -- the game refuses it here: go back to walking the route
      run.scentFails = (run.scentFails or 0) + 1
      if run.scentFails > 8 then run.scentOff = true end
    end
    return true
  end
  local function trainWalk()
    if Bot.mode == "hunt" and Bot.config.huntScent and run.route.kind == "grass" and scentHunt() then return end
    run.away = nearest(run.route) == nil
    if run.away then
      -- on another map (coming back from the Center, say): go to where the route starts
      local first = run.route.points[1]
      if travel(first.map, first.x, first.y) == "blocked" then return Bot.stop("blocked") end
      run.cursor = { i = 1, dir = 1 }
      return
    end
    local state = follow(run.route, run.cursor)
    if state == "end" then loopRoute() end
    if state == "blocked" then return Bot.stop("blocked") end
  end
  local function trainFish()
    local h, spot = host(), run.route.points[1]
    local state = travel(spot.map, spot.x, spot.y)
    if state == "blocked" then return Bot.stop("blocked") end
    run.away = state ~= "arrived"
    if state ~= "arrived" then return end
    if not face(spot.dir) then return end
    if Bot.stats.ticks - (run.lastCast or -100) < 30 then return end
    run.lastCast = Bot.stats.ticks
    -- the rod asked for, or the best one in the bag
    for _, rod in ipairs(Bot.config.rod ~= 0 and { Bot.config.rod } or RODS) do
      if hasItem(rod) then
        local ok = try(h.ItemUse.useField, session(), session().bag, rod)
        if ok ~= true then return Bot.stop("cant_fish") end
        return
      end
    end
    Bot.stop("no_rod")
  end
  -- Trainers that answered the VS Seeker and still wait for their rematch.
  local function rematches()
    local h, out = host(), {}
    local V = h.VsSeeker
    if not (V and V.gather and V.state) then return out end
    local state = V.state(session())
    for _, info in ipairs(try(V.gather, h.Objects) or {}) do
      if info.sane and V.getRematch(state, info.localId) ~= 0 and not run.skipped[info.localId] then
        out[#out + 1] = info
      end
    end
    return out
  end
  local function trainSeeker()
    local h = host()
    local V = h.VsSeeker
    if not (V and hasItem(ITEM_VS_SEEKER)) then return Bot.stop("no_seeker") end
    run.skipped = run.skipped or {}
    local waiting = rematches()
    if #waiting > 0 then
      -- go and talk to the nearest one
      local _, x, y = position()
      table.sort(waiting, function(a, b) return abs(a.x - x) + abs(a.y - y) < abs(b.x - x) + abs(b.y - y) end)
      local foe = waiting[1]
      Bot.status = "seeker"
      local state = walkTo(foe.x, foe.y, true)
      if state == "blocked" then run.skipped[foe.localId] = true return end
      if state ~= "arrived" then return end
      local dir = (foe.x > x and "right") or (foe.x < x and "left") or (foe.y > y and "down") or "up"
      if not face(dir) then return end
      run.talks = (run.talks or 0) + 1
      if run.talks > 40 then run.skipped[foe.localId], run.talks = true, 0 return end
      tap("a", 15)
      return
    end
    run.talks = 0
    local points = run.route.points
    local spot = #points == 1 and points[1] or nil
    local charged = V.getBattery(session()) >= (V.MAX_CHARGE or 100)
    if spot then
      Bot.status = charged and "train" or "charging"
      local map, px, py = position()
      run.away = map ~= spot.map or abs(px - spot.x) + abs(py - spot.y) > 6
      if map ~= spot.map or charged then
        -- the item is used on the marked cell, nowhere else
        local state = travel(spot.map, spot.x, spot.y)
        if state == "blocked" then return Bot.stop("blocked") end
        if state ~= "arrived" then return end
      else
        -- charging takes steps: pace between the spot and a free cell next to it
        if px == spot.x and py == spot.y then
          local step, action = pathStep(spot.x, spot.y, true)
          if step and step ~= "here" and not action then hold(step) else release() end
        else
          if walkTo(spot.x, spot.y) == "blocked" then return Bot.stop("blocked") end
        end
        return
      end
    end
    local _, x, y = position()
    if not h.P.moving and charged
        and Bot.stats.ticks - (run.lastSeek or -1000) > 120 then
      local infos = try(V.gather, h.Objects) or {}
      local code = try(V.canUse, infos, x, y, V.state(session()), try(V.store, session()))
      if code == V.CAN_USE then
        run.lastSeek = Bot.stats.ticks
        release()
        local ok, kind = try(h.ItemUse.useField, session(), session().bag, ITEM_VS_SEEKER)
        if ok == true and kind == "vs_seeker" then
          run.skipped = {}
          Bot.stats.seeker = Bot.stats.seeker + 1
          try(V.use, session(), game)
        end
        return
      end
      if spot then return Bot.stop("no_trainers") end
    end
    if not spot then trainWalk() end
  end
  -- The nearest Pokémon Center door: on this map or one reached through map connections.
  local function isCenter(id)
    if type(id) ~= "string" or id:find("2F", 1, true) then return false end
    return id:find("POKEMON_CENTER", 1, true) ~= nil or id:find("POKECENTER", 1, true) ~= nil
  end
  local function centerDoor(id)
    local def = mapDef(id)
    for _, w in ipairs(def and type(def.warps) == "table" and def.warps or {}) do
      local dest = w.destMap or w.map
      if isCenter(dest) and tonumber(w.x) and tonumber(w.y) then
        return { map = id, x = tonumber(w.x), y = tonumber(w.y), center = dest }
      end
    end
  end
  -- The nearest Pokémon Center door, by the map of links: on this map, or
  -- past map edges, gate houses and caves.
  local function findCenter()
    local start = position()
    local here = centerDoor(start)
    if here then return here end
    local _, found = planHop(start, function(id) return centerDoor(id) ~= nil end, "center")
    return found and centerDoor(found) or nil
  end
  -- Where the player stood when a Center healed the team, remembered per Center.
  local NURSES_KEY = "nurses/v1"
  local nurses = {}
  for map, x, y, dir in tostring(cacheRead(NURSES_KEY) or ""):gmatch("([%w_]+)=(-?%d+),(-?%d+),(%a+)") do
    nurses[map] = { x = tonumber(x), y = tonumber(y), dir = dir }
  end
  -- Recorded heal routes are gone: the bot finds the Center by itself. What an
  -- old one knew, where the player stood to be healed, is kept before dropping it.
  do
    local kept, dropped = {}, false
    for _, route in ipairs(Bot.routes) do
      if route.kind == "heal" then
        local last = route.points[#route.points]
        if isCenter(last.map) and not nurses[last.map] then nurses[last.map] = { x = last.x, y = last.y, dir = last.dir or "up" } end
        dropped = true
      else
        kept[#kept + 1] = route
      end
    end
    if dropped then
      local lines = {}
      for id, n in pairs(nurses) do lines[#lines + 1] = ("%s=%d,%d,%s"):format(id, n.x, n.y, n.dir) end
      cacheWrite(NURSES_KEY, table.concat(lines, "\n"))
      Bot.save()
    end
  end
  local wasHurt = false
  local function learnNurse()
    local h = host()
    local map, x, y = position()
    local healed = fullyHealed(session().party)
    if wasHurt and healed and isCenter(map) and not h.P.moving then
      local known = nurses[map]
      if not (known and known.x == x and known.y == y) then
        nurses[map] = { x = x, y = y, dir = h.P.facing or "up" }
        local lines = {}
        for id, n in pairs(nurses) do lines[#lines + 1] = ("%s=%d,%d,%s"):format(id, n.x, n.y, n.dir) end
        cacheWrite(NURSES_KEY, table.concat(lines, "\n"))
      end
    end
    wasHurt = not healed
  end
  Bot.learnNurse = learnNurse
  -- Where to stand to talk to the nurse: two cells below her, across the counter.
  local function nurseCell(center)
    local h = host()
    if nurses[center] then return nurses[center].x, nurses[center].y, nurses[center].dir end
    local events = h.Space and h.Space.bundle and h.Space.bundle.events and h.Space.bundle.events[center]
    for _, object in ipairs(events and type(events.objects) == "table" and events.objects or {}) do
      local script = tostring(object.scriptKey or object.script or "")
      if script:find("Nurse", 1, true) and tonumber(object.x) and tonumber(object.y) then
        return tonumber(object.x), tonumber(object.y) + 2
      end
    end
    -- a recorded heal route that ends in this Center knows where the player stood
    for _, route in ipairs(Bot.routes) do
      local last = route.points[#route.points]
      if route.kind == "heal" and last.map == center then return last.x, last.y, last.dir end
    end
    return 7, 4
  end
  local function autoHealTick()
    local h = host()
    local auto = run.auto
    local map, x, y = position()
    if run.phase == "to_heal" then
      Bot.status = "to_heal"
      if isCenter(map) then run.phase, run.healTaps = "healing", 0 return end
      if not auto.door then
        auto.door = findCenter()
        if not auto.door then return Bot.stop("no_center") end
      end
      if travel(auto.door.map, auto.door.x, auto.door.y) == "blocked" then return Bot.stop("blocked") end
    elseif run.phase == "healing" then
      Bot.status = "healing"
      if not isCenter(map) then return Bot.stop("heal_failed") end
      auto.center = map
      local nx, ny, facing = nurseCell(map)
      local state = walkTo(nx, ny)
      if state == "blocked" then return Bot.stop("nurse") end
      if state ~= "arrived" or not face(facing or "up") then return end
      if fullyHealed(session().party) and run.healTaps > 0 then
        Bot.stats.heals = Bot.stats.heals + 1
        if run.finishing then return Bot.stop("level_healed") end
        run.phase, run.healSince = "from_heal", nil
        return
      end
      run.healSince = run.healSince or mark()
      if late(run.healSince, 2400, 40) then return Bot.stop("heal_failed") end
      if tap("a", 20) then run.healTaps = run.healTaps + 1 end
    else
      Bot.status = "from_heal"
      if not isCenter(map) then run.phase, run.auto = "train", nil return end
      -- the way out is a warp that leads back outside. The map may list cells
      -- beside the mat too; the ones whose tile really is a way out come first,
      -- and one that does nothing when stepped off is given up for the next.
      local def, exits = mapDef(map), {}
      local outside = auto.door and auto.door.map
      for pass = 1, 2 do
        for _, w in ipairs(def and type(def.warps) == "table" and def.warps or {}) do
          local dest = w.destMap or w.map
          local wx, wy = tonumber(w.x), tonumber(w.y)
          if wx and wy and not isCenter(dest) and (not outside or dest == outside or pass == 2)
              and not auto.deadExit[wx .. ":" .. wy] then
            local real = isWarp(h, wx, wy)
            if (pass == 1) == real then exits[#exits + 1] = { x = wx, y = wy } end
          end
        end
      end
      local exit = exits[1]
      if not exit then return Bot.stop("blocked") end
      if x == exit.x and y == exit.y then
        auto.exitSince = auto.exitSince or mark()
        if late(auto.exitSince, 90, 1.5) then auto.deadExit[exit.x .. ":" .. exit.y], auto.exitSince = true, nil end
        hold("down")
        return
      end
      auto.exitSince = nil
      if walkTo(exit.x, exit.y) == "blocked" then
        auto.deadExit[exit.x .. ":" .. exit.y] = true
      end
    end
  end
  -- Where on a recorded heal path the nurse is. A path may end there (the
  -- bot then walks it backwards to return) or go on back to the training
  -- spot: for caves with a puzzle, where the way back is not the way in reversed.
  local function healIndex(route)
    local points = route.points
    if isCenter(points[#points].map) then return #points, false end
    local lowest
    for index, p in ipairs(points) do
      if isCenter(p.map) then
        local known = nurses[p.map]
        if known and known.x == p.x and known.y == p.y then return index, true end
        if not lowest or p.y < points[lowest].y then lowest = index end
      end
    end
    return lowest or #points, lowest ~= nil
  end
  local function healTick()
    local h = host()
    if run.auto then return autoHealTick() end
    local route = Bot.route(Bot.config.heal)
    if not route then return Bot.stop("needs_heal") end
    local nurseAt, roundTrip = healIndex(route)
    if run.phase == "to_heal" then
      Bot.status = "to_heal"
      local stop = route.points[nurseAt]
      local map, x, y = position()
      if run.healCursor.i > nurseAt and at(stop, map, x, y) and not h.P.moving then
        release()
        run.phase, run.healTaps = "healing", 0
        return
      end
      -- never past the nurse on the way in: join the recording on its outbound part
      run.healCursor.max = nurseAt
      if run.healCursor.i > nurseAt then
        local best, bestDistance
        for index = 1, nurseAt do
          local p = route.points[index]
          if p.map == map then
            local distance = abs(p.x - x) + abs(p.y - y)
            if not bestDistance or distance < bestDistance then best, bestDistance = index, distance end
          end
        end
        run.healCursor.i = best or nurseAt
      end
      local state = follow(route, run.healCursor)
      if state == "blocked" then return Bot.stop("blocked") end
      if state == "end" then run.phase, run.healTaps = "healing", 0 end
    elseif run.phase == "healing" then
      Bot.status = "healing"
      local last = route.points[nurseAt]
      local known = nurses[last.map]
      if not face(known and known.x == last.x and known.y == last.y and known.dir or (roundTrip and "up" or last.dir)) then return end
      if fullyHealed(session().party) and run.healTaps > 0 then
        Bot.stats.heals = Bot.stats.heals + 1
        if run.finishing then return Bot.stop("level_healed") end
        -- back the way it came, or on along the recording when that goes back to the spot itself
        run.phase, run.healSince = "from_heal", nil
        run.healCursor = roundTrip and { i = nurseAt + 1, dir = 1 } or { i = #route.points - 1, dir = -1 }
        return
      end
      run.healSince = run.healSince or mark()
      if late(run.healSince, 2400, 40) then return Bot.stop("heal_failed") end
      if tap("a", 20) then run.healTaps = run.healTaps + 1 end
    else
      Bot.status = "from_heal"
      local state = follow(route, run.healCursor)
      if state == "blocked" then return Bot.stop("blocked") end
      if state == "end" then
        run.phase = "train"
        run.cursor = { i = nearest(run.route) or 1, dir = 1 }
      end
    end
  end
  Bot.SAFARI_PRICE = 500      -- what a visit costs in FireRed and LeafGreen
  function Bot.money()
    local s = session()
    local money = s and tonumber(s.money)
    if money == nil and game and type(game.save) == "table" then money = tonumber(game.save.money) end
    return money
  end
  local function fieldTick()
    local h, c = host(), Bot.config
    local party = session().party
    if run.phase ~= "train" then return healTick() end
    local safari = h.Safari ~= nil and try(h.Safari.isActive, session()) == true
    if run.inSafari and not safari then
      -- the visit is over: pay for another one, as many times as was asked for
      local limit = c.safariReentries
      run.safariEntries = (run.safariEntries or 0)
      if limit ~= -1 and run.safariEntries >= limit then return Bot.stop("safari_over") end
      -- no money for the ticket: say so now rather than stand at the gate
      local money = Bot.money()
      if money and money < Bot.SAFARI_PRICE then return Bot.stop("safari_money") end
      run.safariEntries = run.safariEntries + 1
      Bot.stats.safariEntries = run.safariEntries
      run.inSafari, run.reenter = false, mark()
      -- out here is the one chance to get PP back (Sweet Scent's, above all)
      if c.healOn and not fullyHealed(party) then
        startHeal()
        return
      end
    end
    if safari then run.reenter = nil end
    if run.reenter and late(run.reenter, 3600, 60) then return Bot.stop("safari_reenter") end
    run.inSafari = safari
    if safari or run.reenter then
      -- in there the team does not fight and nothing can be healed: just look for encounters
      run.forceHeal = nil
      Bot.status = "train"
      local kind = run.route.kind
      if kind == "fish" then trainFish() elseif kind == "seeker" then trainSeeker()
      elseif kind == "scent" then trainScent() else trainWalk() end
      return
    end
    if run.forceHeal then
      run.forceHeal = nil
      if c.healOn then
        run.phase, run.auto = "to_heal", { deadExit = {} }
        return
      end
    end
    local slot, why = pickLead(party)
    if not slot then
      if why == "nobody" then return Bot.stop("nobody") end
      if why == "level" then
        -- done: finish at the Pokémon Center with the team healed, when healing is on
        if not c.healOn then return Bot.stop("level") end
        run.finishing = true
      end
      if why == "tired" then
        -- what the bag can mend does not need the walk to the Center
        release()
        if h.P.moving then return end
        if itemHeal(party) then return end
      end
      if not c.healOn then return Bot.stop("needs_heal") end
      local route = Bot.route(c.heal)
      if not route then
        -- no recorded way: find the nearest Center and walk there
        run.phase, run.auto = "to_heal", { deadExit = {} }
        return
      end
      local start = nearest(route)
      if not start then return Bot.stop("heal_far") end
      run.phase, run.healCursor = "to_heal", { i = start, dir = 1 }
      return
    end
    if slot ~= 1 then
      -- put the one who should fight in front, as the party menu's SWITCH does
      release()
      if h.P.moving then return end
      party[1], party[slot] = party[slot], party[1]
      local overlay = session().move_overlay
      if type(overlay) == "table" then overlay[1], overlay[slot] = overlay[slot], overlay[1] end
      if c.policy == "selected" then
        c.selected[1], c.selected[slot] = c.selected[slot], c.selected[1]
      end
      return
    end
    if Bot.mode == "hunt" and c.huntCatch then
      -- ready to hunt: no looking for a target the bot could not then catch
      if not Bot.pickBall() then return Bot.stop("no_balls_ready") end
      if not Bot.roomForCatch() then return Bot.stop("pc_full") end
      if c.catchStatus and c.healOn then
        local lead, knows, ready = party[1], false, false
        for move = 1, 4 do
          local id = type(lead.moves) == "table" and lead.moves[move]
          if type(id) == "table" then id = id.id end
          if id and STATUS_MOVES[id] then
            knows = true
            if (type(lead.pp) == "table" and tonumber(lead.pp[move]) or 0) > 0 then ready = true end
          end
        end
        -- its sleep or paralysis move is out of PP: get it back first
        if knows and not ready then
          run.phase, run.auto = "to_heal", { deadExit = {} }
          return
        end
      end
    end
    Bot.status = "train"
    local kind = run.route.kind
    if kind == "fish" then trainFish() elseif kind == "seeker" then trainSeeker()
    elseif kind == "scent" then trainScent() else trainWalk() end
  end

  ---------------------------------------------------------------------------
  -- One step of the game
  ---------------------------------------------------------------------------
  local function busy()
    local h = host()
    if h.Compat and h.Compat.worldBusy then
      local isBusy = try(h.Compat.worldBusy)
      return isBusy == true
    end
    return h.Field.locked == true
  end
  local function tick()
    Bot.stats.ticks = Bot.stats.ticks + 1
    local h = host()
    if not (h and game and session()) then return end
    recordTick()
    if Bot.stats.ticks % 15 == 0 and h.Field.running then pcall(Bot.learnNurse) end
    if h.Field.running then pcall(Bot.noteCrossing) end
    if not Bot.running then
      -- A paused reset hunt keeps the save locked. If the player then walks off
      -- and plays on, the hunt is over: the lock must not eat their progress.
      if Bot.resetLock and h.Field.running then
        local map, x, y = position()
        local at = Bot.resetAt
        if not at then Bot.resetAt = { map = map, x = x, y = y }
        elseif at.map ~= map or math.abs(at.x - x) + math.abs(at.y - y) >= 4 then
          Bot.finish()
          Bot.reason = "reset_released"
        end
      end
      return
    end
    Bot.resetAt = nil
    if run.reset then
      if run.reset.state == "reload" then return end
      -- the "previously on your quest" replay some saves open with
      if game.phase ~= nil and game.phase ~= "field" then tap("b", 10) return end
      if h.Battle.isActive() then return battleTick() end
      return resetTick()
    end
    if h.Evolution and try(h.Evolution.isOpen) == true then
      release()
      if Bot.config.stopEvolve then return Bot.stop("evolve") end
      -- a new form may want a move the bot should not choose for the player
      if h.Choice and h.Choice.isOpen and h.Choice.isOpen() then return Bot.stop("learn") end
      tap("a", 30)
      return
    end
    if h.Battle.isActive() then
      run.idleSince, run.sameSince = nil, mark()
      return battleTick()
    end
    -- a Repel used in the middle of the run: there is nothing left to find
    if Bot.stats.ticks % 30 == 0 and repelMatters(run.route) and repelLeft() > 0 then return Bot.stop("repel_on") end
    if run.catching and run.battle then
      -- the battle is over: still standing means the ball held
      local c = Bot.config
      -- the battle says how it ended; without that, still standing means the ball held
      local result = run.battle.result
      local caught = result == "catch" or (result == nil and (tonumber(run.catching.foe.hp) or 0) > 0)
      Bot.stats.caught = (Bot.stats.caught or 0) + (caught and 1 or 0)
      Bot.stats.lost = (Bot.stats.lost or 0) + (caught and 0 or 1)
      run.catching, run.battle = nil, nil
      if c.catchHeal then run.forceHeal = true end
      if caught and not c.catchContinue then return Bot.stop("caught") end
    end
    run.battle = nil
    if not h.Field.running then release() return end
    local choice = h.Choice and h.Choice.isOpen and h.Choice.isOpen()
    if choice then
      release()
      -- the nurse asks before healing; anything else is not the bot's to answer
      if run.phase == "healing" then
        if tap("a", 20) then run.healTaps = run.healTaps + 1 end
        return
      end
      -- going back into the Safari Zone: yes to the attendant
      if run.reenter then tap("a", 20) return end
      return Bot.stop("question")
    end
    local message = h.Message
    if message and message.isOpen and message.isOpen() then
      release()
      if message.isWaiting and message.isWaiting() then
        if tap("a", 8) and run.phase == "healing" then run.healTaps = run.healTaps + 1 end
      end
      run.idleSince = run.idleSince or mark()
      if late(run.idleSince, 3600, 30) then return Bot.stop("stuck") end
      return
    end
    if h.Field._fishing then release() return end
    if busy() then
      release()
      run.idleSince = run.idleSince or mark()
      if late(run.idleSince, 3600, 30) then return Bot.stop("stuck") end
      return
    end
    run.idleSince = nil
    -- standing on the same cell for a long time without a fight means something is wrong
    local map, x, y = position()
    local here = map .. ":" .. x .. ":" .. y
    if here ~= run.here then run.here, run.sameSince = here, mark() end
    if run.route.kind ~= "fish" and run.route.kind ~= "scent" and run.phase ~= "healing" and late(run.sameSince, 2400, 30) then
      return Bot.stop("stuck")
    end
    fieldTick()
  end

  mod.hooks:wrap("input.step", function(nextHook, ...)
    local ok, err = pcall(tick)
    if not ok then
      release()
      if Bot.running then Bot.stop("error") end
      if not Bot.logged then
        Bot.logged = true
        mod.log:warn("bot: %s", tostring(err))
      end
      Bot.lastError = tostring(err)
    end
    return nextHook(...)
  end)

  -- Any button the player presses takes the controls back.
  local function interrupt(nextHook, hookGame, event, ...)
    if Bot.running and type(event) == "table" and event.phase == "pressed" then Bot.stop("player") end
    return nextHook(hookGame, event, ...)
  end
  mod.hooks:wrap("input.gamepad", interrupt, 3000)
  mod.hooks:wrap("input.key", interrupt, 3000)

  -- While a reset hunt owns the save, nothing may be written over it: the game
  -- saves on its way out, and that would keep whatever the last attempt gave.
  pcall(function()
    mod.hooks:wrap("save.write", function(nextHook, ...)
      if Bot.resetLock then return false end
      return nextHook(...)
    end, 3000)
  end)

  mod.hooks:wrap("core.quit_to_launcher", function(nextHook)
    Bot.stop("quit")
    Bot.recording, game, H, battleApi = nil, nil, nil, nil
    return nextHook()
  end, 900)
  mod.events:on("game.ready", function(payload)
    game = payload and payload.game or nil
    H, battleApi, worldApi = nil, nil, nil
  end)

  ---------------------------------------------------------------------------
  -- The control panel, when Trainer Desk is there
  ---------------------------------------------------------------------------
  Bot.attacks, Bot.allowed, Bot.hpPct, Bot.isEgg = attacks, allowed, hpPct, isEgg
  local panel
  local okPanel, errPanel = pcall(function()
    panel = assert(loadstring(assert(mod:read("panel.lua")), "@trainer_pilot/panel.lua"))()(mod, Bot, I18n)
  end)
  if not okPanel then mod.log:warn("panel unavailable: %s", tostring(errPanel)) end
  -- Typing a target's name: the keys go to the panel, not to the game (and do not pause the bot).
  mod.hooks:wrap("input.key", function(nextHook, hookGame, event, ...)
    if panel and panel.wantsKeys and panel.wantsKeys() and type(event) == "table" and event.key then
      if event.phase == "pressed" then pcall(panel.key, event.key) end
      return
    end
    return nextHook(hookGame, event, ...)
  end, 3200)
  local docked
  mod.hooks:wrap("core.update", function(nextHook, updateGame, dt)
    local okReload, errReload = pcall(Bot.reloadNow)
    if not okReload then
      Bot.lastError = tostring(errReload)
      if Bot.running then Bot.stop("error") end
    end
    pcall(function()
      if not (panel and mod.find) then return end
      local other = mod.find("trainer_desk")
      local api = other and other.exports and other.exports.dock
      if type(api) == "table" and api.api == 1 and api.active() then
        if docked ~= api then
          api.register({ id = "trainer_pilot.panel", title = "Trainer Pilot", width = panel.W, height = panel.H, pixel = 1,
            interval = 0.1, side = "right", pointer = panel.pointer, responsive = true,
            -- a dock that knows responsive panels says how much room there is, and lends its colours
            draw = function(clock, w, h)
              if api.theme and panel.theme then panel.theme(api.theme().colors) end
              return panel.draw(clock, w, h)
            end })
          docked = api
        end
      else
        docked = nil
      end
    end)
    return nextHook(updateGame, dt)
  end, 880)

  mod.exports = mod.exports or {}
  mod.exports.bot = Bot
end
