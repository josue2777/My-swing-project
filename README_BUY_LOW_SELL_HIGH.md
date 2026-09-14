# BuyLowSellHigh Gold Expert Advisor (MQL5)

Ce bot de trading automatique pour MetaTrader 5 est basé sur la stratégie classique et efficace **"Buy Low, Sell High"** (Acheter bas, Vendre haut), spécialement configurée et optimisée pour la volatilité de l'Or (**XAUUSD / GOLD**).

---

## 🚀 Logique et Stratégie de Trading

Le marché du Gold est réputé pour ses mouvements impulsifs et ses phases de réversion à la moyenne. L'EA utilise une confluence de trois indicateurs majeurs pour identifier les vrais points d'épuisement du prix :

### 1. Unité de Temps (Timeframe) Recommandée
- **M15 à H1** : Excellent compromis pour capturer les mouvements intrajournaliers et swing court terme sur le Gold.

### 2. Conditions d'Entrée

#### 🟢 ACHAT ("Buy Low" - Acheter Bas)
1. **RSI (14)** : Doit être en zone de survente (par défaut `< 30`).
2. **Bandes de Bollinger (20, 2.0)** : Le prix plus bas de la bougie doit avoir touché ou dépassé la Bande Inférieure.
3. **Rejet Hausser (Rebound)** : Clôture de la bougie en hausse (Bougie verte / Clôture > Ouverture).
4. **Filtre de Tendance EMA (200)** : *(Optionnel mais activé par défaut)* Le prix de clôture doit être au-dessus de l'EMA 200 pour s'assurer d'acheter uniquement dans le sens de la tendance globale.

#### 🔴 VENTE ("Sell High" - Vendre Haut)
1. **RSI (14)** : Doit être en zone de surachat (par défaut `> 70`).
2. **Bandes de Bollinger (20, 2.0)** : Le prix plus haut de la bougie doit avoir touché ou dépassé la Bande Supérieure.
3. **Rejet Baissier (Rebound)** : Clôture de la bougie en baisse (Bougie rouge / Clôture < Ouverture).
4. **Filtre de Tendance EMA (200)** : *(Optionnel mais activé par défaut)* Le prix de clôture doit être en-dessous de l'EMA 200 pour s'assurer de vendre uniquement dans le sens de la tendance globale.

---

## 🛡️ Gestion du Risque & Money Management

L'EA intègre 3 modes de calcul de la taille de lot :

1. **Tiered (Par palier de balance - Recommandé)** :
   - Balance $2 - $1,000 : **0.01 lot**
   - Balance $1,001 - $5,000 : **0.03 lot**
   - Balance $5,001 - $13,000 : **0.05 lot**
   - Balance $13,001 - $50,000 : **0.10 lot**
   - Balance $50,001 - $150,000 : **0.50 lot**
   - Balance $150,001 - $350,000 : **1.00 lot**
   - Balance > $350,000 : **3.00 lots**

2. **Fixed** : Utilise une taille de lot fixe configurée par l'utilisateur.
3. **Risk %** : Calcule dynamiquement le lot en fonction d'un pourcentage du capital risqué par trade et de la distance du Stop Loss.

---

## 🎯 Stop Loss, Take Profit & Trailing

L'EA offre deux modes de SL/TP :
- **Fixe en Points (Spécial XAUUSD)** :
  - **Stop Loss** : 400 points (équivalent à $4.00 sur le Gold).
  - **Take Profit** : 800 points (équivalent à $8.00 sur le Gold, ratio Risque/Rendement 1:2).
- **ATR Dynamique** : Basé sur la volatilité courante du marché.

### Breakeven & Trailing Stop
- **Breakeven** : Dès que le trade atteint +300 points ($3.00), le SL est automatiquement déplacé au prix d'entrée + 50 points ($0.50) pour sécuriser le trade sans risque.
- **Trailing Stop** : Démarre à partir de +400 points de profit et suit le prix à une distance de 250 points par pas de 50 points.

---

## ⚙️ Paramètres (Inputs)

| Paramètre | Description | Valeur par Défaut (Gold) |
|---|---|---|
| `InpMagic` | Identifiant unique de l'EA | `777888` |
| `InpLotMode` | Mode de gestion de lot (`TIERED`, `FIXED`, `RISK`) | `LOT_MODE_TIERED` |
| `InpFixedLot` | Taille du lot si mode Fixed | `0.01` |
| `InpRiskPercent` | Risque en % si mode Risk | `1.0%` |
| `InpMaxSpread` | Spread max autorisé (points) | `60` (0.60$) |
| `InpRsiPeriod` | Période du RSI | `14` |
| `InpRsiOversold` | Seuil de survente RSI (Buy Low) | `30.0` |
| `InpRsiOverbought` | Seuil de surachat RSI (Sell High) | `70.0` |
| `InpBBPeriod` | Période des Bandes de Bollinger | `20` |
| `InpBBDev` | Déviation des Bandes de Bollinger | `2.0` |
| `InpUseEmaFilter` | Activer le filtre de tendance EMA 200 | `true` |
| `InpEmaPeriod` | Période de l'EMA de tendance | `200` |
| `InpUseAtrSLTP` | Activer SL/TP basés sur l'ATR | `false` |
| `InpStopLossPoints` | Stop Loss fixe en points | `400` ($4.00) |
| `InpTakeProfitPts` | Take Profit fixe en points | `800` ($8.00) |
| `InpUseBreakeven` | Activer le Breakeven automatique | `true` |
| `InpBETriggerPts` | Profit pour déclencher le Breakeven | `300` points |
| `InpBELockPts` | Profit verrouillé lors du Breakeven | `50` points |
| `InpUseTrailing` | Activer le Trailing Stop | `true` |
| `InpTrailingStart` | Profit requis pour démarrer le Trailing | `400` points |
| `InpTrailingDist` | Distance du Trailing Stop | `250` points |
| `InpTrailingStep` | Pas de mise à jour du Trailing | `50` points |

---

## 🛠 Installation

1. Copiez le fichier `BuyLowSellHigh_Gold_EA.mq5` dans le dossier `MQL5/Experts` de MetaTrader 5.
2. Ouvrez MetaEditor (F4) et compilez le fichier (F7).
3. Ouvrez le graphique du **XAUUSD / GOLD** sur l'unité de temps **M15** ou **H1**.
4. Glissez-déposez l'Expert Advisor sur le graphique.
5. Assurez-vous d'activer l'option **"Trading Algorithmique"** (AutoTrading) dans la barre d'outils de MT5.

---
**Avertissement** : Le trading sur l'Or (XAUUSD) comporte des risques élevés en raison de sa forte volatilité. Veuillez toujours tester l'EA sur un compte Démo avant toute utilisation en réel.
