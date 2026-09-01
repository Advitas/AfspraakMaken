---
description: Synchroniseer .claude/ vanuit de template-repo naar alle geregistreerde projecten
---

Voer de volgende stap uit:

1. Controleer of je in de template-repo staat (de map moet `VERSION` en `projects.txt` bevatten).
   Als dat niet het geval is, stop dan met een foutmelding:
   "Dit command kan alleen vanuit de template-repo worden uitgevoerd."

2. Voer uit: bash sync.sh

Dit script loopt door alle projecten in `projects.txt`, toont een diff per gewijzigd bestand en vraagt per bestand of het overschreven moet worden.
