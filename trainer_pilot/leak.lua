-- leak.lua: a one-off look at what grows between reloads of a reset hunt.
--
-- The hunt's own record (log/perf) showed Lua memory climbing by about 0.1 MB
-- per attempt. This walks every table that can be reached from the game object,
-- the engine's modules and the Trainer mods' own tables, twice (at attempts 60
-- and 160), and writes to log/leak:
--   * how many of the sessions seen so far are still alive after a full
--     collection (a session that is not let go is a leak by itself), and the
--     way from a root to one of them, key by key;
--   * the places (root.key) whose number of tables grew the most.
-- Only tables are followed: what hides in a function's upvalues is out of
-- reach from a mod, and shows up here as "no path found".
return function(mod, extraRoots)
  local Leak = {}
  local MODULES = { "src.battle.game3.BattleAPI", "src.core.Base64", "src.core.BattleCheckpoint", "src.core.Checkpoint", "src.core.ChipAudio", "src.core.ChipSynth", "src.core.CollPermissions", "src.core.Data", "src.core.DatasetHydration", "src.core.DateTime", "src.core.DeferredWrite", "src.core.DeltaSkin", "src.core.DiscordPresence", "src.core.FaithfulRes", "src.core.FilePicker", "src.core.FixedStep", "src.core.FrameCap", "src.core.FrameProfiler", "src.core.Game", "src.core.Game2", "src.core.Game3", "src.core.GameSpeed", "src.core.GameVersion", "src.core.GamepadMap", "src.core.HostDisplay", "src.core.HostPicker", "src.core.HostShell", "src.core.Input", "src.core.IssueReport", "src.core.LaunchOptions", "src.core.Logger", "src.core.LogicClock", "src.core.Music", "src.core.NxAssetOverlay", "src.core.NxDisplay", "src.core.Orientation", "src.core.PadHints", "src.core.PdfImage", "src.core.Performance", "src.core.Platform", "src.core.PlatformHooks", "src.core.Prelaunch", "src.core.PresentProbe", "src.core.PresentSync", "src.core.Printer", "src.core.RefreshRate", "src.core.RequireGuard", "src.core.RomText", "src.core.SafeArea", "src.core.SaveData", "src.core.SaveSerializer", "src.core.ScreenPosition", "src.core.Sensors", "src.core.SessionLifecycle", "src.core.SkinZip", "src.core.Sound", "src.core.StateStack", "src.core.Strings", "src.core.TextClip", "src.core.Timing", "src.core.TouchControls", "src.core.TouchSkin", "src.core.TrainerIdSync", "src.core.TrainerIdentity", "src.core.VSync", "src.core.Version", "src.core.VideoMode", "src.core.WebClip", "src.core.WinApi", "src.core.WorkerFs", "src.core.WorkerLane", "src.core.chip_worker", "src.core.game3.ambient_cry", "src.core.game3.asset_decode", "src.core.game3.asset_stream", "src.core.game3.asset_worker", "src.core.game3.audio", "src.core.game3.audio_policy_rs", "src.core.game3.audio_policy_rse", "src.core.game3.bag", "src.core.game3.battle", "src.core.game3.battle.abilities", "src.core.game3.battle.adapter", "src.core.game3.battle.ai", "src.core.game3.battle.ai_cmds", "src.core.game3.battle.ai_items", "src.core.game3.battle.ai_switch", "src.core.game3.battle.ai_vm", "src.core.game3.battle.anim", "src.core.game3.battle.anim_callbacks", "src.core.game3.battle.anim_context", "src.core.game3.battle.anim_coords", "src.core.game3.battle.anim_ctx", "src.core.game3.battle.anim_pack_fallback", "src.core.game3.battle.anim_pal", "src.core.game3.battle.anim_seq", "src.core.game3.battle.anim_sprites", "src.core.game3.battle.anim_tasks", "src.core.game3.battle.anim_templates", "src.core.game3.battle.anim_vm", "src.core.game3.battle.ball_open", "src.core.game3.battle.battle_text", "src.core.game3.battle.bg", "src.core.game3.battle.capabilities", "src.core.game3.battle.catch_seq", "src.core.game3.battle.catching", "src.core.game3.battle.commands", "src.core.game3.battle.damage", "src.core.game3.battle.damage_adjustment_rs", "src.core.game3.battle.effect_chance_rs", "src.core.game3.battle.effect_ctx", "src.core.game3.battle.effect_ids", "src.core.game3.battle.effects", "src.core.game3.battle.engine", "src.core.game3.battle.env_frlg", "src.core.game3.battle.env_rs", "src.core.game3.battle.env_rse", "src.core.game3.battle.evo_seq", "src.core.game3.battle.exp_seq", "src.core.game3.battle.experience", "src.core.game3.battle.facility_arena", "src.core.game3.battle.facility_dome", "src.core.game3.battle.facility_palace", "src.core.game3.battle.faint_friendship_rs", "src.core.game3.battle.friendship_rs", "src.core.game3.battle.healthbox", "src.core.game3.battle.held_items", "src.core.game3.battle.intro_seq", "src.core.game3.battle.items", "src.core.game3.battle.kinds", "src.core.game3.battle.learn_move", "src.core.game3.battle.level_up_streaks", "src.core.game3.battle.link_guard", "src.core.game3.battle.mod_registries", "src.core.game3.battle.mon_anim_battle", "src.core.game3.battle.move_end_rs", "src.core.game3.battle.move_swap", "src.core.game3.battle.moves", "src.core.game3.battle.oak_advice", "src.core.game3.battle.party_status_rs", "src.core.game3.battle.party_view", "src.core.game3.battle.pic_coords", "src.core.game3.battle.pokedude", "src.core.game3.battle.prize", "src.core.game3.battle.profile", "src.core.game3.battle.residual_handlers", "src.core.game3.battle.residuals", "src.core.game3.battle.results_rs", "src.core.game3.battle.rules", "src.core.game3.battle.sequencing_rs", "src.core.game3.battle.shiny_seq", "src.core.game3.battle.state", "src.core.game3.battle.status", "src.core.game3.battle.switch_seq", "src.core.game3.battle.trainer_rs", "src.core.game3.battle.tutorial_wally", "src.core.game3.battle.types", "src.core.game3.battle.ui", "src.core.game3.battle_bridge", "src.core.game3.battle_downgrade", "src.core.game3.battle_transition", "src.core.game3.battle_transition_ids_frlg", "src.core.game3.battle_transition_ids_rse", "src.core.game3.battle_transition_rse_a", "src.core.game3.battle_transition_rse_b", "src.core.game3.battle_transition_rse_frontier", "src.core.game3.bg", "src.core.game3.bg_affine", "src.core.game3.braille_field", "src.core.game3.braille_field_rs", "src.core.game3.breeding", "src.core.game3.bridge", "src.core.game3.cache_paths", "src.core.game3.camera_object", "src.core.game3.capabilities", "src.core.game3.collision", "src.core.game3.connections", "src.core.game3.constants", "src.core.game3.coord_weather", "src.core.game3.dataset", "src.core.game3.daycare", "src.core.game3.deoxys", "src.core.game3.dex", "src.core.game3.display", "src.core.game3.dive", "src.core.game3.doors", "src.core.game3.easy_chat_text", "src.core.game3.encounters", "src.core.game3.encounters_data_stub", "src.core.game3.encounters_stub", "src.core.game3.evolution", "src.core.game3.fame_checker", "src.core.game3.faraway_island", "src.core.game3.field", "src.core.game3.field_cell_prepare", "src.core.game3.field_effects", "src.core.game3.field_effects_rse", "src.core.game3.field_modules", "src.core.game3.field_move_show_mon", "src.core.game3.field_moves", "src.core.game3.field_plan", "src.core.game3.field_semantics", "src.core.game3.field_view", "src.core.game3.field_weather", "src.core.game3.field_weather_rse", "src.core.game3.fldeff_misc", "src.core.game3.forced_movement", "src.core.game3.gba_fx", "src.core.game3.gba_palette", "src.core.game3.gba_ppu", "src.core.game3.gba_sprites", "src.core.game3.gba_tasks", "src.core.game3.gfx", "src.core.game3.ghosts", "src.core.game3.gift", "src.core.game3.heal_locations", "src.core.game3.help_rules", "src.core.game3.host_stub", "src.core.game3.house_npcs_stub", "src.core.game3.indexed_png", "src.core.game3.item_use", "src.core.game3.itemfinder", "src.core.game3.items", "src.core.game3.items_data", "src.core.game3.layout_native", "src.core.game3.league_lighting", "src.core.game3.m4a_mix", "src.core.game3.m4a_player", "src.core.game3.m4a_sample", "src.core.game3.m4a_seq", "src.core.game3.m4a_worker", "src.core.game3.mail", "src.core.game3.map", "src.core.game3.map_ids", "src.core.game3.marts", "src.core.game3.mb", "src.core.game3.mirage_tower", "src.core.game3.mod_audio", "src.core.game3.mod_decorations", "src.core.game3.mod_landmarks", "src.core.game3.mod_layout", "src.core.game3.mon_anim", "src.core.game3.mon_anim_data", "src.core.game3.move_learn", "src.core.game3.movement_types", "src.core.game3.mystery_gift", "src.core.game3.oam", "src.core.game3.object_prepare", "src.core.game3.objects", "src.core.game3.options", "src.core.game3.ow_sprites", "src.core.game3.pal_fade", "src.core.game3.palette", "src.core.game3.palette_mods", "src.core.game3.party", "src.core.game3.pc_anim", "src.core.game3.player", "src.core.game3.pokecenter_heal", "src.core.game3.pokedex_data", "src.core.game3.pokedex_rating", "src.core.game3.pokedex_units", "src.core.game3.pokemon", "src.core.game3.pokemon_size_record", "src.core.game3.prewarm", "src.core.game3.profile", "src.core.game3.progression", "src.core.game3.quest_log", "src.core.game3.quest_log_recorder", "src.core.game3.renewable_hidden_items", "src.core.game3.rng", "src.core.game3.roamer", "src.core.game3.rom_text", "src.core.game3.rotating_gate", "src.core.game3.rotating_tile_puzzle", "src.core.game3.rtc", "src.core.game3.runtime", "src.core.game3.safari", "src.core.game3.save_mon", "src.core.game3.save_schema_firered", "src.core.game3.save_sections", "src.core.game3.scanline_fx", "src.core.game3.scripting.adapters", "src.core.game3.scripting.collision", "src.core.game3.scripting.collision_frlg", "src.core.game3.scripting.collision_rse", "src.core.game3.scripting.collision_std", "src.core.game3.scripting.ctx", "src.core.game3.scripting.disasm", "src.core.game3.scripting.flags", "src.core.game3.scripting.flags_table", "src.core.game3.scripting.gfx_ids", "src.core.game3.scripting.interaction_scripts", "src.core.game3.scripting.movement", "src.core.game3.scripting.multichoice", "src.core.game3.scripting.natives", "src.core.game3.scripting.natives_apprentice", "src.core.game3.scripting.natives_arena", "src.core.game3.scripting.natives_berry", "src.core.game3.scripting.natives_blender", "src.core.game3.scripting.natives_clock", "src.core.game3.scripting.natives_contest", "src.core.game3.scripting.natives_corner", "src.core.game3.scripting.natives_cutscene", "src.core.game3.scripting.natives_daycare", "src.core.game3.scripting.natives_dewford", "src.core.game3.scripting.natives_diploma_rse", "src.core.game3.scripting.natives_dome", "src.core.game3.scripting.natives_easy_chat_profile_rse", "src.core.game3.scripting.natives_egg_hatch_rse", "src.core.game3.scripting.natives_elevator", "src.core.game3.scripting.natives_ereader_rse", "src.core.game3.scripting.natives_event_islands", "src.core.game3.scripting.natives_events", "src.core.game3.scripting.natives_factory", "src.core.game3.scripting.natives_fame", "src.core.game3.scripting.natives_fan_club", "src.core.game3.scripting.natives_field_rse", "src.core.game3.scripting.natives_frontier", "src.core.game3.scripting.natives_frontier_story", "src.core.game3.scripting.natives_frontier_tutor_rse", "src.core.game3.scripting.natives_game_corner_rse", "src.core.game3.scripting.natives_gift", "src.core.game3.scripting.natives_lilycove_lady", "src.core.game3.scripting.natives_link", "src.core.game3.scripting.natives_link_rs", "src.core.game3.scripting.natives_link_rse", "src.core.game3.scripting.natives_listmenu", "src.core.game3.scripting.natives_lottery", "src.core.game3.scripting.natives_match_call", "src.core.game3.scripting.natives_moveteach", "src.core.game3.scripting.natives_old_man", "src.core.game3.scripting.natives_palace", "src.core.game3.scripting.natives_pc_rse", "src.core.game3.scripting.natives_pike", "src.core.game3.scripting.natives_pokeblock", "src.core.game3.scripting.natives_puzzles_rse", "src.core.game3.scripting.natives_pyramid", "src.core.game3.scripting.natives_queries", "src.core.game3.scripting.natives_region_map_rse", "src.core.game3.scripting.natives_rs", "src.core.game3.scripting.natives_rs_base_lifecycle", "src.core.game3.scripting.natives_rs_contest", "src.core.game3.scripting.natives_rs_daycare", "src.core.game3.scripting.natives_rs_dewford", "src.core.game3.scripting.natives_rs_diploma", "src.core.game3.scripting.natives_rs_easy_chat", "src.core.game3.scripting.natives_rs_easy_chat_message", "src.core.game3.scripting.natives_rs_fan_club", "src.core.game3.scripting.natives_rs_gameplay", "src.core.game3.scripting.natives_rs_glass", "src.core.game3.scripting.natives_rs_gym", "src.core.game3.scripting.natives_rs_move_relearner", "src.core.game3.scripting.natives_rs_npc_trade", "src.core.game3.scripting.natives_rs_old_man", "src.core.game3.scripting.natives_rs_orb", "src.core.game3.scripting.natives_rs_pokedex", "src.core.game3.scripting.natives_rs_rematch", "src.core.game3.scripting.natives_rs_room_decorations", "src.core.game3.scripting.natives_rs_roulette", "src.core.game3.scripting.natives_rs_secret_base", "src.core.game3.scripting.natives_rs_size_records", "src.core.game3.scripting.natives_rs_story", "src.core.game3.scripting.natives_rs_tower", "src.core.game3.scripting.natives_rs_tower_records", "src.core.game3.scripting.natives_rs_tv", "src.core.game3.scripting.natives_rs_tv_playback", "src.core.game3.scripting.natives_rs_tv_routes", "src.core.game3.scripting.natives_rs_weather_flash", "src.core.game3.scripting.natives_scenes_rse", "src.core.game3.scripting.natives_seagallop", "src.core.game3.scripting.natives_secret_base", "src.core.game3.scripting.natives_shared_rse", "src.core.game3.scripting.natives_size_record", "src.core.game3.scripting.natives_size_record_rse", "src.core.game3.scripting.natives_tents", "src.core.game3.scripting.natives_tower", "src.core.game3.scripting.natives_tower_rse", "src.core.game3.scripting.natives_trade", "src.core.game3.scripting.natives_trainer_hill", "src.core.game3.scripting.natives_tv", "src.core.game3.scripting.natives_walda_rse", "src.core.game3.scripting.natives_wireless", "src.core.game3.scripting.opcodes", "src.core.game3.scripting.opcodes_common", "src.core.game3.scripting.opcodes_emerald", "src.core.game3.scripting.opcodes_frlg", "src.core.game3.scripting.opcodes_rs", "src.core.game3.scripting.ops_a", "src.core.game3.scripting.ops_rse", "src.core.game3.scripting.space", "src.core.game3.scripting.stdscripts", "src.core.game3.scripting.text_ir", "src.core.game3.scripting.trainers", "src.core.game3.scripting.vm", "src.core.game3.se_ids", "src.core.game3.slot_machine", "src.core.game3.song_fields", "src.core.game3.song_ids", "src.core.game3.special_field_anim", "src.core.game3.special_scene_rse", "src.core.game3.ss_anne_cutscene", "src.core.game3.step_callbacks_rse", "src.core.game3.step_events", "src.core.game3.storage", "src.core.game3.summary_data", "src.core.game3.surf_bob", "src.core.game3.task", "src.core.game3.teachy_tv", "src.core.game3.tileset_anim", "src.core.game3.tileset_native", "src.core.game3.time_events", "src.core.game3.town_map_stub", "src.core.game3.trade_scene", "src.core.game3.trainer_fan_club", "src.core.game3.trainer_pic", "src.core.game3.trainer_sight", "src.core.game3.trainer_tower", "src.core.game3.trig", "src.core.game3.truck_sequence", "src.core.game3.virtual_objects", "src.core.game3.void_fill", "src.core.game3.vs_seeker", "src.core.game3.vs_seeker_data", "src.core.game3.warm", "src.core.game3.warp", "src.core.game3.warp_arrow", "src.core.game3.weather", "src.core.host_picker_worker", "src.ui.ArenaState", "src.ui.BagMenu", "src.ui.BindingsMenu", "src.ui.BoxMenu", "src.ui.ChoiceBox", "src.ui.Credits", "src.ui.DexEntryMenu", "src.ui.Diploma", "src.ui.EvolutionState", "src.ui.FlyMenu", "src.ui.HallOfFame", "src.ui.IntroMovie", "src.ui.LeaguePC", "src.ui.LevelDisplay", "src.ui.ListMenu", "src.ui.Marquee", "src.ui.Menu", "src.ui.MenuRepeat", "src.ui.ModUI", "src.ui.MoveLearnMenu", "src.ui.MoveSelectMenu", "src.ui.NamingScreen", "src.ui.OakSpeech", "src.ui.OptionRows", "src.ui.OptionsMenu", "src.ui.PadCursor", "src.ui.PaletteScreen", "src.ui.PartyMenu", "src.ui.PicBox", "src.ui.PlayerPC", "src.ui.PokedexMenu", "src.ui.PokemonIcon", "src.ui.PrinterMonStats", "src.ui.PrizeCounter", "src.ui.QuantityBox", "src.ui.QuarantineReport", "src.ui.Screens", "src.ui.ShaderFXParamsScreen", "src.ui.ShaderFXScreen", "src.ui.ShopMenu", "src.ui.SkinStudio", "src.ui.SlotMachine", "src.ui.StartMenu", "src.ui.SummaryMenu", "src.ui.SurfHiScore", "src.ui.SurfingMinigame", "src.ui.Theme", "src.ui.TitleState", "src.ui.TouchControlsEditor", "src.ui.TownMap", "src.ui.TradeAnim", "src.ui.TrainerCard", "src.ui.YellowIntro", "src.ui.game3.arena_state", "src.ui.game3.bag_chrome", "src.ui.game3.bag_menu", "src.ui.game3.battle_chrome", "src.ui.game3.battle_transition_chrome", "src.ui.game3.berry_pouch", "src.ui.game3.berry_pouch_chrome", "src.ui.game3.berry_powder_box", "src.ui.game3.boot", "src.ui.game3.boot_modules", "src.ui.game3.box_storage_ui", "src.ui.game3.braille", "src.ui.game3.cave_transition", "src.ui.game3.choice", "src.ui.game3.chrome", "src.ui.game3.coins_box", "src.ui.game3.controls_menu", "src.ui.game3.credits", "src.ui.game3.daycare_menu", "src.ui.game3.diploma", "src.ui.game3.easy_chat", "src.ui.game3.egg_hatch", "src.ui.game3.elevator_window", "src.ui.game3.evolution_scene", "src.ui.game3.fade", "src.ui.game3.fame_checker", "src.ui.game3.font", "src.ui.game3.font_mods", "src.ui.game3.frlg_font", "src.ui.game3.hall_of_fame", "src.ui.game3.hall_of_fame_gfx", "src.ui.game3.hall_of_fame_pc", "src.ui.game3.help_system", "src.ui.game3.help_window", "src.ui.game3.hud", "src.ui.game3.intro_movie", "src.ui.game3.item_pc", "src.ui.game3.link_menu", "src.ui.game3.link_tags", "src.ui.game3.link_trade_menu", "src.ui.game3.list_menu", "src.ui.game3.mail", "src.ui.game3.mailbox", "src.ui.game3.map_name_popup", "src.ui.game3.map_preview_screen", "src.ui.game3.message", "src.ui.game3.minigame_records", "src.ui.game3.mod_manager", "src.ui.game3.mod_ui", "src.ui.game3.mon_pic", "src.ui.game3.money_box", "src.ui.game3.move_relearner", "src.ui.game3.museum_fossil_pic", "src.ui.game3.mystery_gift", "src.ui.game3.naming", "src.ui.game3.naming_chrome", "src.ui.game3.new_game_scene", "src.ui.game3.option_menu", "src.ui.game3.option_rows", "src.ui.game3.party_chrome", "src.ui.game3.party_menu", "src.ui.game3.pc_chrome", "src.ui.game3.pc_menu", "src.ui.game3.pin_entry", "src.ui.game3.pokedex", "src.ui.game3.pokedex_chrome", "src.ui.game3.prize_corner", "src.ui.game3.quest_log", "src.ui.game3.region_map", "src.ui.game3.region_map_gpu", "src.ui.game3.region_map_position", "src.ui.game3.release_seq", "src.ui.game3.save_menu", "src.ui.game3.screens", "src.ui.game3.seagallop", "src.ui.game3.sell_flow", "src.ui.game3.shaderfx_menu", "src.ui.game3.shop_chrome", "src.ui.game3.shop_menu", "src.ui.game3.slot_machine", "src.ui.game3.stack", "src.ui.game3.start_menu", "src.ui.game3.start_menu_frlg", "src.ui.game3.stat_growth", "src.ui.game3.storage_choose_box", "src.ui.game3.storage_presentation", "src.ui.game3.summary_chrome", "src.ui.game3.summary_menu", "src.ui.game3.teachy_tv", "src.ui.game3.title_screen", "src.ui.game3.tm_case", "src.ui.game3.tm_case_chrome", "src.ui.game3.trade_scene", "src.ui.game3.trainer_card", "src.ui.game3.trainer_tower_records", "src.ui.game3.ui_pass", "src.ui.game3.union_chat", "src.ui.game3.union_room", "src.ui.game3.whiteout_rush", "src.ui.game3.window", "src.ui.game3.wireless_icon", "src.world.Collision", "src.world.ElevatorShake", "src.world.Encounter", "src.world.FieldDefaults", "src.world.Map", "src.world.MapLoader", "src.world.MapOverview", "src.world.NPC", "src.world.OverworldController", "src.world.PikachuFollower", "src.world.Player", "src.world.SsAnneLayout", "src.world.Warp", "src.world.WorldAPI", "src.world.game3.Follower", "src.world.game3.WorldAPI", "src.mods.Events", "src.mods.Hooks", "src.mods.Registry", "src.mods.Runtime", "src.mods.Storage" }
  local sessions = setmetatable({}, { __mode = "k" })
  local order, seenCount = setmetatable({}, { __mode = "v" }), 0
  function Leak.note(session)
    if type(session) == "table" and not sessions[session] then
      seenCount = seenCount + 1
      sessions[session] = seenCount
    end
  end

  local function roots(game)
    local list = { { "game", game } }
    for _, name in ipairs(MODULES) do
      local ok, m = pcall(require, name)
      if ok and type(m) == "table" then list[#list + 1] = { name:gsub("^src%.", ""), m } end
    end
    for name, value in pairs(extraRoots() or {}) do list[#list + 1] = { name, value } end
    return list
  end

  -- Counts tables under every root.key (each table once, for the first place
  -- that reaches it) and remembers how each table was reached.
  local function census(game, current)
    local visited, parent, counts = {}, {}, {}
    visited[sessions], visited[order] = true, true
    local found
    for _, root in ipairs(roots(game)) do
      local rootName, rootTable = root[1], root[2]
      if not visited[rootTable] then
        visited[rootTable] = true
        local queue, head = { rootTable }, 1
        local bucket = { [rootTable] = rootName }
        while queue[head] do
          local t = queue[head]; head = head + 1
          local where = bucket[t]
          counts[where] = (counts[where] or 0) + 1
          local function visit(child, key)
            if type(child) ~= "table" or visited[child] then return end
            visited[child] = true
            parent[child] = { t, key }
            bucket[child] = (t == rootTable) and (rootName .. "." .. tostring(key)) or where
            queue[#queue + 1] = child
            if not found and sessions[child] and child ~= current then found = child end
          end
          for k, v in next, t do
            visit(v, k)
            if type(k) == "table" then visit(k, "<key>") end
          end
          local mt = getmetatable(t)
          if type(mt) == "table" then visit(mt, "<metatable>") end
          bucket[t] = nil
        end
      end
    end
    local path
    if found then
      local parts, at = {}, found
      for _ = 1, 40 do
        local p = parent[at]
        if not p then break end
        table.insert(parts, 1, tostring(p[2]))
        at = p[1]
      end
      path = table.concat(parts, " > ")
      for _, root in ipairs(roots(game)) do if root[2] == at then path = root[1] .. " > " .. path end end
    end
    return counts, path
  end

  local before
  function Leak.sample(game, current, resets)
    collectgarbage("collect"); collectgarbage("collect")
    local alive = 0
    for s in pairs(sessions) do if s ~= current then alive = alive + 1 end end
    local counts, path = census(game, current)
    local lines = { string.format("== attempt %d: %d sessions seen, %d old ones still alive, Lua %.1f MB",
      resets, seenCount, alive, collectgarbage("count") / 1024) }
    lines[#lines + 1] = "path to an old session: " .. (path or "no path found through tables")
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    lines[#lines + 1] = "tables reached: " .. total
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
    local old = mod.cache and mod.cache.read and mod.cache:read("log/leak") or ""
    if resets <= 60 then old = "" end
    if mod.cache and mod.cache.write then mod.cache:write("log/leak", old .. table.concat(lines, "\n") .. "\n") end
    return lines
  end
  return Leak
end
