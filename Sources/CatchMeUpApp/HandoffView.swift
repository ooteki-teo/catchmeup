import SwiftUI
import CatchMeUpCore

struct HandoffView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var context = ""
    @State private var topic = ""
    @State private var layout: CollectionLayout = .list
    @State private var showingHistory = false
    @State private var armedID: String?

    private var handoffItems: [Item] { store.handoffItems }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls

                if let handoff = store.handoff { resultCard(handoff) }

                HStack {
                    Text(L.t("交接素材")).font(.headline)
                    Text("\(handoffItems.count)").font(.body).foregroundStyle(.secondary)
                    Spacer()
                    ViewModeToggle(mode: $layout)
                }

                if handoffItems.isEmpty {
                    EmptyState(icon: "arrow.left.arrow.right", title: L.t("还没有交接素材"),
                               subtitle: L.t("把项目、目录或工作小结用「交接」模式整理，就会出现在这里"))
                        .frame(height: 200)
                } else if layout == .cards {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(handoffItems) { item in
                            block(item)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(handoffItems) { item in
                            block(item)
                        }
                    }
                }

                historySection
            }
            .padding(24)
        }
    }

    private func block(_ item: Item) -> some View {
        ItemBlockView(item: item,
                      tasks: store.tasks(for: item.id),
                      handoff: item.handoff,
                      style: layout,
                      onOpen: { openWindow(id: "item-detail", value: item.id) },
                      onToggleTask: { task in
                          Task { task.status == .done ? await store.reopen(task) : await store.complete(task) }
                      },
                      canRefreshHandoff: true,
                      isRefreshArmed: armedID == item.id,
                      onRefreshTap: { armedID = item.id },
                      onRefreshConfirm: {
                          armedID = nil
                          Task { await store.refreshHandoff(item) }
                      },
                      onRefreshCancel: { armedID = nil })
    }

    private var controls: some View {
        Card(title: L.t("操作")) {
            HStack(spacing: 10) {
                Button {
                    Task { await store.generateHandoff(extraContext: contextOrNil) }
                } label: { Label(L.t("生成交接摘要"), systemImage: "wand.and.stars") }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await store.startSession(topic: topicOrNil, extraContext: contextOrNil) }
                } label: { Label(L.t("开启新 Session"), systemImage: "play.circle") }

                Button {
                    Task { await store.endSession(extraContext: contextOrNil) }
                } label: { Label(L.t("结束当前 Session"), systemImage: "stop.circle") }
                .disabled(store.activeSession == nil)

                Spacer()
            }
            .buttonStyle(.bordered)

            if let session = store.activeSession {
                Text("当前 Session：\(session.topic ?? L.t("未命名")) · 开始于 \(Fmt.full.string(from: session.startedAt))")
                    .font(.body).foregroundStyle(.secondary)
            }

            TextField(L.t("Session 主题（可选）"), text: $topic)
                .textFieldStyle(.roundedBorder)
            TextField(L.t("补充上下文（最近重点 / 卡点 / 背景，可选）"), text: $context, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }

    private func resultCard(_ handoff: HandoffResult) -> some View {
        Card(title: L.t("最新交接摘要")) {
            if !handoff.goals.isEmpty {
                labeledList(L.t("目标"), handoff.goals)
            }
            if !handoff.logic.isEmpty {
                Text(L.t("整体逻辑")).font(.subheadline.weight(.semibold))
                Text(handoff.logic).font(.body).textSelection(.enabled)
            }
            if !handoff.progressSummary.isEmpty {
                Text(L.t("进展")).font(.subheadline.weight(.semibold))
                Text(handoff.progressSummary).font(.body).textSelection(.enabled)
            }
            if !handoff.nextSteps.isEmpty {
                labeledList(L.t("下一步"), handoff.nextSteps)
            }
            if !handoff.risks.isEmpty {
                Text(L.t("风险 / 未决问题")).font(.subheadline.weight(.semibold))
                ForEach(handoff.risks, id: \.self) { risk in
                    Label(risk, systemImage: "exclamationmark.triangle").font(.body).foregroundStyle(.orange)
                }
            }
            HStack {
                Spacer()
                Button { copyHandoff(handoff) } label: { Label(L.t("复制为 Markdown"), systemImage: "doc.on.doc") }
            }
        }
    }

    private func labeledList(_ label: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
            ForEach(Array(items.enumerated()), id: \.offset) { idx, value in
                Text("\(idx + 1). \(value)").font(.body)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !store.sessions.isEmpty {
            DisclosureGroup(L.f("历史 Session（%d）", store.sessions.count), isExpanded: $showingHistory) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.sessions) { session in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(session.topic ?? L.t("未命名")).font(.body.weight(.medium))
                                StatusPill(status: session.status == .active ? .in_progress : .done)
                                Spacer()
                                Text(Fmt.full.string(from: session.startedAt))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let summary = session.summary, !summary.isEmpty {
                                Text(summary).font(.body).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        if session.id != store.sessions.last?.id { Divider() }
                    }
                }
                .padding(.top, 6)
            }
            .font(.headline)
        }
    }

    private var contextOrNil: String? {
        context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : context
    }
    private var topicOrNil: String? {
        topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : topic
    }

    private func copyHandoff(_ handoff: HandoffResult) {
        var md = "# 任务交接\n\n"
        if !handoff.goals.isEmpty {
            md += "## 目标\n"
            for goal in handoff.goals { md += "- \(goal)\n" }
            md += "\n"
        }
        if !handoff.logic.isEmpty { md += "## 整体逻辑\n\(handoff.logic)\n\n" }
        md += "## 进展\n\(handoff.progressSummary)\n\n## 下一步\n"
        for (i, step) in handoff.nextSteps.enumerated() { md += "\(i + 1). \(step)\n" }
        if !handoff.risks.isEmpty {
            md += "\n## 风险 / 未决\n"
            for risk in handoff.risks { md += "- \(risk)\n" }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        store.setStatus(L.t("交接摘要已复制到剪贴板"))
    }
}
