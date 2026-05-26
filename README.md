# oh-my-exegol

Ma configuration d'Exegol, installée via `my-resources`.

Ce dépôt ajoute quelques hooks zsh dans les containers et propose, au premier shell, de mettre à jour les certains outils et d'installer certaines tools.

## Installation

Installation classique :

```bash
./install.sh
```

Au premier shell du container, une question propose de lancer :

- `apt update` / `apt upgrade`
- mise à jour de `pip`
- mise à jour de NetExec
- `msfupdate`

Les logs sont écrits dans le container :

```bash
/root/.config/oh-my-exegol/important-tool-updates.log
```

## AdaptixC2

AdaptixC2 n'est pas installé par défaut.

Pour l'ajouter :

```bash
./install.sh --adaptix
```

Avec cette option, l'installation ajoute Adaptix serveur, l'historique, les alias, le client AppImage ainsi que sa configuration pour utiliser le serveur Adaptix dans exegol.

Alias disponibles dans le container :

```bash
adaptix-server
adaptix-client
```

## Désinstallation

```bash
./install.sh --uninstall
```
