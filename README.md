# Pixel Spell

Jeu Roblox de magie : on construit ses sorts en assemblant des cartes dans une baguette (sorts, modificateurs, multi-tirs), avec incantations, cercles magiques à runes, matière destructible et effets en pixel art.

## Contenu

| Dossier | Rôle |
|---|---|
| `game/` | Tous les scripts Luau du jeu, exportés depuis Roblox Studio (un fichier par script, arborescence identique à l'Explorer). |
| `tools/` | Outils Node : générateurs de sprites et de runes pixel art, petit serveur local pour l'import d'images. |
| `sprites/` | Sprites et planches générés (cercles magiques, runes, icônes). |
| `synth/` | Sons de test synthétisés. |
| `compare/` | Captures de comparaison visuelle. |

Extensions dans `game/` : `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript.

## Note

Le code de référence reste celui de la place Roblox ; `game/` en est un instantané exporté.
