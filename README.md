# Kandela

Dimmer de distrações local e minimalista para Mac (alternativa livre ao
[HazeOver](https://hazeover.com)): escurece todas as janelas exceto a que está
em foco. Feito em Swift/AppKit puro, ~250 linhas, sem dependências, sem
permissões especiais (não pede Acessibilidade nem Gravação de Tela).

Parte da família de ferramentas da Kogumelo, que têm nome próprio começando
por K (ver também o [Konfig](https://github.com/Kogumelo/konfig)). Chamava-se
`km-dimmer` até 11/10/2026.

## Como funciona

Uma janela preta translúcida por monitor é mantida sempre **logo abaixo** da
janela em foco na pilha global de janelas do macOS (números de janela são
globais, então dá para ordenar relativo a janelas de outros apps). Cliques
atravessam o overlay, e ele não aparece em capturas de tela.

## Compilar e rodar

Precisa do Swift das Xcode Command Line Tools (`xcode-select --install`) e do
macOS 11 ou mais novo.

```sh
./build.sh
open Kandela.app
```

Aparece o K do Kandela na barra de menus com:

- **Ativado** — liga/desliga o escurecimento
- **Intensidade** — 20% a 80%
- **Destacar todas as janelas do app** — em vez de só a janela frontal,
  todas as janelas do app em foco ficam claras
- **Sair do Kandela**

As preferências ficam salvas em `defaults` (`br.com.kogut.kandela`). Na
primeira abertura, o Kandela copia as que o `km-dimmer` tinha guardado em
`br.com.kogut.km-dimmer`.

## Ícone

A marca (um K: haste apagada atrás, braços acesos por cima) está em
`Assets/kandela-mark.svg`. O ícone da barra de menus é desenhado em código
(`kandelaMark()` em `Sources/main.swift`); o do app fica em
`Resources/AppIcon.icns`, gerado por:

```sh
swift Tools/make-icon.swift
```

As três versões usam a mesma geometria: mudou uma, mude as outras.

## Iniciar junto com o sistema

Ajustes do Sistema → Geral → Itens de Início e Extensões → "+" → Kandela.app

## Limitações conhecidas (vs. HazeOver pago)

- A troca do escurecimento entre janelas é instantânea (sem fade gradual
  entre janelas — o fade existe só ao ligar/desligar/mudar intensidade).
- Sem intensidade por monitor independente.
- Trocas de foco dentro do mesmo app são detectadas por polling (0,2 s),
  não por evento — imperceptível na prática, CPU ~0%.

## Licença

[MIT](LICENSE) © 2026 Kogumelo Informática Ltda
