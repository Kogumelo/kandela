---
description: Instala o Kandela novo em /Applications — confere que o checkout está no main e limpo, compila com ./build.sh --install (que fecha o Kandela aberto e reabre o novo), aponta o item de login para /Applications e confere o carimbo e o ícone do que foi instalado.
argument-hint: (ignorado) o Kommand passa o ref; instala-se sempre o main do checkout principal
allowed-tools: Bash
---

# /km-instalar — trocar o Kandela de /Applications pelo build do main

Use depois do merge, quando o que está no `main` precisa virar o Kandela que
roda na barra de menus. É o que o botão de deploy do Kommand dispara.

Você **confere, compila e instala**. Não escreve no git: não faz merge, não
commita, não faz push. **Se um portão falhar, pare e diga qual** — não conserte
por conta própria.

O repositório é `~/Kogumelo/Ferramentas/kandela`. Os blocos abaixo chamam esse
caminho de `$R`, e todo comando roda com `-C "$R"` ou dentro de `$R` — também
quando você foi chamado de dentro de uma worktree:

```
R=~/Kogumelo/Ferramentas/kandela
```

`$ARGUMENTS` (o ref que o Kommand manda) não escolhe o que se instala: aqui o
merge já foi feito pelo botão de merge, e o que vai para /Applications é sempre
o `main` do checkout principal. Se `$ARGUMENTS` não for `main` nem vazio, avise
e siga com o `main`.

## 1. Ramo e limpeza

```
git -C "$R" branch --show-current                                              # tem que ser main
git -C "$R" diff --quiet HEAD && echo LIMPO                                    # tem que sair LIMPO
git -C "$R" status --porcelain -- Sources Resources Info.plist build.sh        # tem que sair VAZIO
```

- **Fora do `main`:** pare. O carimbo `KandelaCommit` guarda o commit de onde o
  build saiu; um build de branch põe lá um hash que o `main` não tem.
- **Arquivo versionado alterado:** pare e liste. O build sairia com `-dirty` no
  carimbo, e o app instalado não corresponderia a commit nenhum.
- **Arquivo não versionado em `Sources/` ou `Resources/`:** pare também. O
  `build.sh` copia tudo de `Resources/`, versionado ou não — e o `git diff` não
  vê esse caso, por isso o terceiro comando. Não versionado fora dessas pastas
  (anexos, `.DS_Store`) não entra no app e não barra nada.

O Kandela não tem testes automatizados; o portão de compilação é o próprio
`build.sh`, que recusa chave de tradução faltando em qualquer idioma.

## 2. Guardar o que está instalado e instalar

```
plutil -extract KandelaCommit raw /Applications/Kandela.app/Contents/Info.plist 2>/dev/null || echo "(sem carimbo: primeira instalação, ou build anterior ao carimbo)"   # guarde: ANTERIOR
pgrep -xl Kandela                                                              # de onde roda agora (anote)
"$R/build.sh" --install
```

O `--install` troca `/Applications/Kandela.app`, registra de novo no Launch
Services e, se o Kandela estava aberto, fecha o velho e abre o novo de
`/Applications`. Durante esses segundos a tela fica sem o escurecimento — é
esperado. Se ele disser que o Kandela não fechou, pare: nada foi instalado.

## 3. Item de login

O Kandela abre sozinho no login. Antes deste comando o item apontava para o
build do checkout (`$R/Kandela.app`), que muda a cada `./build.sh` de
desenvolvimento. Ele tem que apontar para `/Applications`:

```
osascript -e 'tell application "System Events" to get the path of every login item whose name is "Kandela"'
```

- **Aponta para `/Applications/Kandela.app`:** nada a fazer.
- **Aponta para outro lugar:** troque e confira de novo:
  ```
  osascript -e 'tell application "System Events" to delete (every login item whose name is "Kandela")' \
            -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Kandela.app", hidden:false}'
  ```
- **Não existe:** não crie — o operador tirou o Kandela do login de propósito.
  Só avise.

## 4. Conferir o que foi instalado

```
plutil -extract KandelaCommit raw /Applications/Kandela.app/Contents/Info.plist   # = hash curto do HEAD, sem -dirty
git -C "$R" rev-parse --short HEAD
ls /Applications/Kandela.app/Contents/Resources/AppIcon.icns                     # tem que existir
codesign --verify /Applications/Kandela.app && echo ASSINATURA-OK
pgrep -xl Kandela                                                                # se estava aberto: um só, de /Applications
ps -o command= -p "$(pgrep -x Kandela)"
```

- carimbo diferente do HEAD, ou com `-dirty`: algo escapou do passo 1 — diga o quê;
- o Kandela estava aberto e agora não está, ou roda de outro caminho que não
  `/Applications/Kandela.app`: diga — o ícone na barra continua o velho. Foi
  exatamente o defeito de 12/10/2026, quando o Kandela rodava um build de antes
  da marca nova.

## Saída (em português)

Um bloco curto: ✅/⚠️ por portão, o commit instalado e o ANTERIOR, o caminho
do item de login, e o que entrou entre os dois
(`git -C "$R" log --oneline <ANTERIOR>..HEAD`, quando havia carimbo).
