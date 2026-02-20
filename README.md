# SuperBollingerSR Expert Advisor (MQL5)

Ce bot de trading automatique pour MetaTrader 5 utilise une stratégie basée sur la confluence de deux indicateurs techniques : le **SuperBollingerTrend (SB)** et les **Support/Resistance High Volume Boxes (SR)**.

## 🚀 Logique de Trading

### 0. Unité de Temps (Timeframe)
Le bot est **multi-timeframe par défaut**. Il utilise l'unité de temps du graphique sur lequel il est déposé.
- **Recommandé** : M15, H1 ou H4 pour un meilleur équilibre entre précision et bruit de marché.

### 1. Conditions d'Entrée
Le bot recherche l'alignement entre la tendance et les zones de prix clés :
- **ACHAT** : Signal d'achat SB (croisement du prix au-dessus de la ligne SBT) + Le prix de clôture doit être à l'intérieur d'une zone de **Support** active (rectangle vert).
- **VENTE** : Signal de vente SB (croisement du prix en-dessous de la ligne SBT) + Le prix de clôture doit être à l'intérieur d'une zone de **Résistance** active (rectangle rouge).

### 2. Objectifs (Take Profit)
Le bot calcule dynamiquement jusqu'à 4 niveaux de TP :
- **TP 4 (Cible principale)** : Recherche d'une zone SR adverse dans un intervalle de **0.01500** (1500 points sur GBPUSD).
- **Distance de Repli** : Si aucune zone adverse n'est trouvée, une distance de **0.00310** est utilisée pour fixer un TP par défaut.
- **Niveaux Intermédiaires** : Calculés comme des fractions de la distance vers le TP 4 (ex: 3/6, 4/6, 5/6, 6/6).

### 3. Gestion des Risques et Capital
La taille des lots et le nombre de trades simultanés s'adaptent automatiquement au solde du compte :

| Capital ($) | Taille du Lot | Nombre de Trades |
|-------------|---------------|------------------|
| 2 - 1,000   | 0.01          | 2                |
| 1,001 - 5,000 | 0.03        | 4                |
| 5,001 - 15,000 | 0.05       | 6                |
| 15,001 - 75,000 | 0.10      | 10               |
| 75,001 - 400,000 | 0.50     | 16               |
| > 400,000   | 1.0 - 3.0     | 20               |

### 4. Gestion des Positions (Trailing SL)
- **Break-Even** : Dès que le **TP 1** est touché, le Stop Loss de tous les autres trades restants est déplacé au niveau du prix d'ouverture (Point mort).
- **Sortie Alternative** : Si un signal SB adverse apparaît ou si une nouvelle zone SR adverse est créée, toutes les positions sont fermées immédiatement.

## 🛠 Installation

1. Copiez le fichier `SuperBollingerSR_EA.mq5` dans votre dossier `MQL5/Experts` de MetaTrader 5.
2. Compilez le fichier dans MetaEditor (F7).
3. Glissez l'Expert Advisor sur un graphique (recommandé : GBPUSD, M15 ou H1).
4. Assurez-vous que le "Trading Algorithmique" est activé dans MT5.

## ⚙️ Paramètres (Inputs)

- `InpSBPeriod` : Période de la moyenne mobile pour le SuperBollinger (Défaut: 12).
- `InpSBMult` : Multiplicateur de l'écart-type (Défaut: 2.0).
- `InpSRLookback` : Période de recherche des points pivots pour le SR (Défaut: 20).
- `InpTP4Interval` : Distance max pour chercher un TP adverse (Défaut: 0.01500).
- `InpMagic` : Numéro magique unique pour l'EA.

---
**Avertissement** : Le trading comporte des risques. Testez toujours ce bot sur un compte de démonstration avant de l'utiliser avec du capital réel.
