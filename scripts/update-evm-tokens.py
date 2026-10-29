#!/usr/bin/env python3
"""EVM 지갑이 잔고를 볼 토큰 목록을 만든다.

Uniswap 기본 토큰 목록 중 Weave가 지원하는 체인에 있고, 바이낸스 USDT 마켓에 있는 토큰만 남긴다.
목록에 없는 컨트랙트는 조회하지 않으니 같은 심볼을 흉내 낸 스팸 토큰이 들어오지 않는다.

사용: python3 -I scripts/update-evm-tokens.py
"""
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/WeaveCore/Linking/EVMTokenList.swift"

CHAINS = {1: "ethereum", 42161: "arbitrum", 8453: "base", 10: "optimism", 137: "polygon"}
# 래핑·브리지 표기를 바이낸스 심볼로 맞춘다 — 지갑의 WETH는 ETH 보유로 본다.
ALIASES = {"WETH": "ETH", "USDC.E": "USDC", "USDBC": "USDC"}
# Uniswap 목록에 이전 버전 컨트랙트가 남은 토큰 — 바이낸스에서 거래되는 새 컨트랙트로 바꾼다.
# KNC: v1("Kyber Network Crystal") → v2("Kyber Network Crystal v2"), 이름은 각 체인에서 name()으로 확인.
REPLACE = {
    ("ethereum", "0xdd974d5c2e2928dea5f71b9825b8b646686bd200"): "0xdefa4e8a7bcba345f687a2f1456f5edd9ce97202",
    ("polygon", "0x324b28d6565f784d596422b0f2e5ab6e9cfa1dc7"): "0x1c954e8fe737f99f68fa1ccda3e51ebdb291948c",
}


def fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Weave token list script"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def main():
    uniswap = fetch_json("https://tokens.uniswap.org")
    exchange = fetch_json("https://api.binance.com/api/v3/exchangeInfo?permissions=SPOT")
    listed = {
        s["baseAsset"]
        for s in exchange["symbols"]
        if s["quoteAsset"] == "USDT" and s["status"] == "TRADING"
    }

    rows = set()
    for token in uniswap["tokens"]:
        chain = CHAINS.get(token["chainId"])
        symbol = ALIASES.get(token["symbol"].upper(), token["symbol"].upper())
        if chain is None or symbol not in listed:
            continue
        address = token["address"].lower()
        rows.add((chain, REPLACE.get((chain, address), address), symbol, int(token["decimals"])))

    order = list(CHAINS.values())
    lines = [
        "// 자동 생성 — scripts/update-evm-tokens.py로 다시 만든다. 손으로 고치지 않는다.",
        f"// 출처: {uniswap['name']} v{uniswap['version']['major']}.{uniswap['version']['minor']}.{uniswap['version']['patch']}"
        " ∩ 바이낸스 USDT 마켓.",
        "",
        "extension EVMToken {",
        "    static let known: [EVMToken] = [",
    ]
    for chain, address, symbol, decimals in sorted(rows, key=lambda r: (order.index(r[0]), r[2], r[1])):
        lines.append(
            f'        EVMToken(chain: .{chain}, contract: "{address}", symbol: "{symbol}", decimals: {decimals}),'
        )
    lines += ["    ]", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"{len(rows)} tokens → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
