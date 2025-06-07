# Hawk High - Findings Report

# Table of contents
- ## [Contest Summary](#contest-summary)
- ## [Results Summary](#results-summary)
- ## High Risk Findings
    - ### [H-01. Calculation of teacher fees causes excess fees to be paid out when there are more than one teacher and potentially reverts if the TEACHER_WAGE is too high due to insufficient bursary funds](#H-01)
    - ### [H-02. Bursary not updated aftert paying the teacher and principal wages, causing incorrect funds accounting](#H-02)
    - ### [H-03. Contract upgrade and wage distribution bypass graduation criteria and timing requirements](#H-03)
- ## Medium Risk Findings
    - ### [M-01. Missing `_disableInitializers()` exposes implementation contract to unauthorised initialisation](#M-01)



# <a id='contest-summary'></a>Contest Summary

### Sponsor: First Flight #39

### Dates: May 1st, 2025 - May 8th, 2025

[See more contest details here](https://codehawks.cyfrin.io/c/2025-05-hawk-high)

# <a id='results-summary'></a>Results Summary

### Number of findings:
- High: 3
- Medium: 1
- Low: 0


# High Risk Findings

## <a id='H-01'></a>H-01. Calculation of teacher fees causes excess fees to be paid out when there are more than one teacher and potentially reverts if the TEACHER_WAGE is too high due to insufficient bursary funds            



## Summary

The `LevelOne.sol::graduateAndUpgrade` function incorrectly calculates the teacher fee by not incorporating the number of teachers and with the current variable assumptions it will revert when there are more than 2 teachers onboarded (with the current TEACHER\_WAGE variable).&#x20;

## Vulnerability Details

The `LevelOne.sol::graduateAndUpgrade` function incorrectly calculates the teacher fee by not incorporating the number of teachers. This causes the contract to pay out too much in teacher fees. Furthermore, when there are more than 2 teachers onboarded to Hawk High (assuming >= 34% TEACHER\_WAGE), the function will revert due to insufficient funds. Causing unpaid wages to both the teacher and principal.

The teacher fees are calculated as follows in the `LevelOne.sol::graduateAndUpgrade` function:

```solidity
...
uint256 public constant TEACHER_WAGE = 35; // 35%
...

function graduateAndUpgrade(address _levelTwo, bytes memory) public onlyPrincipal {
    ...
    uint256 totalTeachers = listOfTeachers.length;

@>  uint256 payPerTeacher = (bursary * TEACHER_WAGE) / PRECISION;
    ...
}
```

The above function should also divide the `payPerTeacher` calculation by the number of teachers.

## Impact

The `LevelOne.sol::graduateAndUpgrade` only works when there is only one teacher onboarded. When more than one teacher is onboarded then the function incorrectly calcuylate the teacher fees as it does not divide the fees by the number of teachers. This ultimately will cause the function to overpay the teacher wages and drain all the bursary when there are more than 2 teachers onboarded (with the current variables).

Impact is high as the function overpays the teacher wages and drains the bursary.
Likelihood is also high as the function will always calculate the teacher fee incorrectly when there are more than 1 teacher onboarded.

## Tools Used

* Manual review
* Foundry test

**Proof of Concept:**

Adding the below code to the `LeveOnelAndGraduateTest.t.sol` file will cause the function to revert..

```solidity
...
contract LevelOneAndGraduateTest is Test {
    ...
    // teachers
    ...
    address charlie;
    ...
    function setUp() public {
    ...
        charlie = makeAddr("third_teacher");
    ...
    }
    ...
    modifier schoolSetUp() {
        _threeTeachersAdded();
        _studentsEnrolled(); //same as per the original test code on github

        vm.prank(principal);
        levelOneProxy.startSession(70);

        _;
    }

    function test_fees_after_graduate() public schoolSetUp {
        levelTwoImplementation = new LevelTwo();
        levelTwoImplementationAddress = address(levelTwoImplementation);

        bytes memory data = abi.encodeCall(LevelTwo.graduate, ());

        vm.prank(principal);
        levelOneProxy.graduateAndUpgrade(levelTwoImplementationAddress, data);

        LevelTwo levelTwoProxy = LevelTwo(proxyAddress);

        console2.log(levelTwoProxy.bursary());
        console2.log(levelTwoProxy.getTotalStudents());
        console2.log(usdc.balanceOf(address(alice)));
        console2.log(levelOneProxy.getListOfTeachers().length);
    }

   function _threeTeachersAdded() internal {
        vm.startPrank(principal);
        levelOneProxy.addTeacher(alice);
        levelOneProxy.addTeacher(bob);
        levelOneProxy.addTeacher(charlie);
        vm.stopPrank();
    }
...
}
```

## Recommendations

**1. Adding the number of teachers to the calculation of the teacher fees:**

By updating the `graduateAndUpgrade` function to calculate the teacher fees correctly, the function will no longer overpay the teacher wages. Furthermore, to be in line with Checks-Effects-Interactions, the function should update also the bursary before any external calls.

```solidity
    function graduateAndUpgrade(address _levelTwo, bytes memory) public onlyPrincipal {
        if (_levelTwo == address(0)) {
            revert HH__ZeroAddress();
        }

        uint256 totalTeachers = listOfTeachers.length;

        uint256 totalTeacherPay = 0; // new variable
        uint256 payPerTeacher = 0; // updated definiton of payPerTeacher to initialise to 0

        uint256 principalPay = (bursary * PRINCIPAL_WAGE) / PRECISION;

        if (totalTeachers > 0) {// adding the if statement to check if there are any teachers before dividing by the number of teachers
            totalTeacherPay = (bursary * TEACHER_WAGE) / PRECISION;
            payPerTeacher = totalTeacherPay / totalTeachers;
        }

        // EFFECTS: update bursary before any external calls
       // Note: I will report this lack of bursary update in another finding
        bursary -= (totalTeacherPay + principalPay);

        _authorizeUpgrade(_levelTwo);

        // INTERACTIONS: transfer funds to the teachers and principal
        for (uint256 n = 0; n < totalTeachers; n++) {
            usdc.safeTransfer(listOfTeachers[n], payPerTeacher);
        }

        usdc.safeTransfer(principal, principalPay);
    }
```

The above calculation correct the teacher wage (assuming 3 teachers):

(3e22 \* 35) / 3 / 100 = 35e20

## <a id='H-02'></a>H-02. Bursary not updated aftert paying the teacher and principal wages, causing incorrect funds accounting            



## Summary

In the `LevelOne.sol::graduateAndUpgrade` function, the contract pays the teacher and principal wages using the bursary balance, but fails to update the bursary afterward. This results in incorrect funds remaining in the bursary, causing future wage calculations to overestimate available funds and violate accurate accounting principles.

## Vulnerability Details

The `LevelOne.sol::graduateAndUpgrade` function calculates the teacher and principal wages using the bursary balance.

```solidity
        uint256 payPerTeacher = (bursary * TEACHER_WAGE) / PRECISION;
        uint256 principalPay = (bursary * PRINCIPAL_WAGE) / PRECISION;
```

However, the bursary value is not updated after the wage payments are made via external safeTransfer calls. As a result:

* Incorrect bursary balance remains, causing subsequent to use outdated values.
* Future wage payments will be overestimated.
* The contract also violates the Check-Effects-Interactions pattern.

Not updating the internal state before making external calls can be dangerous as it can lead to unexpected behaviour and vulnerabilities.

Impacted code:

```solidity
    function graduateAndUpgrade(address _levelTwo, bytes memory) public onlyPrincipal {
        if (_levelTwo == address(0)) {
            revert HH__ZeroAddress();
        }

        uint256 totalTeachers = listOfTeachers.length;

        uint256 payPerTeacher = (bursary * TEACHER_WAGE) / PRECISION;
        uint256 principalPay = (bursary * PRINCIPAL_WAGE) / PRECISION;

        _authorizeUpgrade(_levelTwo);

        for (uint256 n = 0; n < totalTeachers; n++) {
            usdc.safeTransfer(listOfTeachers[n], payPerTeacher);
        }

        usdc.safeTransfer(principal, principalPay);
    }
```

## Impact

**Impact:** High – Incorrect bursary funds affect all future calculations and disbursements.
**Likelihood:** High – This function is expected to be called routinely during upgrades, consistently introducing accounting errors.

## Tools Used

* Manual review
* Foundry test

**Proof of Concept:**

Adding the below code to the `LeveOnelAndGraduateTest.t.sol` file demonstrate that the `bursary` is unchanged after paying the teacher and principal wages:

```solidity
contract LevelOneAndGraduateTest is Test {
    ...

    modifier oneTeacher() {
        _oneTeachersAdded();
        _studentsEnrolled();

        vm.prank(principal);
        levelOneProxy.startSession(70);

        _;
    }

    ...

    function test_fees_after_graduate_one_teacher() public oneTeacher {
        levelTwoImplementation = new LevelTwo();
        levelTwoImplementationAddress = address(levelTwoImplementation);

        bytes memory data = abi.encodeCall(LevelTwo.graduate, ());

        vm.prank(principal);
        levelOneProxy.graduateAndUpgrade(levelTwoImplementationAddress, data);

        LevelTwo levelTwoProxy = LevelTwo(proxyAddress);

        assertEq(levelTwoProxy.bursary(), 3e22); // Bursary balance is not updated
        assertEq(usdc.balanceOf(address(alice)), 105e20); // Alice has received her teacher wage
        assertEq(usdc.balanceOf(address(principal)), 15e20); // Principal has received their wage
    }

  function _oneTeachersAdded() internal {
        vm.startPrank(principal);
        levelOneProxy.addTeacher(alice);
        vm.stopPrank();
    }
...
}
```

## Recommendations

**1. Update the bursary before any external calls:**

By adding the line `bursary -= (totalTeacherPay + principalPay);` before the wage payments, the bursary will be updated before any external calls and stay in line with the Checks-Effects-Interactions pattern.

```solidity
    function graduateAndUpgrade(address _levelTwo, bytes memory) public onlyPrincipal {
        if (_levelTwo == address(0)) {
            revert HH__ZeroAddress();
        }

        uint256 totalTeachers = listOfTeachers.length;

        uint256 totalTeacherPay = 0;
        uint256 payPerTeacher = 0;

        uint256 principalPay = (bursary * PRINCIPAL_WAGE) / PRECISION;

        if (totalTeachers > 0) {
            uint256 totalTeacherPay = (bursary * TEACHER_WAGE) / PRECISION;
            uint256 payPerTeacher = totalTeacherPay / totalTeachers;
        }

        // EFFECTS: update bursary before any external calls
@>      bursary -= (totalTeacherPay + principalPay);

        _authorizeUpgrade(_levelTwo);

        // INTERACTIONS: transfer funds to the teachers and principal
        for (uint256 n = 0; n < totalTeachers; n++) {
            usdc.safeTransfer(listOfTeachers[n], payPerTeacher);
        }

        usdc.safeTransfer(principal, principalPay);
    }
```

**Note:** The above code has also been updated to reflect the correct calculation of the teacher wages as per my other finding related to this function.

## <a id='H-03'></a>H-03. Contract upgrade and wage distribution bypass graduation criteria and timing requirements            



## Summary

The system allows the principal to upgrade the contract and distribute wages before students meet the required number of reviews or complete minimum enrolment duration. This undermines the system's integrity and trust model, potentially leaving students ungraded and financially disadvantaged.

## Vulnerability Details

The `LevelOne.sol::graduateAndUpgrade` function lacks validation for key invariants: it does not check whether students have received the required number of reviews, nor does it enforce a minimum time period after enrolment before the system can be upgraded.

As a result, the principal can prematurely trigger an upgrade and release payments to teachers and themselves, bypassing the graduation requirements. This violates the logical flow of the system, where graduation should precede both contract upgrades and wage disbursements.

**Relevant code:**

```solidity
    function graduateAndUpgrade(address _levelTwo, bytes memory) public onlyPrincipal {
        if (_levelTwo == address(0)) {
            revert HH__ZeroAddress();
        }

        uint256 totalTeachers = listOfTeachers.length;

        uint256 payPerTeacher = (bursary * TEACHER_WAGE) / PRECISION;
        uint256 principalPay = (bursary * PRINCIPAL_WAGE) / PRECISION;

        _authorizeUpgrade(_levelTwo);

        for (uint256 n = 0; n < totalTeachers; n++) {
            usdc.safeTransfer(listOfTeachers[n], payPerTeacher);
        }

        usdc.safeTransfer(principal, principalPay);
    }
```

## Impact

* **Impact:** High – Premature upgrades and payouts can result in students not receiving their expected reviews despite having paid fees, severely eroding trust in the system and breaking the educational logic enforced by the contract.

* **Likelihood:** High - The absence of critical safeguards (such as review count and time-based checks) enables both accidental misuse and deliberate exploitation of the system. Even with a trusted principal, the ease of triggering an upgrade and wage disbursement in a single call makes this vulnerability a significant risk.

## Tools Used

* Manual review of the `GraduiateAndUpgrade` function
* Foundry test

**Proof of Concept:**

The following test demonstrates that a student can graduate without receiving any reviews, and wages are paid out nonetheless::

```solidity
    modifier oneTeacher() {
        _oneTeachersAdded();
        _studentsEnrolled();

        vm.prank(principal);
        levelOneProxy.startSession(70);

        _;
    }

    function test_review_count_after_graduate() public oneTeacher {
        levelTwoImplementation = new LevelTwo();
        levelTwoImplementationAddress = address(levelTwoImplementation);

        bytes memory data = abi.encodeCall(LevelTwo.graduate, ());

        vm.prank(principal);
        levelOneProxy.graduateAndUpgrade(levelTwoImplementationAddress, data);

        assertEq(levelOneProxy.getReviewCount(clara),0);
        assertEq(usdc.balanceOf(address(alice)), 105e20);
        assertEq(usdc.balanceOf(address(principal)), 15e20);
    }
```

## Recommendations

* Add a check in `GraduateAndUpgrade` function to ensure that each student has received the required number of reviews, i.e. 4, before allowing graduation and wage disbursement.
* Introduce a minimum delay, i.e. 4 weeks, after student enrolment before the contract can be upgraded to ensure a fair and complete educational process.

    
# Medium Risk Findings

## <a id='M-01'></a>M-01. Missing `_disableInitializers()` exposes implementation contract to unauthorised initialisation            



## Summary

The implementation contract does not follow best practices for upgradeable contracts: the `initialize` function is declared `public`, and no constructor disables initialisers on the implementation contract. As a result, anyone can call `initialize` directly on the implementation contract.

According to OpenZeppelin’s recommendations, the `LevelOne` contract should include a constructor with `_disableInitializers()` to prevent unauthorised initialisation of the implementation contract.

## Vulnerability Details

A key risk in upgradeable proxy patterns is that the implementation contract is deployed independently and accessible on-chain. While the `initialize` function is intended to be called via the proxy, it is also publicly accessible on the implementation contract itself.

Because `initialize` is `public`, any address can call it directly on the implementation contract. If initialisation has not yet occurred on the implementation contract, the caller can assign themselves as `principal`. This creates a scenario where there are effectively two owners:

1. The `principal` stored in the proxy contract’s storage
2. The `principal` stored in the implementation contract’s storage

Functions protected by `onlyPrincipal` modifiers may check ownership against the contract’s own storage, resulting in unexpected access control behaviour if called on the implementation contract directly.

While this issue does not affect the proxy storage or proxy-based interactions, it leaves the implementation contract unnecessarily exposed and potentially abusable in future deployments, integrations, or tooling relying on the implementation contract.

OpenZeppelin recommends including the following constructor in upgradeable contracts to disable initializers on the implementation contract:

```solidity
constructor() {
    _disableInitializers();
}
```

This prevents any future call to `initialize()` or any `reinitializer()` function on the implementation contract itself.

## Impact

**Impact Classification:** Medium - reduces risk of accidental or malicious use of implementation contract, which could result in unintended access control the implementation contract.

**Likelihood Classification:** Low - requires someone to intentionally call implementation contract

## Tools Used

* Manual code review of the initialize function
* Reference to OpenZeppelin documentation and upgradeable contract best practices

## Recommendations

* Add a constructor with the `_disableInitializers()` function to the implementation contract.

```solidity
constructor() {
    _disableInitializers();
}
```





