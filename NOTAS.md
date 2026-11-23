> Notas de desenvolvimento acumuladas. Até a versão 0.24.0 o mod se chamava PokeBot (id `poke_bot`); o Trainer Desk era PokeDock e o Trainer Lens era PokePanels.

# Trainer Pilot — notas para continuar o trabalho

Estado em 22/11/2026: Trainer Pilot 0.18.0, Trainer Desk 0.2.0, Trainer Lens 1.3.1.
Jogo: Gen1Recomp 0.4.8 (LÖVE 11.5), Pokémon FireRed. Mods em
`%APPDATA%\pokemon-love2d\mods\<id>`; dados salvos dos mods em
`%APPDATA%\pokemon-love2d\mod_cache\<id>\<chave>` (um arquivo por chave).
Zips das versões atuais nesta pasta.

## Arquivos do Trainer Pilot

- `main.lua`: o bot inteiro (gravação de rota, caminho, batalha, cura, paradas).
- `panel.lua`: painel de 480x432 desenhado dentro do Trainer Desk, com 4 abas
  (Controle, Rotas, Paradas, Equipe). Botões são retângulos registrados durante
  o desenho e consultados no clique (`hits`).
- Dados em `mod_cache/trainer_pilot/`: `routes/v1`, `config/v1`, `nurses/v1`
  (onde ficar diante da enfermeira, por Centro), `crossings/v1` (por onde se
  cruza entre dois mapas), `log/last` (motivo e lugar da última parada).

## Como o bot conversa com o jogo (tudo confirmado no jogo real)

- Botões: `mod.input:tap(game, "a")`, `mod.input:press(game, dir)` devolve um
  token para `mod.input:release(token)`. O laço roda no gancho `input.step`.
- Batalha: `require("src.battle.game3.BattleAPI").new(game)`; `snapshot()` dá
  `prompt` ("advance", "menu", "moves", "target", "party", "locked") e
  `revision`; `submit{ id, revision, kind="menu"|"move"|"target"|"back", ... }`.
  O menu aceita `choice = "fight" | "bag" | "pokemon"/"party" | "run"`.
  NÃO há intenção pronta para usar item: capturar exige dirigir a mochila.
- Estado da batalha: `require("src.core.game3.battle")`; `getState()` dá
  `st.wild`, `st.double`, `st.enemy.mon`, `st.player.mon`, `st.battlers[0..3]`,
  `st.foeParty`. O `_phase` fica em `src.core.game3.battle.init`
  ("shift_prompt" é a pergunta de troca). A batalha guarda CÓPIA do Pokémon:
  comparar por `personality` + espécie, nunca pela tabela.
- Pokémon: `src.core.game3.pokemon` (`speciesOf`, `name`, `isShiny`, `isEgg`,
  `types`, `abilityId/abilityName`), `summary_data` (`gender`, `nature`).
  IVs em `mon.ivs.{hp,atk,def,spe,spa,spd}`, EVs em `mon.evs`.
- Campo: `src.core.game3.{field,player,map,collision,objects}`;
  `Collision.canEnter(game, x, y, { fromX, fromY, dir, surfing, elevation })`,
  `ledgeLanding`, `isWater`, `inBounds`, `behavior` + `isWarpMetatileBehavior`.
- Golpes de campo: `require("src.world.game3.WorldAPI").new(game, id)`
  `:useFieldAction("surf" | "cut" | ...)` (lista em `FIELD_ACTIONS` no arquivo).
  Sweet Scent deve estar nessa lista ou em `field_moves.fromMenu("SWEET_SCENT")`.
- Mapas: `game.data.maps[id]` com `.warps` (x, y, destMap, destWarp contado a
  partir de 1) e ligações por `src.core.game3.connections` (`each`, `incoming`,
  `sizeOf`). Ids sem "MAP_": `FR_ROUTE_15`, `SEVII_ONE_ISLAND_POKECENTER`.
- Velocidade: `game.options.speedOverworld` e `speedBattle`.

## Armadilhas já pagas

- Esperas contam em passos do jogo E em segundos reais (`mark()` / `late()`):
  em 200x centenas de passos passam enquanto um mapa ainda carrega.
- No meio da travessia entre mapas a posição fica um quadrado fora do mapa novo.
- A água responde "elevation", não "water", em `canEnter`: olhar `isWater`.
- A lista de `warps` de um Centro inclui quadrados ao lado do tapete que não
  funcionam; preferir os que têm comportamento de warp.
- Batalha em dupla: dois Pokémon em campo (`st.player` e `st.battlers[2]`).
- A tentativa de "procurar a casinha na hora" e de guardar "sem caminho" por
  0,4 s (versão 0.5.3) fez o bot parar na Rota 15; foi desfeita sem achar a causa.

## Pendências

- Travadas na Rota 15 (antes da casinha e na borda com a Rota 14): falta saber
  se é o jogo carregando o mapa ou o bot.
- Mapa de ligações do mundo (mapas + portas) para ir de qualquer lugar a
  qualquer lugar; hoje há só o remendo de "prédio de passagem" no mesmo mapa.
- Texto de "Não achei Centro" ainda sugere gravar rota de cura, que não existe mais.
- Parada por shiny nunca vista no jogo real.
- Simulação de teste (harness) não tem casinha de passagem nem batalha em dupla.

## Próximo: caça (hunting)

Pedido: rota + filtro detalhado por Pokémon (espécie, sexo, IV total mínimo,
IV mínimo por stat, habilidade), capturar e seguir ou parar ao achar, Sweet
Scent, curar depois de cada tentativa, baixar HP até o vermelho, aplicar
status (paralisia/sono) antes de jogar a bola.

Decisões já tomadas pelo dono:

- Bolas: lista em ordem de preferência; Master Ball só com uma opção própria ligada.
- Pokémon que não bate com o filtro: opção "lutar para ganhar EXP" ou "fugir".
- Cura depois de cada tentativa: por opção, no Centro ou com item da mochila
  (também por opção). Medo declarado: encontrar o alvo com HP ou PP baixos.
  Regra proposta: o bot só procura encontro quando está "pronto" (HP e PP acima
  de limites configuráveis, bolas na mochila); se não estiver, cura antes.
- False Swipe: o dono NÃO tem e não quer que o bot dependa dele. Baixar o HP
  será por estimativa de dano: escolher, entre os golpes permitidos, o que deixa
  o alvo mais perto do vermelho sem poder derrubar nem com dano máximo e
  crítico; se nenhum golpe for seguro, não bater (só status e bola). Usar False
  Swipe se por acaso existir na equipe, mas sem exigir.

- Exigir False Swipe também vira opção: ligada, o bot só bate para baixar o HP
  se houver False Swipe; desligada, usa a estimativa de dano.

Feito na 0.7.0 (etapa 1 da caça): aba "Caça" no painel, com lista de até 5
alvos e editor (espécie entre as do mapa, sexo, soma mínima de IVs, IV mínimo
por stat, habilidade). `config.huntOn`, `config.huntExp`, `config.targets`;
`Bot.matches(mon, alvo)` em main.lua. Ao aparecer um alvo o bot para com
"hunt_found" e a batalha aberta. Testado só na simulação.
Faltam: Sweet Scent (etapa 2) e captura (etapa 3: mochila, bolas em ordem,
Master por opção, baixar HP, status, cura por Centro ou item, "pronto para caçar").

Na 0.8.0: treino e caça são modos separados (`Bot.start("train" | "hunt", resume)`,
`Bot.mode`). "INICIAR TREINO" fica na aba Treino (antiga Paradas), "INICIAR CAÇA"
na aba Caça; a aba Controle só tem PARAR e CONTINUAR (retoma mantendo os
números). A caça ignora nível alvo, shiny e lista de espécies do treino.
O filtro tem também natureza (personality % 25) e "só shiny".
Sugestões de filtro ainda não feitas: nível, item segurado, Hidden Power,
várias naturezas por alvo, contador de encontros por espécie.

Na 0.9.0: o filtro ganhou segunda página (várias naturezas, nível mín./máx.,
tipo e poder do Hidden Power via `Bot.hiddenPower`, "segurando algum item"),
a caça tem "parar em qualquer shiny" (`config.huntShiny`), e a aba Controle
mostra encontros por espécie (`Bot.stats.seen`). Item específico (ex.: Light
Ball) ainda não: falta saber de onde ler a lista de itens que a espécie segura.

Na 0.10.0 (etapa 2 da caça): Sweet Scent. `config.huntScent`; em rota de grama
no modo caça o bot fica no ponto de grama mais próximo da rota e chama
`WorldAPI:useFieldAction("sweet_scent")` (golpe 230, 1 PP por uso); sem PP vai
ao Centro. Se o jogo recusar 8 vezes seguidas, volta a andar a rota.
Falta só a etapa 3: captura.

Na 0.11.0 (etapa 3 da caça): captura automática. Tela "Captura automática" na
aba Caça (`config.huntCatch`, `catchContinue`, `catchWeaken`, `catchFalseSwipe`,
`catchStatus`, `catchHeal`, `useMaster`, `ballOrder`). Em main.lua: `catchStep`
(baixar HP só com golpe cujo dano máximo com crítico não derruba, ou False
Swipe 206; status por lista `STATUS_MOVES`; bola), `maxDamage`, `Bot.pickBall`.
A bola é jogada SEM abrir a mochila: no menu de batalha o bot grava
`require("src.core.game3.battle.ui")._pendingCommand = { kind="bag", user="player",
itemId = <bola> }` e `_mode = "none"`, que é o que a tela da mochila faz; a
própria batalha tira a bola da mochila. Ids: 1 Master, 2 Ultra, 3 Great, 4 Poké.
Apelido: responde "não" (B). Captura contada se o alvo termina a batalha com HP > 0.
NÃO feito: curar com item, regra "pronto para caçar", bolas especiais (Net, etc.).
Nada disso foi visto no jogo real ainda.

Na 0.11.1: regra "pronto para caçar" em `fieldTick` (caça com captura): sem
bola na mochila para com "no_balls_ready"; golpe de status do líder sem PP vai
ao Centro antes. Curar com item NÃO foi feito: a WorldAPI não tem uso de item
no campo; seria preciso dirigir a mochila ou achar a função de efeito do item.

Na 0.12.0: obstáculos no caminho além de Surf e Cut. `Bot.obstacleAt(x, y)` lê
o gráfico do objeto (95 árvore, 96 pedra rachada, 97 pedregulho, de
`FieldMoves.GFX_IDS`). Rock Smash: igual ao Cut (`useFieldAction("rock_smash")`).
Strength: `useFieldAction("strength")` uma vez por mapa (`strengthMap`), depois
só anda contra o pedregulho; só planeja empurrar se o quadrado atrás estiver
livre. Waterfall: subindo, surfando, `useFieldAction("waterfall")` até a água
acima. Rock Smash e Strength testados na simulação; Waterfall sem teste nenhum.
Próximo pedido do dono: mapa de ligações do mundo.

Na 0.13.0: mapa de ligações. `mapLinks(id)` devolve as ligações de um mapa
(bordas, custo 1; portas/cavernas/escadas via `def.warps`, custo 3);
`planHop(de, ehDestino, chave)` faz o menor caminho mapa a mapa (limite de
custo 16, lista `AVOID` de mapas a não atravessar: Safari, Liga, Silph, Rocket,
Game Corner, barcos, elevadores) e devolve a primeira ligação. `travel()` usa
isso: borda como antes; porta = andar até um warp deste mapa que leva lá e,
se não abrir, empurrar (`push`). Ligação sem porta alcançável vira `badLinks`
e o plano é refeito. `findCenter()` procura o Centro pelo mesmo mapa.
O remendo `planPortal` (prédio de passagem no mesmo mapa, ex.: casinha da
Rota 15) continua existindo como reserva. A simulação ganhou caverna e 3ª rota.
Não visto no jogo real.

Na 0.14.0: voltou o "Caminho de cura" gravado (rota kind "heal"), para cavernas
com puzzle/Flash onde o automático não serve. Pode terminar na enfermeira (o bot
volta por ele ao contrário) ou ser ida e volta numa gravação só (`healIndex`
acha o ponto da enfermeira; depois de curar segue em frente até o fim). O
`follow` tem `cursor.max` para não pular para a perna de volta. `portalMemo`
lembra o prédio de passagem que funcionou por mapa+destino (evita procurar de
novo; mira as travadas da Rota 15, não confirmado). Feedback do dono na 0.13.0:
caminho melhorou, não entrou em prédio à toa; Rota 15 seguia com travadas.

Na 0.15.0: cavernas com puzzle entram na lista `AVOID` (Victory Road, Seafoam,
Icefall, Mansão, Lost Cave): sem caminho por elas = "Caminho bloqueado"; o dono
quer voltar nisso depois. Caça de pesca: já funcionava pelo mesmo código de
batalha; acrescentados a escolha de vara (`config.rod`, botão na aba Controle
quando a rota é de pesca) e as espécies de pesca no seletor de alvo (`areaSpecies`
agora varre qualquer formato das tabelas de encontro).

Na 0.15.1: placar da caça na aba Controle (`stats.found/caught/lost`).
Na 0.16.0: Safari Zone. Na batalha `st.safari` o menu é BALL/BAIT/ROCK/RUN nas
posições de fight/bag/party/run da BattleAPI (`safariStep`): não-alvo foge
sempre; alvo recebe isca ou pedra uma vez (`config.safariPlan`) e depois bolas.
Captura agora é lida de `st.result == "catch"` (vale fora do Safari também).
No campo, com `Safari.isActive(session)`: sem regras de equipe, sem cura; quando
deixa de estar ativo o bot para com "safari_over". Sweet Scent sem PP no Safari
volta a andar. Não visto no jogo real.

Na 0.16.1: Safari = ciclo repetido de `config.safariBaits` iscas (padrão 2) e
`config.safariBalls` bolas (padrão 3); pedra nunca.
Na 0.17.0: rota kind "scent" = ponto marcado de Sweet Scent (`trainScent`):
vai ao ponto e chama encontros sem andar (não gasta passos do Safari); sem PP
cura (fora do Safari) ou para ("no_scent"). `startHeal()` centraliza o início
da ida ao Centro (caminho gravado ou automático).

Na 0.18.0: reentrada no Safari (`config.safariReentries`, 0..99 ou -1 = sempre).
Em `fieldTick`, quando `Safari.isActive` passa a falso: se há reentradas,
`run.reenter = mark()`; cura antes se a equipe não está cheia (recupera PP do
Sweet Scent); depois o `travel` normal leva de volta ao ponto, e o mapa de
ligações aceita mapas SAFARI quando o destino é no Safari. Com `run.reenter` o
bot responde A às perguntas no campo (o atendente). Limite 180 s → "safari_reenter".
Só simulado: no jogo real falta ver o portão do Safari (roteiro do atendente,
cobrança, andar automático para dentro).

## 0.18.1
- Reentrada no Safari: confere o dinheiro (`session.money`, preço 500) em vez de esperar; "infinito" = até acabar o dinheiro. Tempo limite de 60 s no portão.

## 0.18.2
- Aba Controle: botão FINALIZAR ao lado de CONTINUAR (`Bot.finish()`): encerra a rodada parada e zera modo, motivo e números. Não faz nada com o bot rodando.

## 0.19.0 - caça por reset
- Modo `reset` (`Bot.start("reset")`, aba Caça > "Caça por reset"): salva o jogo no ponto (`game:saveGame()`), aperta A, confere o que veio (batalha selvagem ou Pokémon novo na equipe) com os alvos da Caça / qualquer shiny, e recarrega o save como a tecla F2 do jogo (`_tearDownField` + `_handleBootAction{action="continue"}`), feito no hook `core.update`.
- O jogo salva ao fechar (`Game3:quit`): enquanto `Bot.resetLock` existe, o hook `save.write` devolve false. Liberado ao achar/capturar o alvo ou em FINALIZAR.
- Sorte: `Rng.perturb()` no continue (16 bits de relógio) + espera aleatória de 0..120 passos. `Rng.getState()` é guardado após cada load; com `resetCatch` ligado, captura que falha recarrega com `Rng.setState` + mesma espera para trazer o MESMO Pokémon (confere `personality`), até 10 vezes. Nunca visto no jogo real: depende de o jogo ser determinístico entre o load e o encontro.
- Paradas novas: reset_nothing, reset_trainer, reset_load, no_save.

## 0.20.0 - cura com itens da mochila
- `itemHp` / `itemPp` (aba Treino: "Usar poções" / "Usar éteres"; 0 = não, -1 = sem limite, contados por rodada em `stats.itemsHp/itemsPp`).
- Quando ninguém marcado está apto (`pickLead` devolve "tired"), `itemHeal` usa UM item por passo com `ItemUse.useField(session, bag, id, slot, moveSlot)` (aplica e tira da mochila, sem tela) antes de ir ao Centro.
- HP: Potion 13, Super 22, Fresh Water 26, Soda Pop 27, Lemonade 28, Moomoo Milk 29, Hyper 21: o menor que completa o HP. Max Potion / Full Restore / Revive ficam de fora.
- PP: só quando não sobra ataque permitido com PP: Ether 34 / Max Ether 35 no ataque vazio; Elixir 36 / Max Elixir 37 se há mais de um vazio.

# Trainer Lens / Trainer Desk (notas)
- Trainer Desk 0.3.0: abas que não cabem viram menu (botão no fim da barra), corte de texto respeita UTF-8, hook `input.wheel` manda `pointer("wheel", x, y, dy)` ao painel, F10 esconde/mostra (`api.collapse`), Esc fecha menu, dicas nos ícones.
- Trainer Desk 0.4.0: `register{ responsive = true }` -> `draw(now, w, h)` no tamanho do corpo da doca; em janela própria usa o tamanho registrado. `api.features`.
- Trainer Lens 2.x: desenho em `ui.lua` (fonte vetorial, cartões, responsivo); modelos continuam em `main.lua`. Teia única (atributos/IV/EV). Painéis novos: `tools` (WorldAPI:availableFieldActions/useFieldAction, ItemUse.useField para varas/VS Seeker/repels/rope; ícones por `BagChrome.iconImage` e `Pokemon.monIcon`), `trainer` (trainer_card.isBadgeUnlocked com `_session` trocado, Dex.countSeen/countCaught, session.gameStats), `progress` (espécies por área de `data.gen3Encounters` x Dex.isCaught; roda do mouse/click vira página).
- Falta do Kanto Gear: mapas (WorldAPI:mapOverview existe), utilidades (notas, Day-Care, calendário, contador shiny, mochila, info de golpes), conquistas.
- Trainer Lens 2.3.1: mapa da área com tiles do jogo (`def.midLayout:midAt`, `tileset_native.get/slotFor/quad/overQuad`, desenhado num Canvas próprio; segue o jogador se a célula ficaria < 8 px) e Town Map do jogo (`region_map_extract`, `region_map_position.regionFor/playerCell`, `region_map_gpu.image`); esquemático como reserva.
- Trainer Lens 2.4.0: painéis `bag` (Bag.listPocket), `moves` (Moves.get, Summary.moveDescription, Types.effectiveness contra o oponente), `daycare` (daycare.stateOf/route5Of/levelsGained/cost/isEggPending), `counter` (encontros selvagens por espécie em `mod_cache/trainer_lens/counter/v1`). Trainer Desk 0.4.1: painel novo entra como aba sem roubar a frente.
- Falta: notas (precisa digitar texto; o jogo não repassa `textinput` a mods), calendário (FireRed não tem relógio/eventos por dia), conquistas.
- Trainer Lens 2.5.0: `dex` (grade + detalhe: Pokemon.stats/abilities/evolutions/dexEntry, áreas pela lista do Progresso), `notices` (feed: Trainer Pilot parou via `exports.bot.reasonText`, shiny, VS Seeker carregado, repel acabou, desmaio, Day-Care), equipe reordena por clique (WorldAPI:reorderParty). Conquistas/Momentos do Kanto Gear são invenções dele; o social (PSS) usa a camada online do próprio recomp (`src.online.Client/Connect`).
- Trainer Lens 2.5.1: lista da área clicável (ficha da espécie + "Nesta área"), roda vira página. 2.6.0: painel `online` SOMENTE LEITURA (`src.online.Connect.state/error/name`, `src.online.Client.you/counts/room/invites/plaza/lobby`); nada é enviado. Campos das entradas lidos de forma defensiva (name, status, activity, intent, where, version...) - conferir com dados reais.
- Trainer Lens 2.6.1: painel `online` REMOVIDO. O recomp não deixa entrar online com mods ativos, então não há o que mostrar.
- Trainer Lens 2.7.0: botões < n/m > em todas as paginações (`pager` em ui.lua, hits `{ page = +-1 }`); na mochila ficam embaixo da lista. Auto Repel (ferramenta liga/desliga, guardado em `mod_cache/trainer_lens/autorepel`): quando `field_semantics.getVar(session,"repelSteps")` chega a 0 num mapa com encontros (land; water só surfando), usa Repel 86 > Super 83 > Max 84 por `ItemUse.useField`, sem mostrar mensagem, e registra em Avisos.
- Trainer Pilot 0.20.3: caça por reset pausada é encerrada sozinha (trava de save liberada, motivo `reset_released`) se o jogador sai do ponto (outro mapa ou 4+ células); removido `huntOn`. Trainer Lens 2.7.2: Auto Repel não age com o Trainer Pilot rodando; 2.7.1: Ferramentas mostra só o que dá para usar.
- Princípio do usuário: mods independentes; o bot não conhece recursos de outros mods. Trainer Lens 2.7.3: Auto Repel NÃO olha mais o bot. Trainer Pilot 0.20.4: em rota de grama ou Sweet Scent não inicia com Repel ativo e para se um Repel for ativado na rodada (motivo `repel_on`, lê `field_semantics.getVar(session,"repelSteps")`). Único acoplamento restante: Avisos do Trainer Lens lê `exports.bot` (opcional).
- Trainer Pilot 0.21.0: painel no visual do Trainer Lens (cores do tema da IDE, abas em pílula, interruptores) e `responsive = true`: o layout continua numa folha 480x432, esticada ao espaço (kx, ky entre 0.7 e 2.4; texto por kf = menor escala, 0.8..1.5). Todo desenho e clique passam por box/text/centred/hit.
- Trainer Pilot 0.21.1: abas na ordem Controle, Rotas, Equipe, Treino, Caça; paginação `<  n/m  >` (função `pager`); aba Equipe com ícone (Pokemon.monIcon), barra de HP e golpes na cor do tipo (Types.ID), vermelho = proibido.
- Trainer Pilot 0.22.0: abas refeitas no estilo do Trainer Lens. Regra de cores: azul = escolhido/ligado, verde = iniciar, vermelho = parar/proibir, âmbar = só aviso, cinza = secundário. Controle: ponto de estado, faixa do motivo (dourada/vermelha), blocos de números, etiquetas "Para quando", ícones dos encontros. Treino em 3 grupos. Caça: alvo como cartão com ícone, estado vazio. Rotas: duas fileiras (gravar andando / marcar ponto), tipo como etiqueta colorida.
- Trainer Pilot 0.23.0: treino de EV. `config.evTargets["<personality>"] = { hp, atk, def, spe, spa, spd }` (teto 252). `Bot.evOn` = treino fora de rota VS Seeker. `belowTarget` considera EV pronto (`Bot.evDone`, ou 510 no total); parada vira `ev_done`/`ev_healed`. Na entrada da batalha selvagem, `Bot.evWasted(lutador, espécie)` via `Pokemon.evYield` => foge (`stats.evFled`). Com alvo de EV, nunca troca por escolha no shift prompt; trocas só por desmaio/sem PP (lógica já existente). Editor: aba Equipe > botão EV.
- Trainer Pilot 0.23.1: telas internas da Caça no estilo novo: editor de alvo com cabeçalho (ícone, nome, filtros) e abas Básico/Mais filtros, SALVAR nas duas páginas, gênero e páginas como escolha (`choices`); captura e reset em grupos com títulos; aviso da trava de save em faixa âmbar.
- Trainer Pilot 0.24.0: histórico de paradas (`Bot.history`, até 40, `mod_cache/trainer_pilot/log/history`, linhas `at|reason|mode|route|map|x|y|battles|seconds|found|caught`; gravado em `Bot.stop` só com o bot rodando e já com o motivo final); tela Controle > Histórico. Alvos: até 30 (`Bot.MAX_TARGETS`), lista paginada de 5, campo 19 = nome (`Bot.cleanName`: só letras, números e espaço, 20 chars). Nome digitado no editor (toque no título): gancho `input.key` prioridade 3200 manda as teclas para `panel.key` e não para o jogo. `Bot.roomForCatch()` (equipe < 6 ou `Storage.findOpenSlot`) => motivo `pc_full` ao iniciar caça com captura e na regra de pronto para caçar. Bolas acabando já existia (`no_balls_ready`, `no_balls`).
- Trainer Lens 2.8.0: painel `box` (PC) só leitura: lê `session.storage.boxes[b].mons[1..30]` direto (não chama Storage.ensure nem nada que mova); abre na `storage.currentBox`; clique mostra a ficha (`sheetModel`, com EV); Pokémon de caixa sem stats calculados ganham uma cópia com `Pokemon.calcStats` só para exibir.
