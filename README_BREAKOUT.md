# BreakoutTrading Expert Advisor (MQL5)

Cet Expert Advisor (EA) MetaTrader 5 implémente une stratégie quantitative de **Breakout Trading** conçue pour capturer uniquement les cassures à forte probabilité de continuation tout en filtrant les faux breakouts.

## 🚀 Fonctionnalités Clés & Logique de Trading

### 1. Détection Automatique de Consolidation
Le bot identifie les phases de compression de marché :
- **Hauteur du Range** : Limite supérieure et inférieure calculées sur les `InpConsolidationBars` dernières bougies. La hauteur maximale est bridée en fonction de l'ATR (`InpMaxRangeATRMult`).
- **Compression d'ATR** : Vérification que la volatilité actuelle est compressée par rapport à sa moyenne mobile (`InpATRCompression`).

### 2. Validation du Breakout & Volume / Volatilité
- **Clôture Confirmée** : Entrée uniquement sur bougie clôturée en dehors des bornes du range.
- **Filtre de Volume/Volatilité** : Nécessite une hausse significative du volume tick (`InpVolumeMult`) ou une expansion de l'amplitude de la bougie par rapport à l'ATR (`InpBarExpansionMult`).

### 3. Filtre de Liquidité & Spread
- Suspension des ordres si le spread dépasse le niveau maximal autorisé (`InpMaxSpreadPoints`), évitant de trader lors des périodes illiquides.

### 4. Option de Retest du Niveau Cassé
- Lorsque `InpRequireRetest` est activé, l'EA attend un pullback/retest du niveau de cassure (dans la zone de tolérance ATR) avant d'exécuter la position.

### 5. Gestion des Risques & Stop Loss
- **Stop Loss Structurel ou ATR** : Positionné selon le niveau bas/haut du range de consolidation ou la distance ATR (`InpSL_ATR_Mult`), en choisissant le plus cohérent.
- **Taille de Lot Dynamique** : Gestion du lot adaptée au capital du compte ou par pourcentage de risque.

### 6. Dynamic Take-Profit & Trailing Stop Adaptatif
- **Multiples Take Profit (TP1, TP2, TP3)** basés sur des multiples de l'ATR.
- **Break-Even** : Dès que le niveau TP1 est atteint, les positions restantes basculent leur SL au prix d'ouverture.
- **Trailing Stop Intelligent** : Ajuste dynamiquement le Stop Loss en fonction de la volatilité courante (`InpTrailATRMult * ATR`).

### 7. Suspension en Marché Latéral & Position Unique
- **Filtre Latéral Post-Breakout** : Suspend de nouvelles entrées si le marché devient stagnant après une cassure.
- **Position Unique par Direction** : Interdit l'ouverture de nouvelles positions dans la même direction tant que la position précédente est active.
- **Multi-Actifs** : Fonctionne de manière universelle sur Forex, Indices et Matières premières.

---

## ⚙️ Paramètres Principaux (Inputs)

- `InpConsolidationBars` : Période d'analyse de la consolidation (Défaut : 20).
- `InpMaxRangeATRMult` : Multiplicateur ATR max pour la hauteur du range (Défaut : 3.5).
- `InpVolumeMult` : Seuil de volume relatif minimum (Défaut : 1.25).
- `InpRequireRetest` : Activer/Désactiver l'exigence d'un retest (Défaut : false).
- `InpMaxSpreadPoints` : Spread maximal autorisé en points (Défaut : 50.0).
- `InpSL_ATR_Mult` : Multiplicateur ATR pour le Stop Loss (Défaut : 1.50).
- `InpTrailATRMult` : Multiplicateur ATR pour le Trailing Stop (Défaut : 2.0).
- `InpMagic` : Numéro Magic unique (Défaut : 888111).
