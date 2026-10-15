# Breakout20 Expert Advisor (MQL5) - Version 2.00

Ce bot de trading automatique pour MetaTrader 5 identifie le point le plus haut (High) et le point le plus bas (Low) des **20 dernières bougies** pour placer deux ordres en attente (`Buy Stop` et `Sell Stop`). Il intègre des filtres techniques avancés, un décalage d'ordre dynamique par l'ATR, le Break Even à +1R, un Trailing Stop dynamique et une suspension automatique après pertes consécutives.

## 🚀 Améliorations et Fonctionnalités Clés

1. **Identification des Points Haut et Bas & Décalage (0.5 × ATR)** :
   - Analyse des 20 dernières bougies clôturées (indices 1 à 20).
   - Placement du **Buy Stop** à `High + 0.5 × ATR`.
   - Placement du **Sell Stop** à `Low - 0.5 × ATR`.

2. **Filtres de Trading Avancés** :
   - **Filtre Tendance EMA 200** : Achat uniquement si le prix est au-dessus de l'EMA 200, Vente uniquement si en dessous.
   - **Filtre Mouvement ADX 14** : Les ordres ne sont placés que si l'ADX est supérieur ou égal à 25 ($\text{ADX} \ge 25$).
   - **Filtre Volatilité ATR 14** : Vérification qu'un niveau de volatilité minimal est respecté.

3. **Confirmation de Cassure** :
   - Analyse basée exclusivement sur les bougies clôturées. Pas de faux déclenchements sur simple mèche.

4. **Gestion de Position (Break Even & Trailing Stop)** :
   - **Break Even à +1R** : Dès que le gain de la position atteint le niveau du Stop Loss (+1R / 2000 points), le Stop Loss est déplacé au prix d'entrée.
   - **Trailing Stop Dynamique (2 × ATR)** : Une fois le Break Even activé, le Stop Loss suit le prix à une distance de `2.0 × ATR`.

5. **Gestion des Pertes Consécutives** :
   - Compteur de Stop Loss consécutifs.
   - Après **2 pertes consécutives**, la prise d'ordre est automatiquement **suspendue pendant 10 bougies**, puis reprend automatiquement.

6. **Ordres en Attente & Gestion du Risque** :
   - Annulation automatique de l'ordre opposé dès qu'un ordre est déclenché.
   - Calcul dynamique du lot basé sur **3% du capital** par trade.
   - Recalcul des ordres toutes les **10 bougies** si aucun ordre n'est touché ou après chaque fermeture de position.

## ⚙️ Paramètres (Inputs)

- `InpMagic` : Numéro magique de l'EA (Défaut : `334455`).
- `InpLookbackBars` : Bougies pour le calcul du High/Low (Défaut : `20`).
- `InpRecalcBars` : Bougies sans déclenchement avant recalcul (Défaut : `10`).
- `InpStopLossPoints` : Stop Loss en points (Défaut : `2000`).
- `InpTakeProfitPoints` : Take Profit en points (Défaut : `3000`).
- `InpRiskPercent` : Pourcentage de risque par trade (Défaut : `3.0` %).
- `InpUseEMA` / `InpEMAPeriod` : Activation et période du filtre EMA (Défaut : `200`).
- `InpUseADX` / `InpADXPeriod` / `InpADXMinLevel` : Activation et seuil de l'ADX (Défaut : `14`, seuil `25.0`).
- `InpUseATR` / `InpATRPeriod` / `InpATROffsetMult` : Filtre et décalage ATR (Défaut : `0.5` × ATR).
- `InpUseBreakEven` / `InpUseTrailingStop` / `InpTrailingATRMult` : Break Even +1R et Trailing Stop (`2.0` × ATR).
- `InpMaxLosses` / `InpPauseBars` : Pause de 10 bougies après 2 pertes consécutives.

## 🛠 Installation

1. Copiez le fichier `Breakout20_EA.mq5` dans votre dossier `MQL5/Experts` de MetaTrader 5.
2. Compilez dans MetaEditor (F7).
3. Attachez l'EA au graphique de votre choix.
