# XAUUSD Momentum Scalper Inverse EA (Version 2) - Documentation Technique

## 1. Inversion Totale de la Stratégie (Variante Miroir)

Le **XAUUSD Momentum Scalper Inverse EA** (`XAUUSD_Momentum_Scalper_Inverse_EA.mq5`) est la variante **exactement contraire et inversée** du robot original (Version 1).

### Principe Mathématique d'Inversion
L'objectif de cette Version 2 est d'inverser complètement les résultats de trading par rapport à la Version 1 dans toutes les conditions de marché :
* Si la **Version 1** réalise **1 000 € de profit** et **800 € de perte**,
* La **Version 2 (Inverse)** réalise dans les mêmes conditions exactes **1 000 € de perte** et **800 € de profit**.

---

## 2. Inversion Complète des Conditions de Trading

Chaque condition d'entrée et chaque paramètre d'objectif sont inversés de manière stricte :

| Élément | Version 1 (Standard) | Version 2 (Inversée / Contrarienne) |
| :--- | :--- | :--- |
| **Condition d'Achat (BUY)** | Clôture > SAR, EMA 8 > EMA 21, Cassure du haut | **Inversée** : Déclenchée par la condition de Vente V1 |
| **Condition de Vente (SELL)** | Clôture < SAR, EMA 8 < EMA 21, Cassure du bas | **Inversée** : Déclenchée par la condition d'Achat V1 |
| **Stop Loss (SL)** | 250 points ($2.50) | 500 points ($5.00) (Inversé avec le TP de V1) |
| **Take Profit (TP)** | 500 points ($5.00) | 250 points ($2.50) (Inversé avec le SL de V1) |
| **Magic Number** | `151888` | `151889` |

---

## 3. Déroulement Pratique sur le Marché

1. Lorsque la Version 1 détecte un signal d'Achat et ouvre une position **BUY**, la Version 2 détecte le même signal mais ouvre une position **SELL**.
2. Lorsque la Version 1 détecte un signal de Vente et ouvre une position **SELL**, la Version 2 détecte le même signal mais ouvre une position **BUY**.
3. Les niveaux de Stop Loss et Take Profit étant inversés (SL = 500 points, TP = 250 points), le payoff ratio est inversé, assurant une parfaite symétrie miroir des performances financières.
