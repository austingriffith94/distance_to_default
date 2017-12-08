# distance_to_default
This code uses a naive, direct, and iterative approach to solving for distance to default and probability of default for firms from 1970 to 2015. The data used by the code can be found in the link [here.](https://goo.gl/DoHABj)

## Method 1: Naive
    DD = (log(E + F/F) + (annret − σV^2 /2)T)/(σV * sqrt(T))

where

    - σV = (E/E+F) * σE + (F / E + F)*(0.05 + 0.25 * σE)
    - annret is the annual returns from the previous year

## Method 2: Direct Solve
#### Equation 1:
    E = V * N(d1) − exp(−r * T) + F * N(d2)

where

    - E is the market value of the firm’s equity
    - F is the face value of the firm’s debt
    - r is the instantaneous risk-free rate
    - N() is the cumulative standard normal distribution function
    - d1 = (log(V/F) + (r + σV^2/T))/ σV * sqrt(T)
    - d2 = d1 − σV * sqrt(T)

#### Equation 2:
    σE = (V/E) * N(d1) * σV

The second equation is derived from an application of Ito’s lemma, and the fact that

    ∂E / ∂V = N (d1)

links the volatility of the firm value and the volatility of the equity.

The unknowns are:
- the firm value V and
- the asset volatility σV

With two nonlinear equations and two unknowns, V σV can be directly solved.

## Method 3: Iterative (KMV)
Using Equation 1 from the previous method, V can be solved for iteratively.

- Estimate an initial value of σV; in this case σE is a close approximation for the first iteration
- Use equation 1 (equity option) to solve for asset value V on a per day basis using the estimated σV
- Construct the time-series of asset value by computing the new estimate of σV for the given year
- Repeat the previous steps till the value of σV and its previous estimate converge

## Other Trends
The Distance to Default and Probability of Default methods were compared to other sets of data to draw conclusions on possible correlations and similar trends

- US recession data (USREC)
- Moody's Seasoned Baa Corporate Bond Minus Federal Funds Rate (BAAFFM)
- Cleveland Financial Stress Index (CFSI)
