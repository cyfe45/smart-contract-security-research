# @version 0.4.3
# (c) Curve.Fi, 2020
# Pool for DAI/USDC/USDT

from ethereum.ercs import IERC20
# from vyper.interfaces import ERC20

interface CurveToken:
    def totalSupply() -> uint256: view
    def mint(_to: address, _value: uint256) -> bool: nonpayable
    def burnFrom(_to: address, _value: uint256) -> bool: nonpayable


# Events
event TokenExchange:
    buyer: indexed(address)
    sold_id: int128
    tokens_sold: uint256
    bought_id: int128
    tokens_bought: uint256


event AddLiquidity:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    fees: uint256[N_COINS]
    invariant: uint256
    token_supply: uint256

event RemoveLiquidity:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    fees: uint256[N_COINS]
    token_supply: uint256

event RemoveLiquidityOne:
    provider: indexed(address)
    token_amount: uint256
    coin_amount: uint256

event RemoveLiquidityImbalance:
    provider: indexed(address)
    token_amounts: uint256[N_COINS]
    fees: uint256[N_COINS]
    invariant: uint256
    token_supply: uint256

event CommitNewAdmin:
    deadline: indexed(uint256)
    admin: indexed(address)

event NewAdmin:
    admin: indexed(address)


event CommitNewFee:
    deadline: indexed(uint256)
    fee: uint256
    admin_fee: uint256

event NewFee:
    fee: uint256
    admin_fee: uint256

event RampA:
    old_A: uint256
    new_A: uint256
    initial_time: uint256
    future_time: uint256

event StopRampA:
    A: uint256
    t: uint256


# This can (and needs to) be changed at compile time
N_COINS: constant(int128) = 3  # <- change # @Diff 4

FEE_DENOMINATOR: constant(uint256) = 10 ** 10
LENDING_PRECISION: constant(uint256) = 10 ** 18
PRECISION: constant(uint256) = 10 ** 18  # The precision to convert to
PRECISION_MUL: constant(uint256[N_COINS]) = [1, 1000000000000, 1000000000000] # @Diff 1
RATES: constant(uint256[N_COINS]) = [1000000000000000000, 1000000000000000000000000000000, 1000000000000000000000000000000] # @Diff 2
FEE_INDEX: constant(int128) = 2  # Which coin may potentially have fees (USDT) # @Diff 1

MAX_ADMIN_FEE: constant(uint256) = 10 * 10 ** 9
MAX_FEE: constant(uint256) = 5 * 10 ** 9
MAX_A: constant(uint256) = 10 ** 6
MAX_A_CHANGE: constant(uint256) = 10

ADMIN_ACTIONS_DELAY: constant(uint256) = 3 * 86400
MIN_RAMP_TIME: constant(uint256) = 86400

coins: public(address[N_COINS])
balances: public(uint256[N_COINS])
fee: public(uint256)  # fee * 1e10
admin_fee: public(uint256)  # admin_fee * 1e10

owner: public(address)
token: CurveToken

initial_A: public(uint256)
future_A: public(uint256)
initial_A_time: public(uint256)
future_A_time: public(uint256)

admin_actions_deadline: public(uint256)
transfer_ownership_deadline: public(uint256)
future_fee: public(uint256)
future_admin_fee: public(uint256)
future_owner: public(address)

is_killed: bool
kill_deadline: uint256
KILL_DEADLINE_DT: constant(uint256) = 2 * 30 * 86400

@deploy
# @external
def __init__(
    _owner: address,
    _coins: address[N_COINS],
    _pool_token: address,
    _A: uint256,
    _fee: uint256,
    _admin_fee: uint256
):
    """
    @notice Contract constructor
    @param _owner Contract owner address
    @param _coins Addresses of ERC20 contracts of coins
    @param _pool_token Address of the token representing LP share
    @param _A Amplification coefficient multiplied by n * (n - 1)
    @param _fee Fee to charge for exchanges
    @param _admin_fee Admin fee
    """
    for i: int128 in range(N_COINS):
        assert _coins[i] != 0x0000000000000000000000000000000000000000 #ZERO_ADDRESS
    self.coins = _coins
    self.initial_A = _A
    self.future_A = _A
    self.fee = _fee
    self.admin_fee = _admin_fee
    self.owner = _owner
    self.kill_deadline = block.timestamp + KILL_DEADLINE_DT
    self.token = CurveToken(_pool_token)


@view
@internal
def _A() -> uint256:
    """
    Handle ramping A up or down
    """
    t1: uint256 = self.future_A_time
    A1: uint256 = self.future_A

    if block.timestamp < t1:
        A0: uint256 = self.initial_A
        t0: uint256 = self.initial_A_time
        # Expressions in uint256 cannot have negative numbers, thus "if"
        if A1 > A0:
            return A0 + (A1 - A0) * (block.timestamp - t0) / (t1 - t0)
        else:
            return A0 - (A0 - A1) * (block.timestamp - t0) / (t1 - t0)

    else:  # when t1 == 0 or block.timestamp >= t1
        return A1


@view
@external
def A() -> uint256:
    return self._A()# @Diff


@view
@internal
def _xp() -> uint256[N_COINS]:# @Diff
    result: uint256[N_COINS] = RATES
    for i: int128 in range(N_COINS):
        result[i] = result[i] * self.balances[i] / LENDING_PRECISION
    return result


@pure
@internal
def _xp_mem(_balances: uint256[N_COINS]) -> uint256[N_COINS]:# @Diff
    result: uint256[N_COINS] = RATES
    for i: int128 in range(N_COINS):
        result[i] = result[i] * _balances[i] / PRECISION
    return result


@pure
@internal
def get_D(xp: uint256[N_COINS], amp: uint256) -> uint256:
    S: uint256 = 0
    for _x: uint256 in xp:
        S += _x
    if S == 0:
        return 0

    Dprev: uint256 = 0
    D: uint256 = S
    Ann: uint256 = amp * N_COINS
    for _i: int128 in range(255):
        D_P: uint256 = D
        for _x: uint256 in xp:
            D_P = D_P * D / (_x * N_COINS)  # If division by 0, this will be borked: only withdrawal will work. And that is good# @Diff
        Dprev = D
        D = (Ann * S + D_P * N_COINS) * D / ((Ann - 1) * D + (N_COINS + 1) * D_P)# @Diff
        # Equality with the precision of 1
        if D > Dprev:
            if D - Dprev <= 1:
                break# @Diff
        else:
            if Dprev - D <= 1:
                break# @Diff
    return D


@view
@internal
def get_D_mem(_balances: uint256[N_COINS], amp: uint256) -> uint256:# @Diff
    return self.get_D(self._xp_mem(_balances), amp)


@view
@external
def get_virtual_price() -> uint256:
    """
    Returns portfolio virtual price (for calculating profit)
    scaled up by 1e18
    """
    D: uint256 = self.get_D(self._xp(), self._A())# @Diff
    # D is in the units similar to DAI (e.g. converted to precision 1e18)
    # When balanced, D = n * x_u - total virtual value of the portfolio
    token_supply: uint256 = staticcall self.token.totalSupply()# @Diff
    return D * PRECISION / token_supply


@view
@external
def calc_token_amount(amounts: uint256[N_COINS], deposit: bool) -> uint256:
    """
    Simplified method to calculate addition or reduction in token supply at
    deposit or withdrawal without taking fees into account (but looking at
    slippage).
    Needed to prevent front-running, not for precise calculations!
    """
    _balances: uint256[N_COINS] = self.balances# @Diff
    amp: uint256 = self._A()
    D0: uint256 = self.get_D_mem(_balances, amp)
    for i: int128 in range(N_COINS):
        if deposit:
            _balances[i] += amounts[i]
        else:
            _balances[i] -= amounts[i]
    D1: uint256 = self.get_D_mem(_balances, amp)
    token_amount: uint256 = staticcall self.token.totalSupply()# @Diff
    diff: uint256 = 0
    if deposit:
        diff = D1 - D0
    else:
        diff = D0 - D1
    return diff * token_amount / D0


@external
@nonreentrant
def add_liquidity(amounts: uint256[N_COINS], min_mint_amount: uint256):
    assert not self.is_killed  # dev: is killed

    fees: uint256[N_COINS] = empty(uint256[N_COINS])# @Diff
    _fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))# @Diff
    _admin_fee: uint256 = self.admin_fee# @Diff
    amp: uint256 = self._A()

    token_supply: uint256 = self.token.totalSupply()# @Diff
    # Initial invariant
    D0: uint256 = 0# @Diff
    old_balances: uint256[N_COINS] = self.balances
    if token_supply > 0:# @Diff
        D0 = self.get_D_mem(old_balances, amp)
    new_balances: uint256[N_COINS] = old_balances# @Diff

    for i: int128 in range(N_COINS):# @Diff for loop
        in_amount: uint256 = amounts[i]
        if token_supply == 0:
            assert in_amount > 0  # dev: initial deposit requires all coins
        in_coin: address = self.coins[i]

        # Take coins from the sender
        if in_amount > 0:
            if i == FEE_INDEX:
                in_amount = staticcall IERC20(in_coin).balanceOf(self)

            # "safeTransferFrom" which works for ERC20s which return bool or not
            _response: Bytes[32] = raw_call(
                in_coin,
                concat(
                    method_id("transferFrom(address,address,uint256)"),
                    convert(msg.sender, bytes32),
                    convert(self, bytes32),
                    convert(amounts[i], bytes32),
                ),
                max_outsize=32,
            )  # dev: failed transfer
            if len(_response) > 0:
                assert convert(_response, bool)  # dev: failed transfer

            if i == FEE_INDEX:
                in_amount = staticcall IERC20(in_coin).balanceOf(self) - in_amount

        new_balances[i] = old_balances[i] + in_amount

    # Invariant after change
    D1: uint256 = self.get_D_mem(new_balances, amp) # @Diff order
    assert D1 > D0# @Diff order

    # We need to recalculate the invariant accounting for fees
    # to calculate fair user's share
    D2: uint256 = D1
    if token_supply > 0:
        # Only account for fees if we are not the first to deposit
        for i: int128 in range(N_COINS):
            ideal_balance: uint256 = D1 * old_balances[i] / D0
            difference: uint256 = 0
            if ideal_balance > new_balances[i]:
                difference = ideal_balance - new_balances[i]
            else:
                difference = new_balances[i] - ideal_balance
            fees[i] = _fee * difference / FEE_DENOMINATOR
            self.balances[i] = new_balances[i] - (fees[i] * _admin_fee / FEE_DENOMINATOR)
            new_balances[i] -= fees[i]
        D2 = self.get_D_mem(new_balances, amp)
    else:
        self.balances = new_balances

    # Calculate, how much pool tokens to mint
    mint_amount: uint256 = 0
    if token_supply == 0:
        mint_amount = D1  # Take the dust if there was any
    else:
        mint_amount = token_supply * (D2 - D0) / D0

    assert mint_amount >= min_mint_amount, "Slippage screwed you"

    # Mint pool tokens
    self.token.mint(msg.sender, mint_amount)

    log AddLiquidity(msg.sender, amounts, fees, D1, token_supply + mint_amount)


@view
@internal
def get_y(i: int128, j: int128, x: uint256, xp_: uint256[N_COINS]) -> uint256:
    # x in the input is converted to the same price/precision

    assert i != j       # dev: same coin
    assert j >= 0       # dev: j below zero
    assert j < N_COINS  # dev: j above N_COINS

    # should be unreachable, but good for safety
    assert i >= 0
    assert i < N_COINS

    amp: uint256 = self._A()
    D: uint256 = self.get_D(xp_, amp)
    c: uint256 = D
    S_: uint256 = 0
    Ann: uint256 = amp * N_COINS

    _x: uint256 = 0
    for _i: int128 in range(N_COINS):
        if _i == i:
            _x = x
        elif _i != j:
            _x = xp_[_i]
        else:
            continue
        S_ += _x
        c = c * D / (_x * N_COINS)
    c = c * D / (Ann * N_COINS)
    b: uint256 = S_ + D / Ann  # - D
    y_prev: uint256 = 0
    y: uint256 = D
    for _i: int128 in range(255):
        y_prev = y
        y = (y*y + c) / (2 * y + b - D)
        # Equality with the precision of 1
        if y > y_prev:
            if y - y_prev <= 1:
                break
        else:
            if y_prev - y <= 1:
                break
    return y


@view
@external
def get_dy(i: int128, j: int128, dx: uint256) -> uint256:
    # dx and dy in c-units
    rates: uint256[N_COINS] = RATES# @Diff
    xp: uint256[N_COINS] = self._xp()# @Diff

    x: uint256 = xp[i] + (dx * rates[i] / PRECISION)# @Diff
    y: uint256 = self.get_y(i, j, x, xp)
    dy: uint256 = (xp[j] - y - 1) * PRECISION / rates[j]# @Diff
    _fee: uint256 = self.fee * dy / FEE_DENOMINATOR
    return dy - _fee


@view
@external
def get_dy_underlying(i: int128, j: int128, dx: uint256) -> uint256:# @Diff
    # dx and dy in underlying units
    xp: uint256[N_COINS] = self._xp()
    precisions: uint256[N_COINS] = PRECISION_MUL

    x: uint256 = xp[i] + dx * precisions[i]
    y: uint256 = self.get_y(i, j, x, xp)
    dy: uint256 = (xp[j] - y - 1) / precisions[j]
    _fee: uint256 = self.fee * dy / FEE_DENOMINATOR
    return dy - _fee



@external
@nonreentrant
def exchange(i: int128, j: int128, dx: uint256, min_dy: uint256):# @Diff
    assert not self.is_killed  # dev: is killed
    rates: uint256[N_COINS] = RATES# @Diff

    old_balances: uint256[N_COINS] = self.balances# @Diff
    xp: uint256[N_COINS] = self._xp_mem(old_balances)# @Diff

    # Handling an unexpected charge of a fee on transfer (USDT, PAXG)
    dx_w_fee: uint256 = dx# @Diff
    input_coin: address = self.coins[i]# @Diff

    if i == FEE_INDEX:# @Diff
        dx_w_fee = staticcall IERC20(input_coin).balanceOf(self)# @Diff

    # "safeTransferFrom" which works for ERC20s which return bool or not
    _response: Bytes[32] = raw_call(
        input_coin,
        concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(msg.sender, bytes32),
            convert(self, bytes32),
            convert(dx, bytes32),
        ),
        max_outsize=32,
    )  # dev: failed transfer
    if len(_response) > 0:
        assert convert(_response, bool)  # dev: failed transfer

    if i == FEE_INDEX:
        dx_w_fee = staticcall IERC20(input_coin).balanceOf(self) - dx_w_fee

    x: uint256 = xp[i] + dx_w_fee * rates[i] / PRECISION
    y: uint256 = self.get_y(i, j, x, xp)

    dy: uint256 = xp[j] - y - 1  # -1 just in case there were some rounding errors
    dy_fee: uint256 = dy * self.fee / FEE_DENOMINATOR

    # Convert all to real units
    dy = (dy - dy_fee) * PRECISION / rates[j]
    assert dy >= min_dy, "Exchange resulted in fewer coins than expected"

    dy_admin_fee: uint256 = dy_fee * self.admin_fee / FEE_DENOMINATOR
    dy_admin_fee = dy_admin_fee * PRECISION / rates[j]

    # Change balances exactly in same way as we change actual ERC20 coin amounts
    self.balances[i] = old_balances[i] + dx_w_fee
    # When rounding errors happen, we undercharge admin fee in favor of LP
    self.balances[j] = old_balances[j] - dy - dy_admin_fee

    # "safeTransfer" which works for ERC20s which return bool or not
    _response = raw_call(
        self.coins[j],
        concat(
            method_id("transfer(address,uint256)"),
            convert(msg.sender, bytes32),
            convert(dy, bytes32),
        ),
        max_outsize=32,
    )  # dev: failed transfer
    if len(_response) > 0:
        assert convert(_response, bool)  # dev: failed transfer

    log TokenExchange(msg.sender, i, dx, j, dy)


@external
@nonreentrant
def remove_liquidity(_amount: uint256, min_amounts: uint256[N_COINS]):
    total_supply: uint256 = staticcall self.token.totalSupply()# @Diff
    amounts: uint256[N_COINS] = empty(uint256[N_COINS])# @Diff
    fees: uint256[N_COINS] = empty(uint256[N_COINS])  # Fees are unused but we've got them historically in event# @Diff

    for i: int128 in range(N_COINS):
        value: uint256 = self.balances[i] * _amount / total_supply
        assert value >= min_amounts[i], "Withdrawal resulted in fewer coins than expected"
        self.balances[i] -= value
        amounts[i] = value

        # "safeTransfer" which works for ERC20s which return bool or not
        _response: Bytes[32] = raw_call(# @Diff
            self.coins[i],
            concat(
                method_id("transfer(address,uint256)"),
                convert(msg.sender, bytes32),
                convert(value, bytes32),
            ),
            max_outsize=32,
        )  # dev: failed transfer
        if len(_response) > 0:# @Diff
            assert convert(_response, bool)  # dev: failed transfer

    self.token.burnFrom(msg.sender, _amount)  # dev: insufficient funds# @Diff

    log RemoveLiquidity(msg.sender, amounts, fees, total_supply - _amount)


@external
@nonreentrant
def remove_liquidity_imbalance(amounts: uint256[N_COINS], max_burn_amount: uint256):
    assert not self.is_killed  # dev: is killed

    token_supply: uint256 = staticcall self.token.totalSupply()# @Diff
    assert token_supply != 0  # dev: zero total supply
    _fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))
    _admin_fee: uint256 = self.admin_fee
    amp: uint256 = self._A()

    old_balances: uint256[N_COINS] = self.balances
    new_balances: uint256[N_COINS] = old_balances
    D0: uint256 = self.get_D_mem(old_balances, amp)
    for i: int128 in range(N_COINS):
        new_balances[i] -= amounts[i]
    D1: uint256 = self.get_D_mem(new_balances, amp)
    fees: uint256[N_COINS] = empty(uint256[N_COINS])
    for i: int128 in range(N_COINS):
        ideal_balance: uint256 = D1 * old_balances[i] / D0
        difference: uint256 = 0
        if ideal_balance > new_balances[i]:
            difference = ideal_balance - new_balances[i]
        else:
            difference = new_balances[i] - ideal_balance
        fees[i] = _fee * difference / FEE_DENOMINATOR
        self.balances[i] = new_balances[i] - (fees[i] * _admin_fee / FEE_DENOMINATOR)
        new_balances[i] -= fees[i]
    D2: uint256 = self.get_D_mem(new_balances, amp)

    token_amount: uint256 = (D0 - D2) * token_supply / D0
    assert token_amount != 0  # dev: zero tokens burned
    token_amount += 1  # In case of rounding errors - make it unfavorable for the "attacker"
    assert token_amount <= max_burn_amount, "Slippage screwed you"

    self.token.burnFrom(msg.sender, token_amount)  # dev: insufficient funds
    for i: int128 in range(N_COINS):# @Diff
        if amounts[i] != 0:

            # "safeTransfer" which works for ERC20s which return bool or not
            _response: Bytes[32] = raw_call(# @Diff
                self.coins[i],
                concat(
                    method_id("transfer(address,uint256)"),
                    convert(msg.sender, bytes32),
                    convert(amounts[i], bytes32),
                ),
                max_outsize=32,
            )  # dev: failed transfer
            if len(_response) > 0:
                assert convert(_response, bool)  # dev: failed transfer# @Diff

    log RemoveLiquidityImbalance(msg.sender, amounts, fees, D1, token_supply - token_amount)


@view
@internal
def get_y_D(A_: uint256, i: int128, xp: uint256[N_COINS], D: uint256) -> uint256:
    """
    Calculate x[i] if one reduces D from being calculated for xp to D

    Done by solving quadratic equation iteratively.
    x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
    x_1**2 + b*x_1 = c

    x_1 = (x_1**2 + c) / (2*x_1 + b)
    """
    # x in the input is converted to the same price/precision

    assert i >= 0  # dev: i below zero
    assert i < N_COINS  # dev: i above N_COINS

    c: uint256 = D
    S_: uint256 = 0
    Ann: uint256 = A_ * N_COINS

    _x: uint256 = 0
    for _i: int128 in range(N_COINS):
        if _i != i:
            _x = xp[_i]
        else:
            continue
        S_ += _x
        c = c * D / (_x * N_COINS)
    c = c * D / (Ann * N_COINS)
    b: uint256 = S_ + D / Ann
    y_prev: uint256 = 0
    y: uint256 = D
    for _i: int128 in range(255):
        y_prev = y
        y = (y*y + c) / (2 * y + b - D)
        # Equality with the precision of 1
        if y > y_prev:
            if y - y_prev <= 1:
                break
        else:
            if y_prev - y <= 1:
                break
    return y


@view
@internal
def _calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> (uint256, uint256):
    # First, need to calculate
    # * Get current D
    # * Solve Eqn against y_i for D - _token_amount
    amp: uint256 = self._A()
    _fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))
    precisions: uint256[N_COINS] = PRECISION_MUL# @Diff
    total_supply: uint256 = self.token.totalSupply()# @Diff

    xp: uint256[N_COINS] = self._xp()# @Diff

    D0: uint256 = self.get_D(xp, amp)
    D1: uint256 = D0 - _token_amount * D0 / total_supply
    xp_reduced: uint256[N_COINS] = xp

    new_y: uint256 = self.get_y_D(amp, i, xp, D1)
    dy_0: uint256 = (xp[i] - new_y) / precisions[i]  # w/o fees

    for j: uint256 in range(N_COINS):
        dx_expected: uint256 = 0
        if j == i:
            dx_expected = xp[j] * D1 / D0 - new_y
        else:
            dx_expected = xp[j] - xp[j] * D1 / D0
        xp_reduced[j] -= _fee * dx_expected / FEE_DENOMINATOR

    dy: uint256 = xp_reduced[i] - self.get_y_D(amp, i, xp_reduced, D1)
    dy = (dy - 1) / precisions[i]  # Withdraw less to account for rounding errors# @Diff

    return dy, dy_0 - dy


@view
@external
def calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256:
    return self._calc_withdraw_one_coin(_token_amount, i)[0]

@external
@nonreentrant
def remove_liquidity_one_coin(
    _token_amount: uint256, # Amount of LP tokens to burn
    i: int128, # Which coin to receive 90, 1 or 2)
    min_amount: uint256 # Minimum amount of coin to receive (slippage protection)
    ):
    """
    /*//////////////////////////////////////////////////////////////
        CRITICAL WITHDRAWAL FUNCTION - HIGH SECURITY IMPORTANCE
    //////////////////////////////////////////////////////////////*/

    PURPOSE: Burns LP tokens, returns single coin type to use

    SECURITY CLASSIFICATION: ⚠️ HIGH RISK ⚠️
    - Contains external call that WILL trigger callbacks if token is malicious
    - Multiple state transitions before external call creates attack windows
    - Admin fee mechanism adds economic complexity
    - Read-only reentrancy attack surface (confirmed in real exploits)

    KNOWN ATTACK PATTERN:
    1. Attacker calls this function with malicious ERC20 -> During transfer callback.
    2. Attacker calls view functions that read inconsistent state -> Exploits inflated.
    3. virtual_price to drain other pools or execute advantageous swaps

    PROTECTION: @nonreentrant('lock') prevents direct reentrancy but NOT
    read-only reentrancy into view functions (get_virtual_price, etc.)

    Remove _amount of liquidity all in a form of coin i
    """

    #/*//////////////////////////////////////////////////////////////
    #                   STEP 0: EMERGENCY CONTROLS
    # Line 703: First line of defense - kill switch check
    #//////////////////////////////////////////////////////////////*/
    assert not self.is_killed  # dev: is killed

    # SECURITY NOTE: Kill switch prevents withdrawals during emergency
    # AUDIT QUESTION: Can admin toggle is_killed during callback window?
    # If yes -> potential race condition where attacker frontrun admin's kill tx
    # ATTACK SCENARIO: Admin detects exploit, tries to kill pool, attacker
    # callback executes before kill takes effect.

    #/*//////////////////////////////////////////////////////////////
    #               STEP 1: CALCULATE WITHDRAWAL AMOUNTS
    # Line 717: Calculate output amount using StableSwap invariant
    #//////////////////////////////////////////////////////////////*/
    dy: uint256 = 0 # Amount user receives (before fees)
    dy_fee: uint256 = 0 # Fee charged by protocol
    dy, dy_fee = self._calc_withdraw_one_coin(_token_amount, i)

    # CALCULATION DEEP DIVE:
    # - Uses get_D() to find current pool invariant D
    # - Uses get_y_D() to calculate new balance after LP burn
    # - Difference = dy (what user gets) + dy_fee (protocol revenue)
    #
    # CRITICAL ASSUMPTION: Calculation assumes current pool state is accurate
    # This includes self.balances[], A (amplification coefficient),
    # fee parameters
    #
    # SECURITY IMPLICATION: These values are READ from state
    # but state is about to be MODIFIED  before token are transferred.
    # Creates temporal inconsistency in multi-step operation.

    assert dy >= min_amount, "Not enough coins removed" # Slippage protection
    # SLIPPAGE CHECK: Protects user from sandwich attacks and price manipulation
    # BUT occurs BEFORE state changes - so it validates against pre-withdrawal
    # state.

    #/*//////////////////////////////////////////////////////////////
    #                    STEP 2: UPDATE BALANCES
    # Line 743: Reduce the pool's tracked balance for coin[i]
    # ⚠️ CRITICAL: Pool's internal accounting updated HERE
    # But the tokens haven't been sent yet‼️
    #//////////////////////////////////////////////////////////////*/
    self.balances[i] -= (dy + dy_fee * self.admin_fee / FEE_DENOMINATOR)

    # ⚠️⚠️⚠️ CRITICAL STATE TRANSITION #1 ⚠️⚠️⚠️
    #
    # WHAT JUST HAPPENED:
    # Pool's internal accounting for coins[i] is NOW reduced by:
    # - dy: Amount that will be sent to user
    # - (dy_fee * admin_fee / FEE_DENOMINATOR): Admin's share of fees
    #
    # BUT CRITICALLY:
    # - The actual tokens are STILL IN THE CONTRACT
    # - User hasn't received 'dy' yet
    # - Admin hasn't received their fee yet
    #
    # POOL NOW HOLDS MORE TOKENS THAN self.balances[i] INDICATES
    #
    # FEE MECHANISM EXPLAINED:
    # Total fee = dy_fee
    # Admin gets: dy_fee * admin_fee / FEE_DENOMINATOR
    # LPs keep: dy_fee * (FEE_DENOMINATOR / admin_fee) / FEE_DENOMINATOR
    # The LP portion stays in pool, increasing value for remaining LPs.
    #
    # ATTACK SURFACE - INFLATED POOL VALUE:
    # During callback, if attacker reads get_virtual_price():
    # - Numerator (D) reflects OLD pool composition (larger)
    # - Denominator totalSupply) will be REDUCED (after burn in Step 3)
    # - But pool STILL PHYSICALLY HOLDS tokens not yet transferred
    # - Result: virtual_price is INFLATED
    #
    # ECONOMIC ATTACK VECTOR:
    # Attacker could use inflated virtual_price to:
    # 1. Execute favorable swaps in other pools that trust this price
    # 2. Manipulate lending protocols that use virtual_price as collateral value
    # 3. Exploit cross-pool arbitrage with synthetic pricing


    #/*//////////////////////////////////////////////////////////////
    #                     STEP 3: BURN LP TOKENS
    # Line 783: Destroy the user's LP tokens
    #//////////////////////////////////////////////////////////////*/
    self.token.burnFrom(msg.sender, _token_amount)  # dev: insufficient funds
    # User's LP tokens are no burnet

    # ⚠️⚠️⚠️ CRITICAL STATE TRANSITION #2 ⚠️⚠️⚠️
    # WHAT JUS HAPPENED:
    # - msg.sender's LP token balance: REDUCED by _token_amount
    # - Total LP supply: REDUCED by _token_amount
    # - Pool's self.balances[i]: ALREADY reduced (Step 2)
    # - Actual token balances in contract: UNCHANGED (still holds everything)
    #
    # THE COMMENT "dev: insufficient funds":
    # This comment indicates that the revert message if msg.sender
    # doesn't have enough LP tokens to burn. It's NOT an audit issue,
    # just Curve's internal error labeling convention.
    #
    # STATE INCONSISTENCY WINDOW IS NOW LARGER:
    # Pool believes it has: self.balances[i] (reduced)
    # Pool actually has: self.balances[i] + dy + admin_fe_portion
    # LP supply: reduced (burned)
    #
    # ATTACK IMPLICATION FOR virtual_price:
    # virtual_price = D * 10**18 / totalSupply
    # - D calculated from self.balances[i] (REDUCED)
    # - totalSupply is REDUCED
    # - But actual tokens in contract UNCHANGED
    # Both numerator and denominator ae "WRONG" but in ways that
    # could create exploitable arbitrage

    #/*//////////////////////////////////////////////////////////////
    #               ⚠️ STEP 4: EXTERNAL CALL DANGER ZONE ⚠️
    # Line 816: Transfer tokens to user (CALLBACK EXECUTION POINT)
    #//////////////////////////////////////////////////////////////*/

    # Using low-level raw_call instead of high-level ERC20 interface
    # WHY: Handles non-standard tokens (USDT) that don't return bool

    # "safeTransfer" which works for ERC20s which return bool or not
    _response: Bytes[32] = raw_call(
        self.coins[i],                              # Target: token contract
        concat(
            method_id("transfer(address,uint256)"), # Function selector
            convert(msg.sender, bytes32),           # Recipient
            convert(dy, bytes32),                   # Amount
        ),
        max_outsize=32,                             # Expect up to 32 bytes return
    )  # dev: failed transfer

    # 💄💄💄 THIS IS THE ATTACK WINDOW 💄💄💄
    #
    # CONTROL FLOW TRANSFER TO EXTERNAL CONTRACT:
    # When raw_call executes, control transfer to self.coins[i] contract
    # 
    # IF coins[i] IS MALICIOUS OR HAS HOOKS (ERC777, ERC1363):
    # 1. Attacker's contract receives control flow
    # 2. Attacker can call ANY Curve pool function
    # 3. @nonreentrant('lock') prevents calling THIS function again
    # BUT @nonreentrant DOES NOT prevent calling VIEW FUNCTIONS
    #
    # EXPLOITABLE VIEW FUNCTIONS DURING CALLBACK:
    # - get_virtual_price() -> Returns inflated price due to state inconsistency
    # - get_dy() -> Calculates swap using inconsistent balances
    # - calc_token_amount() -> Estimates deposits using wrong state
    # - Any function reading self.balances[] or totalSupply
    #
    # MULTI-STEP ATTACK CHAIN EXAMPLE:
    # 1. Attacker calls remove_liquidity_one_coin with malicious token
    # 2. During callback, attacker calls get_virtual_price() -> inflated value
    # 3. Attacker uses inflated price in another DeFi protocol
    # 4. Attacker can:
    #   a) Execute unfavorable swaps for remaining LPs
    #   b) Manipulate oracle price feeds
    #   c) Exploit cross-pool arbitrage
    #   d) Over-borrow from lending protocols using inflated collateral
    #
    # RAW_CALL SPECIFIC RISKS:
    # - No automatic safety checks (unlike high-level ERC20 interface)
    # - Calls ANY code at self.coins[i] address
    # - If coins[i] is upgradeable proxy -> admin control inject malicious logic
    # - Return checking is MANUAL (next lines)
    #
    # REAL-WORLD EXPLOIT PATTERN:
    # Multiple Curve-related hacks exploited this exact pattern:
    # - Vyper compiler reentrancy bug (2023)
    # - Read-only reentrancy in forked protocols
    # - Price oracle manipulation attacks

    # Manual return value validation (for non-standard ERC20s)
    if len(_response) > 0:
        assert convert(_response, bool)  # dev: failed transfer

    # RETURN VALUE HANDLING:
    # - Some tokens (USDT) return nothing
    # - Standard tokens return bool
    # - This code handles both: only check bool if response exists
    #
    # SECURITY NOTE: By this point, if transfer fails:
    # - Pool state is already corrupted (balances reduced, LP burned)
    # - But user didn't receive tokens
    # - This would brick the pool state
    # - Assert here is CRITICAL for atomicity

    #/*//////////////////////////////////////////////////////////////
    #                       STEP 5: EMIT EVENT
    # Line 888: Log the withdrawal for off-chain tracking
    #//////////////////////////////////////////////////////////////*/
    log RemoveLiquidityOne(msg.sender, _token_amount, dy)

    # EVENT EMISSION:
    # At this point, operation is complete and state is consistent again
    # Event allows:
    # - Off-chain indexers to track withdrawals
    # - UI to update user balances
    # - Analytics to monitor pool activity
    #
    # AUDIT NOTE: Event emitted AFTER external call
    # Follows check-effects-interactions pattern for events
    # But effects (state changes) happened BEFORE interaction (EXTERNAL call)
    # This is the reentrancy vulnerability root cause

    #/*//////////////////////////////////////////////////////////////
    #                     VULNERABILITY SUMMARY
    #//////////////////////////////////////////////////////////////*/
    #
    # ROOT CAUSE: Checks_Effects_Interactions pattern violated
    # - Effects (balance updates, LP burn) happen in steps 2-3
    # - Interaction (external call) happens in step 4
    # - Creates temporal window where state is inconsistent
    #
    # PROTECTION ANALYSIS:
    # ✅ @nonreentrant('lock') prevents direct reentrancy
    # ❌ Does NOT prevent read-only reentrancy into view functions
    # ❌ Does NOT prevent cross-function reentrancy into other pools
    # ❌ Does NOT prevent cross-contract reentrancy
    #
    # RECOMMENDATION MITIGATIONS:
    # 1. Add reentrancy guard to ALL view functions (expensive)
    # 2. Move external call BEFORE state changes (violates CEI but safer)
    # 3. Use ReentrancyGuard that blocks ALL external calls during execution
    # 4. Implement "temporary state" pattern with commit/rollback
    # 5. Whitelist only trusted tokens (breaks composability)
    #
    # DETECTION STRATEGY:
    # - Look for state modifications before external calls
    # - Check if view functions read modified state
    # - Test with malicious ERC20/ERC777 tokens
    # - Simulate callback scenarios in fuzzing
    #
    # BUSINESS IMPACT IF EXPLOITED:
    # - Pool drained through arbitrage
    # - Oracle manipulation affecting external protocols
    # - Loss of LP funds
    # - Systemic risk to DeFi ecosystem

### Admin functions ###
@external
def ramp_A(_future_A: uint256, _future_time: uint256):
    assert msg.sender == self.owner  # dev: only owner
    assert block.timestamp >= self.initial_A_time + MIN_RAMP_TIME
    assert _future_time >= block.timestamp + MIN_RAMP_TIME  # dev: insufficient time

    _initial_A: uint256 = self._A()
    assert (_future_A > 0) and (_future_A < MAX_A)
    assert ((_future_A >= _initial_A) and (_future_A <= _initial_A * MAX_A_CHANGE)) or\
           ((_future_A < _initial_A) and (_future_A * MAX_A_CHANGE >= _initial_A))
    self.initial_A = _initial_A
    self.future_A = _future_A
    self.initial_A_time = block.timestamp
    self.future_A_time = _future_time

    log RampA(_initial_A, _future_A, block.timestamp, _future_time)


@external
def stop_ramp_A():
    assert msg.sender == self.owner  # dev: only owner

    current_A: uint256 = self._A()
    self.initial_A = current_A
    self.future_A = current_A
    self.initial_A_time = block.timestamp
    self.future_A_time = block.timestamp
    # now (block.timestamp < t1) is always False, so we return saved A

    log StopRampA(current_A, block.timestamp)


@external
def commit_new_fee(new_fee: uint256, new_admin_fee: uint256):
    assert msg.sender == self.owner  # dev: only owner
    assert self.admin_actions_deadline == 0  # dev: active action
    assert new_fee <= MAX_FEE  # dev: fee exceeds maximum
    assert new_admin_fee <= MAX_ADMIN_FEE  # dev: admin fee exceeds maximum

    _deadline: uint256 = block.timestamp + ADMIN_ACTIONS_DELAY
    self.admin_actions_deadline = _deadline
    self.future_fee = new_fee
    self.future_admin_fee = new_admin_fee

    log CommitNewFee(_deadline, new_fee, new_admin_fee)


@external
def apply_new_fee():
    assert msg.sender == self.owner  # dev: only owner
    assert block.timestamp >= self.admin_actions_deadline  # dev: insufficient time
    assert self.admin_actions_deadline != 0  # dev: no active action

    self.admin_actions_deadline = 0
    _fee: uint256 = self.future_fee
    _admin_fee: uint256 = self.future_admin_fee
    self.fee = _fee
    self.admin_fee = _admin_fee

    log NewFee(_fee, _admin_fee)


@external
def revert_new_parameters():
    assert msg.sender == self.owner  # dev: only owner

    self.admin_actions_deadline = 0


@external
def commit_transfer_ownership(_owner: address):
    assert msg.sender == self.owner  # dev: only owner
    assert self.transfer_ownership_deadline == 0  # dev: active transfer

    _deadline: uint256 = block.timestamp + ADMIN_ACTIONS_DELAY
    self.transfer_ownership_deadline = _deadline
    self.future_owner = _owner

    log CommitNewAdmin(_deadline, _owner)


@external
def apply_transfer_ownership():
    assert msg.sender == self.owner  # dev: only owner
    assert block.timestamp >= self.transfer_ownership_deadline  # dev: insufficient time
    assert self.transfer_ownership_deadline != 0  # dev: no active transfer

    self.transfer_ownership_deadline = 0
    _owner: address = self.future_owner
    self.owner = _owner

    log NewAdmin(_owner)


@external
def revert_transfer_ownership():
    assert msg.sender == self.owner  # dev: only owner

    self.transfer_ownership_deadline = 0


@view
@external
def admin_balances(i: uint256) -> uint256:# @Diff
    return staticcall IERC20(self.coins[i]).balanceOf(self) - self.balances[i]


@external
def withdraw_admin_fees():# @Diff
    assert msg.sender == self.owner  # dev: only owner

    for i: int128 in range(N_COINS):
        c: address = self.coins[i]
        value: uint256 = staticcall IERC20(c).balanceOf(self) - self.balances[i]
        if value > 0:
            # "safeTransfer" which works for ERC20s which return bool or not
            _response: Bytes[32] = raw_call(
                c,
                concat(
                    method_id("transfer(address,uint256)"),
                    convert(msg.sender, bytes32),
                    convert(value, bytes32),
                ),
                max_outsize=32,
            )  # dev: failed transfer
            if len(_response) > 0:
                assert convert(_response, bool)  # dev: failed transfer


@external
def donate_admin_fees():
    assert msg.sender == self.owner  # dev: only owner
    for i: int128 in range(N_COINS):
        self.balances[i] = staticcall IERC20(self.coins[i]).balanceOf(self)


@external
def kill_me():
    assert msg.sender == self.owner  # dev: only owner
    assert self.kill_deadline > block.timestamp  # dev: deadline has passed
    self.is_killed = True


@external
def unkill_me():
    assert msg.sender == self.owner  # dev: only owner
    self.is_killed = False

