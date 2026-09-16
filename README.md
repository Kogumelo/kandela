# km-dimmer

Dimmer de distrações local e minimalista (substituto do [HazeOver](https://hazeover.com)):
escurece todas as janelas exceto a que está em foco. Feito em Swift/AppKit
puro, ~250 linhas, sem dependências, sem permissões especiais (não pede
Acessibilidade nem Gravação de Tela).

Parte do ecossistema de utilitários `km-*`.

## Como funciona

Uma janela preta translúcida por monitor é mantida sempre **logo abaixo** da
janela em foco na pilha global de janelas do macOS (números de janela são
globais, então dá para ordenar relativo a janelas de outros apps). Cliques
atravessam o overlay, e ele não aparece em capturas de tela.

## Compilar e rodar

```sh
./build.sh
open km-dimmer.app
```

Aparece um ícone ◐ na barra de menus com:

- **Ativado** — liga/desliga o escurecimento
- **Intensidade** — 20% a 80%
- **Destacar todas as janelas do app** — em vez de só a janela frontal,
  todas as janelas do app em foco ficam claras
- **Sair do km-dimmer**

As preferências ficam salvas em `defaults` (`br.com.kogut.km-dimmer`).

## Iniciar junto com o sistema

Ajustes do Sistema → Geral → Itens de Início e Extensões → "+" → km-dimmer.app

## Limitações conhecidas (vs. HazeOver pago)

- A troca do escurecimento entre janelas é instantânea (sem fade gradual
  entre janelas — o fade existe só ao ligar/desligar/mudar intensidade).
- Sem intensidade por monitor independente.
- Trocas de foco dentro do mesmo app são detectadas por polling (0,2 s),
  não por evento — imperceptível na prática, CPU ~0%.
