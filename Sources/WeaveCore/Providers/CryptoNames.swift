import Foundation

/// Binance exchangeInfo에는 코인 풀네임이 없어서 주요 코인만 매핑한다.
/// 없는 심볼은 심볼 그대로 표시.
public enum CryptoNames {
    public static func name(for baseAsset: String) -> String {
        names[baseAsset.uppercased()] ?? baseAsset.uppercased()
    }

    private static let names: [String: String] = [
        "BTC": "Bitcoin", "ETH": "Ethereum", "BNB": "BNB", "SOL": "Solana",
        "XRP": "XRP", "ADA": "Cardano", "DOGE": "Dogecoin", "TRX": "TRON",
        "AVAX": "Avalanche", "DOT": "Polkadot", "LINK": "Chainlink",
        "MATIC": "Polygon", "POL": "Polygon", "TON": "Toncoin", "SHIB": "Shiba Inu",
        "LTC": "Litecoin", "BCH": "Bitcoin Cash", "UNI": "Uniswap",
        "ATOM": "Cosmos", "XLM": "Stellar", "ETC": "Ethereum Classic",
        "NEAR": "NEAR Protocol", "APT": "Aptos", "ARB": "Arbitrum",
        "OP": "Optimism", "SUI": "Sui", "SEI": "Sei", "INJ": "Injective",
        "FIL": "Filecoin", "AAVE": "Aave", "MKR": "Maker", "ALGO": "Algorand",
        "VET": "VeChain", "ICP": "Internet Computer", "HBAR": "Hedera",
        "SAND": "The Sandbox", "MANA": "Decentraland", "AXS": "Axie Infinity",
        "EGLD": "MultiversX", "THETA": "Theta Network", "XTZ": "Tezos",
        "EOS": "EOS", "GRT": "The Graph", "FTM": "Fantom", "RUNE": "THORChain",
        "PEPE": "Pepe", "WIF": "dogwifhat", "BONK": "Bonk", "ENA": "Ethena",
        "WLD": "Worldcoin", "JUP": "Jupiter", "PYTH": "Pyth Network",
        "TIA": "Celestia", "STX": "Stacks", "IMX": "Immutable", "RNDR": "Render",
        "RENDER": "Render", "CRV": "Curve DAO", "LDO": "Lido DAO",
        "SNX": "Synthetix", "COMP": "Compound", "DYDX": "dYdX", "GMX": "GMX",
        "USDT": "Tether", "USDC": "USD Coin", "DAI": "Dai"
    ]
}
