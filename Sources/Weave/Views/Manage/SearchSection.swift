import SwiftUI
import WeaveCore

/// 검색바 + 라이브서치 결과 리스트. 관리 화면과 온보딩이 공유한다.
struct SearchSection: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 14)
                .padding(.top, 6)

            if model.isAtAssetLimit {
                Text(model.t("Asset limit reached (30). Remove one to add more."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.redText)
                    .padding(.top, 8)
            }

            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 20)
            } else if !model.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.searchResults) { result in
                            SearchResultRow(result: result)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .padding(.top, 4)
            } else if model.searchQuery.trimmingCharacters(in: .whitespaces).count >= 2 {
                Text(model.t("No results"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)
                    .padding(.top, 24)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text2)
            TextField(model.t("Search BTC, 삼성전자, AAPL…"), text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
            if !model.searchQuery.isEmpty {
                Button {
                    model.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.panelStroke, lineWidth: 1))
    }
}

struct SearchResultRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel
    let result: SearchResult
    @State private var isAdding = false

    var body: some View {
        Button {
            guard !isAdding else { return }
            isAdding = true
            Task {
                await model.addAsset(from: result)
                isAdding = false
            }
        } label: {
            HStack(spacing: 10) {
                logo
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(result.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text2)
                }
                Spacer(minLength: 8)
                MarketBadgeChip(market: result.market)
                if isAdding {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.link)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .disabled(model.isAtAssetLimit)
        .opacity(model.isAtAssetLimit ? 0.45 : 1)
    }

    private var logo: some View {
        Group {
            if result.market == .crypto,
               let url = URL(
                   string: "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@master/128/color/\(result.symbol.lowercased()).png"
               ) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(2)
                    } else {
                        initialBadge
                    }
                }
            } else {
                initialBadge
            }
        }
        .frame(width: 28, height: 28)
        .background(theme.iconBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var initialBadge: some View {
        Text(String(result.name.prefix(1)).uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(theme.text2)
    }
}
