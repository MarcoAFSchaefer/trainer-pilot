-- A small stand-in for the game, enough to drive Trainer Pilot end to end:
-- a tile world with grass, water, a door to a Pokémon Center with a nurse,
-- trainers for the VS Seeker, and turn-based battles behind the battle API.
local OUT = os.getenv("TEST_OUT") or "/tmp/kg_out"
local DIR = os.getenv("BOT_MOD")
local function read(name) local f = io.open(DIR .. "/" .. name, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
function love.errorhandler(msg) print("HARNESS ERROR", msg, debug.traceback()); return function() return 1 end end
local function check(cond, msg) if not cond then error("CHECK FAILED: " .. msg, 2) end; print("ok  " .. msg) end

function love.load()
  os.execute("mkdir -p " .. OUT)
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local MAPS = {
    MAP_ROUTE1 = {
      "######D#######",
      "#....gggg....#",
      "#....gggg..T.#",
      "#....gggg.....",
      "#..........~~#",
      "#.........~~.#",
      "##############" },
    MAP_POKEMON_CENTER_1F = {
      "#######",
      "#..N..#",
      "#..C..#",
      "#.....#",
      "#.....#",
      "#..E..#",
      "#######" },
    MAP_CAVE = {
      "#####",
      "#..D#",
      "#...#",
      "#D..#",
      "#####" },
    MAP_ROUTE3 = {
      "#####",
      "#D..#",
      "#..~#",
      "#####" },
    MAP_ROUTE2 = {
      "######",
      "#...D#",
      "#..~~#",
      ".....#",
      "#....#",
      "#....#",
      "######" },
  }
  local WARPS = { ["MAP_ROUTE2:4:1"] = { "MAP_CAVE", 2, 3 }, ["MAP_CAVE:1:3"] = { "MAP_ROUTE2", 3, 1 },
    ["MAP_CAVE:3:1"] = { "MAP_ROUTE3", 1, 2 }, ["MAP_ROUTE3:1:1"] = { "MAP_CAVE", 2, 1 },
    ["MAP_ROUTE1:6:0"] = { "MAP_POKEMON_CENTER_1F", 3, 5 }, ["MAP_POKEMON_CENTER_1F:3:5:down"] = { "MAP_ROUTE1", 6, 1 } }
  local Map = { current = "MAP_ROUTE1" }
  local function cell(x, y, map) local row = MAPS[map or Map.current][y + 1]; return row and row:sub(x + 1, x + 1) or "#" end
  local P = { cellX = 2, cellY = 2, facing = "down", moving = false, currentElevation = 3 }
  local trainer = { localId = 7, x = 11, y = 2 }
  local Objects = {}
  local function mon(species, level, hp, extra)
    local m = { species = species, level = level, hp = hp, maxHp = hp, moves = { 33, 45 }, pp = { 35, 40 }, maxPp = { 35, 40 }, personality = 1, nickname = "" }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
  end
  local session = { map = "MAP_ROUTE1", party = { mon(4, 10, 40), mon(16, 8, 30) }, bag = { [264] = 1, [362] = 1 }, vsSeeker = { steps = 0, rematches = {} } }
  local input = { held = {}, edges = {} }
  function input:sourcePress(btn, source) self.held[source] = btn; self.edges[btn] = true end
  function input:sourceRelease(_, source) self.held[source] = nil end
  local function heldDir() for _, btn in pairs(input.held) do if D[btn] then return btn end end end
  local game = { generation = 3, session = session, input = input, data = {
    maps = { MAP_ROUTE1 = { w = 14, h = 7, warps = { { x = 6, y = 0, destMap = "MAP_POKEMON_CENTER_1F" } }, connections = { { dir = "east", map = "MAP_ROUTE2", offset = 0 } } },
      MAP_ROUTE2 = { w = 6, h = 7, connections = { { dir = "west", map = "MAP_ROUTE1", offset = 0 } }, warps = { { x = 4, y = 1, destMap = "MAP_CAVE" } } },
      MAP_CAVE = { w = 5, h = 5, warps = { { x = 1, y = 3, destMap = "MAP_ROUTE2" }, { x = 3, y = 1, destMap = "MAP_ROUTE3" } } },
      MAP_ROUTE3 = { w = 5, h = 4, warps = { { x = 1, y = 1, destMap = "MAP_CAVE" } } },
      MAP_POKEMON_CENTER_1F = { w = 7, h = 7, warps = { { x = 2, y = 5, destMap = "MAP_ROUTE1" }, { x = 3, y = 5, destMap = "MAP_ROUTE1" } } } }, gen3Encounters = { MAP_ROUTE1 = { land = { slots = { { species = 16 }, { species = 19 } } } },
    MAP_ROUTE2 = { fishing = { old = { { species = 129 } }, super = { slots = { { species = 130 } } } } } } } }
  local Field = { running = true, locked = false, _game = game, _session = session }
  local Message = { open = false, _waiting = false }
  function Message.isOpen() return Message.open end
  function Message.isWaiting() return Message.open and Message._waiting end
  local function say(pages, done) Message.open, Message._waiting, Message.pages, Message.done = true, true, pages, done end
  local Choice = { open = false }
  function Choice.isOpen() return Choice.open end
  local PartyMenu = { open = false, cursor = 1 }
  local Evolution = { open = false, isOpen = function() return false end }
  local sim
  local Collision = {}
  function Collision.elevationAt() return 3 end
  function Collision.behavior(x, y) local c = cell(x, y); return (c == "D" or c == "E") and 1 or 0 end
  function Collision.isWarpMetatileBehavior(b) return b == 1 end
  function Collision.ledgeLanding() return nil end
  function Collision.inBounds(x, y) local def = MAPS[Map.current]; return y >= 0 and y < #def and x >= 0 and x < #def[1] end
  function Collision.isGrass(x, y) return cell(x, y) == "g" end
  function Collision.isWater(x, y) return cell(x, y) == "~" end
  function Collision.canEnter(_, x, y, opts)
    local c = cell(x, y)
    if c == "~" and not (opts and opts.surfing) then return false, "elevation" end
    if c == "#" or c == "N" or c == "C" then return false, "tile" end
    if Map.current == "MAP_ROUTE1" and x == trainer.x and y == trainer.y then return false, "entity" end
    if sim.objects[Map.current .. ":" .. x .. ":" .. y] then return false, "entity" end
    local def = game.data.maps[Map.current]
    if x < 0 or y < 0 or x >= def.w or y >= def.h then return false, "bounds" end
    return true
  end
  -- battles ---------------------------------------------------------------
  local battle = { active = false }
  sim = { objects = {}, grassSteps = 0, encounterEvery = 3, nextWild = nil, foeHits = 6, log = {}, levelPerWin = 1 }
  local Battle = { isActive = function() return battle.active end, getState = function() return battle.st end }
  local function startBattle(wild, foe)
    battle.active = true
    battle.st = { wild = wild, enemy = { mon = foe }, player = { mon = session.party[1] }, playerParty = session.party }
    battle.prompt, battle.revision = "advance", (battle.revision or 0) + 1
    battle.after = "menu"
  end
  local function endBattle() battle.active, battle.st = false, nil end
  local BattleAPI = {}
  function BattleAPI.new() return BattleAPI end
  function BattleAPI:snapshot() if not battle.active then return nil end return { revision = battle.revision, prompt = battle.prompt, active = 0 } end
  function BattleAPI:submit(intent)
    if intent.revision ~= battle.revision then return nil, "stale" end
    battle.revision = battle.revision + 1
    local st = battle.st
    if intent.kind == "menu" and st.safari then
      local what = ({ fight = "sball", bag = "bait", party = "rock", run = "run" })[intent.choice]
      sim.log[#sim.log + 1] = what
      if what == "sball" then
        sim.safariBalls = sim.safariBalls - 1
        st.thrown = (st.thrown or 0) + 1
        if st.thrown >= (sim.safariCatchAt or 2) then st.result = "catch"; sim.log[#sim.log + 1] = "caught"; endBattle()
        elseif sim.safariFlee then st.result = "fled"; endBattle()
        else battle.prompt = "menu" end
      elseif what == "run" then st.result = "run"; endBattle()
      else battle.prompt = "menu" end
      return true
    end
    if intent.kind == "menu" then
      if intent.choice == "party" then sim.log[#sim.log + 1] = "party"; PartyMenu.open, PartyMenu._party, PartyMenu.cursor = true, session.party, 1; battle.prompt = "locked"
      elseif intent.choice == "run" then sim.log[#sim.log + 1] = "run"; battle.prompt, battle.after = "advance", "end" else battle.prompt = "moves" end
    elseif intent.kind == "move" then
      local me, foe = st.player.mon, st.enemy.mon
      assert(me.pp[intent.slot] > 0, "move without PP")
      me.pp[intent.slot] = me.pp[intent.slot] - 1
      sim.log[#sim.log + 1] = "move" .. intent.slot
      local id = me.moves[intent.slot]
      if id == 86 then foe.status = 1 end
      if not (id == 45 or id == 86 or id == 230) then foe.hp = math.max(id == 206 and 1 or 0, foe.hp - (sim.dmg or 20)) end
      if foe.hp == 0 and st.foeParty and foe == st.foeParty[1] then
        Battle._phase, Battle._shiftEnemyIdx, Choice.open, battle.prompt = "shift_prompt", 2, true, "locked"
      elseif foe.hp == 0 then
        me.level = me.level + sim.levelPerWin
        if sim.evYield and me.evs then
          for key, n in pairs(sim.evYield[battle.st.enemy.mon.species] or {}) do me.evs[key] = (me.evs[key] or 0) + n end
        end
        battle.prompt, battle.after = "advance", "end"
      else
        me.hp = math.max(0, me.hp - sim.foeHits)
        battle.prompt, battle.after = "advance", me.hp == 0 and "faint" or "menu"
      end
    end
    return true
  end
  local BattleUi = { _mode = "menu" }
  package.preload["src.core.game3.battle.ui"] = function() return BattleUi end
  local function battleStep()
    if BattleUi._pendingCommand then
      local cmd = BattleUi._pendingCommand
      BattleUi._pendingCommand = nil
      assert(cmd.kind == "bag" and (session.bag[cmd.itemId] or 0) > 0, "threw a ball that is not in the bag")
      session.bag[cmd.itemId] = session.bag[cmd.itemId] - 1
      sim.log[#sim.log + 1] = "ball" .. cmd.itemId
      local foe = battle.st.enemy.mon
      battle.revision = battle.revision + 1
      if (sim.fleeFirst or 0) > 0 then
        sim.fleeFirst = sim.fleeFirst - 1
        battle.st.result = "fled"; sim.log[#sim.log + 1] = "fled"; endBattle()
      elseif cmd.itemId == 1 or (foe.status == 1 and foe.hp <= 12) then
        sim.log[#sim.log + 1] = "caught"
        battle.prompt, Choice.open = "locked", true
        Choice.done = function() sim.log[#sim.log + 1] = "nicknamed" end
        battle.caught = true
      else
        battle.prompt = "menu"
      end
      return
    end
    if battle.caught then
      if not Choice.open then battle.caught = nil; endBattle() elseif input.edges.b then Choice.open, Choice.done = false, nil
      elseif input.edges.a then Choice.open = false; Choice.done() end
      return
    end
    if Battle._phase == "shift_prompt" then
      if Choice.open and (input.edges.a or input.edges.b) then
        Choice.open, Battle._phase = false, "command"
        sim.log[#sim.log + 1] = input.edges.a and "shift_yes" or "shift_no"
        battle.st.enemy.mon = battle.st.foeParty[2]
        battle.revision = battle.revision + 1
        if input.edges.a then PartyMenu.open, PartyMenu._party, PartyMenu.cursor = true, session.party, 1; battle.prompt = "locked" else battle.prompt = "menu" end
      end
      return
    end
    if PartyMenu.open then
      if input.edges.a then
        local chosen = PartyMenu._party[PartyMenu.cursor]
        if chosen and chosen.hp > 0 then battle.st.player.mon = chosen; PartyMenu.open = false; battle.prompt = "menu"; battle.revision = battle.revision + 1 end
      end
      return
    end
    if battle.prompt == "advance" and input.edges.a then
      battle.revision = battle.revision + 1
      if battle.after == "end" then endBattle()
      elseif battle.after == "faint" then
        local alive = false
        for _, m in ipairs(session.party) do if m.hp > 0 then alive = true end end
        if alive then PartyMenu.open, PartyMenu._party, PartyMenu.cursor = true, session.party, 1; battle.prompt = "locked" else endBattle() end
      else battle.prompt = battle.after end
    end
  end
  -- field ------------------------------------------------------------------
  local VsSeeker = { MAX_CHARGE = 100, CAN_USE = 2, ITEM_VS_SEEKER = 362 }
  function VsSeeker.state(s) return s.vsSeeker end
  function VsSeeker.store() return {} end
  function VsSeeker.getBattery(s) return s.vsSeeker.steps end
  function VsSeeker.getRematch(state, id) return state.rematches[id] or 0 end
  function VsSeeker.gather() return Map.current == "MAP_ROUTE1" and { { localId = 7, x = trainer.x, y = trainer.y, sane = true } } or {} end
  function VsSeeker.canUse(infos, px, py, s) if s.steps < 100 then return 0 end; for _, i in ipairs(infos) do if math.abs(i.x - px) <= 7 and math.abs(i.y - py) <= 5 then return 2 end end; return 1 end
  function VsSeeker.use(s) s.vsSeeker.steps = 0; s.vsSeeker.rematches[7] = 1; sim.log[#sim.log + 1] = "seeker" end
  local ItemUse = {}
  function ItemUse.useField(s, _, id, slot, moveSlot)
    if id == 362 then return true, "vs_seeker" end
    local heals = { [13] = 20, [22] = 50, [21] = 200 }
    if heals[id] or id == 34 then
      local m = s.party[slot]
      if (s.bag[id] or 0) < 1 or not m then return false, "noeffect" end
      if heals[id] then
        if m.hp <= 0 or m.hp >= m.maxHp then return false, "noeffect" end
        m.hp = math.min(m.maxHp, m.hp + heals[id])
      else
        if not moveSlot then return false, "need_move" end
        m.pp[moveSlot] = math.min(m.maxPp[moveSlot], m.pp[moveSlot] + 10)
      end
      s.bag[id] = s.bag[id] - 1
      return true, "medicine"
    end
    if id >= 262 and id <= 264 then
      local d = D[P.facing]
      if cell(P.cellX + d[1], P.cellY + d[2]) ~= "~" then return false, "rod" end
      Field._fishing = { timer = 0 }
      sim.rods = sim.rods or {}; sim.rods[id] = true
      return true, "rod"
    end
    return false
  end
  local Bag = { has = function(bag, id) return (bag[id] or 0) > 0 end }
  local Pokemon = { speciesOf = function(m) return m.species end, isEgg = function(m) return m.isEgg == true end, isShiny = function(m) return m.shiny == true end,
    name = function(s) return ({ [4] = "CHARMANDER", [16] = "PIDGEY", [19] = "RATTATA", [129] = "MAGIKARP" })[s] or "MON" end, types = function() return { 0, 0 } end }
  local Moves = { get = function(id) return { power = (id == 45 or id == 86 or id == 230) and 0 or id == 99 and 90 or 40, type = 0, accuracy = 100, pp = 35 } end }
  local Types = { effectiveness = function() return 100 end, ID = { NORMAL = 0, FIRE = 10 } }
  local Compat = { worldBusy = function() return Field.locked or battle.active end }
  local function wild() local m = sim.nextWild or mon(19, 5, 60); sim.nextWild = nil; return m end
  local function arrive()
    session.vsSeeker.steps = math.min(100, session.vsSeeker.steps + 1)
    P.surfing = cell(P.cellX, P.cellY) == "~"
    local c = cell(P.cellX, P.cellY)
    local warp = WARPS[Map.current .. ":" .. P.cellX .. ":" .. P.cellY]
    if warp then Map.current, P.cellX, P.cellY = warp[1], warp[2], warp[3]; session.map = Map.current; return end
    if c == "g" then
      sim.grassSteps = sim.grassSteps + 1
      if sim.grassSteps % sim.encounterEvery == 0 then startBattle(true, wild()) end
    end
  end
  local function interact()
    if sim.static then
      -- a Pokémon that stands still (or is handed over): what it is comes from the luck at that moment
      say({ "..." }, function()
        local v = sim.rng.value
        local made = mon(150, 50, 60, { personality = v, shiny = v % 7 == 0, defense = 50, spDef = 50 })
        sim.statics[#sim.statics + 1] = v
        if sim.static == "gift" and #session.party >= 6 then
          -- a full team: the game sends it to the PC and notes where
          local box = session.storage.boxes[1].mons
          local slot = 1
          while box[slot] do slot = slot + 1 end
          box[slot] = made
          session.monBoxId, session.monBoxPos = 0, slot - 1
          Choice.open = true; Choice.done = function() sim.log[#sim.log + 1] = "nicknamed" end
        elseif sim.static == "gift" then
          session.party[#session.party + 1] = made
          Choice.open = true; Choice.done = function() sim.log[#sim.log + 1] = "nicknamed" end
        else startBattle(true, made) end
      end)
      return
    end
    local d = D[P.facing]
    local fx, fy = P.cellX + d[1], P.cellY + d[2]
    if cell(fx, fy) == "C" and cell(fx, fy - 1) == "N" then
      say({ "heal?" }, function()
        Choice.open = true
        Choice.done = function()
          for _, m in ipairs(session.party) do m.hp = m.maxHp; for i = 1, #m.pp do m.pp[i] = m.maxPp[i] end end
          sim.log[#sim.log + 1] = "healed"
          say({ "see you" })
        end
      end)
    elseif Map.current == "MAP_ROUTE1" and fx == trainer.x and fy == trainer.y and (session.vsSeeker.rematches[7] or 0) ~= 0 then
      session.vsSeeker.rematches[7] = nil
      say({ "rematch!" }, function() startBattle(false, mon(19, 12, 30)); sim.log[#sim.log + 1] = "rematch" end)
    end
  end
  local function fieldStep()
    if Choice.open then if input.edges.a then Choice.open = false; local f = Choice.done; Choice.done = nil; if f then f() end end return end
    if Message.open then
      if input.edges.a then Message.open = false; local f = Message.done; Message.done = nil; if f then f() end end
      return
    end
    if Field._fishing then
      Field._fishing.timer = Field._fishing.timer + 1
      if Field._fishing.timer > 20 then Field._fishing = nil; say({ "bite!" }, function() startBattle(true, mon(129, 5, 20, { gender = sim.fishGender })); sim.log[#sim.log + 1] = "fished" end) end
      return
    end
    if P.moving then
      P.progress = P.progress + 1
      if P.progress >= 4 then P.moving = false; P.cellX, P.cellY = P.targetX, P.targetY; arrive() end
      return
    end
    local dir = heldDir()
    if not dir then for name in pairs(D) do if input.edges[name] then dir = name end end end
    if dir then
      local turned = P.facing ~= dir
      P.facing = dir
      local d = D[dir]
      local tx, ty = P.cellX + d[1], P.cellY + d[2]
      local exit = WARPS[Map.current .. ":" .. P.cellX .. ":" .. P.cellY .. ":" .. dir]
      local cross = (Map.current == "MAP_ROUTE1" and P.cellX == 13 and P.cellY == 3 and dir == "right" and { "MAP_ROUTE2", 0, 3 })
        or (Map.current == "MAP_ROUTE2" and P.cellX == 0 and P.cellY == 3 and dir == "left" and { "MAP_ROUTE1", 13, 3 })
      if cross and sim.gate and not sim.safari and cross[1] == "MAP_ROUTE2" then
        -- the attendant: pay to go in
        Choice.open = true
        Choice.done = function() sim.safari, sim.safariBalls = true, 30; sim.log[#sim.log + 1] = "paid"
          Map.current, P.cellX, P.cellY = "MAP_ROUTE2", 0, 3; session.map = Map.current end
      elseif cross then Map.current, P.cellX, P.cellY = cross[1], cross[2], cross[3]; session.map = Map.current
      elseif exit then Map.current, P.cellX, P.cellY = exit[1], exit[2], exit[3]; session.map = Map.current
      elseif sim.strength and sim.objects[Map.current .. ":" .. tx .. ":" .. ty] and sim.objects[Map.current .. ":" .. tx .. ":" .. ty].graphicsId == 97
          and Collision.canEnter(game, tx + d[1], ty + d[2], {}) then
        -- the boulder slides one cell; the player stays for this step
        sim.objects[Map.current .. ":" .. (tx + d[1]) .. ":" .. (ty + d[2])] = sim.objects[Map.current .. ":" .. tx .. ":" .. ty]
        sim.objects[Map.current .. ":" .. tx .. ":" .. ty] = nil
        sim.log[#sim.log + 1] = "push"
      elseif Collision.canEnter(game, tx, ty, { surfing = P.surfing }) and not (turned and not heldDir()) then
        P.moving, P.progress, P.targetX, P.targetY, P.moveDir = true, 0, tx, ty, dir
      end
    elseif input.edges.a then interact() end
  end

  local Conn = { each = function(def) return def.connections or {} end, sizeOf = function(def) return def.w, def.h end,
    incoming = function(def, dir) for _, c in ipairs(def.connections or {}) do if c.dir == dir then return c end end end }
  local Space = { bundle = { events = { MAP_POKEMON_CENTER_1F = { objects = { { x = 3, y = 1, scriptKey = "Center_EventScript_Nurse" } } } } } }
  local FieldMoves = { GFX_IDS = { CUT_TREE = 95, ROCK_SMASH_ROCK = 96, PUSHABLE_BOULDER = 97 }, partyMoveUser = function(party, move)
    if move == "SWEET_SCENT" then for _, m in ipairs(party) do for i, id in ipairs(m.moves) do if id == 230 then return m end end end return nil end
    if move == "ROCK_SMASH" then return sim.hasSmash and party[1] or nil end
    if move == "STRENGTH" then return sim.hasStrength and party[1] or nil end
    return sim.hasSurf and move == "SURF" and party[1] or nil end }
  local World = { new = function() return { useFieldAction = function(_, id)
    local d = D[P.facing]
    local facingKey = Map.current .. ":" .. (P.cellX + d[1]) .. ":" .. (P.cellY + d[2])
    local facing = sim.objects[facingKey]
    if id == "rock_smash" and facing and facing.graphicsId == 96 then sim.objects[facingKey] = nil; sim.log[#sim.log + 1] = "smash"; return true end
    if id == "strength" and facing and facing.graphicsId == 97 then sim.strength = true; sim.log[#sim.log + 1] = "strength"; return true end
    if id == "sweet_scent" then
      for _, m in ipairs(session.party) do for i, mv in ipairs(m.moves) do
        if mv == 230 and m.pp[i] > 0 and cell(P.cellX, P.cellY) == "g" then
          m.pp[i] = m.pp[i] - 1; sim.log[#sim.log + 1] = "scent"; startBattle(true, mon(19, 5, 20)); return true
        end
      end end
      return false
    end
    if id == "surf" and cell(P.cellX + d[1], P.cellY + d[2]) == "~" then
      P.cellX, P.cellY, P.surfing = P.cellX + d[1], P.cellY + d[2], true
      sim.log[#sim.log + 1] = "surf"
      return true
    end
  end } end }
  Objects.at = function(x, y) return sim.objects[Map.current .. ":" .. x .. ":" .. y] end
  local Safari = { isActive = function() return sim.safari == true end, balls = function() return sim.safariBalls or 0 end, steps = function() return 500 end }
  local Storage = {}
  local preload = { ["src.core.game3.storage"] = Storage, ["src.core.game3.safari"] = Safari, ["src.core.game3.field_moves"] = FieldMoves, ["src.world.game3.WorldAPI"] = World, ["src.core.game3.connections"] = Conn, ["src.core.game3.scripting.space"] = Space, ["src.core.game3.field"] = Field, ["src.core.game3.player"] = P, ["src.core.game3.map"] = Map, ["src.core.game3.collision"] = Collision,
    ["src.core.game3.objects"] = Objects, ["src.core.game3.battle"] = Battle, ["src.core.game3.pokemon"] = Pokemon, ["src.core.game3.battle.moves"] = Moves,
    ["src.core.game3.battle.types"] = Types, ["src.ui.game3.message"] = Message, ["src.ui.game3.choice"] = Choice, ["src.ui.game3.party_menu"] = PartyMenu,
    ["src.ui.game3.evolution_scene"] = Evolution, ["src.core.game3.item_use"] = ItemUse, ["src.core.game3.bag"] = Bag, ["src.core.game3.vs_seeker"] = VsSeeker,
    ["src.mods.Gen3Compat"] = Compat, ["src.battle.game3.BattleAPI"] = BattleAPI }
  for name, value in pairs(preload) do package.preload[name] = function() return value end end

  -- the mod ------------------------------------------------------------------
  local hooks, events, cache, logs, seq = {}, {}, {}, {}, 0
  local function newMod(store)
    local m = { generation = 3, exports = {} }
    m.read = function(_, n) return read(n) end
    -- TEST_LANG picks the panel's language (en by default)
    m.options = { define = function() end, get = function(_, k) if k == "language" then return os.getenv("TEST_LANG") or "en" end end }
    m.hooks = { wrap = function(_, n, f) hooks[n] = f end }
    m.events = { on = function(_, n, f) events[n] = f end }
    m.log = { warn = function(_, f, ...) logs[#logs + 1] = f:format(...); print("WARN", logs[#logs]) end, info = function() end }
    m.cache = { read = function(_, k) return store[k] end, write = function(_, k, v) store[k] = v; return true end }
    m.input = { tap = function(_, g, btn) seq = seq + 1; g.input:sourcePress(btn, "m" .. seq); g.input:sourceRelease(btn, "m" .. seq) end,
      press = function(_, g, btn) seq = seq + 1; g.input:sourcePress(btn, "m" .. seq); return { src = "m" .. seq, btn = btn } end,
      release = function(_, token) input:sourceRelease(token.btn, token.src); return true end }
    m.find = function() return nil end
    assert(loadstring(read("main.lua"), "@trainer_pilot/main.lua"))()(m)
    return m
  end
  -- saving, loading and luck, for reset hunting
  sim.rng, sim.statics, sim.saves, sim.reloads = { value = 1 }, {}, 0, 0
  package.preload["src.core.game3.rng"] = function() return {
    getState = function() return { value = sim.rng.value } end,
    setState = function(st) sim.rng.value = st.value return true end } end
  game.phase = "field"
  function game:quickSaveAllowed() return not battle.active end
  function game:saveGame()
    if hooks["save.write"] and hooks["save.write"](function() return true end, game) == false then return false end
    sim.saves = sim.saves + 1
    sim.saved = { party = #session.party, bag = {} }
    if session.storage then
      sim.saved.boxed = {}
      for slot, m in pairs(session.storage.boxes[1].mons) do sim.saved.boxed[slot] = m end
    end
    for id, n in pairs(session.bag) do sim.saved.bag[id] = n end
    return true
  end
  function game:_tearDownField() endBattle(); Message.open, Message.done, Choice.open, Choice.done = false, nil, false, nil end
  function game:_handleBootAction()
    sim.reloads = sim.reloads + 1
    while #session.party > sim.saved.party do table.remove(session.party) end
    if session.storage and sim.saved.boxed then
      local fresh = {}
      for slot, m in pairs(sim.saved.boxed) do fresh[slot] = m end
      session.storage.boxes[1].mons = fresh
    end
    session.bag = {}
    for id, n in pairs(sim.saved.bag) do session.bag[id] = n end
    sim.rng.value = (sim.rng.value + love.math.random(1, 60000)) % 65537
  end
  local m = newMod(cache)
  local Bot = m.exports.bot
  events["game.ready"]({ game = game })
  -- the game's clock follows its steps here, as it does at normal speed
  local simClock = 0
  love.timer.getTime = function() return simClock end
  local function step(n)
    for _ = 1, n or 1 do
      simClock = simClock + 1 / 60
      sim.rng.value = (sim.rng.value * 75 + 74) % 65537
      hooks["core.update"](function() end, game, 1 / 60)
      hooks["input.step"](function() end, game, 1 / 60)
      if battle.active then battleStep() else fieldStep() end
      input.edges = {}
    end
  end
  local function runUntil(limit, fn) for i = 1, limit do step(1); if fn() then return i end end return nil end
  -- the player walks by hand: tiles along a direction list
  local function walk(path)
    for dir in path:gmatch("%a") do
      local name = ({ u = "up", d = "down", l = "left", r = "right" })[dir]
      input.held.user = name
      local x, y, map = P.cellX, P.cellY, Map.current
      for _ = 1, 30 do step(1); if not P.moving and (P.cellX ~= x or P.cellY ~= y or Map.current ~= map) then break end end
      input.held.user = nil
      step(1)
    end
  end
  sim.encounterEvery = 1e9

  -- recording ------------------------------------------------------------------
  check(Bot.start() == false and Bot.reason == "no_route", "without a route the bot does not start")
  walk("rrr")                                   -- to (5,2), the grass edge
  check(Bot.startRecording("grass"), "recording starts")
  walk("rrrr")
  local grass = Bot.stopRecording(true)
  check(grass and #grass.points == 5 and grass.kind == "grass" and Bot.config.train == grass.name, "a grass route of 5 cells is saved and selected: " .. grass.name)
  -- heal route: from the grass edge down to the door, into the center, up to the nurse
  walk("llll")
  check(P.cellX == 5 and P.cellY == 2, "back at the start")
  check(Bot.startRecording("heal"), "recording the way to the nurse")
  walk("uru")                                   -- (5,1) → (6,1) → door (6,0) → center (3,4)
  check(Map.current == "MAP_POKEMON_CENTER_1F", "the door leads into the center")
  walk("uu")                                    -- (3,3), across the counter from the nurse
  input.held.user = "up"; step(2); input.held.user = nil; step(1)
  local heal = Bot.stopRecording(true)
  check(heal and heal.kind == "heal" and Bot.config.heal == heal.name and heal.points[#heal.points].map == "MAP_POKEMON_CENTER_1F", "heal route saved across two maps: " .. #heal.points .. " points")
  -- walk back out by hand
  walk("ddd")
  check(Map.current == "MAP_ROUTE1", "walked out of the center")
  -- persistence
  local m2store = { ["routes/v1"] = cache["routes/v1"], ["config/v1"] = cache["config/v1"] }
  check(cache["routes/v1"]:find("MAP_POKEMON_CENTER_1F", 1, true) and cache["config/v1"]:find("train=" .. grass.name, 1, true), "routes and settings are written")

  -- grass training with a heal trip and a level stop ---------------------------
  sim.encounterEvery = 2
  Bot.config.stopLevel, Bot.config.hpPct, Bot.config.selected = 16, 50, { [1] = true }
  check(Bot.start() == true and Bot.running, "the bot starts from anywhere on the route's map")
  local took = runUntil(60000, function() return not Bot.running end)
  check(took and Bot.reason == "level_healed" and Map.current == "MAP_POKEMON_CENTER_1F" and session.party[1].hp == session.party[1].maxHp,
    "it trains until the target level, then ends healed inside the Center: '" .. tostring(Bot.reason) .. "' after " .. tostring(took) .. " steps")
  walk("dd"); walk("d")
  check(session.party[1].level >= 16 and Bot.stats.battles >= 6, "lead reached level " .. session.party[1].level .. " in " .. Bot.stats.battles .. " battles")
  check(Bot.stats.heals >= 2 and Map.current == "MAP_ROUTE1", "it went to the nurse " .. Bot.stats.heals .. " time(s), the last one to finish")
  local sawMove2 = false
  for _, entry in ipairs(sim.log) do if entry == "move2" then sawMove2 = true end end
  check(not sawMove2, "it never picks the move that does no damage")
  check(next(input.held) == nil, "no button is left held after stopping")

  -- stops ------------------------------------------------------------------------
  Bot.config.stopLevel = 0
  for _, mm in ipairs(session.party) do mm.hp = mm.maxHp; mm.pp = { 35, 40 } end
  sim.nextWild = mon(19, 5, 20, { shiny = true })
  Bot.start(); runUntil(5000, function() return not Bot.running end)
  check(Bot.reason == "shiny" and battle.active and battle.st.enemy.mon.hp == 20, "a shiny stops the bot before it does anything")
  endBattle()
  Bot.config.species[16] = true
  sim.nextWild = mon(16, 5, 20)
  Bot.start(); runUntil(5000, function() return not Bot.running end)
  check(Bot.reason == "species" and battle.active, "a listed species stops the bot")
  endBattle(); Bot.config.species = {}
  -- the player takes over
  Bot.start(); step(30)
  hooks["input.gamepad"](function() end, game, { phase = "pressed", button = "a" })
  check(not Bot.running and Bot.reason == "player", "any button from the player pauses the bot")
  -- no heal route: stop instead
  Bot.config.healOn = false
  session.party[1].hp = 5
  Bot.start(); runUntil(2000, function() return not Bot.running end)
  check(Bot.reason == "needs_heal", "with healing off it stops when the lead is too weak")
  Bot.config.healOn = true
  -- whole team: the next one takes over, and a faint in battle sends the next
  for _, mm in ipairs(session.party) do mm.hp = mm.maxHp; mm.pp = { 35, 40 } end
  Bot.config.selected, Bot.config.hpPct, sim.foeHits = { [1] = true, [2] = true }, 0, 50
  local first = session.party[1]
  Bot.start()
  runUntil(8000, function() return battle.active and battle.st.player.mon ~= first end)
  check(battle.active and battle.st.player.mon ~= first and first.hp == 0, "whole team: when the lead faints the next one is sent out")
  sim.foeHits = 0
  runUntil(4000, function() return not battle.active end)
  step(200)
  check(Bot.running and session.party[1].hp > 0 and session.party[1] ~= first, "afterwards a healthy one leads")
  Bot.stop("test")
  for _, mm in ipairs(session.party) do mm.hp = mm.maxHp; mm.pp = { 35, 40 } end
  Bot.config.selected, Bot.config.hpPct, sim.foeHits = { [1] = true }, 30, 6

  -- fishing --------------------------------------------------------------------
  sim.encounterEvery = 1e9
  Bot.start(); step(1); Bot.stop("test")
  walk("r"); walk("d")
  -- stand at (10,4)? water is at x=11..12, y=4..5: walk to (10,4) facing right
  while P.cellX < 10 do walk("r") end
  while P.cellY < 4 do walk("d") end
  input.held.user = "right"; step(2); input.held.user = nil; step(1)
  check(P.cellX == 10 and P.cellY == 4 and P.facing == "right", "standing in front of the water")
  local spot = Bot.markFishingSpot()
  check(spot and spot.kind == "fish" and Bot.config.train == spot.name, "a fishing spot is one point")
  walk("lll")
  local before = Bot.stats.battles
  Bot.start()
  runUntil(6000, function() return Bot.stats.battles >= 3 end)
  local fished = 0
  for _, entry in ipairs(sim.log) do if entry == "fished" then fished = fished + 1 end end
  check(Bot.running and fished >= 3 and P.cellX == 10, "it walks to the spot, casts and fights, again and again (" .. fished .. " catches hooked)")
  Bot.stop("test")

  -- VS Seeker ------------------------------------------------------------------
  endBattle(); Message.open, Field._fishing, Choice.open = false, nil, false
  walk("llllluu")
  Bot.startRecording("seeker"); walk("rrrrllll"); local seek = Bot.stopRecording(true)
  check(seek and seek.kind == "seeker", "a VS Seeker route is recorded")
  session.vsSeeker.steps = 90
  Bot.start()
  runUntil(20000, function() local n = 0; for _, e in ipairs(sim.log) do if e == "rematch" then n = n + 1 end end; return n >= 2 end)
  local uses, fights = 0, 0
  for _, entry in ipairs(sim.log) do if entry == "seeker" then uses = uses + 1 elseif entry == "rematch" then fights = fights + 1 end end
  check(Bot.running and uses >= 2 and fights >= 2, "it charges, uses the VS Seeker, walks to the trainer and fights: " .. uses .. " uses, " .. fights .. " rematches")
  Bot.stop("test")
  check(#logs == 0, "no warnings from the bot")

  -- a restart keeps routes and settings -----------------------------------------
  local keptHooks, keptEvents = hooks, events
  hooks, events = {}, {}
  local again = newMod(cache).exports.bot
  check(#again.routes == 4 and again.config.train == seek.name and again.config.heal == heal.name and again.config.selected[1] == true, "a restart keeps the 4 routes and the settings")
  local old = newMod(m2store).exports.bot
  check(#old.routes == 2 and old.routes[2].kind == "heal" and m2store["nurses/v1"] and m2store["nurses/v1"]:find("MAP_POKEMON_CENTER_1F=3,3,up", 1, true), "a recorded heal path is kept, and where its nurse is noted: " .. tostring(m2store["nurses/v1"]))

  hooks, events = keptHooks, keptEvents
  -- the panel draws every tab ---------------------------------------------------
  local panel = assert(loadstring(read("panel.lua"), "@trainer_pilot/panel.lua"))()(m, Bot)
  local G = love.graphics
  local canvas = G.newCanvas(panel.W, panel.H)
  local sheet = G.newCanvas(panel.W * 6, panel.H)
  Bot.reason = "shiny"; Bot.config.species[19] = true; Bot.config.selected = { [1] = true, [2] = true }
  -- the Routes tab: nearest first, and only the nearby ones on request
  do
    local savedRoutes = Bot.routes
    local saveMap, sx, sy = Map.current, P.cellX, P.cellY
    Map.current, session.map, P.cellX, P.cellY = "MAP_ROUTE2", "MAP_ROUTE2", 2, 2
    local function r(name, map, x, y) return { name = name, kind = "grass", points = { { map = map, x = x, y = y, dir = "up" } } } end
    Bot.routes = { r("far cave", "MAP_ROUTE3", 1, 2), r("route 1", "MAP_ROUTE1", 3, 3), r("here far", "MAP_ROUTE2", 5, 6), r("here near", "MAP_ROUTE2", 2, 3) }
    local names = {}
    for _, route in ipairs(Bot.sortedRoutes(false)) do names[#names + 1] = route.name end
    check(table.concat(names, ",") == "here near,here far,route 1,far cave", "routes are listed nearest first: " .. table.concat(names, ","))
    names = {}
    for _, route in ipairs(Bot.sortedRoutes(true)) do names[#names + 1] = route.name end
    check(table.concat(names, ",") == "here near,here far,route 1", "Nearby keeps this map and the ones next to it: " .. table.concat(names, ","))
    Bot.routes = savedRoutes
    Map.current, session.map, P.cellX, P.cellY = saveMap, saveMap, sx, sy
  end
  -- what the Control tab shows while hunting: finds per target
  local savedTargets, savedMode = Bot.config.targets, Bot.mode
  Bot.config.targets = { { species = 129, name = "Magikarp IV", gender = "any", ivTotal = 0, ivs = {}, ability = 0 },
    { species = 0, gender = "any", ivTotal = 0, ivs = {}, ability = 0, shiny = true } }
  local savedSeen = Bot.stats.seen
  Bot.mode, Bot.stats.hits, Bot.stats.seen = "hunt", { [1] = 3, shiny = 1 }, { [129] = 12, [19] = 30, [16] = 5 }
  panel.draw(); panel.pointer("down", 60, 20)
  G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
  check(panel.lastError == nil, "the Control tab draws the finds per target: " .. tostring(panel.lastError))
  local ft = io.open(OUT .. "/bot-targets.png", "wb"); ft:write(canvas:newImageData():encode("png"):getString()); ft:close()
  Bot.config.targets, Bot.mode, Bot.stats.hits, Bot.stats.seen = savedTargets, savedMode, {}, savedSeen
  for index, x in ipairs({ 60, 150, 240, 330, 420 }) do
    panel.draw(); panel.pointer("down", x, 20)
    G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
    check(panel.lastError == nil, "panel tab " .. index .. " draws: " .. tostring(panel.lastError))
    G.setCanvas(sheet); G.setColor(1, 1, 1, 1); G.draw(canvas, (index - 1) * panel.W, 0); G.setCanvas()
  end
  local f = io.open(OUT .. "/bot-panel.png", "wb"); f:write(sheet:newImageData():encode("png"):getString()); f:close()
  -- the hunt tab's editor: new target, pick a species, set the gender, save
  panel.draw(); panel.pointer("down", 420, 20); panel.draw(); panel.pointer("down", 100, 368); panel.draw()
  panel.pointer("down", 60, 130); panel.draw(); panel.pointer("down", 200, 204); panel.draw()   -- a species, female
  G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
  check(panel.lastError == nil, "the target editor draws: " .. tostring(panel.lastError))
  G.setCanvas(sheet); G.setColor(1, 1, 1, 1); G.draw(canvas, 5 * panel.W, 0); G.setCanvas()
  local f2 = io.open(OUT .. "/bot-panel.png", "wb"); f2:write(sheet:newImageData():encode("png"):getString()); f2:close()
  local f1 = io.open(OUT .. "/bot-editor1.png", "wb"); f1:write(canvas:newImageData():encode("png"):getString()); f1:close()
  panel.pointer("down", 240, 365); panel.draw()                 -- only shiny
  panel.pointer("down", 420, 70); panel.draw()                  -- more filters
  panel.pointer("down", 50, 128); panel.draw(); panel.pointer("down", 145, 128); panel.draw()   -- Hardy, Lonely
  panel.pointer("down", 455, 265); panel.draw()                 -- level max + 1
  G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
  check(panel.lastError == nil, "the second editor page draws: " .. tostring(panel.lastError))
  local f3 = io.open(OUT .. "/bot-editor2.png", "wb"); f3:write(canvas:newImageData():encode("png"):getString()); f3:close()
  panel.pointer("down", 100, 398); panel.draw()                 -- save, from the second page
  local made = Bot.config.targets[1]
  check(made and made.natures[0] and made.natures[1] and made.shiny == true and made.levelMax == 1, "natures, shiny and level are set in the editor: " .. Bot.encodeTargets())
  check(#Bot.config.targets == 1 and Bot.config.targets[1].species ~= 0 and Bot.config.targets[1].gender == "F", "a target made in the editor is saved: " .. Bot.encodeTargets())
  Bot.config.targets = {}
  do
    local two = G.newCanvas(panel.W * 2, panel.H)
    panel.draw(); panel.pointer("down", 420, 20); panel.draw(); panel.pointer("down", 150, 400); panel.draw()   -- capture settings
    G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
    check(panel.lastError == nil, "the capture screen draws: " .. tostring(panel.lastError))
    G.setCanvas(two); G.setColor(1, 1, 1, 1); G.draw(canvas, 0, 0); G.setCanvas()
    panel.pointer("down", 100, 405); panel.draw(); panel.pointer("down", 390, 400); panel.draw()                -- back, then reset hunting
    G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
    check(panel.lastError == nil, "the reset screen draws: " .. tostring(panel.lastError))
    G.setCanvas(two); G.setColor(1, 1, 1, 1); G.draw(canvas, panel.W, 0); G.setCanvas()
    local f4 = io.open(OUT .. "/bot-hunt-screens.png", "wb"); f4:write(two:newImageData():encode("png"):getString()); f4:close()
    panel.pointer("down", 100, 388); panel.draw()                -- back
  end
  -- clicking INICIAR on the control tab starts the bot
  panel.draw(); panel.pointer("down", 60, 20); panel.draw()
  Bot.config.selected = { [1] = true }
  panel.pointer("down", 400, 64)
  check(Bot.running, "the control tab's CONTINUAR resumes the stopped run")
  panel.draw(); panel.pointer("down", 400, 80)
  check(not Bot.running, "and its stop button stops it")
  -- 0.2: a VS Seeker spot, and finding the Pokémon Center without a recorded route ---------------
  local function reset()
    Bot.stop("test"); endBattle(); Message.open, Field._fishing, Choice.open, PartyMenu.open = false, nil, false, false
    for _, mm in ipairs(session.party) do mm.hp = mm.maxHp; mm.pp = { 35, 40 } end
    sim.log = {}
    Bot.config.species = {}
  end
  local function count(what) local n = 0; for _, e in ipairs(sim.log) do if e == what then n = n + 1 end end; return n end
  local function goTo(x, y) for _ = 1, 60 do if P.cellX == x and P.cellY == y then break end; walk(P.cellX < x and "r" or P.cellX > x and "l" or P.cellY < y and "d" or "u") end end
  reset(); sim.encounterEvery = 1e9
  Bot.config.heal, Bot.config.healOn, Bot.config.hpPct, Bot.config.selected, Bot.config.stopLevel = nil, true, 60, { [1] = true }, 0
  goTo(9, 4)
  local spotRoute = Bot.markSpot("seeker")
  check(spotRoute and #spotRoute.points == 1 and Bot.config.train == spotRoute.name, "a VS Seeker spot is one marked cell")
  session.vsSeeker.steps, session.vsSeeker.rematches = 60, {}
  goTo(3, 4)
  sim.foeHits = 10
  check(Bot.start(), "starts away from the spot")
  local usedAt = {}
  runUntil(40000, function()
    if count("seeker") > #usedAt then usedAt[#usedAt + 1] = P.cellX .. "," .. P.cellY end
    return count("healed") >= 1 and count("rematch") >= 3
  end)
  check(Bot.running and count("seeker") >= 3 and count("rematch") >= 3, "spot mode: charges by pacing, uses the item, fights who answered (" .. count("seeker") .. " uses, " .. count("rematch") .. " rematches)")
  local onSpot = true
  for _, where in ipairs(usedAt) do if where ~= "9,4" then onSpot = false end end
  check(onSpot, "the VS Seeker is only ever used on the marked cell: " .. table.concat(usedAt, " "))
  check(count("healed") >= 1 and Bot.stats.heals >= 1, "with no heal route it finds the Center door, heals and comes back (" .. Bot.stats.heals .. " trips)")
  -- across a map connection: fish on the next map, heal back on this one
  reset(); sim.foeHits = 12
  step(10); Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE1", "MAP_ROUTE1", 12, 3, false
  walk("rr"); check(Map.current == "MAP_ROUTE2", "walked across the map connection")
  goTo(3, 3); input.held.user = "up"; step(2); input.held.user = nil; step(1)
  local far = Bot.markSpot("fish")
  check(far and far.points[1].map == "MAP_ROUTE2", "a fishing spot on the neighbouring map")
  goTo(0, 3); walk("l"); goTo(10, 3); goTo(10, 4); goTo(3, 4)
  check(Map.current == "MAP_ROUTE1" and Bot.start(), "starts on a different map from the spot")
  runUntil(60000, function() return count("healed") >= 1 and count("fished") >= 4 and Map.current == "MAP_ROUTE2" end)
  check(Bot.running and count("fished") >= 4 and count("healed") >= 1 and Map.current == "MAP_ROUTE2", "it crosses to the spot, fishes, crosses back to heal and returns (" .. count("fished") .. " hooked, " .. count("healed") .. " heals)")
  -- a route recorded across a connection holds a point just outside the map; following it both ways must still work
  do
    reset(); Bot.stop("x")
    local pts = {}
    local function add(map, x, y, dir) pts[#pts + 1] = { map = map, x = x, y = y, dir = dir } end
    add("MAP_ROUTE2", 2, 3, "left"); add("MAP_ROUTE2", 1, 3, "left"); add("MAP_ROUTE2", 0, 3, "left")
    add("MAP_ROUTE1", 14, 3, "left"); add("MAP_ROUTE1", 13, 3, "left"); add("MAP_ROUTE1", 12, 3, "left")
    for x = 11, 6, -1 do add("MAP_ROUTE1", x, 3, "left") end
    add("MAP_ROUTE1", 6, 2, "up"); add("MAP_ROUTE1", 6, 1, "up")
    add("MAP_POKEMON_CENTER_1F", 3, 5, "up"); add("MAP_POKEMON_CENTER_1F", 3, 4, "up"); add("MAP_POKEMON_CENTER_1F", 3, 3, "up")
    local oneWay = {}
    for index, p in ipairs(pts) do oneWay[index] = p end
    -- and the way back, a different one, recorded in the same go: the path does not end at the nurse
    add("MAP_POKEMON_CENTER_1F", 3, 4, "down"); add("MAP_POKEMON_CENTER_1F", 3, 5, "down")
    add("MAP_ROUTE1", 6, 1, "down"); add("MAP_ROUTE1", 6, 2, "down"); add("MAP_ROUTE1", 6, 3, "down"); add("MAP_ROUTE1", 6, 4, "down")
    for x = 7, 10 do add("MAP_ROUTE1", x, 4, "right") end
    add("MAP_ROUTE1", 10, 3, "up"); add("MAP_ROUTE1", 11, 3, "right"); add("MAP_ROUTE1", 12, 3, "right"); add("MAP_ROUTE1", 13, 3, "right")
    add("MAP_ROUTE2", 0, 3, "right"); add("MAP_ROUTE2", 1, 3, "right"); add("MAP_ROUTE2", 2, 3, "right")
    Bot.routes[#Bot.routes + 1] = { name = "Cura ida e volta", kind = "heal", points = pts }
    Bot.config.heal, Bot.config.train, Bot.config.hpPct, Bot.config.travelRun = "Cura ida e volta", far.name, 60, true
    Map.current, session.map, P.cellX, P.cellY, P.moving, P.surfing = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false, false
    session.party[1].hp = 5
    local visited = {}
    Bot.start()
    runUntil(30000, function() visited[Map.current .. ":" .. P.cellX .. ":" .. P.cellY] = true; return count("healed") >= 1 and Map.current == "MAP_ROUTE2" and count("fished") >= 1 end)
    check(Bot.running and count("healed") == 1 and visited["MAP_ROUTE1:8:4"] and Map.current == "MAP_ROUTE2", "a heal path recorded there and back is followed forward all the way: the return goes by its own cells (" .. tostring(Bot.reason) .. ")")
    reset(); Bot.stop("x"); Bot.deleteRoute("Cura ida e volta")
    Bot.routes[#Bot.routes + 1] = { name = "Cura real", kind = "heal", points = oneWay }
    Bot.config.heal, Bot.config.train, Bot.config.hpPct, Bot.config.travelRun = "Cura real", far.name, 60, true
    Map.current, session.map, P.cellX, P.cellY, P.moving, P.surfing = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false, false
    session.party[1].hp = 5
    Bot.start()
    runUntil(30000, function() return count("healed") >= 1 and Map.current == "MAP_ROUTE2" and count("fished") >= 1 end)
    check(Bot.running and count("healed") == 1 and Map.current == "MAP_ROUTE2", "a recorded heal route with a point outside the map is followed there and back: " .. tostring(Bot.reason))
    Bot.stop("x"); Bot.deleteRoute("Cura real"); Bot.config.train, Bot.config.hpPct = far.name, 0
  end
  -- water in the way: Surf across when the team can
  reset(); sim.foeHits = 0
  Map.current, session.map, P.cellX, P.cellY, P.facing, P.moving, P.surfing = "MAP_ROUTE1", "MAP_ROUTE1", 12, 5, "up", false, false
  local island = Bot.markSpot("fish")
  P.cellX, P.cellY = 3, 4
  sim.hasSurf = false
  Bot.start(); runUntil(3000, function() return not Bot.running end)
  check(Bot.reason == "blocked" and count("surf") == 0, "without Surf, a spot across the water is out of reach")
  local blockedLog = cache["log/blocked"] or ""
  check(blockedLog:find("|stop|", 1, true) and blockedLog:find("no way to", 1, true) and not blockedLog:find("retry", 1, true),
    "with no way at all it stops at once, and writes down why: " .. blockedLog:sub(1, 200))
  sim.hasSurf = true
  Bot.start(); runUntil(8000, function() return count("fished") >= 2 end)
  check(Bot.running and count("surf") >= 1 and count("fished") >= 2 and P.cellX == 12 and P.cellY == 5 and not P.surfing, "with Surf it crosses the water and carries on (" .. count("surf") .. " surf, " .. count("fished") .. " hooked)")
  Bot.deleteRoute(island.name); Bot.config.train = far.name
  -- the trainer's "will you switch?" question
  local function trainerBattle()
    reset(); Bot.stop("x")
    Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false
    session.party[2].moves, session.party[2].pp, session.party[2].maxPp = { 99 }, { 10 }, { 10 }
    Bot.start()
    startBattle(false, mon(19, 5, 20)); battle.st.foeParty = { battle.st.enemy.mon, mon(16, 5, 20) }
    runUntil(3000, function() return not battle.active end)
  end
  Bot.config.selected, Bot.config.hpPct, sim.foeHits = { [1] = true }, 0, 0
  local leader = session.party[1]
  trainerBattle()
  check(count("shift_no") == 1 and count("shift_yes") == 0 and Bot.running, "leader only: it answers no to the switch question and fights on")
  Bot.config.selected = { [1] = true, [2] = true }
  trainerBattle()
  check(count("shift_yes") == 1 and Bot.running, "whole team: it says yes when another one hits the next foe harder")
  local sent = false
  for _, e in ipairs(sim.log) do if e == "move1" then sent = true end end
  check(sent and session.party[2].pp[1] < 10, "and sends that one out to fight")
  -- out of PP against a trainer: bring in another one
  reset(); Bot.stop("x")
  Bot.config.selected, Bot.config.stopNoPP = { [1] = true, [2] = true }, false
  session.party[1].pp = { 0, 5 }
  Bot.start(); startBattle(false, mon(19, 5, 20))
  runUntil(3000, function() return not battle.active end)
  check(count("party") == 1 and not battle.active and Bot.running, "no PP left: it opens the party and another one finishes the battle")
  reset(); Bot.stop("x"); Bot.config.stopNoPP = true
  session.party[1].pp = { 0, 5 }
  Bot.start(); startBattle(false, mon(19, 5, 20)); runUntil(3000, function() return not Bot.running end)
  check(Bot.reason == "no_pp", "or stops, when that is the setting")
  endBattle(); Bot.config.stopNoPP = false
  -- wild Pokémon met on the way are run from, when that is the setting
  reset(); Bot.stop("x"); Bot.config.selected, Bot.config.travelRun = { [1] = true }, true
  Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE1", "MAP_ROUTE1", 3, 4, false
  Bot.start(); step(5); startBattle(true, mon(19, 5, 20)); runUntil(2000, function() return not battle.active end)
  check(count("run") == 1 and Bot.running, "on the way to the route it runs from a wild Pokémon")
  Bot.config.travelRun = false
  startBattle(true, mon(19, 5, 20)); runUntil(2000, function() return not battle.active end)
  check(count("run") == 1 and count("move1") >= 1, "or fights it, when set to fight")
  -- out of PP with only the leader marked: anyone else finishes the battle
  reset(); Bot.stop("x"); Bot.config.selected, Bot.config.stopNoPP = { [1] = true }, false
  session.party[1].pp = { 0, 5 }
  Bot.start(); startBattle(false, mon(19, 5, 20)); runUntil(3000, function() return not battle.active end)
  check(count("party") == 1 and not battle.active and Bot.running, "only the leader marked and no PP: another team member is sent in to finish")
  check(cache["nurses/v1"] and cache["nurses/v1"]:find("MAP_POKEMON_CENTER_1F=3,3,up", 1, true), "the place in front of the nurse was learned from an earlier heal: " .. tostring(cache["nurses/v1"]))
  -- hunting: a wild Pokémon that fits a target stops the bot; others are run from or fought
  reset(); Bot.stop("x"); Bot.config.selected = { [1] = true }
  Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false
  Bot.config.huntExp = false
  Bot.config.targets = { { species = 129, gender = "F", ivTotal = 100, ability = 0, ivs = { hp = 25, atk = 0, def = 0, spe = 31, spa = 31, spd = 0 } } }
  local function wildWith(extra) local w = mon(129, 5, 20, extra); Bot.start("hunt"); startBattle(true, w); runUntil(2000, function() return not battle.active or not Bot.running end) end
  wildWith({ gender = "F", ivs = { hp = 25, atk = 5, def = 5, spe = 31, spa = 31, spd = 3 } })
  check(Bot.reason == "hunt_found" and battle.active and count("run") == 0, "a wild one that fits every condition stops the bot with the battle open")
  check(Bot.stats.hits and Bot.stats.hits[1] == 1, "the find is counted for the target it matched")
  endBattle()
  wildWith({ gender = "M", ivs = { hp = 25, atk = 5, def = 5, spe = 31, spa = 31, spd = 3 } })
  check(Bot.running and count("run") == 1, "wrong gender: not a target, and it runs")
  wildWith({ gender = "F", ivs = { hp = 24, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 } })
  check(Bot.running and count("run") == 2, "one stat below its minimum: not a target")
  wildWith({ gender = "F", ivs = { hp = 25, atk = 0, def = 0, spe = 31, spa = 31, spd = 0 } })
  check(Bot.running and count("run") == 3, "IV total below the minimum (87 < 100): not a target")
  Bot.config.huntExp = true
  wildWith({ gender = "M", ivs = { hp = 1, atk = 1, def = 1, spe = 1, spa = 1, spd = 1 } })
  check(Bot.running and count("run") == 3 and count("move1") >= 1, "with EXP on, the ones that do not fit are fought")
  local saved = Bot.encodeTargets(); Bot.save()
  check(cache["config/v1"]:find("targets=129,F,100,25,0,0,31,31,0,0,-1,0", 1, true), "targets are saved: " .. saved)
  Bot.config.huntExp = false
  Bot.config.targets = { { species = 129, gender = "any", ivTotal = 0, ability = 0, natures = { [3] = true, [7] = true }, shiny = true, ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } } }
  Bot.config.stopShiny, Bot.config.huntShiny = false, false
  wildWith({ personality = 28, shiny = true })
  check(Bot.reason == "hunt_found", "nature (28 % 25 = 3, Adamant) and shiny both fit: found")
  endBattle()
  wildWith({ personality = 28, shiny = false })
  check(Bot.running, "right nature but not shiny: not a target")
  wildWith({ personality = 29, shiny = true })
  check(Bot.running, "shiny but another nature: not a target")
  Bot.config.stopShiny, Bot.config.huntShiny = true, true
  -- level range, held item and Hidden Power
  local function target(extra) local t = { species = 129, gender = "any", ivTotal = 0, ability = 0, ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } }; for k, v in pairs(extra) do t[k] = v end; return t end
  local probe = mon(129, 5, 20, { heldItem = 0, ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 } })
  local hpType, hpPower = Bot.hiddenPower(probe)
  check(hpType == 15 and hpPower == 70, "Hidden Power of all-31 IVs is Dark 70: " .. hpType .. " " .. hpPower)
  check(Bot.matches(probe, target({ levelMin = 5, levelMax = 5 })) and not Bot.matches(probe, target({ levelMin = 6 })) and not Bot.matches(probe, target({ levelMax = 4 })), "the level range is respected")
  check(not Bot.matches(probe, target({ item = true })), "'holding an item' rejects one that holds nothing")
  probe.heldItem = 5; check(Bot.matches(probe, target({ item = true })), "and accepts one that holds something")
  check(Bot.matches(probe, target({ hpType = 15, hpPower = 70 })) and not Bot.matches(probe, target({ hpType = 8 })), "Hidden Power type and power are respected")
  -- a hunt stops for any shiny when asked to, target or not
  Bot.config.targets = { target({ species = 4 }) }
  Bot.config.huntShiny = true; wildWith({ shiny = true }); check(Bot.reason == "shiny" and battle.active, "a hunt stops for a shiny that is not a target")
  endBattle(); Bot.config.huntShiny = false; wildWith({ shiny = true }); check(Bot.running, "unless that is turned off")
  check((Bot.stats.seen[129] or 0) >= 1, "encounters are counted by species: " .. tostring(Bot.stats.seen[129]))
  Bot.config.huntShiny = true
  -- Sweet Scent: stands in the grass, calls encounters, and goes to the Center when the PP runs out
  reset(); Bot.stop("x")
  Map.current, session.map, P.cellX, P.cellY, P.moving, P.surfing = "MAP_ROUTE1", "MAP_ROUTE1", 3, 4, false, false
  session.party[2].moves, session.party[2].pp, session.party[2].maxPp = { 230 }, { 3 }, { 3 }
  Bot.config.train, Bot.config.huntScent, Bot.config.huntExp, Bot.config.huntShiny = grass.name, true, false, true
  Bot.config.targets = { target({ species = 4 }) }
  sim.encounterEvery = 1e9
  Bot.start("hunt")
  runUntil(40000, function() return count("scent") >= 5 end)
  check(Bot.running and count("scent") >= 5 and count("run") >= 4 and count("healed") >= 1, "Sweet Scent calls the encounters; with its PP spent the bot heals and comes back (" .. count("scent") .. " uses, " .. count("healed") .. " heal)")
  Bot.stop("x"); Bot.config.huntScent = false
  session.party[2].moves, session.party[2].pp, session.party[2].maxPp = { 33, 45 }, { 35, 40 }, { 35, 40 }
  Bot.config.train = far.name
  -- the map of links: a spot two maps and a cave away, and the Center back on the first map
  reset(); Bot.stop("x"); sim.foeHits = 12
  Map.current, session.map, P.cellX, P.cellY, P.facing, P.moving, P.surfing = "MAP_ROUTE3", "MAP_ROUTE3", 2, 2, "right", false, false
  local deep = Bot.markSpot("fish")
  check(deep and deep.points[1].map == "MAP_ROUTE3", "a fishing spot beyond a cave")
  local hop, goal = Bot.planHop("MAP_ROUTE1", function(id) return id == "MAP_ROUTE3" end, "t1")
  check(hop and hop.kind == "conn" and hop.to == "MAP_ROUTE2" and goal == "MAP_ROUTE3", "the trip is planned map by map: first across to the next route")
  hop = Bot.planHop("MAP_ROUTE2", function(id) return id == "MAP_ROUTE3" end, "t2")
  check(hop and hop.kind == "warp" and hop.to == "MAP_CAVE", "then into the cave")
  Map.current, session.map, P.cellX, P.cellY = "MAP_ROUTE1", "MAP_ROUTE1", 3, 4
  Bot.config.hpPct = 60
  check(Bot.start("train"), "starts three maps away from the spot")
  runUntil(120000, function() return count("healed") >= 1 and count("fished") >= 4 and Map.current == "MAP_ROUTE3" end)
  check(Bot.running and count("fished") >= 4 and count("healed") >= 1 and Map.current == "MAP_ROUTE3", "it goes through the cave to the spot, and to the Center and back the same way (" .. count("fished") .. " hooked, " .. count("healed") .. " heals): " .. tostring(Bot.reason))
  Bot.stop("x"); Bot.deleteRoute(deep.name); Bot.config.train, Bot.config.hpPct = far.name, 0
  sim.foeHits = 0
  endBattle(); Message.open, Field._fishing, Choice.open = false, nil, false
  -- a cracked rock or a boulder in the only way through
  local function throughObstacle(gfx)
    reset(); Bot.stop("x"); sim.log = {}; sim.strength = false
    sim.objects = { ["MAP_ROUTE2:1:3"] = { graphicsId = gfx } }
    Map.current, session.map, P.cellX, P.cellY, P.facing, P.moving = "MAP_ROUTE2", "MAP_ROUTE2", 0, 3, "right", false
    Bot.config.train = far.name
    Bot.start("train"); runUntil(6000, function() return count("fished") >= 1 or not Bot.running end)
  end
  sim.hasSmash, sim.hasStrength = false, false
  throughObstacle(96); check(Bot.reason == "blocked" and count("smash") == 0, "a cracked rock with no Rock Smash in the team blocks the way")
  sim.hasSmash = true
  throughObstacle(96); check(Bot.running and count("smash") == 1 and count("fished") >= 1, "with Rock Smash the rock is broken and the bot goes on")
  throughObstacle(97); check(Bot.reason == "blocked" and count("push") == 0, "a boulder with no Strength blocks the way")
  sim.hasStrength = true
  throughObstacle(97); check(Bot.running and count("strength") == 1 and count("push") >= 1 and count("fished") >= 1, "with Strength it is switched on once and the boulder is pushed out of the way (" .. count("push") .. " push)")
  sim.objects = {}; Bot.stop("x")
  -- catching: weaken without risk, status, then balls in the chosen order; decline the nickname; go on
  reset(); Bot.stop("x"); sim.dmg = 13
  Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false
  Bot.config.train, Bot.config.selected = far.name, { [1] = true }
  local hunter = session.party[1]
  hunter.level, hunter.attack, hunter.spAtk = 10, 30, 30
  hunter.moves, hunter.pp, hunter.maxPp = { 33, 86 }, { 35, 20 }, { 35, 20 }
  session.bag[2], session.bag[3], session.bag[4], session.bag[1] = 0, 1, 5, 1
  Bot.config.targets = { target({ species = 129 }) }
  Bot.config.huntCatch, Bot.config.catchContinue, Bot.config.catchWeaken, Bot.config.catchStatus, Bot.config.useMaster, Bot.config.ballOrder = true, true, true, true, false, "2,3,4"
  local function hunted(extra) local w = mon(129, 5, 60, { defense = 50, spDef = 50 }); for k, v in pairs(extra or {}) do w[k] = v end; Bot.start("hunt"); startBattle(true, w); runUntil(4000, function() return not battle.active or not Bot.running end); if not battle.active then step(3) end; return w end
  local prey = hunted()
  check(Bot.running and count("caught") == 1 and count("nicknamed") == 0 and prey.hp > 0 and prey.hp <= 12 and prey.status == 1, "it weakens the target without making it faint (HP " .. prey.hp .. "/60), paralyses it, and catches it")
  check(sim.log[#sim.log - 1] == "ball3" and count("ball1") == 0 and count("move2") == 1, "the first ball in the order that is in the bag is thrown (Great, there is no Ultra); the Master Ball is left alone")
  check(Bot.stats.found == 1 and Bot.stats.caught == 1 and Bot.stats.lost == 0, "the hunt's score counts the target and the catch")
  -- a move that could make it faint is never used: straight to status and ball
  hunter.attack = 400; sim.log = {}
  prey = hunted()
  check(count("move1") == 0 and prey.hp == 60 and count("move2") == 1, "when the only attack could make it faint, the bot does not attack at all")
  -- only with False Swipe, and there is none: no weakening
  hunter.attack = 30; Bot.config.catchFalseSwipe = true; sim.log = {}
  prey = hunted(); check(count("move1") == 0 and prey.hp == 60, "with 'only False Swipe' on and no False Swipe, it does not weaken")
  endBattle(); Choice.open = false; session.bag[4] = 5
  hunter.moves[1] = 206; sim.dmg = 100; sim.log = {}
  prey = hunted(); check(prey.hp == 1 and count("caught") == 1, "with False Swipe it goes down to 1 HP and is caught")
  hunter.moves[1], Bot.config.catchFalseSwipe, sim.dmg = 33, false, 13
  -- out of balls: stop with the target on screen; Master Ball only when allowed
  session.bag[3], session.bag[4] = 0, 0; sim.log = {}
  hunted(); check(Bot.reason == "no_balls" and battle.active and count("ball1") == 0, "no ordinary ball left: it stops with the battle open and keeps the Master Ball")
  endBattle(); Bot.config.useMaster = true; sim.log = {}
  hunted(); check(count("ball1") == 1 and count("caught") == 1, "with the Master Ball allowed, it is thrown")
  Bot.config.catchContinue = false; session.bag[4] = 9; Bot.config.useMaster = false; sim.log = {}
  hunted(); check(not Bot.running and Bot.reason == "caught", "with 'go on after a catch' off, it stops once it has caught")
  -- ready to hunt: without balls it does not look for a target; with the status move spent it heals first
  endBattle(); Choice.open, Message.open, Field._fishing = false, false, nil
  session.bag[3], session.bag[4], session.bag[1] = 0, 0, 0
  Bot.start("hunt"); step(20)
  check(not Bot.running and Bot.reason == "no_balls_ready", "a catching hunt with no balls in the bag does not go looking")
  session.bag[4] = 9; hunter.pp[2] = 0; sim.log = {}
  Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE1", "MAP_ROUTE1", 3, 4, false
  Bot.start("hunt"); runUntil(20000, function() return count("healed") >= 1 end)
  check(count("healed") == 1 and hunter.pp[2] == 20, "with the paralysis move out of PP it goes to the Center before hunting")
  Bot.stop("x")
  Bot.config.huntCatch, Bot.config.catchContinue, sim.dmg = false, true, nil
  endBattle(); Choice.open = false; Bot.config.targets = { target({ species = 4 }) }
  hunter.moves, hunter.pp, hunter.maxPp, hunter.attack = { 33, 45 }, { 35, 40 }, { 35, 40 }, nil
  -- fishing hunts: the rod asked for is the one used; the hooked one is checked like any wild Pokémon
  reset(); Bot.stop("x"); sim.rods = {}
  Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false
  Bot.config.train, Bot.config.huntExp, Bot.config.huntCatch = far.name, false, false
  Bot.config.targets = { target({ species = 129, gender = "F" }) }
  session.bag[262], session.bag[264] = 1, 1
  Bot.config.rod = 262
  sim.fishGender = "M"
  Bot.start("hunt"); runUntil(8000, function() return count("run") >= 2 end)
  check(Bot.running and count("run") >= 2 and sim.rods[262] and not sim.rods[264], "a fishing hunt casts with the chosen rod and runs from what does not fit")
  sim.fishGender = "F"
  runUntil(8000, function() return not Bot.running end)
  check(Bot.reason == "hunt_found" and battle.active, "and stops when the hooked one fits the target")
  endBattle(); Bot.config.rod = 263
  Bot.start("hunt"); runUntil(2000, function() return not Bot.running end)
  check(Bot.reason == "no_rod", "a rod that is not in the bag is not replaced by another: it says so")
  Bot.config.rod, sim.fishGender = 0, nil
  -- the Safari Zone: no fighting, only ball, bait, rock and run; nothing to heal; ends when the game ends it
  reset(); Bot.stop("x"); sim.safari, sim.safariBalls, sim.safariCatchAt, sim.safariFlee = true, 30, 2, false
  Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false
  Bot.config.train, Bot.config.huntExp, Bot.config.huntCatch, Bot.config.catchContinue = far.name, true, true, true
  sim.safariCatchAt = 5
  Bot.config.targets = { target({ species = 129, gender = "F" }) }
  session.party[1].hp = 1                       -- a team in no state to fight does not matter in there
  local function safariWild(gender) Bot.start("hunt"); startBattle(true, mon(129, 5, 20, { gender = gender })); battle.st.safari = true
    runUntil(3000, function() return not battle.active or not Bot.running end); if not battle.active then step(3) end end
  safariWild("M")
  check(Bot.running and count("run") == 1 and count("sball") == 0 and count("move1") == 0, "in the Safari, one that is not a target is run from, even with 'fight for EXP' on")
  safariWild("F")
  check(Bot.running and table.concat(sim.log, " "):find("bait bait sball sball sball bait bait sball sball caught", 1, true) and count("rock") == 0 and Bot.stats.caught == 1, "a target gets 2 baits, 3 balls, 2 baits, balls... until caught, and never a rock: " .. table.concat(sim.log, " "))
  sim.safariFlee = true; sim.safariCatchAt = 9
  safariWild("F")
  check(Bot.stats.caught == 1 and Bot.stats.lost == 1 and Bot.stats.found == 2, "one that flees is a failure, not a catch")
  check(Bot.running and count("healed") == 0, "it does not leave to heal")
  sim.safari = false; runUntil(600, function() if battle.active then endBattle() end; return not Bot.running end)
  check(not Bot.running and Bot.reason == "safari_over", "when the game ends the Safari, the bot stops and says so")
  sim.safari, sim.safariFlee, session.party[1].hp = nil, nil, session.party[1].maxHp
  Bot.config.huntExp, Bot.config.huntCatch = false, false
  -- going back in when a Safari visit ends, as many times as asked
  reset(); Bot.stop("x"); sim.safari, sim.gate, sim.safariBalls, sim.safariFlee = true, true, 30, false
  Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3, false
  Bot.config.train, Bot.config.huntExp, Bot.config.huntCatch, Bot.config.safariReentries = far.name, false, false, 1
  Bot.config.targets = { target({ species = 4 }) }
  local function endVisit()
    endBattle(); Message.open, Field._fishing, Choice.open = false, nil, false
    sim.safari = false; Map.current, session.map, P.cellX, P.cellY, P.moving = "MAP_ROUTE1", "MAP_ROUTE1", 3, 4, false
  end
  Bot.start("hunt"); runUntil(3000, function() if battle.active then battle.st.safari = true end; return count("fished") >= 1 end)
  endVisit(); sim.log = {}
  runUntil(20000, function() if battle.active then battle.st.safari = true end; return count("fished") >= 1 or not Bot.running end)
  check(Bot.running and count("paid") == 1 and sim.safari and Map.current == "MAP_ROUTE2", "when the visit ends it goes back to the gate, pays and returns to its spot")
  endVisit()
  runUntil(6000, function() return not Bot.running end)
  check(Bot.reason == "safari_over" and count("paid") == 1, "after the number of re-entries asked for, it stops")
  Bot.config.safariReentries = -1; sim.safari = true; sim.log = {}
  Map.current, session.map, P.cellX, P.cellY = "MAP_ROUTE2", "MAP_ROUTE2", 3, 3
  Bot.start("hunt"); step(30)
  for visit = 1, 3 do endVisit(); runUntil(20000, function() if battle.active then battle.st.safari = true end; return count("paid") >= visit or not Bot.running end) end
  check(Bot.running and count("paid") == 3, "with no limit it keeps going back in")
  runUntil(200, function() if battle.active then battle.st.safari = true end; return false end)
  session.money = 499; endVisit(); runUntil(3000, function() return not Bot.running end)
  check(Bot.reason == "safari_money" and count("paid") == 3, "with no limit, the money is the limit: without enough for a ticket it stops at once")
  session.money = nil
  Bot.stop("x"); sim.safari, sim.gate = nil, nil; Bot.config.safariReentries = 0
  endBattle(); Message.open, Field._fishing, Choice.open = false, nil, false
  -- a marked Sweet Scent spot: no steps taken; heals when the PP is gone; in the Safari it stops instead
  reset(); Bot.stop("x")
  Map.current, session.map, P.cellX, P.cellY, P.moving, P.surfing = "MAP_ROUTE1", "MAP_ROUTE1", 6, 2, false, false
  local scentSpot = Bot.markSpot("scent")
  check(scentSpot and scentSpot.kind == "scent" and #scentSpot.points == 1 and Bot.config.train == scentSpot.name, "a Sweet Scent spot is one marked cell")
  session.party[2].moves, session.party[2].pp, session.party[2].maxPp = { 230 }, { 3 }, { 3 }
  Bot.config.heal, Bot.config.huntExp, Bot.config.targets = nil, false, { target({ species = 4 }) }
  P.cellX, P.cellY = 3, 4
  local stepsBefore = session.vsSeeker.steps
  Bot.start("hunt"); runUntil(4000, function() return count("scent") >= 3 end)
  check(count("scent") == 3 and P.cellX == 6 and P.cellY == 2, "it walks to the spot once and calls three encounters without moving from it")
  runUntil(40000, function() return count("scent") >= 5 end)
  check(Bot.running and count("healed") == 1 and count("scent") >= 5, "with the PP spent it heals and comes back to the spot")
  Bot.stop("x"); sim.safari = true; session.party[2].pp[1] = 1; sim.log = {}
  Map.current, session.map, P.cellX, P.cellY = "MAP_ROUTE1", "MAP_ROUTE1", 6, 2
  Bot.start("hunt"); runUntil(6000, function() if battle.active and battle.st then battle.st.safari = true end; return not Bot.running end)
  check(Bot.reason == "no_scent" and count("scent") == 1 and count("healed") == 0, "in the Safari, with the PP gone it stops instead of leaving to heal")
  sim.safari = nil; Bot.deleteRoute(scentSpot.name); Bot.config.train = far.name
  session.party[2].moves, session.party[2].pp, session.party[2].maxPp = { 33, 45 }, { 35, 40 }, { 35, 40 }
  -- a hunt does not use the training stops, and needs a target
  Bot.config.stopLevel = 1
  wildWith({ personality = 30 })
  check(Bot.running, "the level target of training does not stop a hunt")
  Bot.stop("x"); Bot.config.stopLevel = 0
  Bot.config.huntExp, Bot.config.targets = false, {}
  check(Bot.start("hunt") == false and Bot.reason == "no_targets", "a hunt without targets does not start")
  -- resume keeps the numbers; a fresh start clears them
  Bot.start("train"); Bot.stats.battles = 7; Bot.stop("player")
  Bot.start("train", true); check(Bot.stats.battles == 7 and Bot.mode == "train", "CONTINUAR keeps the run's numbers")
  Bot.stop("x"); Bot.start("train"); check(Bot.stats.battles == 0, "a new start clears them"); Bot.stop("x")
  Bot.stats.battles, Bot.stats.found = 4, 2
  check(Bot.finish() and Bot.mode == nil and Bot.stats.battles == 0 and Bot.stats.found == 0 and Bot.stats.startedAt == nil, "FINALIZAR closes the stopped run and clears its numbers")
  Bot.start("train"); check(Bot.finish() == false and Bot.running, "a running bot is not finished by it"); Bot.stop("x")
  -- EV training: targets per Pokémon, running from the wrong yield, done when reached
  reset(); Bot.stop("x"); Bot.finish()
  P.cellX, P.cellY, Map.current, session.map = 2, 2, "MAP_ROUTE1", "MAP_ROUTE1"
  do
    local keepTrain2, keepLevel = Bot.config.train, sim.levelPerWin
    local grassRoute
    for _, r in ipairs(Bot.routes) do if r.kind == "grass" then grassRoute = grassRoute or r.name end end
    assert(grassRoute, "the harness has a recorded grass route")
    Bot.config.train, Bot.config.selected, Bot.config.healOn, sim.levelPerWin = grassRoute, { [1] = true }, false, 0
    sim.evYield = { [19] = { spe = 1 }, [16] = { atk = 1 } }
    local keepEvery = sim.encounterEvery
    sim.encounterEvery = 3
    Pokemon.evYield = function(species) return sim.evYield[species] or {} end
    local me = session.party[1]
    me.evs, me.hp, me.pp = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, me.maxHp, { 35, 40 }
    Bot.config.evTargets[tostring(me.personality)] = { spe = 3 }
    check(Bot.evTarget(me) ~= nil and not Bot.evDone(me) and Bot.evWasted(me, 16) and not Bot.evWasted(me, 19), "EV targets: Speed wanted, an Attack yield would be wasted")
    Bot.save(); check(cache["config/v1"]:find("evTargets=" .. tostring(me.personality) .. ":0.0.0.3.0.0", 1, true), "the targets are saved with the settings")
    sim.log = {}; sim.nextWild = mon(16, 5, 20)
    Bot.start("train"); runUntil(3000, function() return count("run") >= 1 or not Bot.running end)
    check(count("run") == 1 and count("move1") == 0 and Bot.stats.evFled == 1 and me.evs.atk == 0, "it runs from the species that would give the wrong EV")
    runUntil(40000, function() return not Bot.running end)
    check(Bot.reason == "ev_done" and me.evs.spe == 3 and me.evs.atk == 0, "and stops when the target is reached, with nothing wasted: " .. tostring(Bot.reason) .. " spe=" .. me.evs.spe)
    -- on a VS Seeker route the EV rules are off
    Bot.config.evTargets, sim.evYield, Pokemon.evYield = {}, nil, nil
    Bot.config.train, Bot.config.healOn, sim.levelPerWin, sim.encounterEvery = keepTrain2, true, keepLevel, keepEvery
    me.evs = nil; endBattle(); Bot.finish()
  end
  -- the stop history: every stop is written down, newest first, and kept
  reset(); Bot.stop("x"); Bot.finish()
  Bot.clearHistory()
  Bot.start("train"); step(5); Bot.stop("stuck")
  Bot.start("train"); step(5); Bot.stop("player")
  check(#Bot.history == 2 and Bot.history[1].reason == "player" and Bot.history[2].reason == "stuck" and Bot.history[1].mode == "train",
    "each stop goes into the history, newest first")
  check(cache["log/history"] and cache["log/history"]:find("|stuck|", 1, true), "and is kept between sessions")
  Bot.history = {}; Bot.historyLoad()
  check(#Bot.history == 2 and Bot.history[2].reason == "stuck", "it comes back when the game opens again")
  Bot.stop("x"); check(#Bot.history == 2, "a stop of a bot that was not running is not written down")
  -- more than five targets, with names that cannot break the saved settings
  do
    local keepTargets = Bot.config.targets
    Bot.config.targets = {}
    for index = 1, 7 do
      Bot.config.targets[index] = { species = 129, gender = "any", ivTotal = 0, ability = 0, shiny = false, natures = {},
        name = index == 3 and "Meu, alvo; especial|x" or nil, ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = index } }
    end
    Bot.save()
    Bot.config.targets = {}
    Bot.reloadConfig()
    check(#Bot.config.targets == 7 and Bot.config.targets[7].ivs.spd == 7, "more than five targets are saved and come back: " .. #Bot.config.targets)
    check(Bot.config.targets[3].name == "Meu alvo especialx" and Bot.config.targets[2].name == nil,
      "a target keeps its name, cleaned of what would break the settings: " .. tostring(Bot.config.targets[3].name))
    Bot.config.targets = keepTargets
    Bot.save()
  end
  -- a catch with nowhere to go
  do
    local keepParty, keepCatch = session.party, Bot.config.huntCatch
    local full = {}
    for index = 1, 6 do full[index] = mon(19, 5, 20) end
    session.party, Bot.config.huntCatch = full, true
    Bot.config.targets = { { species = 129, gender = "any", ivTotal = 0, ability = 0, shiny = false, natures = {}, ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } } }
    session.storage = { boxes = { { mons = {} } } }
    Storage.findOpenSlot = function(st) for b, box in ipairs(st.boxes) do for slot = 1, 30 do if not box.mons[slot] then return b, slot end end end end
    check(Bot.roomForCatch() == true, "with a full team, a free PC slot is room enough")
    for slot = 1, 30 do session.storage.boxes[1].mons[slot] = {} end
    check(Bot.roomForCatch() == false and Bot.start("hunt") == false and Bot.reason == "pc_full", "team and PC full: a hunt that catches does not start")
    Bot.config.huntCatch = false
    check(Bot.start("hunt") == true, "a hunt that only stops still starts")
    Bot.stop("x"); Bot.finish()
    session.party, Bot.config.huntCatch, session.storage, Bot.config.targets = keepParty, keepCatch, nil, {}
  end
  -- a Repel and a grass route do not go together
  reset(); Bot.stop("x"); Bot.finish()
  P.cellX, P.cellY, Map.current, session.map = 2, 2, "MAP_ROUTE1", "MAP_ROUTE1"
  local keepTrain = Bot.config.train
  Bot.routes[#Bot.routes + 1] = { name = "repel test", kind = "grass", points = { { map = "MAP_ROUTE1", x = 5, y = 1, dir = "right" }, { map = "MAP_ROUTE1", x = 8, y = 1, dir = "right" } } }
  Bot.config.train = "repel test"
  session.repelSteps = 80
  check(Bot.start("train") == false and Bot.reason == "repel_on", "with a Repel active the bot does not start on a grass route")
  session.repelSteps = 0
  check(Bot.start("train") == true, "without it, it starts")
  step(10); session.repelSteps = 100; runUntil(200, function() return not Bot.running end)
  check(Bot.reason == "repel_on", "a Repel used during the run stops the bot: " .. tostring(Bot.reason))
  session.repelSteps = 0; endBattle()
  Bot.routes[#Bot.routes] = nil; Bot.config.train = keepTrain
  -- healing from the bag, up to the number allowed, before any walk to the Center
  reset(); Bot.stop("x"); Bot.finish(); sim.static = nil
  P.cellX, P.cellY, Map.current, session.map = 2, 2, "MAP_ROUTE1", "MAP_ROUTE1"
  Bot.config.selected, Bot.config.hpPct, Bot.config.itemHp, Bot.config.itemPp = { [1] = true }, 50, 2, 1
  session.bag[13], session.bag[22], session.bag[34] = 5, 5, 3
  local keepMax = session.party[1].maxHp; session.party[1].maxHp = 40
  session.party[1].hp = 10                       -- 40 max: 30 missing, a Super Potion's job
  P.moving = false
  Bot.start("train"); runUntil(60, function() return (Bot.stats.itemsHp or 0) >= 1 end)
  check(session.party[1].hp == 40 and session.bag[22] == 4 and session.bag[13] == 5 and Bot.stats.itemsHp == 1 and Bot.status ~= "to_heal",
    "low HP: the smallest potion that fills it is used, and there is no trip to the Center")
  session.party[1].hp = 15; runUntil(300, function() return Bot.stats.itemsHp == 2 end)
  check(session.party[1].hp == 40 and Bot.stats.itemsHp == 2, "a second potion while the limit allows")
  session.party[1].pp = { 0, 0 }; runUntil(300, function() return Bot.stats.itemsPp == 1 end)
  check(session.party[1].pp[1] > 0 and session.bag[34] == 2 and Bot.stats.itemsPp == 1, "out of PP: an Ether on the attack that ran dry")
  endBattle(); session.party[1].hp = 10; local potions = session.bag[22] + session.bag[13]; step(30)
  check(session.party[1].hp == 10 and session.bag[22] + session.bag[13] == potions and Bot.running, "past the limit no more potions are spent: " .. tostring(Bot.status))
  Bot.stop("x"); Bot.finish(); session.bag[13], session.bag[22], session.bag[34] = nil, nil, nil
  session.party[1].maxHp = keepMax; session.party[1].hp = keepMax; Bot.config.hpPct, Bot.config.itemHp, Bot.config.itemPp = 30, 0, 0
  -- reset hunting: save in front of the Pokémon, look at what comes, load again
  reset(); Bot.stop("x"); Bot.finish()
  Bot.config.targets, Bot.config.huntShiny, Bot.config.resetCatch = {}, false, false
  check(Bot.start("reset") == false and Bot.reason == "no_targets", "a reset hunt needs a target or the shiny stop")
  Bot.config.huntShiny = true
  sim.static, sim.statics, sim.saves, sim.reloads = "battle", {}, 0, 0
  check(Bot.start("reset") and sim.saves == 1, "starting a reset hunt saves the game on the spot")
  step(1)                         -- a lucky first attempt must not end the hunt before this check
  check(game:saveGame() == false and sim.saves == 1, "while it runs nothing is saved over that point")
  runUntil(200000, function() return not Bot.running end)
  check(Bot.reason == "hunt_found" and battle.active and battle.st.enemy.mon.shiny, "it loads again and again until the shiny appears, and stops there: " .. Bot.stats.resets .. " attempts")
  check(sim.reloads == Bot.stats.resets and #sim.statics == Bot.stats.resets and Bot.stats.found == 1, "one load per attempt, counted")
  check(game:saveGame() == true, "with the target on screen the game may be saved again")
  -- a handed-over Pokémon is looked at before the nickname question is answered
  reset(); Bot.finish()
  sim.static, sim.statics, sim.reloads = "gift", {}, 0
  local before = #session.party
  check(Bot.start("reset"), "a reset hunt for a gift starts")
  runUntil(200000, function() return not Bot.running end)
  check(Bot.reason == "hunt_found" and #session.party == before + 1 and session.party[#session.party].shiny and Choice.open,
    "gifts: stops with the shiny in the team and the nickname question untouched: " .. Bot.stats.resets .. " attempts")
  Choice.open, Choice.done = false, nil; table.remove(session.party); Bot.finish()
  -- with a full team the gift goes to the PC: it is looked at there, the nickname still untouched
  do
    local keepParty = session.party
    local full = {}
    for index = 1, 6 do full[index] = keepParty[index] or mon(19, 5, 20) end
    session.party = full
    session.storage = { boxes = { { mons = { mon(19, 5, 20) } } } }
    Storage.countTotalMons = function(st) local n = 0; for _, box in ipairs(st.boxes) do for slot = 1, 30 do if box.mons[slot] then n = n + 1 end end end return n end
    reset(); Bot.finish()
    sim.static, sim.statics, sim.reloads, sim.log = "gift", {}, 0, {}
    check(Bot.start("reset"), "a reset hunt for a gift with a full team starts")
    runUntil(200000, function() return not Bot.running end)
    local boxed = session.storage.boxes[1].mons[session.monBoxPos + 1]
    check(Bot.reason == "hunt_found" and #session.party == 6 and boxed and boxed.shiny and Choice.open and #sim.log == 0,
      "gift to the PC: stops with the shiny in the box and the nickname question untouched: " .. tostring(Bot.reason) .. ", " .. Bot.stats.resets .. " attempts")
    check(Bot.stats.resets > 0 and sim.reloads == Bot.stats.resets, "each gift that was not the target was loaded away, without pressing on")
    Choice.open, Choice.done = false, nil
    session.party, session.storage, session.monBoxId, session.monBoxPos = keepParty, nil, nil, nil
    Storage.countTotalMons = nil
    Bot.finish()
  end
  -- with capture on, a catch that fails brings the same Pokémon back
  reset()
  session.bag[1], session.bag[4] = nil, 50
  Bot.config.resetCatch, Bot.config.useMaster, Bot.config.catchWeaken, Bot.config.catchStatus = true, false, false, false
  sim.static, sim.statics, sim.reloads, sim.fleeFirst = "battle", {}, 0, 2
  check(Bot.start("reset"), "a reset hunt with capture starts")
  runUntil(200000, function() return count("fled") == 2 and battle.active and battle.st.enemy.mon.shiny end)
  local n = #sim.statics
  check(sim.statics[n] == sim.statics[n - 1] and sim.statics[n] == sim.statics[n - 2], "after a failed catch the load brings the very same Pokémon back")
  check(Bot.running and Bot.stats.found == 1 and (Bot.stats.lost or 0) == 0, "and it still counts as one target, not yet lost")
  session.bag[1] = 1; Bot.config.useMaster = true
  runUntil(20000, function() return not Bot.running end)
  check(Bot.reason == "caught" and Bot.stats.caught == 1 and game:saveGame() == true, "caught: the hunt ends and saving is free again")
  Bot.config.resetCatch, Bot.config.useMaster, Bot.config.catchWeaken, Bot.config.catchStatus = false, false, true, true
  -- Trainer Tactics, when it is there, chooses the move
  do
    check(Bot.tacticsMove({ mon = session.party[1] }) == nil, "without Trainer Tactics the bot picks moves itself")
    local asked
    m.find = function(id) return id == "trainer_tactics" and { exports = { tactics = { api = 1,
      bestMove = function(opts) asked = opts; return 3 end } } } or nil end
    check(Bot.tacticsMove({ mon = session.party[1] }) == 3 and asked.fast == true and type(asked.ban) == "function",
      "with it, the move comes from its brain, asked for speed and with the forbidden moves")
    m.find = function() return nil end
  end
  -- nothing in front of the player
  reset(); Bot.finish(); sim.static = nil
  Bot.start("reset"); runUntil(20000, function() return not Bot.running end)
  check(Bot.reason == "reset_nothing", "with nothing to talk to it gives up instead of pressing A for ever")
  Bot.stop("player"); check(game:saveGame() == false, "a paused reset hunt still protects the save")
  Bot.finish(); check(game:saveGame() == true, "FINALIZAR frees it")
  -- walking away from a paused reset hunt ends it, so playing on is saved
  Bot.start("reset"); step(5); Bot.stop("player"); step(2)
  check(game:saveGame() == false, "paused on the spot, the save is still protected")
  P.cellX = P.cellX + 5; step(2)
  check(Bot.reason == "reset_released" and Bot.mode == nil and game:saveGame() == true, "walking away ends the hunt and frees the save: " .. tostring(Bot.reason))
  P.cellX = P.cellX - 5
  Bot.mode, Bot.stats.startedAt, Bot.stats.resets, Bot.resetLock = "reset", 0, 12, true
  local two = G.newCanvas(panel.W * 2, panel.H)
  panel.draw(); panel.pointer("down", 60, 20); panel.draw()
  G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
  G.setCanvas(two); G.setColor(1, 1, 1, 1); G.draw(canvas, 0, 0); G.setCanvas()
  panel.pointer("down", 420, 20); panel.draw(); panel.pointer("down", 390, 400); panel.draw()
  G.setCanvas(canvas); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
  check(panel.lastError == nil, "the reset hunt screen draws: " .. tostring(panel.lastError))
  G.setCanvas(two); G.setColor(1, 1, 1, 1); G.draw(canvas, panel.W, 0); G.setCanvas()
  local f9 = io.open(OUT .. "/bot-reset.png", "wb"); f9:write(two:newImageData():encode("png"):getString()); f9:close()
  panel.pointer("down", 100, 368); panel.draw()
  Bot.resetLock = nil; Bot.finish()
  Bot.config.huntShiny = true
  -- speed while running, restored on stop; and a banned move is never used
  reset(); Bot.stop("x"); Bot.config.selected = { [1] = true }
  game.options = { speedOverworld = 2, speedBattle = 3 }
  Bot.setSpeed(50); check(game.options.speedOverworld == 2, "choosing a speed while stopped changes nothing in the game")
  Bot.start(); check(game.options.speedOverworld == 50 and game.options.speedBattle == 50, "while running the game takes the bot's speed")
  Bot.setSpeed(10); check(game.options.speedBattle == 10, "and follows a change made on the way")
  Bot.stop("x"); check(game.options.speedOverworld == 2 and game.options.speedBattle == 3, "stopping gives back the speeds from before")
  Bot.setSpeed(0)
  session.party[1].moves, session.party[1].pp, session.party[1].maxPp = { 33, 99 }, { 35, 10 }, { 35, 10 }
  Bot.config.banned[Bot.moveKey(session.party[1], 99)] = true
  sim.log = {}; Bot.start(); startBattle(false, mon(19, 5, 60)); runUntil(3000, function() return not battle.active end)
  check(count("move1") >= 3 and count("move2") == 0, "a move marked as forbidden is never chosen, even though it is the strongest")
  Bot.config.banned = {}
  Bot.stop("probe")
  check(cache["log/last"] and cache["log/last"]:find("reason=probe", 1, true), "the last stop is written down: " .. cache["log/last"]:gsub("\n", " "))
  -- the new look, stretched to rooms of other sizes
  do
    local sheet2 = G.newCanvas(1700, 560)
    local x2 = 0
    local iconData = love.image.newImageData(32, 32)
    iconData:mapPixel(function(x, y) if (x - 16) ^ 2 + (y - 16) ^ 2 < 150 then return 0.95, 0.55, 0.25, 1 end return 0, 0, 0, 0 end)
    local iconImage = G.newImage(iconData)
    Pokemon.monIcon = function() return { image = iconImage, w = 32, h = 32 } end
    Bot.config.selected = { [1] = true }
    session.party[1].hp = 12
    Bot.config.banned[Bot.moveKey(session.party[1], 33)] = true
    Pokemon.icon = function() return { image = iconImage, w = 32, h = 32 } end
    Bot.stats.seen = { [19] = 14, [16] = 6, [129] = 2 }
    Bot.mode, Bot.stats.startedAt, Bot.stats.endedAt, Bot.reason = "hunt", 0, 4000, "hunt_found"
    Bot.stats.found, Bot.stats.caught, Bot.stats.lost, Bot.stats.battles = 2, 1, 1, 87
    local me1 = session.party[1]
    me1.evs = { hp = 0, atk = 40, def = 0, spe = 252, spa = 0, spd = 0 }
    Bot.config.evTargets[tostring(me1.personality)] = { atk = 252, spe = 252 }
    Pokemon.evYield = function(species) return ({ [19] = { spe = 1 }, [16] = { atk = 1 } })[species] or {} end
    Bot.config.targets = { { species = 129, gender = "F", ivTotal = 120, ability = 0, shiny = true, ivs = { hp = 0, atk = 0, def = 0, spe = 31, spa = 0, spd = 0 } } }
    Bot.config.targets[2] = { species = 0, gender = "any", ivTotal = 165, ability = 0, shiny = false, ivs = { hp = 30, atk = 30, def = 25, spe = 30, spa = 25, spd = 25 } }
    for index, shot in ipairs({ { 240, 20, 447, 453 }, { 240, 20, 447, 453 }, { 60, 20, 447, 453 } }) do
      if index == 2 then panel.draw(nil, 447, 453); panel.pointer("down", 196 * 447 / 480, 76 * 453 / 432) end
      if index == 3 then Bot.mode, Bot.reason = "train", nil; panel.draw(nil, 447, 453); panel.pointer("down", 60 * 447 / 480, 20 * 453 / 432) end
      local c = G.newCanvas(shot[3], shot[4])
      panel.draw(nil, shot[3], shot[4]); panel.pointer("down", shot[1] * shot[3] / 480, shot[2] * shot[4] / 432)
      G.setCanvas(c); G.clear(0, 0, 0, 1); panel.draw(nil, shot[3], shot[4]); G.setCanvas()
      check(panel.lastError == nil, "the panel draws at " .. shot[3] .. "x" .. shot[4] .. ": " .. tostring(panel.lastError))
      G.setCanvas(sheet2); G.setColor(1, 1, 1, 1); G.draw(c, x2, 0); G.setCanvas()
      x2 = x2 + shot[3] + 10
    end
    Bot.config.banned = {}; session.party[1].hp = session.party[1].maxHp; Pokemon.monIcon = nil; Pokemon.icon = nil
    Bot.stats.seen = {}; Bot.finish(); Bot.config.targets = {}; Bot.config.evTargets = {}; Pokemon.evYield = nil; me1.evs = nil
    local f8 = io.open(OUT .. "/bot-new.png", "wb"); f8:write(sheet2:newImageData():encode("png"):getString()); f8:close()
    panel.draw(); panel.pointer("down", 60, 20); panel.draw()
  end
  do
    -- the hunt list with more than five targets, typing a name, and the history
    Bot.config.targets = {}
    for index = 1, 7 do
      Bot.config.targets[index] = { species = index % 2 == 0 and 129 or 0, gender = "F", ivTotal = 100, ability = 0, shiny = index == 1, natures = {},
        name = index == 2 and "Magikarp perfeito" or nil, ivs = { hp = 0, atk = 0, def = 0, spe = 31, spa = 0, spd = 0 } }
    end
    Bot.history = {
      { at = os.time(), reason = "hunt_found", mode = "hunt", route = "Grama Route1", map = "FR_ROUTE_15", x = 12, y = 8, battles = 140, seconds = 3720, found = 1, caught = 0 },
      { at = os.time() - 600, reason = "stuck", mode = "train", route = "Grama Route1", map = "FR_ROUTE_15", x = 30, y = 4, battles = 12, seconds = 300, found = 0, caught = 0 },
      { at = os.time() - 900, reason = "player", mode = "train", route = "Pesca Route2", map = "MAP_ROUTE2", x = 3, y = 2, battles = 4, seconds = 61, found = 0, caught = 0 } }
    local out = G.newCanvas(1440, 432)
    local function shot(x, setup)
      setup()
      local c = G.newCanvas(480, 432)
      G.setCanvas(c); G.clear(0, 0, 0, 1); panel.draw(); G.setCanvas()
      check(panel.lastError == nil, "panel draws: " .. tostring(panel.lastError))
      G.setCanvas(out); G.setColor(1, 1, 1, 1); G.draw(c, x, 0); G.setCanvas()
    end
    -- an earlier check left the reset screen open: back to the list first
    shot(0, function() panel.draw(); panel.pointer("down", 420, 20); panel.draw(); panel.pointer("down", 100, 388); panel.draw()
      panel.pointer("down", 455, 139); panel.draw() end)  -- page 2 of targets
    shot(480, function()
      panel.pointer("down", 384, 139); panel.draw()                         -- back to page 1
      panel.pointer("down", 388, 210); panel.draw()                         -- edit the second target
      panel.pointer("down", 150, 56); panel.draw()                          -- touch the title: type a name
      for _, k in ipairs({ "backspace", "backspace", "backspace", "backspace", "backspace", "backspace", "backspace", "backspace", "x", "2" }) do panel.key(k) end
    end)
    do
      local f0 = io.open(OUT .. "/bot-0.24.png", "wb"); f0:write(out:newImageData():encode("png"):getString()); f0:close()
    end
    check(panel.wantsKeys() == true, "while a name is being typed the panel takes the keyboard")
    panel.key("return")
    check(panel.wantsKeys() == false, "Enter ends the typing")
    panel.pointer("down", 100, 398); panel.draw()                           -- save
    check(Bot.config.targets[2].name == "Magikpex2" or Bot.config.targets[2].name:find("x2$"), "the typed name is saved: " .. tostring(Bot.config.targets[2].name))
    shot(960, function() panel.pointer("down", 60, 20); panel.draw(); panel.pointer("down", 100, 383); panel.draw() end)  -- control > history
    local f9 = io.open(OUT .. "/bot-0.24.png", "wb"); f9:write(out:newImageData():encode("png"):getString()); f9:close()
    panel.pointer("down", 100, 395); panel.draw()
    Bot.config.targets, Bot.history = {}, {}
  end
  check(#logs == 0, "no warnings in the new checks")
  print("ALL BOT CHECKS PASSED")
  love.event.quit()
end
