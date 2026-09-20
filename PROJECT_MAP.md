# PROJECT_MAP — ncd

Navigation rapide vers un répertoire déjà visité, à partir d'un fragment de nom.
Perl 5 + fonctions bash. Aucune dépendance hors modules core.

## Périmètre

- **CORE** : `ncd.pl`, `bashrc.inc`
- **TESTS** : `t/ncd.t`
- **IGNORE** : `.git/`

## Installation

`ncd.pl` → `$HOME/bin/` (exécutable) ; `. $HOME/bin/bashrc.inc` dans `~/.bashrc`.

## Fichiers

### ncd.pl — CORE

Résout un fragment en chemin absolu, l'écrit sur **stdout** (le `cd` est fait par le
shell), messages sur stderr. Sortie 1 = pas de match (le fragment est renvoyé tel
quel pour un `cd` ordinaire).

État persisté :

| Fichier | Contenu |
|---|---|
| `$NCDfile` (déf. `~/.ncdpath`) | pile MRU, un chemin absolu par ligne, plus récent en tête |
| `$NCDfile.mem` | L1 = dernière requête, L2 = index de rotation, L3+ = liste de candidats en cache |

Env : `NCDfile` ; `NCDmax` (illimité si non défini) ; `NCDautoremove` (0 par
défaut) ; `NCDquiet`.

Répertoire disparu : **toujours** signalé sur stderr et sauté, dans tous les cas.
Il reste dans `.ncdpath` sauf si `NCDautoremove` est défini — un
partage démonté ou un volume débranché ne doit pas effacer l'historique.

Options : `-v` (liste les candidats), `-l` (affiche l'historique), `-h`,
`-SWAPLAST [n]`.

**Smart case** : un fragment tout en minuscules ignore la casse ; dès qu'il
contient une majuscule, la recherche devient sensible à la casse (`$CASESENS`,
fixé une fois pour toute l'exécution juste après la résolution de la requête).
`ncd ncd` trouve `NCD_upper` **et** `ncd` ; `ncd NCD` ne trouve que `NCD_upper`.

Flux principal :

1. `read_history()` — lecture + `norm()` + dédoublonnage.
2. `-SWAPLAST n` → anneau `($cwd, historique sans $cwd)`, index `n-1` borné. n=2 ≡ `cd -`.
   Remet la rotation à zéro.
3. Fragment qui est un répertoire réel → `abs_path`, prioritaire sur l'historique.
4. Requête identique à `.mem` L1 → rotation sur la **liste en cache**, conservée
   telle quelle (entrées mortes incluses) pour que `lastidx` reste aligné.
   Sinon `candidates()` et idx=0.
5. `pick()` avance jusqu'au premier candidat vivant et différent du cwd, sur
   **exactement un cycle**. Cache entièrement périmée → nouvelle recherche.
6. `finish()` — `write_history()`, `write_mem()`, `print $target`.

Fonctions :

| Sub | Rôle |
|---|---|
| `norm` | supprime `\r\n` et le `/` final (sauf racine) |
| `tier($comp,$q)` | rang 1..3 : exact → préfixe → sous-chaîne ; 0 = pas de match. Sensible à la casse ou non selon `$CASESENS`. Toujours `\Q…\E` |
| `candidates($q)` | découpe chaque chemin en composants, fenêtre de `k` composants (`k` = segments de la requête, donc `ncd a/b` marche), tronque **juste après** le composant qui matche, `%best` dédoublonne. Tri : tier, puis récence, puis longueur |
| `existing` | filtre les répertoires disparus (anneau `-SWAPLAST` uniquement), un message stderr par entrée |
| `pick($idx,$cwd,@cand)` | avance sur **au plus un tour complet** ; renvoie le 1er candidat vivant ≠ cwd, à défaut le cwd, sinon `-1`. C'est le garde-fou anti-boucle |
| `write_history` | pousse destination **puis** origine en tête, dédoublonne ; purge si `NCDautoremove`, plafonne si `NCDmax` |
| `read_mem`/`write_mem` | cache de rotation |

### bashrc.inc — CORE

`ncd [-v] <fragment>` et `ncs [n]`. Capturent stdout de `ncd.pl` et font le `cd`.
Arguments quotés (`"$@"`). Si la sortie est vide, pas de `cd`.

### t/ncd.t — TESTS

Tests `Test::More` en bac à sable (`tempdir` + `NCDfile`/`HOME` détournés).
Lancer : `prove -v t/ncd.t`.
57 tests. Couvre : priorité des tiers, troncature au bon composant, rotation
(ordre, wrap, reset par une autre requête, reset par `ncs`), saut du cwd,
`ncd .` / `ncd ..`, métacaractères regex (`a+b`, `x.y`), espaces, requête
multi-segments, smart case (minuscules → insensible, majuscule → sensible,
échec assumé), chemins ne différant que par la casse (skippés sur FS
insensible), mise à jour de l'historique, répertoires disparus (écartés,
conservés par défaut, purgés avec `NCDautoremove`, sans perturber la rotation),
cycle borné (tous les candidats morts, cache entièrement périmée),
`NCDmax` défini/illimité, `-SWAPLAST` (toggle, `n`, clamp), sans argument,
historique vide.

## Invariants

- `ncd.pl` n'écrit **que** le chemin cible sur stdout, jamais de diagnostic.
- Aucune regex n'est construite à partir d'un chemin ou d'une requête sans `\Q…\E`.
- Chemins normalisés partout — jamais de comparaison sur une ligne brute du fichier.
- Toute comparaison d'**identité** de chemin est sensible à la casse (`uniq`, clés
  `%best`, `ne $cwd`) : sous Linux, `/a/Proj` et `/a/proj` sont deux répertoires.
  Seul `tier()` replie la casse, et seulement pour le match flou.
- La rotation s'appuie sur le cache `.mem`, pas sur l'historique (qui bouge à chaque appel).
- Tout parcours de la liste de candidats est borné à un cycle (`for (1 .. $n)` dans
  `pick`) : jamais de `while` sur une condition qui peut ne jamais se réaliser.
- L'historique n'est jamais amputé sans que l'utilisateur l'ait demandé
  (`NCDautoremove`, `NCDmax`) : par défaut il ne fait que croître.
- Destination **et** origine entrent dans l'historique (sinon un répertoire atteint
  puis jamais quitté via `ncd` resterait invisible).

## Pièges corrigés (ne pas réintroduire)

- Comparer `$cwd` à une ligne portant encore son `\n` → le saut du cwd ne se fait jamais.
- Re-tronquer le chemin après coup → `ncd .` remonte au parent.
- `.*` gourmand pour tronquer → on atterrit sur `…/ncdtest` au lieu de `…/ncd`.
- Filtrer les entrées mortes de la liste en cache → `lastidx` se désaligne et la
  rotation ressert deux fois le même répertoire.
- Recalculer les candidats entre deux appels d'une même requête → rotation qui piétine.
- `$a` comme variable globale (réservée à `sort`) et interpolée brute en regex.
