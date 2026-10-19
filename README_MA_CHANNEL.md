# Expert Advisor : Scalper Canal de Moyennes Mobiles (`MAChannel_Scalper_EA`)

## Description
L'Expert Advisor **`MAChannel_Scalper_EA.mq5`** implémente une stratégie de scalping M1 (principalement conçue pour **XAUUSD** / Or) basée sur un canal formé par deux moyennes mobiles (MA High et MA Low).

La stratégie exploite la dynamique d'une bougie englobant ou traversant entièrement le canal pour capturer le déclenchement de la tendance et entrer sur la cassure du plus haut / plus bas de cette bougie de signal.

---

## Logique de la Stratégie

### 1. Canal de Moyennes Mobiles
* **Moyenne Mobile Supérieure** : EMA 20 appliquée sur les `HIGH` (Haut de bougie).
* **Moyenne Mobile Inférieure** : EMA 20 appliquée sur les `LOW` (Bas de bougie).
* **Largeur du canal** = $|MA_{Upper} - MA_{Lower}|$.

### 2. Signal d'Achat (BUY)
Une bougie complète (index 1) déclenche un signal d'Achat si :
1. **Low $\le$ MA Inférieure** (La bougie touche ou traverse la limite inférieure du canal).
2. **Close $>$ MA Supérieure** (La bougie clôture au-dessus de la limite supérieure du canal).
3. **Pente des MAs** : Les deux moyennes mobiles doivent être orientées à la hausse ($MA1 > MA2$). *(Note : Ce filtre peut être désactivé via le paramètre `InpRequireMASlope`)*.

**Entrée** :
* Ordre suspendu `Buy Stop` placé au `High` de la bougie de signal + `InpBreakoutBuffer`.
* **Stop Loss (SL)** : Placé au `Low` de la bougie de signal.
* **Take Profit (TP)** : Placé à $2.5 \times \text{Largeur du canal}$.

### 3. Signal de Vente (SELL)
Une bougie complète (index 1) déclenche un signal de Vente si :
1. **High $\ge$ MA Supérieure** (La bougie touche ou traverse la limite supérieure du canal).
2. **Close $<$ MA Inférieure** (La bougie clôture en dessous de la limite inférieure du canal).
3. **Pente des MAs** : Les deux moyennes mobiles doivent être orientées à la baisse ($MA1 < MA2$). *(Optionnel selon `InpRequireMASlope`)*.

**Entrée** :
* Ordre suspendu `Sell Stop` placé au `Low` de la bougie de signal - `InpBreakoutBuffer`.
* **Stop Loss (SL)** : Placé au `High` de la bougie de signal.
* **Take Profit (TP)** : Placé à $2.5 \times \text{Largeur du canal}$.

### 4. Règle d'Invalidation Strict du Signal
* **Achat** : Si le prix franchit vers le bas le `Low` de la bougie de signal avant le déclenchement de l'ordre d'achat, le signal et l'ordre suspendu sont immédiatement annulés.
* **Vente** : Si le prix franchit vers le haut le `High` de la bougie de signal avant le déclenchement de l'ordre de vente, le signal et l'ordre suspendu sont immédiatement annulés.

---

## Paramètres d'Entrée (`Inputs`)

| Paramètre | Type | Valeur par défaut | Description |
| :--- | :--- | :--- | :--- |
| `InpUpperMAPeriod` | `int` | `20` | Période de la MA Supérieure |
| `InpUpperMAMethod` | `ENUM_MA_METHOD` | `MODE_EMA` | Méthode (EMA, SMA, etc.) |
| `InpUpperMAPrice` | `ENUM_APPLIED_PRICE` | `PRICE_HIGH` | Prix appliqué à la MA Supérieure |
| `InpLowerMAPeriod` | `int` | `20` | Période de la MA Inférieure |
| `InpLowerMAMethod` | `ENUM_MA_METHOD` | `MODE_EMA` | Méthode (EMA, SMA, etc.) |
| `InpLowerMAPrice` | `ENUM_APPLIED_PRICE` | `PRICE_LOW` | Prix appliqué à la MA Inférieure |
| `InpRequireMASlope`| `bool` | `true` | Exiger l'orientation (pente) des MAs |
| `InpEntryMode` | `ENUM_ENTRY_MODE` | `ENTRY_MODE_PENDING_STOP` | `ENTRY_MODE_PENDING_STOP` ou `ENTRY_MODE_MARKET_BREAKOUT` |
| `InpChannelTPMult` | `double` | `2.5` | Multiplicateur TP en largeurs de canal |
| `InpBreakoutBuffer` | `double` | `10.0` | Buffer de cassure en points |
| `InpUseTrailingStop`| `bool` | `true` | Activer le Trailing Stop dynamique |
| `InpTrailingStep` | `double` | `0.5` | Distance du Trailing Stop en fraction de canal |
| `InpMinModStep` | `double` | `20.0` | Seuil minimum de modification SL en points (évite les erreurs `failed modify`) |
| `InpMagicNumber` | `ulong` | `555888` | Magic Number unique du bot |
| `InpFixedLot` | `double` | `0.01` | Taille de lot fixe |
| `InpUseAutoLot` | `bool` | `true` | Auto-calcul de la taille de lot par risque |
| `InpRiskPercent` | `double` | `1.0` | Pourcentage du solde risqué par trade |

---

## Remarques Techniques & Conformité Courtier

1. **Gestion des Niveaux de Stop (`SYMBOL_TRADE_STOPS_LEVEL`)** :
   Le bot intègre une vérification automatique des contraintes de distance minimale imposable par le courtier (`StopsLevel`). Si la distance entre le cours actuel et le Stop Loss / Take Profit ou le prix d'entrée d'un ordre suspendu est inférieure au niveau de stop du courtier, le prix est automatiquement ajusté au niveau autorisé afin d'éviter tout rejet d'ordre ou erreur `failed modify`.

2. **Ajustement de la Pente des Moyennes Mobiles (`InpRequireMASlope`)** :
   Si vous trouvez que les signaux sont trop rares en backtest sur certaines paires ou périodes très peu volatiles, vous pouvez passer `InpRequireMASlope` à `false`. Cela autorisera les entrées dès qu'une bougie traverse le canal du bas vers le haut (Achat) ou du haut vers le bas (Vente).
