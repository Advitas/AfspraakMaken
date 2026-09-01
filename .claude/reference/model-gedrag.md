# Modelgedrag — werkrelevante distillatie

> Gedistilleerd uit het volledige stock system prompt (`claude-fable-5.md` in de
> repo-root, gearchiveerde bron). Bewust kort en model-agnostisch gehouden zodat het
> een modelwissel overleeft — zie ADR-012. Dit is de "ken je gereedschap"-laag onder de
> Coding Principles in `CLAUDE.md` en de `karpathy-guidelines` skill.

Deze notitie vat alleen dát deel van het modelgedrag samen dat verandert *hoe wij
werken* in dit project. Het is geen samenvatting van het hele system prompt.

## Opmaak en prose

Het model neigt naar minimale opmaak: geen bullets, genummerde lijsten of overmatige
**bold** in doorlopende prose tenzij expliciet gevraagd of tenzij de inhoud
meerdimensionaal genoeg is dat lijsten nodig zijn voor duidelijkheid.

Toepassing hier: `HANDOFF.md`, `DECISIONS.md` en andere docs die het model schrijft
blijven in prose waar dat kan. Lijsten alleen waar ze echt verhelderen (bijv. stappen,
tabellen met kolommen). Dit voorkomt de "AI-opsomming"-stijl in onze docs.

## Skill-triggering-discipline

Het model roept relevante skills aan vóór het handelt — ook bij een geschatte kans van
1%. Dit sluit direct aan op Superpowers `using-superpowers`.

Toepassing hier: bij feature/bug/refactor eerst de juiste skill (brainstorming,
systematic-debugging, test-driven-development), niet meteen editen. De commands in
`.claude/commands/` gaan hiervóór — een `/`-command is een expliciete instructie.

## Memory-gedrag

Het model heeft een persistente memory over eerdere gesprekken en past die stil toe,
zonder meta-commentaar ("ik zie…", "op basis van je gegevens…"). Memory is niet
compleet en wordt periodiek bijgewerkt.

Toepassing hier: vertrouw voor projectstatus op de waarheid-docs (`HANDOFF.md`,
`TODO_*.md`, `DECISIONS.md`), niet op modelmemory. Memory kan verouderd zijn; de docs
zijn de bron van waarheid.

## Evidence before claims

Het model moet niet claimen dat iets "werkt" of "klaar" is zonder bewijs.

Toepassing hier: identiek aan Coding Principle "Evidence before assertions" en het
CONVENTIONS-patroon. Bij build/commit: uitvoeren en resultaat tonen. Ketent door naar
Superpowers `verification-before-completion` en de karpathy "Goal-Driven Execution".
