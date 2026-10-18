# XAUUSD Momentum Scalper Inverse EA - Documentation Technique

## 1. Concept & Logique Inverse

Le **XAUUSD Momentum Scalper Inverse EA** (`XAUUSD_Momentum_Scalper_Inverse_EA.mq5`) est une variante **miroir/inversée** de la stratégie originale.

### Objectif de la Variante Inverse
Cette version est conçue pour produire exactement **l'inverse symétrique des résultats de la version 1** sous des conditions de marché identiques :
* Si la **Version 1 (Standard)** réalise **1 000 € de profit** et **800 € de perte**,
* La **Version Inverse (v2)** réalisera dans les mêmes conditions **1 000 € de perte** et **800 € de profit**.

---

## 2. Règle de Prise de Position Miroir

Le filtrage des indicateurs (Parabolic SAR, EMA 8, EMA 21, ATR 14) reste rigoureusement identique pour détecter les points d'inflexion du marché, mais **l'exécution des ordres est totalement inversée** :

* **Signal d'Achat détecté (BUY Signal)** :
  * *Version Standard* : Ouvre une position **BUY**
  * *Version Inverse* : Ouvre une position **SELL** (au prix Bid avec SL et TP inversés).

* **Signal de Vente détecté (SELL Signal)** :
  * *Version Standard* : Ouvre une position **SELL**
  * *Version Inverse* : Ouvre une position **BUY** (au prix Ask avec SL et TP inversés).

---

## 3. Paramètres de Configuration

| Paramètre | Valeur par défaut | Description |
| :--- | :--- | :--- |
| `InpTimeframe` | `PERIOD_M5` | Unité de temps M5 |
| `InpRiskMode` | `RISK_PERCENT_EQUITY` | Calcul du lot basé sur l'Equity (Compounding) |
| `InpRiskPercent` | `2.5` | Pourcentage de risque par position |
| `InpStopLossPoints` | `250` | Stop Loss en points (équivalent au TP de la version standard) |
| `InpTakeProfitPoints` | `500` | Take Profit en points (équivalent au SL de la version standard) |
| `InpMagicNumber` | `151889` | Identifiant Magic Number distinct pour la variante inverse |

---

*Fichier faisant partie de la suite d'EAs MQL5 pour MetaTrader 5.*
