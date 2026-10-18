# Explication Complète de la Stratégie XAUUSD Momentum Scalper EA

---

## 1. Stratégie Globale : Momentum Scalper pour l'Or (XAUUSD)

La stratégie repose sur un principe fondamental d'analyse quantitative : **l'alignement des tendances multi-indicateurs couplé à une cassure d'impulsion de volatilité sur l'Or (XAUUSD M5)**.

---

## 2. Origine Théorique (Kakushadze - 151 Trading Strategies)

Le code est structuré selon deux théories quantitatives majeures extraites de la littérature de trading algorithmique :
1. **Price-Momentum (Section 3.1)** : L'Or étant un actif très spéculatif, lorsqu'un mouvement directionnel est initié avec du volume, le prix a une forte probabilité d'extrapolation à court terme (effet d'inertie).
2. **Channel / Volatility Breakout (Section 3.15 & 10.4)** : Les meilleures opportunités de scalping surviennent lorsque le prix sort avec force d'un canal moyen (`EMA`), confirmées par un filtre de volatilité (`ATR`).

---

## 3. Rôle des Indicateurs Techniques du Robot

Le robot utilise 4 indicateurs complémentaires exécutés sur chaque clôture de bougie (bougie index 1) :

| Indicateur | Paramètres par défaut | Rôle dans le Robot |
| :--- | :--- | :--- |
| **Parabolic SAR** | `Step = 0.02`, `Max = 0.20` | **Filtre Macro-Directionnel** : Indique le sens global du flux institutionnel (Acheteur si prix > SAR, Vendeur si prix < SAR). |
| **EMA Rapide** | `Period = 8` | **Canal Dynamique Rapide** : Sert de référence pour la mesure de la vitesse d'impulsion immédiate. |
| **EMA Lente** | `Period = 21` | **Filtre de Tendance Médiane** : Valide le croisement de tendance (`EMA 8 > EMA 21` pour Achat, `EMA 8 < EMA 21` pour Vente). |
| **ATR** | `Period = 14`, `Min = 80 pts` | **Filtre Anti-Rangement (Flat)** : Vérifie que le marché a une volatilité suffisante ($\ge \$0.80$ d'amplitude moyenne) pour éviter les fausses cassures en marché stagnant. |

---

## 4. Algorithme de Prise de Position (Conditions Strictes)

Le robot évalue les signaux uniquement à l'ouverture d'une nouvelle bougie (confirmation sur bougie fermée) afin d'éviter le bruit de marché intra-bougie.

### 🔵 Conditions pour un Ordre d'ACHAT (BUY)
Toutes les conditions suivantes doivent être réunies simultanément :
1. **Spread** : Le spread actuel du courtier est sous la limite tolérée (`InpMaxSpreadPoints` = 250 points, soit $2.50).
2. **Session** : L'heure du serveur se situe entre 7h00 et 21h00 (Sessions Londres & New York).
3. **Macro Tendance** : La clôture précédente $C_1 > SAR_1$.
4. **Alignement EMA** : $EMA_8 > EMA_{21}$.
5. **Volatilité Validée** : $ATR_{14} \ge 80 \text{ points}$ ($0.80 XAU).
6. **Impulsion Breakout** : Le plus haut de la bougie précédente $H_1 > EMA_8 + \text{InpBreakoutPoints}$ ($0.30 de dépassement du canal).

### 🔴 Conditions pour un Ordre de VENTE (SELL)
1. **Spread** : Spread sous le seuil maximal.
2. **Session** : Filtre horaire actif (7h-21h).
3. **Macro Tendance** : La clôture précédente $C_1 < SAR_1$.
4. **Alignement EMA** : $EMA_8 < EMA_{21}$.
5. **Volatilité Validée** : $ATR_{14} \ge 80 \text{ points}$.
6. **Impulsion Breakout** : Le plus bas de la bougie précédente $L_1 < EMA_8 - \text{InpBreakoutPoints}$.

---

## 5. Modèle Mathématique de Gestion du Capital & Compounding (~50%/Mois)

C'est le moteur financier du robot permettant de viser la cible de rendement de ~50%/mois.

### Calcul Dynamique de la Taille de Lot (*Risk Percent Equity*)
Au lieu d'utiliser un lot fixe, le robot calcule la taille exacte de position selon l'Équité courante du compte :

$$\text{Montant Risqué (\$) } = \text{Equity} \times \left( \frac{\text{InpRiskPercent}}{100} \right)$$

$$\text{Volume (Lots)} = \frac{\text{Montant Risqué (\$)}}{\text{StopLoss (Points)} \times \text{Valeur du Point (\$) }}$$

*Exemple pratique* :
* Capital = $10,000 | Risque = 2.5% ($250)
* Stop Loss = 250 points ($2.50 sur XAUUSD)
* Lot calculé = 1.00 Lot
* En cas de victoire (Take Profit = 500 points / $5.00), le gain est de **+$500 (+5.0% de capital)**.
* Grâce au réinvestissement automatique (*compounding*), le trade suivant à $10,500 de capital risquera $262.50, accélérant la courbe des gains géométriquement.

---

## 6. Gestion Active et Sécurisation des Positions (Chaque Tick)

Une fois la position ouverte, le robot bascule sur un algorithme de suivi en temps réel exécuté à chaque variation de prix (*tick*) :

1. **Break-Even (Sécurisation à 0 Risque)** :
   * Dès que le gain latent atteint `InpBreakEvenPoints` (150 points = $1.50 XAU), le Stop Loss est automatiquement déplacé à :
     $$\text{Nouveau SL} = \text{Prix d'Entrée} + \text{InpBreakEvenProfit} \text{ (30 points = \$0.30)}$$
   * La position devient mathématiquement **impossible à perdre** et verrouille un petit profit minimum.

2. **Trailing Stop (Verrouillage Progressif des Gains)** :
   * Lorsque le profit dépasse `InpTrailingStopPoints` (200 points = $2.00 XAU), le Stop Loss suit le cours à une distance constante de 200 points.
   * Le Stop Loss est mis à jour chaque fois que le cours progresse d'au moins `InpTrailingStepPoints` (50 points = $0.50 XAU).

3. **Protection Contre les Contraintes Broker** :
   * Avant de modifier un Stop Loss ou d'ouvrir une position, le code vérifie la règle `SYMBOL_TRADE_STOPS_LEVEL` du courtier pour éviter les rejets d'ordres ou les erreurs de modification.
