# PLEA

PLEA is a fixed-supply ERC-20 for [imdacc.fun](https://imdacc.fun/). Its constructor
mints **1,000,000,000 PLEA with 18 decimals** to the immediate deployer. When the
IdentityMD factory creates it, the factory receives the entire supply and then
performs the launch distribution.

## Contract and behavior

Deployable contract: [`src/PLEA.sol:PLEA`](src/PLEA.sol). Constructor arguments:
**none** (`[]`); deployment value: **0 ETH**. There are no initialization calls,
application contracts, linked libraries, or external contract dependencies at
construction or during transfers.

| Property | Value |
| --- | --- |
| Solidity identifier | `PLEA` |
| Token name / symbol | `PLEA` / `PLEA` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Initial recipient | Constructor `msg.sender` (the launch factory) |

The token inherits the unmodified
[OpenZeppelin v5.4.0 ERC-20 implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.4.0/contracts/token/ERC20/ERC20.sol).
Transfers deliver exactly the requested amount. Standard `transfer`, `approve`,
`transferFrom`, `balanceOf`, `allowance`, metadata and supply getters are available.
Successful transfers and approvals return `true`; invalid operations revert with
ERC-6093 custom errors. Zero-value transfers between nonzero addresses are valid.
Transfers to the zero address and approvals to a zero spender revert.

There is no external mint or burn function, owner, administrator, pause,
blacklist, seizure, tax, rebase, transfer limit, upgrade, or permit function. The
constructor emits one `Transfer` from the zero address. Supply remains constant
for the lifetime of the deployed token. No address, including the factory, can
spend another holder's tokens without that holder's allowance.

`approve` replaces the existing allowance. Finite allowances decrease when spent;
`type(uint256).max` is treated as unlimited and is not decreased. As in
OpenZeppelin v5, `transferFrom` emits `Transfer` without an additional `Approval`
event. Integrations should read `allowance()` for its current value. Users should
approve only what they need and revoke unused approvals; changing an existing
nonzero approval has the standard ERC-20 transaction-ordering risk.

## Distribution and launch parameters

The percentages describe the **factory's distribution after construction**. The
token does not reserve balances or send tokens to destinations in its constructor.
The allocation sums to the complete fixed supply:

| Allocation | Share | PLEA | Base units |
| --- | --- | --- | --- |
| Liquidity pool | 87% | 870,000,000 | `870000000000000000000000000` |
| Season rewards | 3% | 30,000,000 | `30000000000000000000000000` |
| Merkle distribution | 10% | 100,000,000 | `100000000000000000000000000` |

The launch configuration supplied with this assignment is:

| Parameter | Value |
| --- | --- |
| Network | Ethereum, chain ID `1` |
| Pair currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Pool allocation | `poolBps = 8700` |
| Initial market cap | `initialMarketCapWei = "1000000000000000000000"` (1,000 IMD) |
| Season rewards recipient | `remainderTo = 0xee2aaa315cf7ed169f93148d30d24af9318dbb66` |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Pool initial-price provenance | `"79228162514264337593543950336"` |

The deployer derives the actual opening price from the specified market cap,
supply and token ordering. The initial-price provenance value is not a price
calculation performed by this token. The pair and rewards addresses above are
assignment-provided deployment data; the token does not hardcode or call them.

The factory sends 10% to its launch MerkleDistributor before seeding the pool and
forwarding the 3% remainder to the season rewards recipient. Under the supplied
launch policy, 2% of total supply is split among accepted contributors and 8%
among eligible paired seats. The launch infrastructure determines those claims
and manages the Merkle proofs. No additional distributor, pool, rewards vault,
or vesting scheme is implemented in this repository.

The separate manifest step supplies `launch.json` after acceptance; this project
does not generate one. Its token entry should select `PLEA`, with no constructor
arguments and the exact base-unit supply above. Only `src/PLEA.sol:PLEA` is a
production deployment target. Contracts in `test/` are local fixtures.

## Assumptions and operational responsibilities

- The standard ERC-20 behavior above is intentional: the brief specifies no
  additional transfer rules, reward schedule or vesting period.
- Allocation execution, pool initialization, liquidity custody, Merkle roots and
  claim handling belong to the launch infrastructure. A direct standalone
  deployment places all tokens with its caller; it does not enforce allocation.
- The recipient of the 3% allocation is responsible for season eligibility,
  scheduling, custody and reward payments. Those policies are external to PLEA.
- The website is informational project metadata; the token makes no website or
  network calls. All token amounts passed to the API use 18-decimal base units.

### After launch

There are **no owner-settable settings or maintenance calls**. The launch operator
must verify the deployed source, token metadata, total supply, constructor mint
event and final allocation receipts; publish the token/pool/distributor addresses;
and provide the claim interface and proofs. The season rewards custodian must
secure the supplied recipient and administer the season allocation. Explorer
verification and independent adversarial review belong to the release process.

The token rejects ordinary ETH sends and has no rescue function. Tokens sent to
contracts without a withdrawal mechanism (including PLEA itself) cannot be
recovered by an administrator. Transfers do not invoke recipient callbacks.

## Build and check

Run from this repository's root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x1bbbbde71244cad00c7e07a391f288df916ea07debfa75ac7ee8c99b3b438352 forge test
forge fmt --check
sha256sum --check lib/SHA256SUMS
```

[`foundry.toml`](foundry.toml) pins the compiler version, Cancun EVM target,
optimizer at 200 runs and `bytecode_hash = "none"`. FFI and filesystem permissions
are not enabled. All source dependencies and their licenses are vendored as
ordinary files in [`lib/`](lib/README.md); no downloads, RPC, credentials,
environment variables read by tests, submodules or install commands are needed.
An offline verifier needs only its preinstalled Foundry and pinned compiler.
`out/` and `cache/` are generated artifacts and are not source deliverables.

The tests cover:

- Exact metadata, initial supply and mint event; CREATE2 deployment to a factory
  with no initial allocation to the transaction origin or other recipients.
- Transfers, self-transfers, zero and smallest-unit amounts, complete balance
  transfers, approvals, revocation, finite and infinite allowances, and events.
- Insufficient balance/allowance, invalid destinations, rollback of allowances on
  failure, rejected unknown/admin calls, and rejected ETH transfers.
- The 87% / 3% / 10% token movements, full distributor claims, season payments and
  transfers in both directions through a pool-account fixture without deductions.
- Fuzzed transfer and failure boundaries (512 runs per fuzz test), plus stateful
  sequences (128 runs of 64 calls) checked against independent balance and
  allowance accounting, including unsuccessful operations.
- Runtime size and absence of `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT`.

The supplied protected tests and security reference were reviewed. Local launch
fixtures exercise the token's part of the flow; they do not execute a real
Uniswap v4 swap or verify Merkle proofs. The protected suite requires the network's
factory/pool harness and deployment manifest environment and is run separately
by the verifier. Local tests do not import the removable `.imd/reads/` inputs.

Security review of the delivered contract found a single constructor mint and no
later supply-changing entry point, external callbacks, privileged paths, or
upgrade mechanism. The reported checks are Foundry compilation, unit/fuzz/stateful
tests and formatting; Slither and Mythril were not run. These checks are not an
independent security audit.
