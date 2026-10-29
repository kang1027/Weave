import Foundation

public struct ImportResult: Equatable, Sendable {
    public var added = 0
    public var openingBalances = 0
    public var merged = 0
    /// 자산이 없어 넣지 못한 거래 수.
    public var skippedWithoutAsset = 0
}

/// 검토를 마친 계획을 문서에 넣는다.
public enum ImportApplier {
    /// - assetIDs: 계획의 missingAssets를 호출부가 자산으로 만든 결과. 기존 자산은 종목으로 찾는다.
    /// - mergeDuplicates: 직접 입력과 겹친 체결을 가져온 기록으로 합칠지(직접 입력 쪽을 지운다).
    @discardableResult
    public static func apply(
        _ plan: ImportPlan,
        to document: inout PortfolioDocument,
        assetIDs: [ImportInstrument: UUID] = [:],
        mergeDuplicates: Bool = true,
        now: Date = Date()
    ) -> ImportResult {
        var result = ImportResult()
        let alreadyImported = Set(
            document.trades.filter { $0.sourceID == plan.sourceID }.compactMap(\.externalID)
        )
        var addedExternalIDs = Set<String>()

        for planned in plan.trades {
            if let externalID = planned.externalID, alreadyImported.contains(externalID) { continue }
            guard let assetID = assetIDs[planned.instrument]
                ?? document.assets.first(where: planned.instrument.matches)?.id
            else {
                result.skippedWithoutAsset += 1
                continue
            }
            // 같은 계획을 두 번 적용해도 기초 잔고가 겹치지 않게 — 계좌·자산당 하나.
            if planned.isOpeningBalance, document.trades.contains(where: {
                $0.sourceID == plan.sourceID && $0.assetID == assetID && $0.isOpeningBalance
            }) {
                continue
            }
            document.trades.append(planned.asTrade(assetID: assetID, sourceID: plan.sourceID))
            if let externalID = planned.externalID {
                addedExternalIDs.insert(externalID)
                result.added += 1
            } else {
                result.openingBalances += 1
            }
        }

        if mergeDuplicates {
            // 짝이 되는 체결이 실제로 들어간 경우에만 직접 입력을 지운다.
            let merged = Set(
                plan.duplicates.filter { addedExternalIDs.contains($0.externalID) }.map(\.manualTradeID)
            )
            document.trades.removeAll { merged.contains($0.id) && !$0.isImported }
            result.merged = merged.count
        }

        if let index = document.sources.firstIndex(where: { $0.id == plan.sourceID }) {
            document.sources[index].lastSyncedAt = now
        }
        return result
    }
}
