// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PLEA
/// @notice Fixed-supply token for https://imdacc.fun/.
/// @dev The deployer receives all tokens. The launch factory handles the 87% liquidity,
///      3% season rewards and 10% Merkle distribution after construction.
contract PLEA is ERC20 {
    /// @notice One billion PLEA expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("PLEA", "PLEA") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
