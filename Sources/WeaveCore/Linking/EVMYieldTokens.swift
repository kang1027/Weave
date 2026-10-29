// 손으로 관리 — 이자·스테이킹 토큰. 토큰 자체를 자산으로 보이고, 값은 원금 코인 시세 × 원금 교환비로 매긴다.
// 주소마다 이더리움에서 symbol()·decimals()와 asset()(ERC-4626) 또는 UNDERLYING_ASSET_ADDRESS()(aToken)를 불러 원금을 확인했다.
// USDT·GHO처럼 바이낸스 USDT 마켓이 없는 원금은 시세가 없어 "가져오지 않은 잔고"로만 보인다.

extension EVMToken {
    static let yieldBearing: [EVMToken] = [
        // Aave v3 aToken — 잔고가 곧 원금이고 이자가 붙으며 늘어난다.
        EVMToken(chain: .ethereum, contract: "0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c", symbol: "aEthUSDC", decimals: 6,
                 name: "Aave USDC", underlying: "USDC", underlyingDecimals: 6, vaultPath: []),
        EVMToken(chain: .ethereum, contract: "0x23878914efe38d27c4d67ab83ed1b93a74d4086a", symbol: "aEthUSDT", decimals: 6,
                 name: "Aave USDT", underlying: "USDT", underlyingDecimals: 6, vaultPath: []),
        EVMToken(chain: .ethereum, contract: "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8", symbol: "aEthWETH", decimals: 18,
                 name: "Aave ETH", underlying: "ETH", underlyingDecimals: 18, vaultPath: []),
        EVMToken(chain: .ethereum, contract: "0x5ee5bf7ae06d1be5997a1a72006fe6c607ec6de8", symbol: "aEthWBTC", decimals: 8,
                 name: "Aave WBTC", underlying: "WBTC", underlyingDecimals: 8, vaultPath: []),
        // Aave static aToken(ERC-4626) — 1개에 convertToAssets를 불러 원금 몇 개인지 본다.
        EVMToken(chain: .ethereum, contract: "0xd4fa2d31b7968e448877f69a96de69f5de8cd23e", symbol: "waEthUSDC", decimals: 6,
                 name: "Wrapped Aave USDC", underlying: "USDC", underlyingDecimals: 6, vaultPath: ["0xd4fa2d31b7968e448877f69a96de69f5de8cd23e"]),
        EVMToken(chain: .ethereum, contract: "0x7bc3485026ac48b6cf9baf0a377477fff5703af8", symbol: "waEthUSDT", decimals: 6,
                 name: "Wrapped Aave USDT", underlying: "USDT", underlyingDecimals: 6, vaultPath: ["0x7bc3485026ac48b6cf9baf0a377477fff5703af8"]),
        EVMToken(chain: .ethereum, contract: "0x0bfc9d54fc184518a81162f8fb99c2eaca081202", symbol: "waEthWETH", decimals: 18,
                 name: "Wrapped Aave ETH", underlying: "ETH", underlyingDecimals: 18, vaultPath: ["0x0bfc9d54fc184518a81162f8fb99c2eaca081202"]),
        // Aave Umbrella 스테이킹 — stk → waEth(static aToken) → 원금.
        EVMToken(chain: .ethereum, contract: "0x6bf183243fdd1e306ad2c4450bc7dcf6f0bf8aa6", symbol: "stkwaEthUSDC.v1", decimals: 6,
                 name: "Aave Umbrella USDC", underlying: "USDC", underlyingDecimals: 6, vaultPath: ["0x6bf183243fdd1e306ad2c4450bc7dcf6f0bf8aa6", "0xd4fa2d31b7968e448877f69a96de69f5de8cd23e"]),
        EVMToken(chain: .ethereum, contract: "0xa484ab92fe32b143aee7019fc1502b1daa522d31", symbol: "stkwaEthUSDT.v1", decimals: 6,
                 name: "Aave Umbrella USDT", underlying: "USDT", underlyingDecimals: 6, vaultPath: ["0xa484ab92fe32b143aee7019fc1502b1daa522d31", "0x7bc3485026ac48b6cf9baf0a377477fff5703af8"]),
        EVMToken(chain: .ethereum, contract: "0xaafd07d53a7365d3e9fb6f3a3b09ec19676b73ce", symbol: "stkwaEthWETH.v1", decimals: 18,
                 name: "Aave Umbrella ETH", underlying: "ETH", underlyingDecimals: 18, vaultPath: ["0xaafd07d53a7365d3e9fb6f3a3b09ec19676b73ce", "0x0bfc9d54fc184518a81162f8fb99c2eaca081202"]),
        EVMToken(chain: .ethereum, contract: "0x4f827a63755855cdf3e8f3bcd20265c833f15033", symbol: "stkGHO.v1", decimals: 18,
                 name: "Aave Umbrella GHO", underlying: "GHO", underlyingDecimals: 18, vaultPath: ["0x4f827a63755855cdf3e8f3bcd20265c833f15033"])
    ]
}
