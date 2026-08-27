# Cursor Composer — séparer le gabarit technique des sources linguistiques et renforcer l'arbitrage Whisper

## Contexte

Repo : `Tetram76/powershell-toolkit`  
PR : `#32`  
Branche : `feat/media-translation`

État observé avant ce brief :

```text
head = b8ec27317c6e30e04c1a639036f2a83e251595d7
```

Le module envoie actuellement la source `-SubtitlePath` au LLM sous cette forme :

```text
===== SOURCE PRINCIPALE — STRUCTURE TECHNIQUE FINALE =====
[
  {
    "cueId": 1,
    "start": "...",
    "end": "...",
    "text": "..."
  }
]
===== FIN SOURCE PRINCIPALE =====
```

Les autres sous-titres et transcriptions Whisper sont ensuite présentés comme des sources secondaires.

Même si le prompt dit déjà que la source principale n'a pas de priorité linguistique, cette représentation crée un ancrage fort :

```text
cueId -> texte de la source principale -> traduction
```

Le but de cette tâche est de supprimer cet ancrage structurel.

## Objectif

Séparer explicitement :

1. le **gabarit technique final**, qui contient uniquement les cues à produire ;
2. la **source linguistique structurante**, qui contient le texte du fichier `-SubtitlePath` mais sans `cueId` ;
3. les autres **sources linguistiques**, sous-titres ou Whisper.

Le LLM doit recevoir conceptuellement :

```text
GABARIT TECHNIQUE FINAL
    cueId + start + end
            |
            v
      cues à produire

SOURCES LINGUISTIQUES
    sous-titre structurant
    autre sous-titre
    Whisper
    Whisper
    ...
            |
            v
    déterminer le sens
            |
            v
       français final
```

Le fichier `-SubtitlePath` reste absolument inchangé comme autorité technique locale pour la reconstruction finale.

Cette tâche ne change pas le contrat public de la commande.

## Nouveau gabarit technique

À partir de `$canonicalCue`, produire un JSON contenant uniquement :

```json
[
  {
    "cueId": 1,
    "start": "00:00:01,000",
    "end": "00:00:02,000"
  }
]
```

Le champ `text` doit être absent du gabarit.

Le bloc envoyé au prompt doit être :

```text
===== GABARIT TECHNIQUE FINAL =====
<json cueId/start/end>
===== FIN GABARIT TECHNIQUE FINAL =====
```

Créer une petite fonction privée dédiée, par exemple :

```powershell
ConvertTo-TechnicalTemplateCueJson
```

ou un nom cohérent avec les conventions existantes.

Ne pas modifier `Get-CanonicalSubtitleCue` : ses objets complets restent utiles à la reconstruction et aux validations.

## Source linguistique structurante

Le texte provenant de `-SubtitlePath` doit être envoyé séparément comme un sous-titre linguistique ordinaire :

```json
[
  {
    "start": "00:00:01,000",
    "end": "00:00:02,000",
    "text": "..."
  }
]
```

Il ne doit contenir aucun `cueId`.

Réutiliser autant que possible la logique existante qui produit déjà le format `start/end/text` des sous-titres secondaires.

Le bloc doit être :

```text
===== SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT =====
<json start/end/text>
===== FIN SOURCE LINGUISTIQUE 1 =====
```

Le mot `STRUCTURANT` exprime uniquement le lien avec la reconstruction technique.

Il ne doit impliquer aucune priorité linguistique.

## Autres sources linguistiques

Remplacer dans les blocs dynamiques la nomenclature :

```text
SOURCE SECONDAIRE
```

par :

```text
SOURCE LINGUISTIQUE
```

Les sources fournies avec `-SecondarySourcePath` commencent à l'index 2 puisque la source structurante est `SOURCE LINGUISTIQUE 1`.

Exemples :

```text
===== SOURCE LINGUISTIQUE 2 — SOUS-TITRE =====
...
===== FIN SOURCE LINGUISTIQUE 2 =====
```

```text
===== SOURCE LINGUISTIQUE 3 — TRANSCRIPTION WHISPER JSON =====
...
===== FIN SOURCE LINGUISTIQUE 3 =====
```

Conserver l'ordre fourni dans `-SecondarySourcePath`.

Cet ordre n'exprime aucune priorité linguistique.

Ne pas renommer le paramètre public `-SecondarySourcePath` dans cette tâche.

## Règle essentielle sur `cueId`

`cueId` doit apparaître uniquement dans le gabarit technique et dans le JSON de sortie attendu.

Aucune source linguistique ne doit recevoir de `cueId`, y compris la source structurante.

C'est le point central de cette refonte : empêcher le modèle d'associer directement un `cueId` à un texte anglais ou à une autre traduction particulière.

L'alignement entre gabarit et sources reste temporel/sémantique.

Ne pas ajouter d'alignement PowerShell.

## Markers / formatage

Ne pas extraire, parser ou modéliser séparément les markers.

Cela vaut pour ASS comme pour SRT.

Le `text` de la source structurante doit être transmis tel qu'il est produit aujourd'hui par le parseur canonique, avec ses markers éventuels.

Les autres sources de sous-titres conservent également leur `text` et leurs markers éventuels.

Le prompt doit établir la distinction suivante :

- les markers présents dans la **source linguistique structurante** sont les contraintes techniques à préserver dans le texte français final ;
- les markers d'une source non structurante peuvent être informatifs mais ne sont pas des contraintes du fichier final ;
- ils ne doivent pas être copiés automatiquement dans la sortie.

Ne pas ajouter de parser générique de tags.

Ne pas ajouter de champ `requiredMarkers`.

Ne pas modifier la validation ASS existante.

Ne pas ajouter de validation SRT supplémentaire dans cette tâche.

## Reconstruction

La reconstruction finale reste strictement basée sur le fichier `-SubtitlePath` original.

Conserver :

- les identifiants natifs SRT ;
- les timestamps natifs ;
- les champs techniques ASS ;
- les validations existantes ;
- le remplacement par `cueId`.

`$canonicalCue` complet, avec son `text`, reste disponible localement pour :

- `Assert-CueTranslationNotEmptied` ;
- la reconstruction ;
- les autres validations existantes.

La séparation gabarit/source linguistique ne concerne que la représentation envoyée au LLM.

## Whisper

Ne modifier ni le compactage Whisper ni son contrat JSON.

Conserver :

```text
language
segments[].start
segments[].end
segments[].text
segments[].temperature        si présent
segments[].avg_logprob        si présent
segments[].compression_ratio  si présent
segments[].no_speech_prob     si présent
```

Ne pas réintroduire :

```text
tokens
words
id
seek
text racine
```

Ne pas ajouter de scoring PowerShell.

La pondération Whisper doit rester entièrement dans le raisonnement du LLM.

## Nouveau prompt ressource

Remplacer :

```text
Tetram.Media.Translation/Resources/ConvertTo-FrenchSubtitle.generate.prompt.md
```

par le contenu du fichier fourni avec ce brief :

```text
ConvertTo-FrenchSubtitle.generate.prompt.v3.md
```

Ce nouveau prompt fait partie du contrat de cette tâche.

Il introduit notamment les règles suivantes.

### Séparation structure / sens

Le prompt doit présenter :

- le gabarit technique comme dépourvu de contenu linguistique ;
- la source structurante comme une source linguistique parmi les autres ;
- les autres sous-titres comme des sources pouvant être dans n'importe quelle langue, y compris une traduction française à améliorer ;
- aucune hiérarchie linguistique fixe.

### Méthode anti-ancrage

Le modèle doit explicitement :

1. rassembler les segments pertinents de toutes les sources ;
2. déterminer le sens avant de produire du français ;
3. comparer les hypothèses concurrentes ;
4. formuler ensuite la traduction française.

La règle suivante est essentielle :

```text
Ne commence pas par traduire la source structurante puis par corriger cette traduction grâce aux autres sources.
```

Une autre source doit réellement pouvoir contredire la source structurante.

### Traductions officielles / français existant

Le prompt doit prévoir qu'une source linguistique peut être :

- une traduction officielle ;
- un sous-titre dans une autre langue ;
- une traduction française déjà existante à améliorer.

Une traduction officielle peut être très utile mais ne reçoit pas d'autorité absolue.

Un français déjà correct peut être conservé tel quel ; ne pas reformuler uniquement pour être différent.

### Pondération Whisper

Le prompt fourni décrit une pondération **qualitative et locale**, jamais numérique.

Il doit expliquer l'usage concret de :

- `avg_logprob` ;
- `compression_ratio` ;
- `no_speech_prob` ;
- `temperature`.

Principes obligatoires :

- aucune métrique n'est un score de confiance absolu ;
- aucun seuil mécanique ;
- aucune moyenne entre transcriptions ;
- aucun score global ;
- aucune comparaison numérique naïve entre modèles différents ;
- les métriques ajustent le poids local d'une hypothèse de transcription.

### Convergence Whisper

Le prompt doit exploiter activement la convergence entre plusieurs transcriptions.

Une convergence sémantique entre plusieurs Whisper couvrant la même zone doit peser réellement dans l'arbitrage.

Elle doit pouvoir remettre en cause un sous-titre humain, y compris la source structurante.

Elle n'est cependant jamais une preuve absolue car plusieurs modèles Whisper peuvent partager des biais et des erreurs de famille.

En cas de transcription isolée divergente :

- prendre en compte ses diagnostics ;
- son alignement temporel ;
- sa plausibilité ;
- le contexte ;
- le soutien éventuel d'une autre source.

L'objectif est d'éviter deux extrêmes :

```text
"Whisper dit X donc X est vrai"
```

et :

```text
"les métriques ne sont pas absolues donc je les ignore"
```

Le prompt doit faire des métriques un outil réel de pondération locale.

## Implémentation suggérée

L'organisation actuelle permet une modification limitée.

Dans `Private/Merge.ps1` :

- conserver `Get-CanonicalSubtitleCue` ;
- conserver `ConvertTo-SecondarySubtitleCueJson` ;
- ajouter une fonction qui convertit des cues canoniques en `cueId/start/end` sans `text`.

Dans `Tetram.Media.Translation.psm1` :

1. parser `-SubtitlePath` comme aujourd'hui ;
2. produire le gabarit technique depuis `$canonicalCue` ;
3. produire la source structurante `start/end/text` depuis le même `$canonicalCue` ;
4. créer deux `PromptPart` distincts ;
5. indexer les `SecondarySourcePath` à partir de 2 ;
6. conserver le reste de l'orchestration.

Ne pas dupliquer le parsing du fichier source.

## Tests ciblés

Adapter les tests existants sans créer de matrice excessive.

Couvrir au minimum :

1. le gabarit SRT contient `cueId/start/end` mais aucun `text` ;
2. le gabarit ASS contient `cueId/start/end` mais aucun `text` ni champ technique ASS ;
3. la source linguistique structurante contient `start/end/text` mais aucun `cueId` ;
4. le texte de la source structurante est identique au texte canonique envoyé auparavant ;
5. des markers présents dans le `text` structurant restent présents dans ce bloc sans parsing spécifique ;
6. aucun bloc de source linguistique ne contient `cueId` ;
7. la source structurante est numérotée 1 ;
8. les `SecondarySourcePath` sont numérotés 2..N+1 dans l'ordre fourni ;
9. les blocs sous-titres utilisent `SOURCE LINGUISTIQUE N — SOUS-TITRE` ;
10. les blocs Whisper utilisent `SOURCE LINGUISTIQUE N — TRANSCRIPTION WHISPER JSON` ;
11. le compactage Whisper reste inchangé ;
12. une exécution sans source secondaire contient quand même le gabarit + la source linguistique structurante ;
13. la reconstruction finale reste exclusivement basée sur `-SubtitlePath` ;
14. les tests de conservation des tags ASS continuent à passer ;
15. le prompt ressource contient les notions de gabarit technique, source structurante, détermination du sens avant traduction, convergence Whisper et pondération locale ;
16. le prompt ne présente plus une `SOURCE PRINCIPALE` contenant `cueId` et `text`.

Mettre à jour les helpers de tests tels que :

```powershell
Get-CanonicalCuePart
Get-SecondaryWhisperJsonFromPrompt
```

pour les nouveaux marqueurs.

Les appels réseau restent mockés.

Ne pas créer de matrice Gemini/Ollama pour cette transformation, puisqu'elle intervient avant le dispatcher.

## Documentation

Mettre à jour les descriptions devenues fausses dans :

```text
docs/help/Tetram.Media.Translation/ConvertTo-FrenchSubtitle.md
Tetram.Media.Translation/fr-FR/Tetram.Media.Translation-Help.xml
```

La documentation doit expliquer succinctement :

- `-SubtitlePath` définit toujours la structure finale ;
- le LLM reçoit désormais un gabarit `cueId/start/end` sans texte ;
- le texte de `-SubtitlePath` est envoyé séparément comme source linguistique structurante ;
- les autres sources restent des sources linguistiques facultatives ;
- aucune source linguistique n'a de priorité fixe.

Ne pas refondre toute l'aide.

## Non-objectifs

Ne pas :

- renommer `SubtitlePath` ;
- renommer `SecondarySourcePath` ;
- changer l'API publique ;
- modifier les providers Gemini/Ollama ;
- modifier le structured output `{ cueId, text }` ;
- modifier les guards Free Tier ;
- modifier `countTokens` ;
- changer les limites RPM/TPM/RPD ;
- modifier le compactage Whisper ;
- introduire une API fichiers/attachments ;
- ajouter de scoring ou d'alignement PowerShell ;
- extraire les markers ;
- ajouter `requiredMarkers` ;
- ajouter une validation générique des markers SRT ;
- changer la reconstruction finale ;
- ajouter retry/chunking/suppression dynamique de sources ;
- optimiser dans cette tâche la représentation JSON `start/end/text` des sous-titres.

## Critères d'acceptation

1. Le LLM reçoit un gabarit technique `cueId/start/end` sans `text`.
2. Le texte de `-SubtitlePath` est envoyé séparément comme `SOURCE LINGUISTIQUE 1 — SOUS-TITRE STRUCTURANT`.
3. Cette source contient `start/end/text` et aucun `cueId`.
4. Toutes les autres sources sont présentées comme `SOURCE LINGUISTIQUE N`.
5. Aucun texte linguistique n'est directement attaché à un `cueId`.
6. La source structurante n'a aucune priorité linguistique dans le prompt.
7. Ses markers restent les seules contraintes de formatage du fichier final, sans extraction PowerShell.
8. Les markers des autres sous-titres restent informatifs mais non contraignants.
9. Le prompt impose de déterminer le sens avant de formuler le français.
10. Le prompt exploite activement convergence/divergence entre Whisper.
11. Les métriques Whisper servent à une pondération locale qualitative et non à un score mécanique.
12. Une convergence de plusieurs Whisper peut explicitement remettre en cause le sous-titre structurant.
13. Le compactage Whisper reste inchangé.
14. La reconstruction depuis `-SubtitlePath` reste inchangée.
15. Les tests Pester passent.
16. PSScriptAnalyzer passe.
