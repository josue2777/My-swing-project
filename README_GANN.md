# Gann50 Expert Advisor (MQL5)

Ce bot de trading automatique pour MetaTrader 5 utilise la **Théorie des 50% de Gann** appliquée au range de la journée précédente.

## 🚀 Logique de Trading

### 1. Signal d'Entrée (Rebond des 50%)
Le bot calcule le point milieu (50%) entre le Plus Haut et le Plus Bas de la journée précédente :
- **ACHAT** : Le prix touche le niveau 50% par le haut, puis une bougie confirme le rebond en clôturant au-dessus du niveau 50%.
- **VENTE** : Le prix touche le niveau 50% par le bas, puis une bougie confirme le rebond en clôturant en-dessous du niveau 50%.

### 2. Niveaux de Take Profit (Harmoniques de Gann)
Le bot divise le mouvement attendu en paliers basés sur les divisions de Gann :
- **TP 1** : Niveau 62.5% du range (Huitième de Gann).
- **TP 2** : Niveau 75% du range.
- **TP 3** : Niveau 87.5% du range.
- **TP 4** : Niveau 100% (Plus Haut ou Plus Bas de la veille).

### 3. Gestion des Risques
Le bot utilise la même structure de gestion que le bot SuperBollingerSR :
- **Lots** : Adaptés selon le solde du compte (de 0.01 à 3.0).
- **Nombre de Trades** : Entre 2 et 20 positions simultanées par signal selon le capital.

### 4. Gestion du Stop Loss
- **Position initiale** : Fixée au niveau harmonique opposé (37.5% ou 62.5%).
- **Breakeven** : Dès que le **TP 1** est atteint, le Stop Loss de toutes les positions restantes est déplacé au prix d'entrée (0 risque).

## 🛠 Installation

1. Copiez `Gann50_EA.mq5` dans `MQL5/Experts`.
2. Compilez dans MetaEditor.
3. Appliquez sur un graphique (GBPUSD recommandé).

---
**Avertissement** : Les niveaux de Gann sont des points pivots psychologiques puissants mais nécessitent une gestion rigoureuse. Testez sur compte démo.
