// 손으로 관리 — 이자·스테이킹 토큰을 원금 코인 보유로 센다.
// 주소마다 이더리움에서 symbol()·decimals()와 asset()(ERC-4626) 또는 UNDERLYING_ASSET_ADDRESS()(aToken)를 불러 원금을 확인했다.
// USDT·GHO처럼 바이낸스 USDT 마켓이 없는 원금은 시세가 없어 "가져오지 않은 잔고"로만 보인다.

extension EVMToken {
    static let yieldBearing: [EVMToken] = [
        // Aave v3 aToken — 잔고가 곧 원금이고 이자가 붙으며 늘어난다.
        EVMToken(chain: .ethereum, contract: "0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c", symbol: "USDC", decimals: 6),   // aEthUSDC
        EVMToken(chain: .ethereum, contract: "0x23878914efe38d27c4d67ab83ed1b93a74d4086a", symbol: "USDT", decimals: 6),   // aEthUSDT
        EVMToken(chain: .ethereum, contract: "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8", symbol: "ETH", decimals: 18),   // aEthWETH
        EVMToken(chain: .ethereum, contract: "0x5ee5bf7ae06d1be5997a1a72006fe6c607ec6de8", symbol: "WBTC", decimals: 8),   // aEthWBTC
        // Aave static aToken(ERC-4626) — 지분을 convertToAssets로 원금으로 바꾼다.
        EVMToken(chain: .ethereum, contract: "0xd4fa2d31b7968e448877f69a96de69f5de8cd23e", symbol: "USDC", decimals: 6,    // waEthUSDC
                 vaultPath: ["0xd4fa2d31b7968e448877f69a96de69f5de8cd23e"]),
        EVMToken(chain: .ethereum, contract: "0x7bc3485026ac48b6cf9baf0a377477fff5703af8", symbol: "USDT", decimals: 6,    // waEthUSDT
                 vaultPath: ["0x7bc3485026ac48b6cf9baf0a377477fff5703af8"]),
        EVMToken(chain: .ethereum, contract: "0x0bfc9d54fc184518a81162f8fb99c2eaca081202", symbol: "ETH", decimals: 18,    // waEthWETH
                 vaultPath: ["0x0bfc9d54fc184518a81162f8fb99c2eaca081202"]),
        // Aave Umbrella 스테이킹 — stk → waEth(static aToken) → 원금.
        EVMToken(chain: .ethereum, contract: "0x6bf183243fdd1e306ad2c4450bc7dcf6f0bf8aa6", symbol: "USDC", decimals: 6,    // stkwaEthUSDC.v1
                 vaultPath: ["0x6bf183243fdd1e306ad2c4450bc7dcf6f0bf8aa6", "0xd4fa2d31b7968e448877f69a96de69f5de8cd23e"]),
        EVMToken(chain: .ethereum, contract: "0xa484ab92fe32b143aee7019fc1502b1daa522d31", symbol: "USDT", decimals: 6,    // stkwaEthUSDT.v1
                 vaultPath: ["0xa484ab92fe32b143aee7019fc1502b1daa522d31", "0x7bc3485026ac48b6cf9baf0a377477fff5703af8"]),
        EVMToken(chain: .ethereum, contract: "0xaafd07d53a7365d3e9fb6f3a3b09ec19676b73ce", symbol: "ETH", decimals: 18,    // stkwaEthWETH.v1
                 vaultPath: ["0xaafd07d53a7365d3e9fb6f3a3b09ec19676b73ce", "0x0bfc9d54fc184518a81162f8fb99c2eaca081202"]),
        EVMToken(chain: .ethereum, contract: "0x4f827a63755855cdf3e8f3bcd20265c833f15033", symbol: "GHO", decimals: 18,    // stkGHO.v1
                 vaultPath: ["0x4f827a63755855cdf3e8f3bcd20265c833f15033"])
    ]
}
