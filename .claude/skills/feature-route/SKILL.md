---
name: feature-route
description: Triage-poort voor feature-implementaties. Gebruik bij ELK verzoek om nieuwe functionaliteit of een gedragswijziging, VOORDAT brainstorming of een implementatie-skill start. Stelt de routevraag (A: PoC, B: kleine feature, C: grote feature) en bepaalt daarmee de zwaarte van het proces. Niet gebruiken bij bugs (daar geldt systematic-debugging) of triviale one-liners.
---

# Feature Route — triage-poort voor feature-implementaties

Bepaal bij elk feature-verzoek éérst hoe zwaar het proces moet zijn. Stel de routevraag en volg daarna de gekozen route. Start géén brainstorming of andere implementatie-skill voordat de route vaststaat.

## Stap 1 — Check de uitzonderingen

Sla de routevraag over bij:

1. **Bug:** volg `superpowers:systematic-debugging` — deze skill is niet van toepassing.
2. **Triviale one-liner:** direct uitvoeren (bestaande uitzondering "skip brainstorm").
3. **Route al genoemd:** zegt de gebruiker zelf al welke route ("bouw dit als PoC", "dit is een grote feature"), bevestig de keuze dan in één zin en ga direct naar Stap 4.
4. **Autonome context** (nacht-routine of andere sessie zonder beschikbare gebruiker): kies conservatief **route B**, log de gemaakte keuze in het rapport en ga naar Stap 4.

## Stap 2 — Analyseer de omvang

Schat het verzoek in en bepaal je advies:

- **Route A (PoC)** past bij: experiment- of wegwerpdoel, één component, laag risico, "even proberen of dit kan".
- **Route B (kleine feature)** past bij: afgebakende feature, enkele bestanden, bestaande patronen, voorspelbaar werk.
- **Route C (grote feature)** past bij: meerdere lagen of subsystemen, nieuw patroon, verhoogd risico, of naar verwachting meer dan 2 uur werk.

## Stap 3 — Stel de routevraag

Gebruik **AskUserQuestion**. Zet je geadviseerde optie vooraan met "(Aanbevolen)" in het label. De drie opties, elk met deze inhoud in de beschrijving:

- **A — PoC:** geen spec, geen implementatieplan, geen review-agents, geen verplichte TDD. Wél de karpathy-guidelines en een werkende build. De gebruiker controleert de feature zelf functioneel.
- **B — Kleine feature:** spec (brainstorming) + implementatieplan, uitvoering subagent-driven of inline. Geen extra review-agents — ook niet per taak.
- **C — Grote feature:** als B, plus een review-subagent na elke afgeronde plan-taak én een eindreview over de volledige diff.

**Vervolgvraag bij route B of C** (mag als tweede vraag in dezelfde AskUserQuestion-call): de uitvoeringsvorm —

- **Subagent-driven** (`superpowers:subagent-driven-development`): bij onafhankelijke plan-taken.
- **Inline** (`superpowers:executing-plans`): bij sequentiële of kleine plannen.

Adviseer op basis van taak-onafhankelijkheid; de gebruiker beslist.

## Stap 4 — Voer de gekozen route uit

**Route A — PoC:**
1. Implementeer direct, zonder spec of plan.
2. Volg de `karpathy-guidelines` skill: leesbare code, bestaande patronen, geen gelegenheids-refactors.
3. Toon bewijs dat de build werkt (evidence before assertions).
4. Meld expliciet dat er geen reviews of tests zijn gedraaid en dat de gebruiker functioneel controleert.
5. **Groeit de PoC uit zijn jasje** (structurele wijzigingen of meer dan 2 uur werk): stop en stel de routevraag opnieuw.

**Route B — Kleine feature:**
1. `superpowers:brainstorming` → spec.
2. `superpowers:writing-plans` → implementatieplan.
3. Uitvoering via de gekozen vorm: `superpowers:subagent-driven-development` of `superpowers:executing-plans`.
4. **Geen extra review-agents — deze regel overschrijft de uitvoerings-skill.** Ook bij subagent-driven uitvoering dus géén task-reviewer-subagent per taak en géén eindreview-subagent; alleen implementers. Suites, lint en build zijn het bewijs. Reviews horen exclusief bij route C.

**Route C — Grote feature:**
1. Als route B, stap 1 t/m 3.
2. Na elke afgeronde plan-taak: `superpowers:requesting-code-review`.
3. Na afronding van het volledige plan: een eindreview over de volledige diff.

## Afsluiting

Meld bij afronding altijd: welke route is gevolgd, wat er wél en níét is gecontroleerd (reviews, tests, build), en bij route A dat functionele controle bij de gebruiker ligt.
