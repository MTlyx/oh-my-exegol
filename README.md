# oh-my-exegol

Ma configuration d'exegol avec my-ressources. 

À chaque nouveau container, le premier shell propose de mettre à jour les outils essentiels. Il permet grossièrement de faire :
- `apt update`
- `apt upgrade`
- `pip update`
- `NetExec update`

Les logs complets sont gardés dans le container :

```bash
root/.config/oh-my-exegol/important-tool-updates.log
```

## Installation

```bash
./install.sh
```

Puis démarre un nouveau container :

```bash
exegol start test full
```

## Désinstallation

```bash
./install.sh --uninstall
```
