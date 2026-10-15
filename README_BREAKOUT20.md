# Breakout20 Expert Advisor (MQL5)

Ce bot de trading automatique pour MetaTrader 5 identifie le point le plus haut (High) et le point le plus bas (Low) des **20 dernières bougies** pour placer deux ordres en attente (`Buy Stop` au High et `Sell Stop` au Low).

## 🚀 Fonctionnement et Logique de Trading

1. **Identification des Points Haut et Bas** :
   - À chaque recalcul, l'EA analyse les 20 dernières bougies clôturées (indices 1 à 20).
   - Il détermine le plus haut sommet (`Highest High`) et le plus bas creux (`Lowest Low`).

2. **Ordres en Attente** :
   - Placements simultanés :
     - **Buy Stop** au niveau du point haut.
     - **Sell Stop** au niveau du point bas.
   - **Take Profit (TP)** : Fixé à **3000 points**.
   - **Stop Loss (SL)** : Fixé à **2000 points**.

3. **Gestion du Capital et Risk Management** :
   - Risque fixe de **3% du capital (solde du compte)** par ordre.
   - Le volume du lot est calculé dynamiquement selon la formule :
     $$\text{Lot} = \frac{\text{Capital} \times 0.03}{\text{Distance SL en Ticks} \times \text{Valeur du Tick}}$$
   - Ajustement automatique selon les règles du courtier (lot minimum, lot maximum, pas de lot).

4. **Recalcul et Actualisation des Ordres** :
   - **Cycle des 10 Nouvelles Bougies** : Si pendant 10 bougies aucun ordre n'est déclenché (touché), les anciens ordres en attente sont annulés, le point haut/bas des 20 dernières bougies est recalculé, et deux nouveaux ordres sont positionnés.
   - **Fermeture de Position (SL / TP)** : Lorsqu'une position ouverte est clôturée (par SL ou TP), tous les ordres en attente restants sont annulés, un nouveau calcul des 20 dernières bougies est effectué et de nouveaux ordres sont placés.

## ⚙️ Paramètres (Inputs)

- `InpMagic` : Numéro magique unique identifiant les ordres de l'EA (Défaut : `334455`).
- `InpLookbackBars` : Nombre de bougies pour le calcul du High/Low (Défaut : `20`).
- `InpRecalcBars` : Nombre de nouvelles bougies avant recalcul si les ordres ne sont pas touchés (Défaut : `10`).
- `InpStopLossPoints` : Stop Loss en points (Défaut : `2000`).
- `InpTakeProfitPoints` : Take Profit en points (Défaut : `3000`).
- `InpRiskPercent` : Pourcentage de risque par trade basé sur le solde du compte (Défaut : `3.0` %).

## 🛠 Installation

1. Copiez le fichier `Breakout20_EA.mq5` dans le dossier `MQL5/Experts` de votre plateforme MetaTrader 5.
2. Compilez le fichier dans MetaEditor (F7).
3. Attachez l'Expert Advisor sur le graphique de votre choix.
4. Assurez-vous que l'option **"Trading Algorithmique"** est activée dans MetaTrader 5.
