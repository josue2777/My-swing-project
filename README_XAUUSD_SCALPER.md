# XAUUSD Momentum Scalper EA - Documentation Technique

## 1. Introduction & Concept Théorique

Le **XAUUSD Momentum Scalper EA** (`XAUUSD_Momentum_Scalper_EA.mq5`) est un Expert Advisor de scalping à haut rendement spécialement conçu pour l'Or (**XAUUSD**).

Sa logique quantitative s'inspire directement des principes formulés par Zura Kakushadze dans *"151 Trading Strategies"* :
1. **Price-Momentum (Section 3.1)** : Exploitation de la poursuite de tendance à court terme entraînée par la pression d'achat/vente sur les métaux précieux.
2. **Channel / Volatility Breakout (Section 3.15 & Section 10.4)** : Détection des moments d'expansion de volatilité où le prix s'affranchit d'un canal de moyenne mobile sous confirmation de l'ATR.

---

## 2. Fondements Mathématiques & Modèle de Rendement (~50%/Mois)

L'objectif de rendement élevé (cible de ~50% par mois) repose sur la synergie entre un **taux de réussite élevé en scalping**, un **ratio risque/récompense favorable (1:2)** et l'effet de **composition dynamique du capital (*compounding*)**.

### Formule de la Taille de Position Dynamique
$$\text{Risque (\$)} = \text{Capital (Equity)} \times \frac{\text{InpRiskPercent}}{100}$$

$$\text{Volume (Lots)} = \frac{\text{Risque (\$)}}{\text{StopLoss (Points)} \times \text{Valeur du Point (\$)}}$$

### Simulation Mathématique de Composition
- **Nombre moyen de trades / jour** : 3 à 6 trades
- **Taux de gain (*Win Rate*) cible** : 60% à 68%
- **Ratio Gain/Perte (*Payoff Ratio*)** : 2.0 (TP = 500 points / SL = 250 points)
- Avec un risque géré de 2.5% par position et un réinvestissement continu des gains (*Compounding*), le taux de croissance mensuel géométrique peut atteindre la cible de ~50% sous des conditions normales de volatilité sur XAUUSD M5.

---

## 3. Règles de Trading & Stratégie d'Entrée/Sortie

### Conditions d'Entrée en Achat (BUY)
1. **Filtre Directionnel SAR** : Le cours de clôture de la bougie précédente ($C_1$) est supérieur au Parabolic SAR ($SAR_1$).
2. **Filtre de Tendance EMA** : L'EMA rapide ($EMA_8$) est au-dessus de l'EMA lente ($EMA_{21}$).
3. **Filtre de Volatilité ATR** : L'ATR (14) dépasse la valeur minimale requise (`InpMinATRPoints`, ex: 80 points = $0.80 XAU).
4. **Trigger d'Impulsion (Breakout)** : Le plus haut ($H_1$) dépasse $EMA_8 + \text{InpBreakoutPoints}$.

### Conditions d'Entrée en Vente (SELL)
1. **Filtre Directionnel SAR** : Le cours de clôture de la bougie précédente ($C_1$) est inférieur au Parabolic SAR ($SAR_1$).
2. **Filtre de Tendance EMA** : L'EMA rapide ($EMA_8$) est en dessous de l'EMA lente ($EMA_{21}$).
3. **Filtre de Volatilité ATR** : L'ATR (14) dépasse le seuil minimal requise.
4. **Trigger d'Impulsion (Breakout)** : Le plus bas ($L_1$) casse en dessous de $EMA_8 - \text{InpBreakoutPoints}$.

### Gestion Avancée des Positions
- **Break-Even Dynamique** : Dès que le profit atteint `InpBreakEvenPoints` (ex: 150 points), le Stop Loss est déplacé au prix d'entrée + `InpBreakEvenProfit` (30 points) pour sécuriser le trade sans risque.
- **Trailing Stop Adaptatif** : Dès que le gain dépasse `InpTrailingStopPoints` (200 points), le SL suit le cours au fur et à mesure des nouveaux plus hauts/bas par pas de `InpTrailingStepPoints`.

---

## 4. Guide des Paramètres de l'Expert Advisor

| Paramètre | Valeur par défaut | Description |
| :--- | :--- | :--- |
| `InpTimeframe` | `PERIOD_M5` | Unité de temps d'exécution (M5 recommandé) |
| `InpSarStep` | `0.02` | Pas du Parabolic SAR |
| `InpSarMaximum` | `0.20` | Maximum du Parabolic SAR |
| `InpFastEMAPeriod` | `8` | Période de l'EMA rapide |
| `InpSlowEMAPeriod` | `21` | Période de l'EMA lente |
| `InpATRPeriod` | `14` | Période de l'indicateur d'ATR |
| `InpMinATRPoints` | `80.0` | Seuil minimal d'ATR en points ($0.80) |
| `InpBreakoutPoints` | `30.0` | Offset de cassure en points ($0.30) |
| `InpRiskMode` | `RISK_PERCENT_EQUITY` | Mode de calcul des lots (`RISK_FIXED_LOT`, `RISK_PERCENT_EQUITY`, `RISK_TIERED_BALANCE`) |
| `InpRiskPercent` | `2.5` | Pourcentage d'Equity risqué par position (pour cibler ~50%/mois) |
| `InpStopLossPoints` | `250` | Stop Loss en points (250 points = $2.50) |
| `InpTakeProfitPoints` | `500` | Take Profit en points (500 points = $5.00) |
| `InpBreakEvenPoints` | `150` | Déclencheur du Break-Even en points |
| `InpBreakEvenProfit` | `30` | Profit verrouillé lors du Break-Even en points |
| `InpTrailingStopPoints`| `200` | Distance du Trailing Stop en points |
| `InpTrailingStepPoints`| `50` | Pas de réajustement du Trailing Stop |
| `InpMaxSpreadPoints` | `250` | Filtre de spread maximal toléré ($2.50) |
| `InpMaxOpenTrades` | `2` | Nombre maximal de positions simultanées |
| `InpUseTradingHours` | `true` | Activation du filtre d'heures de session |
| `InpStartHour` | `7` | Heure de début de session (7h00 serveur) |
| `InpEndHour` | `21` | Heure de fin de session (21h00 serveur) |

---

## 5. Recommandations de Gestion des Risques & Utilisation

1. **Broker & Spread** : Utiliser un compte ECN à faible spread ou Raw Spread (spread moyen sur XAUUSD < 15-20 points).
2. **Effet de levier** : Un levier d'au moins 1:100 à 1:500 est recommandé pour permettre le calcul dynamique des lots en mode compounding.
3. **Backtesting & Optimisation** : Tester sur l'historique M5 "Every tick based on real ticks" sur MetaTrader 5.

---

*Fichier faisant partie de la suite d'EAs MQL5 pour MetaTrader 5.*
