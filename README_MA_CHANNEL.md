# MA Channel Scalper EA (MQL5)

Expert Advisor de scalping automatique pour MetaTrader 5 basé sur une stratégie de canal de moyennes mobiles (MA Channel) spécialement conçue pour **XAUUSD M1**.

---

## 📌 Logique et Principe de la Stratégie

Le robot crée un canal dynamique à partir de deux moyennes mobiles (MA Supérieure appliquée aux prix Hauts / High et MA Inférieure appliquée aux prix Bas / Low). La stratégie analyse conjointement :
1. **Le comportement du prix par rapport au canal**
2. **L'orientation/pente des deux moyennes mobiles**

### 1. Conditions d'Achat (Long)
- **Signal** : Une bougie de 1 minute (M1) touche la limite inférieure du canal (`Low <= Lower MA`) et clôture au-dessus de la limite supérieure du canal (`Close > Upper MA`).
- **Filtre de Tendance** : Les deux moyennes mobiles formant le canal doivent être orientées à la hausse (`Upper MA1 > Upper MA2` et `Lower MA1 > Lower MA2`).
- **Exécution / Entrée** : L'entrée s'effectue dès que le prix franchit le plus haut (`High`) de cette bougie de signal (via ordre suspendu `Buy Stop` ou cassure au marché).
- **Stop Loss** : Placé au plus bas (`Low`) de la bougie de signal.
- **Règle d'Invalidation** : Le signal/ordre est annulé si le prix franchit le plus bas de la bougie de signal avant l'activation.

### 2. Conditions de Vente (Short)
- **Signal** : Une bougie de 1 minute (M1) touche la limite supérieure du canal (`High >= Upper MA`) et clôture en-dessous de la limite inférieure du canal (`Close < Lower MA`).
- **Filtre de Tendance** : Les deux moyennes mobiles formant le canal doivent être orientées à la baisse (`Upper MA1 < Upper MA2` et `Lower MA1 < Lower MA2`).
- **Exécution / Entrée** : L'entrée s'effectue dès que le prix franchit le plus bas (`Low`) de cette bougie de signal (via ordre suspendu `Sell Stop` ou cassure au marché).
- **Stop Loss** : Placé au plus haut (`High`) de la bougie de signal.
- **Règle d'Invalidation** : Le signal/ordre est annulé si le prix franchit le plus haut de la bougie de signal avant l'activation.

### 3. Take Profit & Gestion des Sorties
- **Take Profit (TP)** : Fixé à une distance équivalente à **2 à 3 fois la largeur du canal** (`Upper MA - Lower MA`).
- **Trailing Stop** : Trailing Stop dynamique basé sur des fractions/multiplicateurs de la largeur du canal.

---

## ⚙️ Paramètres d'Entrée (Inputs)

### Canal de Moyennes Mobiles
- `InpUpperMAPeriod` (Défaut : 20) : Période de la MA supérieure.
- `InpUpperMAMethod` (Défaut : EMA) : Méthode de la MA supérieure.
- `InpUpperMAPrice` (Défaut : PRICE_HIGH) : Prix appliqué à la MA supérieure.
- `InpLowerMAPeriod` (Défaut : 20) : Période de la MA inférieure.
- `InpLowerMAMethod` (Défaut : EMA) : Méthode de la MA inférieure.
- `InpLowerMAPrice` (Défaut : PRICE_LOW) : Prix appliqué à la MA inférieure.

### Exécution & Gestion
- `InpEntryMode` (Défaut : ENTRY_MODE_PENDING_STOP) : Ordres `Buy Stop / Sell Stop` ou exécution au marché sur cassure.
- `InpChannelTPMult` (Défaut : 2.5) : Multiplicateur du TP en nombre de largeurs de canal (ex: 2.5 x largeur du canal).
- `InpBreakoutBuffer` (Défaut : 10.0 points) : Buffer de sécurité au-dessus/en-dessous du High/Low pour l'entrée.
- `InpUseTrailingStop` (Défaut : true) : Active le suivi de tendance adaptatif.
- `InpTrailingStep` (Défaut : 0.5) : Pas du Trailing Stop (en fraction de largeur de canal).

### Gestion des Risques
- `InpMagicNumber` (Défaut : 555888) : Identifiant unique de l'EA.
- `InpFixedLot` (Défaut : 0.01) : Taille de lot fixe si AutoLot est désactivé.
- `InpUseAutoLot` (Défaut : true) : Calcul automatique de la taille de lot basé sur le risque.
- `InpRiskPercent` (Défaut : 1.0%) : Pourcentage du capital risqué par position.

---

## 🛠️ Configuration & Backtest Recommandés
1. **Actif** : XAUUSD (Gold).
2. **Timeframe** : M1 (1 minute).
3. **Type de Compte** : ECN / RAW Spread (faibles spreads recommandés pour le scalping M1).
4. **Exécution** : Activez l'option "Trading Algorithmique" sur MetaTrader 5.
