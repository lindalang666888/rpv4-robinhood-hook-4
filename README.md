# RPV4 Robinhood Custom V4 Hook

Source preparation for an RPV4 launch through Programmable V4 on Robinhood Chain (`4663`). This repository does not
contain a private key or API key, and no script signs or broadcasts a transaction.

The design uses hook-owned token inventory and a virtual constant-product curve. It starts at a virtual 2 ETH FDV,
charges 1% on buys and sells, limits an exact-input buy to 0.05 ETH, and enforces a 2% token balance ceiling for
non-exempt wallets. The immutable fee recipient and launch wallet are
`0x0000F19B0bf75Fc367A2bf318876d2d87D78DeAD`.

See [RPV4-LAUNCH-SPEC.md](RPV4-LAUNCH-SPEC.md) for the owner-approved parameters.

## Safety status

This is unaudited custom accounting. Local compilation and Programmable packing are preparation evidence, not an
audit, platform approval, deployment, or proof of third-party router compatibility. Submission and wallet broadcast
require separate explicit owner confirmation.

## Reproducible preparation

Use Node.js 24.14.x. The official Programmable CLI 4.0.0 is pinned to its immutable GitHub release tarball.

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm run test:economics
```

`build-and-configure.mjs` follows the official V4 clean-room flow. It requires the public environment inputs printed
by `node build-and-configure.mjs --help`, fetches only public V4 capabilities, compiles exact Solidity sources, and
writes ignored build/config artifacts. The builder deliberately refuses `PROGRAMMABLE_API_KEY`.
