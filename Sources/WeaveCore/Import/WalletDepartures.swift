import Foundation

/// 지갑 밖으로 나간 코인 정리.
/// 동기화는 지갑에서 줄어든 만큼을 일단 직접 입력분으로 돌려놓는다 — 같은 동기화에서 다른 연결 지갑이 늘었으면
/// 거기서 평단 그대로 가져가게. 모든 지갑을 반영한 뒤에도 직접 입력분에 남은 것 중 원래 직접 입력분에서 오지 않은 몫은
/// 지갑 밖(거래소로 보냄, 다른 토큰으로 바꿈)으로 나간 것이라 포트폴리오에서 뺀다.
public enum WalletDepartures {
    private static let walletPrefix = "move:"
    private static let manualPrefix = "move-manual:"

    /// 자산마다 지갑 → 직접 입력 이동이 직접 입력 → 지갑 이동보다 많은 만큼을, 최근 이동부터 지갑 쪽 잔고 맞춤 매도로 바꾼다.
    /// 지갑 평단에 팔아 실현손익은 없다. 돌아온 코인을 이미 직접 매도했으면 그만큼은 건드리지 않는다.
    /// - Returns: 정리한 자산 수.
    @discardableResult
    public static func settle(_ document: inout PortfolioDocument) -> Int {
        let manualLegs = document.trades.filter { $0.sourceID == nil && $0.isTransfer }
        var settled = 0
        for (assetID, legs) in Dictionary(grouping: manualLegs, by: \.assetID) {
            let net = legs.reduce(Decimal(0)) { $0 + ($1.side == .buy ? $1.quantity : -$1.quantity) }
            let manual = PositionCalculator.snapshot(
                trades: document.trades.filter { $0.assetID == assetID && $0.sourceID == nil }
            ).quantity
            var excess = min(net, manual)
            guard excess > 0 else { continue }
            let returns = legs.filter { $0.side == .buy }.sorted { $0.date > $1.date }
            for leg in returns where excess > 0 {
                guard let manualID = leg.externalID, manualID.hasPrefix(manualPrefix),
                      let manualIndex = document.trades.firstIndex(where: { $0.id == leg.id })
                else { continue }
                let walletID = walletPrefix + manualID.dropFirst(manualPrefix.count)
                guard let walletIndex = document.trades.firstIndex(where: {
                    $0.assetID == assetID && $0.sourceID == leg.transferSourceID && $0.isTransfer
                        && $0.side == .sell && $0.externalID == walletID
                }) else { continue }
                let gone = min(leg.quantity, excess)
                excess -= gone
                if gone == leg.quantity {
                    // 통째로 나갔다 — 지갑 쪽 이동을 잔고 맞춤 매도로 바꾸고 직접 입력 쪽은 지운다.
                    // externalID는 남겨 같은 이동이 다시 들어오지 않게 한다.
                    document.trades[walletIndex].transferSourceID = nil
                    document.trades[walletIndex].balanceAdjustment = true
                    document.trades.remove(at: manualIndex)
                } else {
                    let wallet = document.trades[walletIndex]
                    document.trades[walletIndex].quantity -= gone
                    document.trades[manualIndex].quantity -= gone
                    document.trades.append(Trade(
                        assetID: assetID, side: .sell, quantity: gone, price: wallet.price, date: wallet.date,
                        sourceID: wallet.sourceID, externalID: "leave:" + manualID.dropFirst(manualPrefix.count),
                        balanceAdjustment: true
                    ))
                }
            }
            settled += 1
        }
        return settled
    }
}
