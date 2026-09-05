# RPV4 launch specification

Status: source preparation only. Nothing has been submitted, signed, or broadcast.

## Chain and controller

- Chain: Robinhood Chain Mainnet (`4663`, `eip155:4663`)
- Launch wallet: `0x0000f19b0bf75fc367a2bf318876d2d87d78dead`
- Project fee recipient: `0x0000f19b0bf75fc367a2bf318876d2d87d78dead`

## Token metadata

- Name: `RPV4`
- Symbol: `RPV4`
- Decimals: `18`
- Fixed supply: `1,000,000,000 RPV4`
- Description: `RPV4 — A custom Programmable V4 token on Robinhood Chain.`
- Image: `https://litter.catbox.moe/jphz4uq8i7mrv730.png`
- Website: `https://programmable.family/`
- X: `https://x.com/ProgrammableHQ`

The website and X profile are Programmable's official links, selected explicitly by the project owner as defaults.

## Market behavior

- Liquidity model: hook-owned inventory custom accounting
- Launch style: token-side inventory only; no classical two-sided LP deposit
- Initial virtual FDV: `2 ETH`
- Buy fee: `1%`
- Sell fee: `1%`
- Maximum native input per buy: `0.05 ETH`
- Maximum balance per non-exempt wallet: `2%` of fixed supply (`20,000,000 RPV4`)
- Intended launch-wallet initial buy: approximately `0.039 ETH`, bounded by the 2% wallet cap
- No minting after deployment, pause, blacklist, proxy, or upgrade path

## Required safety gates

- Exact compiler and dependency lock
- Unit, fuzz, and Robinhood-fork tests
- Deterministic Programmable CLI `4.0.0` pack and local validation
- Authenticated remote preflight
- Independent wallet review of the exact transaction
- Explicit owner confirmation before submission and again before wallet broadcast

