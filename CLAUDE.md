# CLAUDE.md — ncd

Outil de navigation : `ncd <fragment>` saute vers un répertoire déjà visité dont un
composant du chemin matche le fragment ; répéter la commande fait tourner sur les
autres correspondances. `ncs [n]` alterne entre les n derniers répertoires.
Recherche en *smart case* : minuscules → insensible à la casse, une majuscule
quelque part → sensible à la casse.

Voir `PROJECT_MAP.md` pour l'architecture détaillée (ne pas la dupliquer ici).

## Périmètre

- **CORE** : `ncd.pl`, `bashrc.inc` — toute modification ici impose de relancer les tests
- **TESTS** : `t/ncd.t`
- **DOC** : `PROJECT_MAP.md`, `CLAUDE.md`
- **IGNORE** : `.git/`, `~/.ncdpath*` (état runtime de l'utilisateur, hors dépôt)

## Commandes

```bash
prove -v t/ncd.t      # suite complète
perl -c ncd.pl        # contrôle de syntaxe
```

Cinq tests portent sur deux répertoires ne différant que par la casse. Ils sont
skippés sur un FS insensible (NTFS, macOS par défaut) — jamais supprimés, le
script doit gérer ce cas sous Linux. Pour les exécuter sous Windows :

```bash
fsutil file setCaseSensitiveInfo <dir> enable   # cmd/PowerShell
TMPDIR=/c/chemin/vers/<dir> prove -v t/ncd.t
```

Un run qui affiche `# skip` sur ces tests ne vaut pas validation : avant de
toucher à `tier()`, `uniq()` ou aux comparaisons de chemins, lancer la suite
au moins une fois sur un FS sensible à la casse.

Les tests s'exécutent en bac à sable (`tempdir`, `NCDfile`/`HOME` détournés) : ils ne
touchent jamais le `~/.ncdpath` réel. Ne jamais écrire de test qui s'en écarte.

## Contraintes

- **Perl core uniquement.** Aucune dépendance CPAN — le script est copié tel quel dans
  `$HOME/bin` sur des machines sans droits d'installation.
- **Cible double : msys/Git-Bash (Windows) et Linux.** Chemins POSIX (`/c/...`),
  séparateur `/`, jamais de `\` ni de `File::Spec` dans la logique de matching.
- **stdout est réservé au chemin cible.** Tout diagnostic passe par `info()` → stderr,
  sinon le `cd` du shell casse. Sortie 1 + fragment renvoyé = « pas de match, tente un
  `cd` ordinaire ».
- **`use strict; use warnings;`** en tête de tout script Perl du dépôt.
- Toute regex construite à partir d'un chemin ou d'une requête utilisateur passe par
  `\Q…\E`.
- Ne pas réintroduire les pièges listés en fin de `PROJECT_MAP.md`.

## Workflow

1. Modifier `ncd.pl` ou `bashrc.inc`.
2. `prove -v t/ncd.t` — doit être vert avant toute conclusion.
3. Ajouter un test pour tout comportement nouveau ou tout bug corrigé (le dépôt a une
   histoire de régressions silencieuses : un bug sans test revient).
4. Proposer `/update-map` si la structure de `ncd.pl` a changé.

## Git

Dépôt local uniquement, pas de remote. Voir les préférences globales.
