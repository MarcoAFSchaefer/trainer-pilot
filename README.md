# Trainer Pilot

Bot de treino e caça para Pokémon FireRed/LeafGreen no Gen1Recomp. Joga apertando os botões do próprio jogo; qualquer botão seu pausa o bot.

## O que faz

- **Rotas:** grama (gravada andando), pesca, VS Seeker e Sweet Scent (pontos marcados).
- **Treino:** batalhas com quem você marca, golpes proibidos por Pokémon, paradas por nível, shiny, espécie, golpe novo, evolução e PP.
- **Treino de EV:** alvo por atributo e por Pokémon; foge das espécies que dariam EV errado; para no alvo.
- **Cura:** volta ao Centro Pokémon mais próximo por um mapa de ligações do mundo (ou por um caminho gravado), ou usa poções e éteres até o limite que você escolher.
- **Obstáculos no caminho:** Surf, Cut, Rock Smash, Strength e Waterfall.
- **Caça:** até 30 alvos com nome e filtro por espécie, gênero, natureza, habilidade, IVs, Hidden Power, nível, item e shiny; captura automática opcional; Safari; caça por reset para iniciais, presentes e lendários.
- **Controle:** velocidade do jogo durante a rodada, números da rodada, histórico das últimas 40 paradas.

Não inicia numa rota de grama com Repel ativo e para se um Repel for usado no meio.

## Instalação

Copie a pasta `trainer_pilot` para a pasta de mods do jogo:

```
%APPDATA%\pokemon-love2d\mods\trainer_pilot
```

O painel de controle aparece nas docas do Trainer Desk.

## Testes

Rodam no Linux com LÖVE 11.5 e um X virtual, sobre um jogo simulado:

```
BOT_MOD=$PWD/trainer_pilot xvfb-run -a love tests
```

O resultado esperado é `ALL BOT CHECKS PASSED`.

## Notas

`NOTAS.md` reúne as decisões, APIs do jogo usadas e armadilhas encontradas ao longo do desenvolvimento.

## Histórico

Até a versão 0.24.0 se chamava PokeBot (id `poke_bot`).
