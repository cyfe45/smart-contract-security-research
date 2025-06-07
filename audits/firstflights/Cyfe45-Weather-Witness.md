# Weather Witness - Findings Report

# Table of contents
- ## [Contest Summary](#contest-summary)
- ## [Results Summary](#results-summary)
- ## High Risk Findings
    - ### [H-01. Contract locks Ether without a withdraw mechanism resulting in locked Eth](#H-01)




# <a id='contest-summary'></a>Contest Summary

### Sponsor: First Flight #40

### Dates: May 15th, 2025 - May 22nd, 2025

[See more contest details here](https://codehawks.cyfrin.io/c/2025-05-weather-witness)

# <a id='results-summary'></a>Results Summary

### Number of findings:
- High: 1
- Medium: 0
- Low: 0


# High Risk Findings

## <a id='H-01'></a>H-01. Contract locks Ether without a withdraw mechanism resulting in locked Eth            



## Description

The `WeatherNft` contract includes a `payable` function that accepts Ether, but does not implement any mechanism for withdrawing or refunding the received funds. As a result, any Ether sent to the contract becomes permanently locked. This presents a significant usability and trust issue, especially if users make accidental or erroneous payments.

Additionally, the contract does not validate location inputs, increasing the risk that users may unintentionally pay for incorrect weather tracking services. For example, a user intending to track weather in *London, UK* might mistakenly enter *London, Kentucky, USA* without any contract-side safeguards to prevent this.

Moreover, the contract lacks a documented or implemented economic model. There is no indication of how the collected Ether will be used, how refunds will be handled, or how the contract owner is incentivised. This undermines transparency and may affect user confidence in the system. If one checks out [OpenWeatherMap](https://openweathermap.org/price) there are various price bands for accessing this service and with now contract fee mechanism the contract would not be able to extract any weather data, unless the contract owner pays for weather updates out of their own pocket without being reimbursed. Eventhough the first 1,000 daily API calls are free OpenWeatherMap still requires a credit card in case the daily API calls goes above this threshold. Should this contract become popular some people might not be able to get their weather updates, if the bank card is able to pay for the API calls above the threshold.&#x20;

While NFT ownership is transferable, this does not substitute for proper refund mechanisms. Relying on secondary market sales to recover funds places an unfair burden on users and does not guarantee a return of their Ether.

## Risk

**Likelihood**: High - The absence of a withdrawal or refund mechanism means that funds are irretrievable once sent. Given that user errors are common—especially with unvalidated inputs—the risk of accidental loss is high.

**Impact**: High - Users who send Ether to the contract with incorrect details or change their minds will not be able to recover their funds. This can lead to user frustration, loss of trust in the platform, and reputational damage. While users may theoretically sell their NFTs, this assumes the existence of a willing buyer—likely at a discount—and does not represent a reliable or user-friendly fallback.

Additionally, the lack of owner incentives or a monetisation strategy reduces the likelihood of long-term maintenance and support for the contract, potentially leading to abandonment.

## Proof of Concept

1. Bob sends 2 Ether to the `WeatherNft` contract to track the weather in *London, UK* (where his sister lives).
2. However, he accidentally enters location coordinates for *London, Kentucky, USA*, where he currently resides.
3. Upon reviewing the contract and associated documentation, Bob discovers there is no function to request a refund.
4. Now receiving irrelevant weather updates, Bob realises his Ether is permanently locked in the contract.
5. Disillusioned, Bob loses trust in the `WeatherNft` project and opts to use a competitor service instead.

## Recommended Mitigation

1. **Location Validation:** Implement input validation or selection mechanisms (e.g., dropdowns or geolocation-based lookup) to ensure the location data provided is accurate and intended.
2. **Refund Functionality:** Introduce a `withdraw` or `refund` function with appropriate safeguards—such as time limits, ownership checks, or limited refund windows, allowing users to reclaim their Ether if needed.
3. **Economic Incentives:** If the contract is intended to financially reward the deployer or owner, define and document a clear mechanism for profit distribution or service fees. This transparency helps build user trust and ensures sustainable operation.

    





