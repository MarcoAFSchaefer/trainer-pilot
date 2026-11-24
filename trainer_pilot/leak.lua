-- leak.lua: a one-off look at what grows between reloads of a reset hunt.
--
-- The hunt's own record (log/perf) showed Lua memory climbing by about 0.1 MB
-- per attempt. At attempts 60 and 160 this writes to log/leak:
--   * how many of the sessions seen so far are still alive after a full
--     collection (cheap: a weak table is counted);
--   * a walk over the tables reachable from the game object and from the
--     engine modules that are always loaded, with the places (root.key) that
--     grew the most, and the way to an old session if one is reached.
-- The walk is bounded: it gives up after 3 seconds or 2 million tables and
-- says so. Only tables are followed: what hides in a function's upvalues is
-- out of reach from a mod and shows up as "no path found".
return function(mod, rootsOf)
  local Leak = {}
  -- modules the game itself requires at start: asking for them loads nothing new
  local MODULES = { "src.core.SaveData", "src.core.Input", "src.core.game3.runtime", "src.core.game3.audio",
    "src.core.game3.options", "src.core.game3.dataset", "src.core.game3.display", "src.ui.game3.help_system",
    "src.ui.game3.quest_log", "src.core.game3.quest_log_recorder", "src.core.game3.field_modules", "src.mods.Runtime",
    "src.core.game3.profile", "src.core.game3.warm" }
  local sessions = setmetatable({}, { __mode = "k" })
  local seenCount = 0
  function Leak.note(session)
    if type(session) == "table" and not sessions[session] then
      seenCount = seenCount + 1
      sessions[session] = seenCount
    end
  end
  local function write(text, fresh)
    if not (mod.cache and mod.cache.write) then return end
    local old = (not fresh and mod.cache.read and mod.cache:read("log/leak")) or ""
    mod.cache:write("log/leak", old .. text .. "\n")
  end

  local function roots(game)
    local list = { { "game", game } }
    for _, name in ipairs(MODULES) do
      local ok, m = pcall(require, name)
      if ok and type(m) == "table" then list[#list + 1] = { (name:gsub("^src%.", "")), m } end
    end
    for name, value in pairs(rootsOf() or {}) do
      if type(value) == "table" then list[#list + 1] = { name, value } end
    end
    return list
  end

  local function census(game, current)
    local visited, parentOf, keyOf, bucket, counts = {}, {}, {}, {}, {}
    visited[sessions] = true
    local found, total, gaveUp = nil, 0, nil
    local started = love.timer.getTime()
    local all = roots(game)
    for _, root in ipairs(all) do
      local rootName, rootTable = root[1], root[2]
      if not visited[rootTable] and not gaveUp then
        visited[rootTable] = true
        bucket[rootTable] = rootName
        local queue, head = { rootTable }, 1
        while queue[head] do
          local t = queue[head]; queue[head] = nil; head = head + 1
          local where = bucket[t]
          bucket[t] = nil
          counts[where] = (counts[where] or 0) + 1
          total = total + 1
          if total % 20000 == 0 and (love.timer.getTime() - started > 3 or total >= 2000000) then
            gaveUp = string.format("stopped after %d tables, %.1f s (in %s)", total, love.timer.getTime() - started, where)
            break
          end
          local top = t == rootTable
          for k, v in next, t do
            if type(v) == "table" and not visited[v] then
              visited[v] = true
              parentOf[v], keyOf[v] = t, k
              bucket[v] = top and (rootName .. "." .. tostring(k)) or where
              queue[#queue + 1] = v
              if not found and sessions[v] and v ~= current then found = v end
            end
          end
          local mt = getmetatable(t)
          if type(mt) == "table" and not visited[mt] then
            visited[mt] = true
            parentOf[mt], keyOf[mt] = t, "<metatable>"
            bucket[mt] = where
            queue[#queue + 1] = mt
          end
        end
      end
    end
    local path
    if found then
      local parts, at = {}, found
      for _ = 1, 40 do
        if not parentOf[at] then break end
        table.insert(parts, 1, tostring(keyOf[at]))
        at = parentOf[at]
      end
      path = table.concat(parts, " > ")
      for _, root in ipairs(all) do if root[2] == at then path = root[1] .. " > " .. path end end
    end
    return counts, path, total, gaveUp
  end

  local before
  function Leak.sample(game, current, resets)
    collectgarbage("collect"); collectgarbage("collect")
    local alive = 0
    for s in pairs(sessions) do if s ~= current then alive = alive + 1 end end
    -- written before the walk: if the walk goes wrong, this much is known
    write(string.format("== attempt %d: %d sessions seen, %d old ones still alive, Lua %.1f MB",
      resets, seenCount, alive, collectgarbage("count") / 1024), resets <= 60)
    local counts, path, total, gaveUp = census(game, current)
    local lines = { "path to an old session: " .. (path or "no path found through tables"),
      "tables reached: " .. total .. (gaveUp and (" (" .. gaveUp .. ")") or "") }
    if before then
      local grown = {}
      for where, n in pairs(counts) do
        local d = n - (before[where] or 0)
        if d > 20 then grown[#grown + 1] = { where, d, n } end
      end
      table.sort(grown, function(a, b) return a[2] > b[2] end)
      for i = 1, math.min(25, #grown) do
        lines[#lines + 1] = string.format("  +%d tables (now %d)  %s", grown[i][2], grown[i][3], grown[i][1])
      end
      if #grown == 0 then lines[#lines + 1] = "  nothing reachable through tables grew" end
    else
      local big = {}
      for where, n in pairs(counts) do big[#big + 1] = { where, n } end
      table.sort(big, function(a, b) return a[2] > b[2] end)
      for i = 1, math.min(15, #big) do lines[#lines + 1] = string.format("  %d tables  %s", big[i][2], big[i][1]) end
    end
    before = counts
    write(table.concat(lines, "\n"))
    return lines
  end
  return Leak
end
