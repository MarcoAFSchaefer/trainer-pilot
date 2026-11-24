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
  -- (worked out from the engine's source: everything Game3 and the field require at load time)
  local MODULES = { "src.carts.CartManifest", "src.carts.CartStore", "src.core.Base64", "src.core.Data", "src.core.DateTime", "src.core.FixedStep", "src.core.Game3", "src.core.GameVersion", "src.core.GamepadMap", "src.core.Input", "src.core.Logger", "src.core.PadHints", "src.core.Platform", "src.core.SafeArea", "src.core.SaveData", "src.core.SaveSerializer", "src.core.SessionLifecycle", "src.core.Strings", "src.core.Version", "src.core.WorkerLane", "src.core.game3.asset_decode", "src.core.game3.asset_stream", "src.core.game3.audio", "src.core.game3.bag", "src.core.game3.battle.abilities", "src.core.game3.battle.adapter", "src.core.game3.battle.anim", "src.core.game3.battle.anim_context", "src.core.game3.battle.anim_coords", "src.core.game3.battle.anim_ctx", "src.core.game3.battle.anim_pal", "src.core.game3.battle.anim_seq", "src.core.game3.battle.anim_sprites", "src.core.game3.battle.anim_tasks", "src.core.game3.battle.anim_vm", "src.core.game3.battle.ball_open", "src.core.game3.battle.battle_text", "src.core.game3.battle.bg", "src.core.game3.battle.capabilities", "src.core.game3.battle.catch_seq", "src.core.game3.battle.catching", "src.core.game3.battle.commands", "src.core.game3.battle.damage", "src.core.game3.battle.effect_ctx", "src.core.game3.battle.effect_ids", "src.core.game3.battle.effects", "src.core.game3.battle.effects._helpers", "src.core.game3.battle.effects.secondary", "src.core.game3.battle.engine", "src.core.game3.battle.evo_seq", "src.core.game3.battle.exp_seq", "src.core.game3.battle.experience", "src.core.game3.battle.healthbox", "src.core.game3.battle.held_items", "src.core.game3.battle.init", "src.core.game3.battle.intro_seq", "src.core.game3.battle.kinds", "src.core.game3.battle.learn_move", "src.core.game3.battle.level_up_streaks", "src.core.game3.battle.mod_registries", "src.core.game3.battle.mon_anim_battle", "src.core.game3.battle.moves", "src.core.game3.battle.oak_advice", "src.core.game3.battle.party_view", "src.core.game3.battle.pic_coords", "src.core.game3.battle.pokedude", "src.core.game3.battle.profile", "src.core.game3.battle.residual_handlers", "src.core.game3.battle.residuals", "src.core.game3.battle.rules", "src.core.game3.battle.shiny_seq", "src.core.game3.battle.state", "src.core.game3.battle.status", "src.core.game3.battle.switch_seq", "src.core.game3.battle.tutorial_wally", "src.core.game3.battle.types", "src.core.game3.battle.ui", "src.core.game3.bg", "src.core.game3.cache_paths", "src.core.game3.capabilities", "src.core.game3.collision", "src.core.game3.connections", "src.core.game3.constants", "src.core.game3.dataset", "src.core.game3.dex", "src.core.game3.display", "src.core.game3.evolution", "src.core.game3.field", "src.core.game3.field_modules", "src.core.game3.gba_fx", "src.core.game3.help_rules", "src.core.game3.item_use", "src.core.game3.items", "src.core.game3.items_data", "src.core.game3.m4a_mix", "src.core.game3.m4a_player", "src.core.game3.m4a_sample", "src.core.game3.m4a_seq", "src.core.game3.map", "src.core.game3.map_ids", "src.core.game3.mb", "src.core.game3.mod_audio", "src.core.game3.mon_anim", "src.core.game3.mon_anim_data", "src.core.game3.movement_types", "src.core.game3.mystery_gift", "src.core.game3.oam", "src.core.game3.object_prepare", "src.core.game3.objects", "src.core.game3.options", "src.core.game3.ow_sprites", "src.core.game3.pal_fade", "src.core.game3.palette", "src.core.game3.palette_mods", "src.core.game3.player", "src.core.game3.pokedex_data", "src.core.game3.pokemon", "src.core.game3.profile", "src.core.game3.progression", "src.core.game3.quest_log", "src.core.game3.quest_log_recorder", "src.core.game3.rom_text", "src.core.game3.rs.battle_text_policy", "src.core.game3.runtime", "src.core.game3.save_schema_firered", "src.core.game3.scripting.adapters", "src.core.game3.scripting.collision", "src.core.game3.scripting.ctx", "src.core.game3.scripting.disasm", "src.core.game3.scripting.flags", "src.core.game3.scripting.flags_table", "src.core.game3.scripting.gfx_ids", "src.core.game3.scripting.interaction_scripts", "src.core.game3.scripting.movement", "src.core.game3.scripting.natives", "src.core.game3.scripting.opcodes", "src.core.game3.scripting.opcodes_common", "src.core.game3.scripting.ops_a", "src.core.game3.scripting.ops_rse", "src.core.game3.scripting.space", "src.core.game3.scripting.stdscripts", "src.core.game3.scripting.text_ir", "src.core.game3.scripting.trainers", "src.core.game3.scripting.vm", "src.core.game3.se_ids", "src.core.game3.song_ids", "src.core.game3.storage", "src.core.game3.summary_data", "src.core.game3.task", "src.core.game3.trainer_pic", "src.core.game3.trig", "src.core.game3.virtual_objects", "src.core.game3.warm", "src.core.game3.warp_arrow", "src.import.CacheBlob", "src.import.CacheFs", "src.import.gba.battle_chrome_extract", "src.import.gba.extract_island1", "src.import.gba.extract_map_events", "src.import.gba.extract_scripts", "src.import.gba.family", "src.import.gba.lz77", "src.import.gba.map_catalog", "src.import.gba.map_sections_extract", "src.import.gba.maps", "src.import.gba.metatile", "src.import.gba.native_pack", "src.import.gba.ow_extract", "src.import.gba.palette_rules", "src.import.gba.party_chrome_extract", "src.import.gba.pokemon_extract", "src.import.gba.quantize", "src.import.gba.quantize_lab", "src.import.gba.quantize_mrf", "src.import.gba.region_map_extract", "src.import.gba.revision_view", "src.import.gba.rom", "src.import.gba.summary_chrome_extract", "src.import.gba.tileset", "src.import.gba.versions", "src.import.gba.versions_game", "src.inventory.Badges", "src.link.Json", "src.mods.AssetTransform", "src.mods.Events", "src.mods.Gen2Compat", "src.mods.Gen3Compat", "src.mods.Hooks", "src.mods.ImportAccess", "src.mods.Job", "src.mods.JobAssetIO", "src.mods.LegacyCompat", "src.mods.LoadOrder", "src.mods.Loader", "src.mods.Manifest", "src.mods.Merge", "src.mods.ModTargets", "src.mods.Net", "src.mods.Registry", "src.mods.RequiredImports", "src.mods.Runtime", "src.mods.SafePath", "src.mods.Sandbox", "src.mods.Schemas", "src.mods.Semver", "src.mods.Steps", "src.mods.StreamMD5", "src.pokemon.Boxes", "src.pokemon.Stats", "src.render.Assets", "src.render.AtlasPrefetch", "src.render.GameViewport", "src.render.PixelCanvas", "src.ui.LevelDisplay", "src.ui.ModUI", "src.ui.game3.bag_menu", "src.ui.game3.battle_chrome", "src.ui.game3.boot", "src.ui.game3.boot_modules", "src.ui.game3.choice", "src.ui.game3.chrome", "src.ui.game3.fade", "src.ui.game3.font_mods", "src.ui.game3.frlg_font", "src.ui.game3.help_system", "src.ui.game3.hud", "src.ui.game3.intro_movie", "src.ui.game3.list_menu", "src.ui.game3.message", "src.ui.game3.money_box", "src.ui.game3.mystery_gift", "src.ui.game3.naming", "src.ui.game3.naming_chrome", "src.ui.game3.new_game_scene", "src.ui.game3.option_menu", "src.ui.game3.option_rows", "src.ui.game3.party_chrome", "src.ui.game3.party_menu", "src.ui.game3.pc_menu", "src.ui.game3.pokedex", "src.ui.game3.pokedex_chrome", "src.ui.game3.quest_log", "src.ui.game3.region_map", "src.ui.game3.region_map_gpu", "src.ui.game3.region_map_position", "src.ui.game3.rs.naming_data", "src.ui.game3.save_menu", "src.ui.game3.screens", "src.ui.game3.shaderfx_menu", "src.ui.game3.shop_menu", "src.ui.game3.stack", "src.ui.game3.start_menu", "src.ui.game3.start_menu_frlg", "src.ui.game3.summary_chrome", "src.ui.game3.summary_menu", "src.ui.game3.title_screen", "src.ui.game3.trainer_card", "src.ui.game3.window", "src.ui.game3.wireless_icon" }
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
    local entries, bytes, others = {}, {}, {}  -- per place: keys held, bytes of strings, cdata and functions
    visited[sessions] = true
    local found, total, gaveUp = nil, 0, nil
    local started = love.timer.getTime()
    -- markers, so that a freeze can be told apart: in the modules or in the walk
    write("  asking for the loaded modules")
    local all = roots(game)
    write("  walking from " .. #all .. " roots")
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
          local n, size, other = 0, 0, 0
          for k, v in next, t do
            n = n + 1
            local tv, tk = type(v), type(k)
            if tv == "string" then size = size + #v elseif tv == "cdata" or tv == "function" or tv == "userdata" then other = other + 1 end
            if tk == "string" then size = size + #k end
          end
          entries[where] = (entries[where] or 0) + n
          bytes[where] = (bytes[where] or 0) + size
          others[where] = (others[where] or 0) + other
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
    return counts, path, total, gaveUp, { entries = entries, bytes = bytes, others = others }
  end

  local before, beforeMore
  function Leak.sample(game, current, resets)
    collectgarbage("collect"); collectgarbage("collect")
    local alive = 0
    for s in pairs(sessions) do if s ~= current then alive = alive + 1 end end
    -- written before the walk: if the walk goes wrong, this much is known
    write(string.format("== attempt %d: %d sessions seen, %d old ones still alive, Lua %.1f MB",
      resets, seenCount, alive, collectgarbage("count") / 1024), resets <= 60)
    local counts, path, total, gaveUp, more = census(game, current)
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
      if #grown == 0 then lines[#lines + 1] = "  no place has more tables" end
      -- the same for what tables hold: keys, bytes of strings, and cdata/functions/userdata
      for _, what in ipairs({ "entries", "bytes", "others" }) do
        local list = {}
        for where, n in pairs(more[what]) do
          local d = n - (beforeMore[what][where] or 0)
          if d > (what == "bytes" and 2000 or 50) then list[#list + 1] = { where, d, n } end
        end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        lines[#lines + 1] = what .. " that grew:" .. (#list == 0 and " none" or "")
        for i = 1, math.min(15, #list) do
          lines[#lines + 1] = string.format("  +%d %s (now %d)  %s", list[i][2], what, list[i][3], list[i][1])
        end
      end
    else
      local big = {}
      for where, n in pairs(counts) do big[#big + 1] = { where, n } end
      table.sort(big, function(a, b) return a[2] > b[2] end)
      for i = 1, math.min(15, #big) do lines[#lines + 1] = string.format("  %d tables  %s", big[i][2], big[i][1]) end
    end
    before, beforeMore = counts, more
    write(table.concat(lines, "\n"))
    return lines
  end
  return Leak
end
