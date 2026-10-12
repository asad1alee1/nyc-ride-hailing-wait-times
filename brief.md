# Product ops brief: where and when do riders wait longest, and who is served least well?

*Independent project using public NYC TLC data (April 2026, Uber and Lyft). Not work experience.*

## Summary

A typical rider waits about four minutes. The tail is the problem, and it is concentrated. On Uber, riders who request a **wheelchair-accessible vehicle** wait about 3 minutes longer at the median than other riders. **LaGuardia and JFK**, **outer Queens and Staten Island**, and **weekend nights and 3 to 5am** also account for a disproportionate share of long waits. I propose three small pilots with clear success metrics. The data cannot confirm causes, so the first step is to pull supply and cancellation data for the affected zones and hours.

## Evidence

- **Tail, not median.** Median wait is 4.1 minutes on Uber and 3.9 on Lyft, but the 90th percentile is 10.0 vs 7.5 minutes, and 9.8% of Uber trips wait over 10 minutes against 3.7% on Lyft. Compared within the same pickup zone, hour and day type (7,354 cells), Uber's tail is longer in 95% of them, by 2.6 minutes on average.
- **Accessible requests wait longer.** On Uber the median wait is 7.3 minutes against 4.1, and 22.9% wait over 10 minutes against 9.8%. The gap appears in every borough, from 19.9% in Manhattan to 28.9% in the Bronx (other riders: 6.1% to 17.3%). Keeping the excluded rows barely changes it (median 7.2, 22.2%).
- **Airports.** LaGuardia and JFK are 3.5% of trips but about 10% of all waits over 10 minutes; roughly one pickup in four waits that long.
- **Remote zones.** City Island, Broad Channel, the Rockaways and southern Staten Island have the longest 90th-percentile waits (13 to 18 minutes), though few riders are affected.
- **Time.** The 90th percentile peaks at 3 to 5am (about 11 to 12 minutes) and on weekend nights, and is lowest at 9 to 11am (about 8 minutes).

## Likely causes (hypotheses, not findings)

Accessible vehicles are a small pool, so a nearby match is rarer. Airport waits may reflect pickup-point friction more than supply. Early-morning and remote-zone waits fit thin supply. Uber's longer tail may partly reflect when its app records the request. This data cannot separate these.

## Recommendations

1. **Set a service target for accessible requests.** Track the ratio of accessible to standard 90th-percentile wait by borough and hour, and pilot dispatch priority or pre-positioning in the Bronx, Queens and Brooklyn. Success: the ratio falls from about 1.8x at the median toward parity. Guardrail: standard-ride waits do not worsen.
2. **Diagnose the airport pickup flow.** Test clearer pickup-point guidance and staging of supply at LaGuardia and JFK. Success: the share of airport waits over 10 minutes falls from about 24%. Guardrail: airport cancellations.
3. **Target supply at the weak slots.** Run a time-boxed incentive pilot in a few weekend-night and 3 to 5am zone-hours against matched control cells. Success: 90th-percentile wait falls versus control. Guardrails: driver earnings per hour and incentive cost per trip.

## Weekly scorecard

90th-percentile wait and share over 10 minutes by zone and hour; accessible-to-standard wait ratio; share of trips excluded for bad timestamps (data health). Judge pilots with a before-and-after comparison against control cellLimits, and data needed to confirm causes

There are no cancellations, unmatched requests, driver supply or support tickets. Every accessible request here was matched, so the true accessible gap may be larger. About 1.3% of trips had impossible request times, concentrated in early morning and outer zones and affecting 59% of Lyft accessible requests, so accessible results are Uber only and overnight waits are probably understated. To confirm causes I would need: cancellation and no-driver-found rates by zone and hour, unmatched accessible requests, driver supply and acceptance, support tickets mentioning waiting or accessibility, and trusted request and arrival timestamps.
