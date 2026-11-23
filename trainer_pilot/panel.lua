-- Trainer Pilot's control panel: five tabs drawn into a Trainer Desk panel. Everything
-- clickable is registered as a rectangle while drawing and looked up when the
-- pointer goes down.
return function(mod, Bot, I18n)
  local G = love.graphics
  -- main.lua passes its texts; loaded on its own, the panel makes its own
  I18n = I18n or assert(load(assert(mod:read("i18n.lua")), "@trainer_pilot/i18n.lua"))()(mod, function()
    local ok, value = pcall(function() return mod.options:get("language") end)
    return ok and value or "en"
  end)
  local T, F = I18n.T, I18n.F
  local floor, max, min = math.floor, math.max, math.min
  local Panel = { W = 480, H = 432 }
  local tab, routePage, speciesPage, picked = "control", 1, 1, nil
  local hits = {}
  local fonts = {}
  local function font(size)
    size = max(8, floor(size + 0.5))
    if not fonts[size] then fonts[size] = I18n.font(size) end
    return fonts[size]
  end
  -- The panel is laid out on a 480x432 sheet and stretched to the room it is
  -- given: positions follow the room, text follows the smaller of the two scales.
  local kx, ky, kf, ox, oy = 1, 1, 1, 0, 0

  local function hex(value)
    return { tonumber(value:sub(1, 2), 16) / 255, tonumber(value:sub(3, 4), 16) / 255, tonumber(value:sub(5, 6), 16) / 255 }
  end
  -- The same look as the other panels of the IDE.
  local C = {
    bg = hex("0f1216"), card = hex("1b1f26"), line = hex("2f3742"),
    text = hex("e6ebf2"), muted = hex("9aa5b4"), accent = hex("4f9cf7"),
    go = hex("2f9e58"), stop = hex("d9534f"), warn = hex("d1912a"),
    on = hex("4f9cf7"), off = hex("252b34"),
  }
  -- A dock theme, when there is one, gives the surfaces and the text their colours.
  function Panel.theme(colors)
    if type(colors) ~= "table" then return end
    C.bg, C.card, C.off = colors.panel or C.bg, colors.dock or C.card, colors.tabActive or C.off
    C.text, C.muted = colors.textActive or C.text, colors.text or C.muted
    C.accent, C.on = colors.accent or C.accent, colors.accent or C.on
  end
  -- Texts by key come from lang/<language>.lua (see i18n.lua).
  local REASONS = setmetatable({}, { __index = function(_, code) return T("reasons")[code] end })
  Bot.reasonText = function(code) return REASONS[code] or tostring(code) end
  local STATUS = setmetatable({}, { __index = function(_, key) return T("status")[key] end })
  local KIND = setmetatable({}, { __index = function(_, key) return T("kinds")[key] end })
  local KIND_COLOR = { grass = hex("3fa35a"), fish = hex("3a86d8"), seeker = hex("9a6ae0"), heal = hex("d9534f"), scent = hex("d86aa8") }

  local function color(c, a) G.setColor(c[1], c[2], c[3], a or 1) end
  local function box(x, y, w, h, c, r)
    color(c)
    local radius = min((r or 6) * kf, h * ky / 2, w * kx / 2)
    G.rectangle("fill", floor(ox + x * kx), floor(oy + y * ky), floor(w * kx + 0.5), floor(h * ky + 0.5), radius, radius)
  end
  local function text(str, x, y, c, size, limit, align)
    G.setFont(font((size or 13) * kf))
    color(c or C.text)
    local px, py = floor(ox + x * kx), floor(oy + y * ky)
    if limit then G.printf(tostring(str), px, py, max(1, floor(limit * kx)), align or "left") else G.print(tostring(str), px, py) end
  end
  -- One line only: what does not fit in `limit` loses its end instead of
  -- wrapping onto whatever is underneath.
  local function line(str, x, y, c, size, limit, align)
    local f = font((size or 13) * kf)
    G.setFont(f)
    color(c or C.text)
    str = tostring(str)
    local room = max(1, limit * kx)
    if f:getWidth(str) > room then
      local chars = {}
      for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
      while #chars > 0 and f:getWidth(table.concat(chars) .. "..") > room do chars[#chars] = nil end
      str = table.concat(chars) .. ".."
    end
    local px = ox + x * kx
    if align == "right" then px = px + room - f:getWidth(str) end
    G.print(str, floor(px), floor(oy + y * ky))
  end
  -- One line of text in the middle of a box, whatever the two scales are.
  local function centred(str, x, y, w, h, c, size)
    local f = font((size or 13) * kf)
    G.setFont(f)
    color(c or C.text)
    G.printf(tostring(str), floor(ox + x * kx), floor(oy + y * ky + (h * ky - f:getHeight()) / 2), max(1, floor(w * kx)), "center")
  end
  local function hit(x, y, w, h, action)
    hits[#hits + 1] = { x = ox + x * kx, y = oy + y * ky, w = w * kx, h = h * ky, action = action }
  end
  local function button(label, x, y, w, h, fill, action, size, radius)
    box(x, y, w, h, fill or C.off, radius or 6)
    centred(label, x, y, w, h, C.text, size or 13)
    hit(x, y, w, h, action)
  end
  local function toggle(label, x, y, w, value, action)
    box(x, y, w, 26, C.card)
    local f = font(13 * kf)
    G.setFont(f)
    color(C.text)
    G.print(tostring(label), floor(ox + (x + 8) * kx), floor(oy + y * ky + (26 * ky - f:getHeight()) / 2))
    -- the switch keeps its shape: it is sized by the text scale, not stretched
    local sw, sh = 40 * kf, 20 * kf
    local sx, sy = ox + (x + w) * kx - sw - 8 * kf, oy + y * ky + (26 * ky - sh) / 2
    color(value and C.on or C.line)
    G.rectangle("fill", sx, sy, sw, sh, sh / 2, sh / 2)
    color(C.text)
    G.circle("fill", value and sx + sw - sh / 2 or sx + sh / 2, sy + sh / 2, sh / 2 - 3 * kf)
    hit(x, y, w, 26, action)
  end
  local function stepper(label, x, y, w, shown, minus, plus)
    box(x, y, w, 26, C.card)
    local f = font(13 * kf)
    G.setFont(f)
    color(C.text)
    G.print(tostring(label), floor(ox + (x + 8) * kx), floor(oy + y * ky + (26 * ky - f:getHeight()) / 2))
    button("-", x + w - 112, y + 2, 26, 22, C.off, minus)
    centred(shown, x + w - 84, y, 54, 26, C.text, 13)
    button("+", x + w - 28, y + 2, 26, 22, C.off, plus)
  end
  -- Back and forward buttons with "page/pages" between them, ending at `right`.
  local function pager(right, y, h, page, pages, set)
    if pages <= 1 then return end
    local bw, lw = 28, 44
    local x = right - (bw * 2 + lw)
    for index, mark in ipairs({ "<", ">" }) do
      local bx = index == 1 and x or right - bw
      local live = (index == 1 and page > 1) or (index == 2 and page < pages)
      box(bx, y, bw, h, live and C.off or C.card)
      centred(mark, bx, y, bw, h, live and C.text or C.line, 12)
      if live then hit(bx, y, bw, h, function() set(page + (index == 1 and -1 or 1)) end) end
    end
    centred(page .. "/" .. pages, x + bw, y, lw, h, C.muted, 11)
  end
  -- A picture (a Pokémon icon) fitted in a square of the sheet, kept in proportion.
  local function sprite(pic, x, y, size, dim)
    if not (type(pic) == "table" and pic.image) then return end
    local quad = pic.quads and (pic.quads[0] or pic.quads[1])
    local w, h = pic.w or pic.image:getWidth(), pic.h or pic.image:getHeight()
    local room = size * min(kx, ky)
    local scale = min(room / w, room / h)
    if scale >= 1 then scale = floor(scale) end
    local shade = dim and 0.45 or 1
    G.setColor(shade, shade, shade, 1)
    local px = floor(ox + x * kx + (size * kx - w * scale) / 2)
    local py = floor(oy + y * ky + (size * ky - h * scale) / 2)
    if quad then G.draw(pic.image, quad, px, py, 0, scale, scale) else G.draw(pic.image, px, py, 0, scale, scale) end
  end
  -- Game names come in capitals: "PIDGEY" reads better as "Pidgey".
  local function nameCase(value)
    return (tostring(value):lower():gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
  end
  local function mix(a, b, k) return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k } end
  local TYPE = { NORMAL = "a8a878", FIRE = "f08030", WATER = "5890f0", ELECTRIC = "f0c020", GRASS = "70c048",
    ICE = "68c8d0", FIGHTING = "c03028", POISON = "a040a0", GROUND = "d8b058", FLYING = "a890f0", PSYCHIC = "f85888",
    BUG = "a8b820", ROCK = "b8a038", GHOST = "705898", DRAGON = "7038f8", DARK = "705848", STEEL = "b8b8d0" }
  for key, value in pairs(TYPE) do TYPE[key] = hex(value) end
  local typeNames
  local function typeColor(h, id)
    if not typeNames then
      typeNames = {}
      for name, value in pairs(type(h.Types) == "table" and type(h.Types.ID) == "table" and h.Types.ID or {}) do typeNames[value] = name end
    end
    return TYPE[typeNames[id] or ""]
  end
  -- A small rounded label; returns its width on the sheet.
  local function pill(label, x, y, fill, ink, size)
    size = size or 11
    local w = font(size * kf):getWidth(tostring(label)) / kx + 14
    box(x, y, w, 18, fill, 9)
    centred(label, x, y, w, 18, ink or C.text, size)
    return w
  end
  -- One number with its name under it.
  local function tile(label, value, x, y, w, ink)
    box(x, y, w, 46, C.card, 8)
    centred(value, x, y + 4, w, 24, ink or C.text, 17)
    centred(label, x, y + 27, w, 14, C.muted, 10)
  end
  local function speciesIcon(id, x, y, size, dim)
    local h = Bot.host()
    local ok, pic = pcall(function() return h.Pokemon.icon(id) end)
    if ok then sprite(pic, x, y, size, dim) end
  end
  local GOOD = { ev_done = true, ev_healed = true, hunt_found = true, shiny = true, caught = true, level = true, level_healed = true, species = true }
  local function save() Bot.save() end

  ---------------------------------------------------------------------------
  local speciesName
  local EV_NAMES = setmetatable({}, { __index = function(_, key) return T("ev")[key] end })
  local function monName(mon)
    local h = Bot.host()
    local ok, name = pcall(function()
      return (mon.nickname and mon.nickname ~= "" and mon.nickname) or h.Pokemon.name(h.Pokemon.speciesOf(mon))
    end)
    return ok and nameCase(name) or "?"
  end
  -- The first Pokémon marked to fight that has EV targets, while the mode allows them.
  local function evLead()
    if Bot.mode == "hunt" or Bot.mode == "reset" then return nil end
    local session = Bot.session()
    for slot, mon in ipairs(session and session.party or {}) do
      if Bot.config.selected[slot] and Bot.evTarget(mon) then return mon end
    end
  end
  local fightIcon
  local controlView, historyPage = nil, 1
  local MODE_NAMES = setmetatable({}, { __index = function(_, key) return T("modes")[key] end })
  local function placeName(map)
    map = tostring(map or ""):gsub("^%u%u_", ""):gsub("_", " ")
    return nameCase(map)
  end
  local function drawHistory()
    local list = Bot.history or {}
    box(10, 44, 460, 34, C.card, 8)
    text(T("history_title"), 22, 51, C.text, 14)
    line(#list == 1 and T("history_one") or F("history_many", #list), 200, 54, C.muted, 10, 150)
    if #list > 0 then button(T("clear"), 384, 50, 78, 22, C.off, function() Bot.clearHistory() historyPage = 1 end, 11, 8) end
    local perPage = 8
    local pages = max(1, math.ceil(#list / perPage))
    historyPage = max(1, min(pages, historyPage))
    if #list == 0 then
      centred(T("history_empty"), 10, 120, 460, 20, C.muted, 12)
    end
    for row = 1, perPage do
      local e = list[(historyPage - 1) * perPage + row]
      if e then
        local y = 84 + (row - 1) * 36
        local good = GOOD[e.reason]
        local tint = e.reason == "player" and C.line or good and C.warn or C.stop
        box(10, y, 460, 32, C.card, 6)
        box(14, y + 6, 3, 20, tint, 2)
        line(os.date("%d/%m %H:%M", e.at), 458 - 64, y + 3, C.muted, 10, 64, "right")
        line(REASONS[e.reason] or e.reason, 24, y + 2, C.text, 12, 360)
        local seconds = e.seconds or 0
        local length = seconds >= 3600 and ("%dh%02d"):format(floor(seconds / 3600), floor(seconds / 60) % 60)
          or ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
        local parts = { MODE_NAMES[e.mode] or "?", length, F("battles_n", e.battles) }
        if e.route ~= "" then table.insert(parts, 2, e.route) end
        if (e.found or 0) > 0 then parts[#parts + 1] = F("targets_n", e.found) end
        if e.map ~= "" then parts[#parts + 1] = placeName(e.map) .. (e.x and (" (" .. e.x .. "," .. e.y .. ")") or "") end
        line(table.concat(parts, "  ·  "), 24, y + 18, C.muted, 10, 434)
      end
    end
    button(T("back"), 10, 380, 226, 30, C.off, function() controlView = nil end, 13)
    pager(470, 382, 26, historyPage, pages, function(page) historyPage = page end)
  end
  local function drawControl()
    if controlView == "history" then return drawHistory() end
    local c = Bot.config
    local running = Bot.running
    local mode = Bot.mode
    local train, heal = Bot.route(c.train), Bot.route(c.heal)
    -- what it is doing, and the buttons that stop or resume it
    box(10, 44, 460, 64, C.card, 8)
    color(running and C.go or C.line)
    G.circle("fill", ox + 28 * kx, oy + 64 * ky, 6 * kf)
    text(STATUS[Bot.status] or Bot.status, 42, 50, C.text, 18)
    local label = mode == "reset" and T("reset_title") or mode and MODE_NAMES[mode] or nil
    local px = 22
    if label then px = px + pill(label, px, 82, C.accent) + 6 end
    if mode ~= "reset" then
      line(train and train.name or T("no_route_hint"), px, 84, C.muted, 11, 326 - px)
    end
    if running then
      button(T("stop_btn"), 340, 52, 118, 48, C.stop, function() Bot.stop("player") Bot.reason = nil end, 15, 8)
    elseif mode and Bot.stats.startedAt then
      button(T("continue_btn"), 340, 50, 118, 28, C.go, function() Bot.start(Bot.mode, true) end, 13, 8)
      button(T("finish_btn"), 340, 82, 118, 22, C.off, function() Bot.finish() end, 11, 8)
    end
    -- why it stopped: gold when that is good news, red when it is not
    local reason = not running and Bot.reason and REASONS[Bot.reason] ~= "" and (REASONS[Bot.reason] or Bot.reason) or nil
    if reason then
      local good = GOOD[Bot.reason] or Bot.reason == "player"
      local tint = Bot.reason == "player" and C.off or good and C.warn or C.stop
      box(10, 112, 460, 24, mix(C.card, tint, 0.55), 6)
      box(15, 117, 3, 14, tint, 2)
      line(reason, 26, 117, C.text, 11, 436)
    end
    -- the run in numbers
    local stats = Bot.stats
    local elapsed = stats.startedAt and floor((running and love.timer.getTime() or stats.endedAt or love.timer.getTime()) - stats.startedAt) or 0
    local clock = elapsed >= 3600 and ("%d:%02d:%02d"):format(floor(elapsed / 3600), floor(elapsed / 60) % 60, elapsed % 60)
      or ("%02d:%02d"):format(floor(elapsed / 60), elapsed % 60)
    local used = (stats.itemsHp or 0) + (stats.itemsPp or 0)
    tile(T("t_battles"), stats.battles or 0, 10, 140, 110)
    tile(T("t_heals"), stats.heals or 0, 126, 140, 110)
    tile(T("t_items"), used, 242, 140, 110)
    tile(T("t_time"), clock, 358, 140, 112)
    if mode == "reset" or mode == "hunt" then
      local reset = mode == "reset"
      tile(reset and T("t_attempts") or T("t_targets"), reset and (stats.resets or 0) or #c.targets, 10, 190, 110)
      tile(T("t_found"), stats.found or 0, 126, 190, 110, (stats.found or 0) > 0 and C.warn or nil)
      tile(T("t_caught"), stats.caught or 0, 242, 190, 110, (stats.caught or 0) > 0 and C.go or nil)
      tile(T("t_lost"), stats.lost or 0, 358, 190, 112, (stats.lost or 0) > 0 and C.stop or nil)
    elseif evLead() then
      -- EV training: how far the one fighting is from each of its targets
      local mon = evLead()
      local t, evs = Bot.evTarget(mon), Bot.evsOf(mon)
      box(10, 190, 460, 46, C.card, 8)
      local shown = 0
      for _, key in ipairs(Bot.EV_KEYS) do
        if (t[key] or 0) > 0 and shown < 6 then
          local x, y = 22 + (shown % 3) * 150, 194 + floor(shown / 3) * 20
          local have = tonumber(evs[key]) or 0
          local done = have >= t[key]
          line(EV_NAMES[key] .. " " .. have .. "/" .. t[key], x, y, done and C.go or C.text, 10, 78)
          box(x + 80, y + 4, 56, 5, C.line, 3)
          box(x + 80, y + 4, max(3, 56 * min(1, have / t[key])), 5, done and C.go or C.accent, 3)
          shown = shown + 1
        end
      end
      if shown <= 3 then
        local fled = stats.evFled or 0
        line(F("ev_of", monName(mon)) .. (fled > 0 and F("ev_fled", fled) or ""), 22, 216, C.muted, 10, 436)
      end
    else
      -- training: what it is set to stop for, as labels
      box(10, 190, 460, 46, C.card, 8)
      text(T("stops_when"), 22, 194, C.muted, 10)
      local x = 22
      local function stop(label2) x = x + pill(label2, x, 212, C.off, C.text, 10) + 5 end
      if c.stopLevel > 0 then stop(F("s_level", c.stopLevel)) end
      if c.stopShiny then stop(T("s_shiny")) end
      if next(c.species) then stop(T("s_species")) end
      if c.stopLearn then stop(T("s_learn")) end
      if c.stopEvolve then stop(T("s_evolve")) end
      if c.stopNoPP then stop(T("s_pp")) end
      if not c.healOn then stop(T("s_heal")) end
      if x == 22 then text(T("s_nothing"), 22, 213, C.muted, 11) end
    end
    -- where, and how it heals
    box(10, 240, 460, 50, C.card, 8)
    if mode == "reset" then
      text(T("reset_line"), 22, 246, C.text, 13, 436)
      text(Bot.resetLock and T("save_locked") or T("save_free"), 22, 268, C.muted, 11, 436)
    else
      local nx = 22
      if train then nx = nx + pill(KIND[train.kind], nx, 246, C.off, C.text, 10) + 6 end
      line(train and train.name or T("no_route_chosen"), nx, 247, C.text, 13, 350 - nx)
      local fighters = 0
      for _ in pairs(c.selected) do fighters = fighters + 1 end
      local cure = not c.healOn and T("cure_none") or heal and F("cure_path", heal.name) or T("cure_center")
      line(F("fighting_line", fighters, c.hpPct, cure), 22, 270, C.muted, 11, 436)
      if train and train.kind == "fish" then
        local rods = T("rods")
        button(rods[c.rod] or rods[0], 360, 244, 100, 20, C.off, function()
          c.rod = (c.rod == 0 and 262) or (c.rod == 262 and 263) or (c.rod == 263 and 264) or 0
          save()
        end, 10, 10)
      end
    end
    local LEVELS = { 0, 1, 2, 3, 4, 10, 20, 30, 50, 75, 100, 200 }
    local at = 1
    for index, level in ipairs(LEVELS) do if level == c.speed then at = index end end
    stepper(T("speed"), 10, 294, 460, c.speed == 0 and T("game_speed") or (c.speed .. "x"),
      function() Bot.setSpeed(LEVELS[max(1, at - 1)]) end, function() Bot.setSpeed(LEVELS[min(#LEVELS, at + 1)]) end)
    -- what has appeared so far, most often first
    local rec = Bot.recording
    if rec then
      box(10, 326, 460, 40, mix(C.card, C.stop, 0.6), 8)
      text(F("recording_n", KIND[rec.kind], #rec.points), 22, 338, C.text, 13)
    else
      -- how many of each target's species this run has met, whatever the target's
      -- other filters; a target for any species brings in every species met
      local seenBy, list, listed = stats.seen or {}, {}, {}
      if Bot.mode == "hunt" or Bot.mode == "reset" then
        local anySpecies = false
        for _, target in ipairs(c.targets) do
          if target.species == 0 then anySpecies = true
          elseif not listed[target.species] then
            listed[target.species] = true
            list[#list + 1] = { species = target.species, count = seenBy[target.species] or 0,
              name = target.name or speciesName(target.species) }
          end
        end
        if anySpecies then
          for species, count in pairs(seenBy) do
            if not listed[species] then
              listed[species] = true
              list[#list + 1] = { species = species, count = count, name = speciesName(species) }
            end
          end
        end
        table.sort(list, function(a, b)
          if a.count ~= b.count then return a.count > b.count end
          return a.species < b.species
        end)
      end
      if #list > 0 then
        box(10, 326, 460, 40, C.card, 8)
        local shown = min(4, #list)
        for index = 1, shown do
          local entry, x = list[index], 16 + (index - 1) * 114
          if index == 4 and #list > 4 then
            text(F("more_targets", #list - 3), x + 4, 338, C.muted, 12)
            break
          end
          if entry.species ~= 0 then speciesIcon(entry.species, x, 330, 32, entry.count == 0) end
          local count = tostring(entry.count)
          local nx = x + (entry.species ~= 0 and 34 or 2)
          line(count, nx, 329, entry.count > 0 and C.gold or C.muted, 14, x + 108 - nx, "right")
          line(entry.name, nx, 346, entry.count > 0 and C.text or C.muted, 11, x + 108 - nx)
        end
      end
    end
    button(F("history_btn", #(Bot.history or {})), 10, 372, 200, 22, C.off, function() controlView = "history" end, 11, 8)
    text(T("control_hint1"), 12, 400, C.muted, 11, 456)
    text(T("control_hint2"), 12, 414, C.muted, 11, 456)
  end

  local ROUTES_PER_PAGE = 4
  local routesNear = false   -- Routes tab: only this map and the ones next to it
  local function drawRoutes()
    local c, rec = Bot.config, Bot.recording
    if rec then
      box(10, 44, 460, 96, C.card)
      text(F("recording", KIND[rec.kind]), 22, 52, C.warn, 16)
      text(F("recording_steps", #rec.points), 22, 76, C.text, 13)
      button(T("save_btn"), 22, 100, 150, 30, C.go, function() Bot.stopRecording(true) end)
      button(T("cancel"), 182, 100, 150, 30, C.off, function() Bot.stopRecording(false) end)
    else
      box(10, 44, 460, 130, C.card, 8)
      text(T("new_route"), 22, 50, C.muted, 10)
      text(T("record_walk"), 22, 66, C.text, 12)
      button(KIND.grass, 22, 84, 140, 26, C.off, function() Bot.startRecording("grass") end, 12)
      button(KIND.seeker, 168, 84, 140, 26, C.off, function() Bot.startRecording("seeker") end, 12)
      button(T("heal_path"), 314, 84, 144, 26, C.off, function() Bot.startRecording("heal") end, 12)
      text(T("mark_here"), 22, 118, C.text, 12)
      button(KIND.fish, 22, 136, 140, 26, C.off, function() Bot.markFishingSpot() end, 12)
      button(KIND.scent, 168, 136, 140, 26, C.off, function() Bot.markSpot("scent") end, 12)
      button(KIND.seeker, 314, 136, 144, 26, C.off, function() Bot.markSpot("seeker") end, 12)
    end
    -- nearest first; "Nearby" keeps this map and the ones right next to it
    local list = Bot.sortedRoutes(routesNear)
    local pages = max(1, math.ceil(#list / ROUTES_PER_PAGE))
    routePage = max(1, min(pages, routePage))
    if #list == 0 and #Bot.routes > 0 then centred(T("no_routes_near"), 10, 230, 460, 40, C.muted, 12) end
    for row = 1, ROUTES_PER_PAGE do
      local route = list[(routePage - 1) * ROUTES_PER_PAGE + row]
      if route then
        local y = 182 + (row - 1) * 40
        local chosen = picked == route.name
        box(10, y, 460, 36, chosen and mix(C.card, C.accent, 0.22) or C.card, 8)
        if chosen then box(10, y + 6, 3, 24, C.accent, 2) end
        local nx = 20 + pill(KIND[route.kind], 20, y + 9, mix(C.card, KIND_COLOR[route.kind] or C.muted, 0.55), C.text, 10) + 8
        line(route.name, nx, y + 3, C.text, 13, 330 - nx)
        text(#route.points == 1 and T("point_one") or F("point_many", #route.points), nx, y + 20, C.muted, 10)
        local tx = 462
        if c.heal == route.name then tx = tx - 44; pill(T("pill_heal"), tx, y + 9, C.go, C.text, 10); tx = tx - 6 end
        if c.train == route.name then tx = tx - 52; pill(T("in_use"), tx, y + 9, C.accent, C.text, 10) end
        hit(10, y, 460, 36, function() picked = route.name end)
      end
    end
    local chosen = picked and Bot.route(picked)
    if chosen then
      if chosen.kind == "heal" then
        button(T("use_heal"), 10, 352, 220, 30, C.accent, function() c.heal = chosen.name save() end, 12)
      else
        button(T("use_route"), 10, 352, 220, 30, C.accent, function() c.train = chosen.name save() end)
      end
      button(T("delete"), 240, 352, 110, 30, C.stop, function() Bot.deleteRoute(chosen.name) picked = nil end)
    end
    if c.heal then
      button(T("auto_heal"), 10, 388, 220, 28, C.off, function() c.heal = nil save() end, 12)
    end
    button(T("routes_all"), 250, 390, 104, 24, not routesNear and C.accent or C.off, function() routesNear, routePage = false, 1 end, 11)
    button(T("routes_near"), 358, 390, 104, 24, routesNear and C.accent or C.off, function() routesNear, routePage = true, 1 end, 11)
    pager(470, 352, 30, routePage, pages, function(page) routePage = page end)
  end

  -- Species that can show up on this map, plus any already on the list.
  local function areaSpecies()
    local out, seen = {}, {}
    local h = Bot.host()
    local session = Bot.session()
    local function add(species)
      species = tonumber(species)
      if species and species > 0 and not seen[species] then
        seen[species] = true
        local ok, name = pcall(h.Pokemon.name, species)
        out[#out + 1] = { id = species, name = ok and name and tostring(name) or ("#" .. species) }
      end
    end
    if h and session then
      local map = Bot.position()
      local ok, game = pcall(function() return h.Field._game end)
      local data = ok and game and game.data and game.data.gen3Encounters and game.data.gen3Encounters[map]
      -- grass, water, rocks and every rod: whatever shape the tables have, each entry with a species counts
      local function collect(node, depth)
        if type(node) ~= "table" or depth > 5 then return end
        if node.species ~= nil then add(node.species) end
        for _, child in pairs(node) do collect(child, depth + 1) end
      end
      collect(data, 1)
      for species in pairs(Bot.config.species) do add(species) end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end
  local function drawStops()
    local c = Bot.config
    text(T("stop_when"), 12, 42, C.muted, 10)
    stepper(T("reach_level"), 10, 56, 460, c.stopLevel > 0 and c.stopLevel or T("no"),
      function() c.stopLevel = max(0, c.stopLevel - (c.stopLevel > 10 and 5 or 1)) save() end,
      function() c.stopLevel = min(100, c.stopLevel + (c.stopLevel >= 10 and 5 or 1)) save() end)
    toggle(T("shiny_appears"), 10, 84, 228, c.stopShiny, function() c.stopShiny = not c.stopShiny save() end)
    toggle(T("evolves"), 242, 84, 228, c.stopEvolve, function() c.stopEvolve = not c.stopEvolve save() end)
    toggle(T("learn_move"), 10, 112, 460, c.stopLearn, function() c.stopLearn = not c.stopLearn save() end)
    toggle(T("pp_out"), 10, 140, 460, c.stopNoPP, function() c.stopNoPP = not c.stopNoPP save() end)
    text(T("heal_head"), 12, 172, C.muted, 10)
    stepper(T("min_hp"), 10, 186, 460, c.hpPct .. "%",
      function() c.hpPct = max(0, c.hpPct - 5) save() end, function() c.hpPct = min(90, c.hpPct + 5) save() end)
    toggle(T("go_center"), 10, 214, 460, c.healOn, function() c.healOn = not c.healOn save() end)
    local LIMITS = { 0, 1, 2, 3, 5, 10, 20, 50, -1 }
    local function limit(label, x, key)
      local at = 1
      for index, value in ipairs(LIMITS) do if value == c[key] then at = index end end
      stepper(label, x, 242, 228, c[key] == -1 and T("no_limit") or (c[key] == 0 and T("no") or c[key]),
        function() c[key] = LIMITS[max(1, at - 1)] save() end, function() c[key] = LIMITS[min(#LIMITS, at + 1)] save() end)
    end
    limit(T("use_potions"), 10, "itemHp")
    limit(T("use_ethers"), 242, "itemPp")
    text(T("on_the_way"), 12, 274, C.muted, 10)
    toggle(T("flee_travel"), 10, 288, 460, c.travelRun, function() c.travelRun = not c.travelRun save() end)
    text(T("stop_if"), 12, 320, C.muted, 10)
    local list = areaSpecies()
    local per = 6
    local pages = max(1, math.ceil(#list / per))
    speciesPage = max(1, min(pages, speciesPage))
    if #list == 0 then text(T("no_wild_map"), 12, 338, C.muted, 12) end
    for index = 1, per do
      local entry = list[(speciesPage - 1) * per + index]
      if entry then
        local x, y = 10 + ((index - 1) % 3) * 154, 334 + floor((index - 1) / 3) * 28
        local on = c.species[entry.id] == true
        button("      " .. nameCase(entry.name), x, y, 150, 24, on and C.accent or C.off, function()
          c.species[entry.id] = (not on) or nil
          save()
        end, 12)
        speciesIcon(entry.id, x + 2, y, 24)
      end
    end
    button(T("start_training"), 10, 398, 350, 28, C.go, function()
      -- started or not, the Control tab says what happened
      Bot.start("train")
      tab = "control"
    end, 14)
    pager(470, 398, 28, speciesPage, pages, function(page) speciesPage = page end)
  end

  -- Two crossed swords in a round button: green when that Pokémon fights.
  function fightIcon(cx, cy, on)
    local r = 13 * kf
    local px, py = ox + cx * kx, oy + cy * ky
    color(on and C.go or C.off)
    G.circle("fill", px, py, r)
    color(on and C.text or C.muted)
    G.setLineWidth(max(2, 2.2 * kf))
    local a = r * 0.6
    for side = -1, 1, 2 do
      -- the blade, from the hilt at one bottom corner to the tip at the opposite top corner
      local hx, hy, tx, ty = px - side * a, py + a, px + side * a, py - a
      G.line(hx, hy, tx, ty)
      -- the crossguard, across the blade near the hilt
      local gx, gy = hx + (tx - hx) * 0.22, hy + (ty - hy) * 0.22
      local g = r * 0.3
      G.line(gx - g, gy - side * g, gx + g, gy + side * g)
    end
    G.setLineWidth(1)
  end
  local evSlot
  local function drawEv()
    local c = Bot.config
    local session, h = Bot.session(), Bot.host()
    local mon = session and session.party and session.party[evSlot]
    if not (mon and h) then evSlot = nil return end
    local who = tostring(mon.personality or 0)
    local t = c.evTargets[who] or {}
    local evs = Bot.evsOf(mon)
    box(10, 44, 460, 58, C.card, 8)
    local okPic, pic = pcall(h.Pokemon.monIcon, mon)
    if okPic then sprite(pic, 16, 50, 46) end
    line(F("ev_title", monName(mon)), 70, 50, C.text, 15, 390)
    local total, wanted = 0, 0
    for _, key in ipairs(Bot.EV_KEYS) do total, wanted = total + (tonumber(evs[key]) or 0), wanted + (t[key] or 0) end
    line(F("ev_total", total, wanted), 70, 74, wanted > 510 and C.warn or C.muted, 11, 390)
    text(T("ev_head"), 12, 108, C.muted, 10)
    for index, key in ipairs(Bot.EV_KEYS) do
      local x, y = 10 + ((index - 1) % 2) * 232, 122 + floor((index - 1) / 2) * 30
      local value = t[key] or 0
      local function set(n)
        c.evTargets[who] = c.evTargets[who] or {}
        c.evTargets[who][key] = max(0, min(252, n))
        save()
      end
      stepper(EV_NAMES[key] .. " · " .. (tonumber(evs[key]) or 0), x, y, 228, value > 0 and value or T("no"),
        function() set(value - 4) end, function() set(value + 4) end)
      hit(x + 228 - 84, y, 54, 26, function() set(value >= 252 and 0 or 252) end)
    end
    -- what this map gives, and what the bot will do about it
    text(T("on_this_map"), 12, 218, C.muted, 10)
    local list = areaSpecies()
    if #list == 0 then text(T("no_wild_here"), 12, 234, C.muted, 11) end
    for index = 1, min(8, #list) do
      local entry = list[index]
      local x, y = 10 + ((index - 1) % 2) * 232, 232 + floor((index - 1) / 2) * 28
      local okYield, yield = pcall(h.Pokemon.evYield, entry.id)
      local parts = {}
      for _, key in ipairs(Bot.EV_KEYS) do
        local n = okYield and type(yield) == "table" and tonumber(yield[key]) or 0
        if n > 0 then parts[#parts + 1] = "+" .. n .. " " .. EV_NAMES[key] end
      end
      local flee = Bot.evTarget(mon) ~= nil and Bot.evWasted(mon, entry.id)
      box(x, y, 228, 24, C.card, 6)
      speciesIcon(entry.id, x + 2, y, 24)
      line(nameCase(entry.name), x + 30, y + 5, C.text, 11, 86)
      line(#parts > 0 and table.concat(parts, " ") or T("no_ev"), x + 118, y + 6, flee and C.stop or C.go, 10, 104, "right")
    end
    line(T("ev_legend"), 12, 348, C.muted, 10, 456)
    button(T("back"), 10, 372, 226, 32, C.off, function() evSlot = nil end)
    button(T("clear_targets"), 244, 372, 226, 32, C.off, function() c.evTargets[who] = nil save() end)
    line(T("ev_where"), 12, 412, C.muted, 10, 456)
  end
  local function drawTeam()
    if evSlot then return drawEv() end
    local c = Bot.config
    line(T("team_hint"), 12, 43, C.muted, 11, 456)
    local session, h = Bot.session(), Bot.host()
    local party = session and session.party or {}
    for slot = 1, 6 do
      local mon = party[slot]
      local y = 62 + (slot - 1) * 58
      if mon and h then
        local on = c.selected[slot] == true
        local egg = Bot.isEgg(mon)
        local hp, maxHp = tonumber(mon.hp) or 0, max(1, tonumber(mon.maxHp) or 1)
        local fainted = not egg and hp <= 0
        box(10, y, 460, 54, on and mix(C.card, C.accent, 0.10) or C.card, 8)
        if on then box(10, y + 8, 3, 38, C.accent, 2) end
        -- its picture, in a round frame
        local radius = 22 * min(kx, ky)
        color(C.off)
        G.circle("fill", ox + 40 * kx, oy + (y + 27) * ky, radius)
        local okPic, pic = pcall(h.Pokemon.monIcon, mon)
        if okPic then sprite(pic, 18, y + 5, 44, fainted or not on) end
        local ok, name = pcall(function()
          if egg then return T("egg") end
          return (mon.nickname and mon.nickname ~= "" and mon.nickname) or h.Pokemon.name(h.Pokemon.speciesOf(mon))
        end)
        line(ok and nameCase(name) or "?", 70, y + 4, on and C.text or C.muted, 14, 108)
        if not egg then
          -- EV targets: blue when this one has some
          button("EV", 182, y + 5, 30, 18, Bot.evTarget(mon) and C.accent or C.off, function() evSlot = slot end, 10, 9)
        end
        if not egg then
          text(F("level_short", tostring(mon.level or "?")), 222, y + 6, C.muted, 12)
          -- HP as a bar: green, amber, red
          local ratio = max(0, min(1, hp / maxHp))
          box(266, y + 10, 76, 7, C.line, 4)
          if ratio > 0 then box(266, y + 10, max(4, 76 * ratio), 7, ratio > 0.5 and C.go or ratio > 0.2 and C.warn or C.stop, 4) end
          line(hp .. "/" .. maxHp, 346, y + 6, C.muted, 10, 54, "right")
          -- fights or stays out: crossed swords, green when it fights
          fightIcon(446, y + 14, on)
          hit(428, y + 1, 36, 27, function()
            c.selected[slot] = (not on) or nil
            save()
          end)
          for index = 1, 4 do
            local id = type(mon.moves) == "table" and mon.moves[index]
            if type(id) == "table" then id = id.id end
            local mx = 70 + (index - 1) * 99
            if id and id ~= 0 and id ~= "" then
              local okName, label = pcall(h.Moves.displayName, id)
              local def = select(2, pcall(h.Moves.get, id))
              local hurts = type(def) == "table" and (tonumber(def.power) or 0) > 0
              local key = Bot.moveKey(mon, id)
              local banned = c.banned[key] == true
              local pp = type(mon.pp) == "table" and mon.pp[index] or "?"
              local tint = type(def) == "table" and typeColor(h, def.type) or C.muted
              -- the move in its type's colour; a forbidden one turns red, one without damage stays grey
              local usable = on and hurts and not banned
              local fill = (banned and on and mix(C.card, C.stop, 0.45)) or (usable and mix(C.card, tint, 0.38)) or C.off
              box(mx, y + 29, 95, 20, fill, 5)
              box(mx + 3, y + 33, 3, 12, (banned and on and C.stop) or (hurts and tint) or C.line, 2)
              line(tostring(pp), mx + 73, y + 32, usable and C.text or C.muted, 10, 18, "right")
              line(okName and nameCase(label) or tostring(id), mx + 10, y + 32, usable and C.text or C.muted, 10, 62)
              if on and hurts then hit(mx, y + 29, 95, 20, function() c.banned[key] = (not banned) or nil save() end) end
            else
              box(mx, y + 29, 95, 20, C.off, 5)
            end
          end
        end
      else
        box(10, y, 460, 54, C.card, 8)
        text(T("empty_slot"), 20, y + 18, C.line, 13)
      end
    end
    line(T("team_legend"), 12, 414, C.muted, 11, 456)
  end

  ---------------------------------------------------------------------------
  -- Hunting: the list of targets, and the editor for one of them
  ---------------------------------------------------------------------------
  local STATS = { { "hp" }, { "atk" }, { "def" }, { "spa" }, { "spd" }, { "spe" } }
  for _, stat in ipairs(STATS) do setmetatable(stat, { __index = function(_, k) if k == 2 then return EV_NAMES[stat[1]] end end }) end
  local NATURES = setmetatable({}, { __index = function(_, n) return T("natures")[n] end })
  local HP_TYPES = setmetatable({}, { __index = function(_, n) return T("hp_types")[n] end })
  local editing, editIndex, huntPage, editPage
  local targetPage, nameEditing = 1, false
  -- Fills in what a target saved by an older version does not have.
  local function normalize(t)
    t.levelMin, t.levelMax = t.levelMin or 0, t.levelMax or 0
    t.hpType, t.hpPower, t.item = t.hpType or -1, t.hpPower or 0, t.item == true
    t.natures = t.natures or {}
    if (t.nature or -1) >= 0 then t.natures[t.nature] = true end
    t.nature = nil
    return t
  end
  local function clone(t)
    local copy = {}
    for key, value in pairs(t) do
      if type(value) == "table" then
        copy[key] = {}
        for k, v in pairs(value) do copy[key][k] = v end
      else
        copy[key] = value
      end
    end
    return normalize(copy)
  end
  function speciesName(id)
    local h = Bot.host()
    local ok, name = pcall(function() return h.Pokemon.name(id) end)
    return ok and name and nameCase(name) or ("#" .. tostring(id))
  end
  local function abilityName(id)
    if id == 0 then return T("any_ability") end
    local h = Bot.host()
    local ok, name = pcall(function() return h.Pokemon.abilityName(id) end)
    return ok and name and tostring(name) or ("#" .. tostring(id))
  end
  -- bare: only the filters, without the species in front
  local function describe(t, bare)
    local parts = { not bare and (t.species ~= 0 and speciesName(t.species) or T("any")) or nil }
    if t.gender ~= "any" then parts[#parts + 1] = t.gender == "F" and T("female") or T("male") end
    if t.ivTotal > 0 then parts[#parts + 1] = "IV>=" .. t.ivTotal end
    for _, stat in ipairs(STATS) do
      if (t.ivs[stat[1]] or 0) > 0 then parts[#parts + 1] = stat[2] .. ">=" .. t.ivs[stat[1]] end
    end
    if t.ability ~= 0 then parts[#parts + 1] = abilityName(t.ability) end
    local natures = {}
    for nature = 0, 24 do if t.natures and t.natures[nature] then natures[#natures + 1] = NATURES[nature] end end
    if #natures > 0 then parts[#parts + 1] = table.concat(natures, "/") end
    if (t.levelMin or 0) > 0 or (t.levelMax or 0) > 0 then
      parts[#parts + 1] = F("level_short", ((t.levelMin or 0) > 0 and t.levelMin or 1) .. "-" .. ((t.levelMax or 0) > 0 and t.levelMax or 100))
    end
    if (t.hpType or -1) >= 0 then parts[#parts + 1] = F("hp_type_short", HP_TYPES[t.hpType]) end
    if (t.hpPower or 0) > 0 then parts[#parts + 1] = F("hp_power_short", t.hpPower) end
    if t.item then parts[#parts + 1] = T("with_item") end
    if t.shiny then parts[#parts + 1] = T("shiny_caps") end
    return table.concat(parts, "  ")
  end
  -- A row of choices where one is picked: blue for the picked one.
  local function choices(list, x, y, w, h, current, set, size)
    local each = (w - (#list - 1) * 4) / #list
    for index, entry in ipairs(list) do
      local bx = x + (index - 1) * (each + 4)
      local on = entry[1] == current
      button(entry[2], bx, y, each, h, on and C.accent or C.off, function() set(entry[1]) end, size or 12)
    end
  end
  local function heading(label, x, y) text(label, x, y, C.muted, 10) end
  local function saveTarget(t)
    nameEditing = false
    t.name = Bot.cleanName(t.name)
    if t.name == "" then t.name = nil end
    if editIndex then Bot.config.targets[editIndex] = t else table.insert(Bot.config.targets, t) end
    editing, editIndex = nil, nil
    save()
  end
  -- The top of both editor pages: the target as it stands, and the two pages.
  local function editorHeader(t)
    box(10, 44, 460, 54, C.card, 8)
    if t.species ~= 0 then
      speciesIcon(t.species, 14, 47, 46)
    else
      color(C.off)
      G.circle("fill", ox + 37 * kx, oy + 71 * ky, 20 * min(kx, ky))
      centred("?", 17, 51, 40, 40, C.muted, 18)
    end
    -- the title is the target's name: a touch on it lets you type one
    local named = t.name and t.name ~= ""
    if nameEditing then
      box(62, 46, 228, 24, C.off, 6)
      local blink = floor(love.timer.getTime() * 2) % 2 == 0 and "|" or ""
      line((t.name or "") .. blink, 68, 49, C.text, 15, 216)
      line(T("type_name"), 66, 74, C.accent, 10, 222)
    else
      line(named and t.name or (t.species ~= 0 and speciesName(t.species) or T("any_species")), 66, 49, C.text, 15, 222)
      local filters = describe(t, not named)
      line((filters ~= "" and filters or T("no_filters")) .. T("tap_title"), 66, 74, C.muted, 10, 222)
    end
    hit(62, 46, 228, 24, function() nameEditing = not nameEditing end)
    choices({ { 1, T("page_basic") }, { 2, T("page_more") } }, 294, 58, 168, 26, editPage, function(page) editPage = page end, 11)
  end
  local function editorFooter(t)
    button(T("save_target"), 10, 384, 226, 30, C.go, function() saveTarget(t) end, 13)
    button(T("cancel"), 244, 384, 226, 30, C.off, function() editing, editIndex, nameEditing = nil, nil, false end, 13)
  end
  -- The editor's second page: natures, level, Hidden Power, held item.
  local function drawEditorMore(t)
    heading(T("nature_head"), 12, 104)
    for nature = 0, 24 do
      local x, y = 10 + (nature % 5) * 93, 118 + floor(nature / 5) * 23
      local on = t.natures[nature] == true
      button(NATURES[nature], x, y, 89, 20, on and C.accent or C.off, function() t.natures[nature] = (not on) or nil end, 11, 10)
    end
    heading(T("level_head"), 12, 238)
    stepper(T("minimum"), 10, 252, 228, t.levelMin > 0 and t.levelMin or "-",
      function() t.levelMin = max(0, t.levelMin - 1) end, function() t.levelMin = min(100, t.levelMin + 1) end)
    stepper(T("maximum"), 242, 252, 228, t.levelMax > 0 and t.levelMax or "-",
      function() t.levelMax = max(0, t.levelMax - 1) end, function() t.levelMax = min(100, t.levelMax + 1) end)
    heading(T("hidden_power"), 12, 284)
    stepper(T("hp_type"), 10, 298, 228, t.hpType < 0 and T("hp_all") or HP_TYPES[t.hpType],
      function() t.hpType = (t.hpType + 1 - 1 + 17) % 17 - 1 end, function() t.hpType = (t.hpType + 1 + 1) % 17 - 1 end)
    stepper(T("hp_power"), 242, 298, 228, t.hpPower > 0 and t.hpPower or "-",
      function() t.hpPower = t.hpPower <= 30 and 0 or t.hpPower - 5 end,
      function() t.hpPower = t.hpPower == 0 and 30 or min(70, t.hpPower + 5) end)
    heading(T("item_head"), 12, 330)
    toggle(T("only_item"), 10, 344, 460, t.item, function() t.item = not t.item end)
    editorFooter(t)
  end
  local function drawEditor()
    local t = normalize(editing)
    editorHeader(t)
    if editPage == 2 then return drawEditorMore(t) end
    local list = areaSpecies()
    local per = 6
    local pages = max(1, math.ceil(#list / per))
    huntPage = max(1, min(pages, huntPage or 1))
    heading(T("species_head"), 12, 104)
    pager(470, 100, 18, huntPage, pages, function(page) huntPage = page end)
    if #list == 0 then text(T("no_wild_map"), 12, 124, C.muted, 11) end
    for index = 1, per do
      local entry = list[(huntPage - 1) * per + index]
      if entry then
        local x, y = 10 + ((index - 1) % 3) * 154, 120 + floor((index - 1) / 3) * 28
        button("      " .. nameCase(entry.name), x, y, 150, 24, t.species == entry.id and C.accent or C.off, function()
          -- a second touch on the chosen one goes back to "any species"
          t.species, t.ability = t.species ~= entry.id and entry.id or 0, 0
        end, 12)
        speciesIcon(entry.id, x + 2, y, 24)
      end
    end
    heading(T("gender_head"), 12, 178)
    choices({ { "any", T("any") }, { "M", T("gender_male") }, { "F", T("gender_female") } }, 10, 192, 228, 24, t.gender,
      function(value) t.gender = value end, 11)
    heading(T("ability_head"), 244, 178)
    button(nameCase(abilityName(t.ability)), 242, 192, 228, 24, t.ability ~= 0 and C.accent or C.off, function()
      local h = Bot.host()
      local options = { 0 }
      local ok, found = pcall(function() return h.Pokemon.abilities(t.species) end)
      for _, id in ipairs(ok and type(found) == "table" and found or {}) do
        id = tonumber(id)
        local known = false
        for _, have in ipairs(options) do if have == id then known = true end end
        if id and id ~= 0 and not known then options[#options + 1] = id end
      end
      local at = 1
      for index, id in ipairs(options) do if id == t.ability then at = index end end
      t.ability = options[at % #options + 1]
    end, 11)
    heading(T("ivs_head"), 12, 224)
    stepper(T("iv_sum"), 10, 238, 460, t.ivTotal > 0 and t.ivTotal or "-",
      function() t.ivTotal = max(0, t.ivTotal - 5) end, function() t.ivTotal = min(186, t.ivTotal + 5) end)
    for index, stat in ipairs(STATS) do
      local x, y = 10 + ((index - 1) % 2) * 232, 268 + floor((index - 1) / 2) * 28
      local key = stat[1]
      stepper(stat[2], x, y, 228, t.ivs[key] > 0 and t.ivs[key] or "-",
        function() t.ivs[key] = max(0, t.ivs[key] - 1) end, function() t.ivs[key] = min(31, t.ivs[key] + 1) end)
      hit(x + 228 - 84, y, 54, 26, function()
        local jumps, nextValue = { 0, 20, 25, 30, 31 }, 0
        for _, value in ipairs(jumps) do if value > t.ivs[key] then nextValue = value break end end
        t.ivs[key] = nextValue
      end)
    end
    toggle(T("only_shiny"), 10, 352, 460, t.shiny == true, function() t.shiny = not t.shiny end)
    editorFooter(t)
  end
  local huntView
  local ORDERS = { "2,3,4", "4,3,2", "3,2,4", "3,4,2", "2,4,3", "4,2,3" }
  local BALLS = setmetatable({}, { __index = function(_, id) return T("balls")[id] end })
  local function orderLabel(order)
    local names = {}
    for id in order:gmatch("%d+") do names[#names + 1] = BALLS[tonumber(id)] or ("#" .. id) end
    return table.concat(names, " > ")
  end
  local function drawCatch()
    local c = Bot.config
    local function row(y, label, key, x, w)
      toggle(label, x or 10, y, w or 460, c[key], function() c[key] = not c[key] save() end)
    end
    heading(T("catch_head"), 12, 42)
    row(56, T("catch_on"), "huntCatch")
    row(84, T("catch_continue"), "catchContinue")
    row(112, T("catch_heal"), "catchHeal")
    heading(T("before_ball"), 12, 144)
    row(158, T("weaken"), "catchWeaken")
    row(186, T("false_swipe"), "catchFalseSwipe")
    row(214, T("status_move"), "catchStatus")
    heading(T("balls_head"), 12, 246)
    button(F("order", orderLabel(c.ballOrder)), 10, 260, 290, 26, C.off, function()
      local at = 1
      for index, order in ipairs(ORDERS) do if order == c.ballOrder then at = index end end
      c.ballOrder = ORDERS[at % #ORDERS + 1]
      save()
    end, 12)
    row(260, T("master_ball"), "useMaster", 304, 166)
    local x = 12
    local any = false
    for _, id in ipairs({ 1, 2, 3, 4 }) do
      if Bot.session() and Bot.host() and Bot.hasItem(id) then
        x = x + pill(BALLS[id], x, 290, C.off, C.text, 10) + 4
        any = true
      end
    end
    line(any and T("in_bag") or T("no_balls_bag"), any and x + 4 or 12, 291, any and C.muted or C.warn, 10, 300)
    heading(T("safari_head"), 12, 314)
    local money = Bot.session() and Bot.money()
    if money then
      line(F("money_entries", money, floor(money / Bot.SAFARI_PRICE)), 200, 314, C.muted, 10, 270, "right")
    end
    stepper(T("baits"), 10, 328, 228, c.safariBaits,
      function() c.safariBaits = max(0, c.safariBaits - 1) save() end, function() c.safariBaits = min(5, c.safariBaits + 1) save() end)
    stepper(T("then_balls"), 242, 328, 228, c.safariBalls,
      function() c.safariBalls = max(1, c.safariBalls - 1) save() end, function() c.safariBalls = min(9, c.safariBalls + 1) save() end)
    local RE = { 0, 1, 2, 3, 5, 10, 20, 50, -1 }
    local at = 1
    for index, value in ipairs(RE) do if value == c.safariReentries then at = index end end
    stepper(T("reenter"), 10, 356, 460,
      c.safariReentries == -1 and T("always") or (c.safariReentries == 0 and T("no") or (c.safariReentries .. "x")),
      function() c.safariReentries = RE[max(1, at - 1)] save() end, function() c.safariReentries = RE[min(#RE, at + 1)] save() end)
    button(T("back"), 10, 392, 226, 28, C.off, function() huntView = nil end, 13)
  end
  local function drawReset()
    local c = Bot.config
    box(10, 44, 460, 50, C.card, 8)
    text(T("reset_title"), 22, 49, C.text, 15)
    line(T("reset_sub"), 22, 72, C.muted, 10, 436)
    heading(T("how_it_works"), 12, 100)
    local steps = {
      T("reset_step1"), T("reset_step2"), T("reset_step3"),
    }
    for index, step in ipairs(steps) do
      local y = 114 + (index - 1) * 26
      box(10, y, 460, 22, C.card, 6)
      color(C.accent)
      G.circle("fill", ox + 23 * kx, oy + (y + 11) * ky, 8 * kf)
      centred(index, 15, y, 16, 22, C.text, 10)
      line(step, 38, y + 4, C.text, 11, 426)
    end
    -- the one thing that can cost the player: the save lock
    box(10, 196, 460, 40, mix(C.card, C.warn, 0.45), 8)
    box(15, 202, 3, 28, C.warn, 2)
    line(T("lock1"), 26, 200, C.text, 11, 436)
    line(T("lock2"), 26, 217, C.text, 11, 436)
    heading(T("when_target"), 12, 244)
    toggle(T("try_catch"), 10, 258, 460, c.resetCatch, function() c.resetCatch = not c.resetCatch save() end)
    if c.resetCatch then
      line(T("reset_catch1"), 12, 288, C.muted, 10, 456)
      line(T("reset_catch2"), 12, 302, C.muted, 10, 456)
    else
      line(T("reset_nocatch"), 12, 288, C.muted, 10, 456)
    end
    heading(T("uses_hunt_tab"), 12, 322)
    local x = 12
    x = x + pill(#c.targets == 1 and T("target_one") or F("target_many", #c.targets), x, 336, #c.targets > 0 and C.accent or C.off, C.text, 10) + 4
    pill(c.huntShiny and T("any_shiny_yes") or T("any_shiny_no"), x, 336, c.huntShiny and C.accent or C.off, C.text, 10)
    button(T("back"), 10, 372, 226, 32, C.off, function() huntView = nil end)
    button(T("save_start"), 244, 372, 226, 32, C.go, function()
      if Bot.start("reset") then tab = "control" huntView = nil end
    end, 13)
    if Bot.reason == "no_targets" then
      line(T("reset_need"), 12, 412, C.warn, 11, 456)
    elseif Bot.reason == "no_save" or Bot.reason == "no_game" then
      line(REASONS[Bot.reason], 12, 412, C.warn, 11, 456)
    end
  end
  local function drawHunt()
    if editing then return drawEditor() end
    if huntView == "catch" then return drawCatch() end
    if huntView == "reset" then return drawReset() end
    local c = Bot.config
    toggle(T("hunt_shiny"), 10, 44, 460, c.huntShiny, function() c.huntShiny = not c.huntShiny save() end)
    toggle(T("hunt_exp"), 10, 74, 460, c.huntExp, function() c.huntExp = not c.huntExp save() end)
    toggle(T("hunt_scent"), 10, 104, 460, c.huntScent, function() c.huntScent = not c.huntScent save() end)
    local perPage = 5
    local pages = max(1, math.ceil(#c.targets / perPage))
    targetPage = max(1, min(pages, targetPage))
    text(F("targets_head", #c.targets, Bot.MAX_TARGETS), 12, 134, C.muted, 10)
    pager(470, 130, 18, targetPage, pages, function(page) targetPage = page end)
    if #c.targets == 0 then
      box(10, 150, 460, 76, C.card, 8)
      centred(T("no_targets_yet"), 10, 162, 460, 20, C.text, 14)
      centred(T("targets_how"), 10, 186, 460, 16, C.muted, 11)
      centred(T("targets_reset"), 10, 202, 460, 16, C.muted, 11)
    end
    for row = 1, perPage do
      local index = (targetPage - 1) * perPage + row
      local t = c.targets[index]
      if t then
        local y = 150 + (row - 1) * 40
        box(10, y, 460, 36, C.card, 8)
        local shown = normalize(t)
        if shown.species ~= 0 then speciesIcon(shown.species, 14, y + 2, 32) end
        local any = shown.species == 0
        -- its name when it has one, else the species
        local title = (shown.name and shown.name ~= "") and shown.name or (any and T("any_species") or speciesName(shown.species))
        line(title, any and 20 or 52, y + 2, C.text, 13, any and 328 or 296)
        -- the filters; the species is already the title (or named next to it)
        local filters = describe(shown, not (shown.name and shown.name ~= "" and not any))
        line(filters ~= "" and filters or T("no_filters"), any and 20 or 52, y + 20, C.muted, 10, any and 328 or 296)
        button(T("edit"), 356, y + 5, 64, 26, C.off, function()
          editIndex, editing, editPage = index, clone(t), 1
        end, 11)
        button("x", 426, y + 5, 36, 26, C.stop, function() table.remove(c.targets, index) save() end, 12)
      end
    end
    if #c.targets < Bot.MAX_TARGETS then
      button(T("new_target"), 10, 352, 226, 32, C.off, function()
        editPage = 1
        editIndex, editing = nil, { species = 0, gender = "any", ivTotal = 0, ability = 0, shiny = false,
          ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } }
      end)
    end
    button(T("start_hunt"), 244, 352, 226, 32, C.go, function()
      if Bot.start("hunt") then tab = "control" end
    end, 14)
    button(F("catch_state", c.huntCatch and T("on_caps") or T("off_low")), 10, 388, 296, 24,
      C.off, function() huntView = "catch" end, 11)
    button(T("reset_btn"), 312, 388, 158, 24, C.off, function() huntView = "reset" end, 12)
    if Bot.reason == "no_targets" or Bot.reason == "no_route" or Bot.reason == "repel_on" or Bot.reason == "pc_full" then
      line(REASONS[Bot.reason], 12, 415, C.warn, 11, 456)
    end
  end

  local TABS = { { "control" }, { "routes" }, { "team" }, { "stops" }, { "hunt" } }
  function Panel.draw(_, w, h)
    hits = {}
    w, h = tonumber(w) or Panel.W, tonumber(h) or Panel.H
    -- stretch to the room, within reason: below 0.7 the text would not be readable
    kx, ky = max(0.7, min(2.4, w / Panel.W)), max(0.7, min(2.4, h / Panel.H))
    kf = max(0.8, min(1.5, min(kx, ky)))
    ox, oy = max(0, floor((w - Panel.W * kx) / 2)), max(0, floor((h - Panel.H * ky) / 2))
    G.push("all")
    G.setLineStyle("smooth")
    color(C.bg)
    G.rectangle("fill", 0, 0, w, h)
    for index, entry in ipairs(TABS) do
      local x = 10 + (index - 1) * 93
      local current = tab == entry[1]
      button(T("tabs")[entry[1]], x, 8, 90, 28, current and C.accent or C.card, function() tab = entry[1] end, 12, 14)
    end
    local ok, err = pcall(tab == "routes" and drawRoutes or tab == "stops" and drawStops or tab == "team" and drawTeam
      or tab == "hunt" and drawHunt or drawControl)
    Panel.lastError = (not ok) and tostring(err) or nil
    if not ok then text(F("panel_error", tostring(err)), 12, 60, C.warn, 12, 456) end
    G.pop()
  end
  -- While a target's name is being typed, the keyboard belongs to the panel.
  function Panel.wantsKeys() return nameEditing and editing ~= nil end
  function Panel.key(key)
    if not Panel.wantsKeys() then return false end
    local name = editing.name or ""
    if key == "return" or key == "kpenter" then nameEditing = false
    elseif key == "escape" then editing.name, nameEditing = nil, false
    elseif key == "backspace" then
      editing.name = name:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
    elseif key == "space" then
      if #name > 0 and #name < 20 then editing.name = name .. " " end
    elseif #key == 1 and key:match("[%w]") and #name < 20 then
      local shift = love.keyboard and love.keyboard.isDown and love.keyboard.isDown("lshift", "rshift")
      editing.name = name .. ((shift or #name == 0) and key:upper() or key)
    end
    return true
  end
  function Panel.pointer(action, x, y, amount)
    if action == "wheel" then
      -- the wheel turns the pages of whatever list is on screen (each draw keeps them in range)
      local step = (tonumber(amount) or 0) > 0 and -1 or 1
      if tab == "routes" then routePage = routePage + step
      elseif tab == "stops" then speciesPage = speciesPage + step
      elseif tab == "hunt" then huntPage = (huntPage or 1) + step end
      return
    end
    if action ~= "down" then return end
    for index = #hits, 1, -1 do
      local at = hits[index]
      if x >= at.x and x < at.x + at.w and y >= at.y and y < at.y + at.h then
        at.action()
        return
      end
    end
  end
  return Panel
end
