# LuckyReversal Expert Advisor (MQL5)

Ce bot de trading automatique pour MetaTrader 5 utilise l'indicateur **Lucky Reversal** pour détecter des opportunités d'achat et de vente sans filtre de support/résistance, avec une gestion de positions avancée.

## 🚀 Logique de Trading

### 0. Unité de Temps (Timeframe)
- **Défaut** : Le bot est configuré pour chercher les signaux sur l'unité de temps **M5** (5 minutes) par défaut.
- **Configurable** : Vous pouvez modifier l'unité de temps via le paramètre `InpTimeframe` dans les réglages du bot.

### 1. Conditions d'Entrée
Le bot réagit immédiatement aux signaux de l'indicateur :
- **ACHAT** : Dès qu'un signal d'achat est détecté par l'indicateur (Buffer 0).
- **VENTE** : Dès qu'un signal de vente est détecté par l'indicateur (Buffer 1).
- **Note** : Les signaux sont lus sur la bougie précédente fermée (index 1) pour éviter les problèmes de repeinture (repainting).

### 2. Gestion des Positions "Forcées"
Une règle spécifique est appliquée selon la taille de votre capital :
- **Si le capital permet au moins 10 trades** : Le bot ouvre 3 positions spécifiques sans **Take Profit**.
- **Conservation** : Ces 3 positions restent ouvertes jusqu'à ce qu'un signal inverse soit détecté.
- **Objectif** : Maximiser les gains sur les grandes tendances (Runners).

### 3. Objectifs (Take Profit Multiple)
Pour les autres positions, le bot utilise des niveaux de TP dynamiques basés sur une distance de repli (`InpFallbackDist`) :
- **TP 1 à TP 4** : Calculés comme des fractions de la distance cible (ex: 0.5x, 0.8x, 1.0x, 1.2x).
- **Distribution** : Les trades sont répartis entre ces niveaux selon des paliers de capital.

### 4. Gestion des Risques et Capital
La taille des lots et le nombre de trades s'adaptent automatiquement :

| Capital ($) | Taille du Lot | Nombre de Trades | Règle des 3 Positions |
|-------------|---------------|------------------|-----------------------|
| 2 - 1,000   | 0.01          | 2                | Non                   |
| 1,001 - 5,000 | 0.03        | 4                | Non                   |
| 5,001 - 15,000 | 0.05       | 6                | Non                   |
| 15,001 - 75,000 | 0.10      | 10               | **Oui (3 trades)**    |
| 75,001 - 400,000 | 0.50     | 16               | **Oui (3 trades)**    |
| > 400,000   | 1.0 - 3.0     | 20               | **Oui (3 trades)**    |

### 5. Trailing Stop Loss (Mise à l'équilibre)
- **Break-Even** : Dès que le niveau **TP 1** est atteint, le Stop Loss de toutes les positions restantes (y compris les 3 positions forcées) est automatiquement déplacé au prix d'ouverture (**Point mort**).

### 6. Sortie sur Signal Inverse
Si un signal opposé à la position actuelle apparaît (ex: signal de Vente alors qu'un Achat est en cours), le bot ferme immédiatement **toutes** les positions, sans exception.

## 🛠 Installation

1. Copiez `LuckyReversal_EA.mq5` dans `MQL5/Experts`.
2. Assurez-vous que l'indicateur `lucky-reversal` est dans `MQL5/Indicators`.
3. Compilez dans le MetaEditor (F7).
4. Activez le "Trading Algorithmique" sur votre plateforme.

## ⚙️ Paramètres (Inputs)

- `InpIndiName` : Nom de l'indicateur (Défaut: "lucky-reversal").
- `InpTimeframe` : Unité de temps pour la détection (Défaut: M5).
- `InpFallbackDist` : Distance par défaut pour les TP (Défaut: 0.00310).
- `InpStopLossPips` : Stop Loss fixe de sécurité en pips.
- `InpMagic` : Numéro magique unique pour ce bot.

---
**Attention** : Testez toujours le bot sur un compte démo avant toute utilisation réelle.
