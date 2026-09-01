# Doc-drift signals — buffer voor /dag-afsluiting

Append-only door `/handoff`. Geleegd door `/dag-afsluiting` in dezelfde commit als de doc-updates.

**Doel:** captures van wijzigingen die één van de "waarheid-docs" raken (`CONVENTIONS`, `ARCHITECTURE`, `GLOSSARY`, `README`, `CONTRIBUTING`). `/handoff` voegt entries toe; `/dag-afsluiting` verwerkt en leegt.

**Format per entry:**

```
## YYYY-MM-DD — sessie N — TARGET-DOC

**Wat:** [korte beschrijving van de wijziging]
**Code:** [betrokken bestanden, paden t.o.v. repo-root]
**Commit:** [commit-hash van de relevante commit]
**Voorgestelde plek:** [hint voor /dag-afsluiting — welke sectie in de waarheid-doc]
```

---

<!-- Entries hieronder. Verwijder deze regel bij de eerste echte entry. -->
