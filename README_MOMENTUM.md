# MomentumTrading Expert Advisor (MQL5)

Cet Expert Advisor (EA) MetaTrader 5 implémente une stratégie quantitative de **Momentum Trading** conçue pour entrer sur le marché uniquement en phase de forte accélération du prix et de tendance confirmée.

## 🚀 Fonctionnalités Clés & Logique de Trading

### 1. Détection de la Tendance Dominante
- **Filtre de Tendance EMA & ADX** : Combine une moyenne mobile exponentielle (`InpEMAPeriod`) et l'ADX (`InpMinADX`) pour valider la direction du marché.
- **Interdiction du Counter-Trend** : Refuse catégoriquement toute prise de position à contre-courant de la tendance majeure.

### 2. Moteur de Momentum Multi-Confirmations
L'entrée nécessite la convergence simultanée de plusieurs critères :
- **Taux de Variation du Prix (ROC %)** : Accélération supérieure au seuil minimum (`InpMinROCPercent`).
- **Amplitude des Bougies** : Taille du corps de la bougie supérieure au ratio ATR (`InpBarBodyATRRatio`).
- **Confirmation par le Volume** : Volume supérieur au volume moyen (`InpVolumeIncrease`).

### 3. Filtre de Volatilité
- Évite les marchés calmes ou en consolidation grâce au contrôle du ratio ATR actuel par rapport à sa moyenne mobile long terme (`InpMinATRMulti`).

### 4. Stop Loss & Sortie Dynamique
- **Stop Loss Basé sur l'ATR** : Calculé selon la volatilité récente (`InpSL_ATR_Mult * ATR`) au lieu d'une distance fixe en points.
- **Sortie Rapide sur Ralentissement** : Ferme automatiquement la position si le momentum faiblit (`InpROCExitThreshold`).
- **Trailing Stop Adaptatif** : Accompagne le mouvement tant que la dynamique reste forte (`InpTrailATRMult * ATR`).

### 5. Protection contre le Sur-Trading
- **Période de Pause (Cooldown)** : Impose un nombre minimum de bougies (`InpCooldownBars`) entre deux entrées consécutives.
- **Nombre Maximal de Positions** : Limite le nombre de positions ouvertes simultanément (`InpMaxOpenPositions`).
- **Adaptation Multi-Actifs** : Les paramètres basés sur les pourcentages et l'ATR s'adaptent naturellement à tous les instruments (Forex, Indices, Commodities).

---

## ⚙️ Paramètres Principaux (Inputs)

- `InpEMAPeriod` : Période de l'EMA de tendance dominante (Défaut : 200).
- `InpMinADX` : Niveau minimal d'ADX pour valider la force de tendance (Défaut : 22.0).
- `InpROCPeriod` : Période du calcul de Rate of Change (Défaut : 10).
- `InpMinROCPercent` : Seuil minimal d'accélération en % (Défaut : 0.35).
- `InpBarBodyATRRatio` : Ratio taille du corps / ATR (Défaut : 1.10).
- `InpSL_ATR_Mult` : Multiplicateur ATR du Stop Loss (Défaut : 1.75).
- `InpROCExitThreshold` : Seuil ROC de ralentissement pour sortie anticipée (Défaut : 0.10).
- `InpCooldownBars` : Pause en bougies entre 2 trades (Défaut : 5).
- `InpMagic` : Numéro Magic unique (Défaut : 999222).
