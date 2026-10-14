# Vendored dependencies

All Solidity dependencies are ordinary source files, with no submodules or install
step. Upstream sources are unchanged. `SHA256SUMS` records each included file; from
the project root run `sha256sum --check lib/SHA256SUMS` to check them.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0) | v5.4.0 | ERC20 and its four transitive imports, plus LICENSE | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | v1.9.7 | Solidity files under src/, plus both license files | MIT / Apache-2.0 |

Source archive SHA-256 digests:

```text
b89829be48bc501051002191733268a93ef6e238a4bb65d8fd1cbdf3969050d1  openzeppelin-contracts-v5.4.0.tar.gz
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94  forge-std-v1.9.7.tar.gz
```

The archives were fetched from `https://codeload.github.com/<organization>/<repository>/tar.gz/refs/tags/<release>`.
Forge Standard Library is used only by tests. Neither dependency needs a linked
library address. Compiler binaries are supplied by the Foundry environment, not
vendored here.
