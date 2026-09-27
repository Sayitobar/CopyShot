//
//  QuickActionsSettingsView.swift
//  CopyShot
//
//  Created by Mac on 26.09.26.
//

import SwiftUI
import AppKit

/// Calculates continuous non-mutating drag displacement offset for rows in reorderable lists.
private func calculateDragOffset(index: Int, isDragging: Bool, dragStart: Int?, dragTarget: Int?, translation: CGFloat, rowHeight: CGFloat) -> CGFloat {
    guard let dragStart = dragStart, let dragTarget = dragTarget else { return 0 }
    if isDragging { return translation }
    if dragStart < dragTarget {
        if index > dragStart && index <= dragTarget { return -rowHeight }
    } else if dragStart > dragTarget {
        if index >= dragTarget && index < dragStart { return rowHeight }
    }
    return 0
}

/// Settings pane for configuring Quick Action ordering, visibility, action-specific parameters, and custom actions.
struct QuickActionsSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var expandedActionId: String? = nil
    @State private var showingCustomActionTemplate: Bool = false
    @State private var customActionName: String = "Format JSON"
    @State private var customActionType: String = "Shell Script"
    @State private var showingResetConfirmation: Bool = false
    
    // Direct manipulation drag states
    @State private var draggingActionId: String? = nil
    @State private var dragStartIndex: Int? = nil
    @State private var dragTargetIndex: Int? = nil
    @State private var dragTranslation: CGFloat = 0
    
    private var metadataMap: [String: ActionMetadata] {
        Dictionary(uniqueKeysWithValues: ActionMetadata.allActions.map { ($0.id, $0) })
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Master Enable Row
            SettingsRow(
                label: "Quick Actions",
                tooltip: "Show expandable action bars next to the notification HUD to format, search, or translate recognized text.",
                zIndexValue: 12
            ) {
                Toggle("", isOn: $settings.quickActionsConfig.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .accessibilityIdentifier("settings-quick-actions-master")
            
            if settings.quickActionsConfig.isEnabled {
                // MARK: - Ergonomics & Preferences (Directly under Quick Actions)
                SettingsRow(
                    label: "Numeric Badges",
                    tooltip: "Display 1-9 monospaced number badges on action pills for instant keyboard activation.",
                    zIndexValue: 11
                ) {
                    Toggle("", isOn: $settings.quickActionsConfig.showNumericShortcuts)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                SettingsRow(
                    label: "Tactile Haptics",
                    tooltip: "Perform a tactile trackpad feedback click whenever hovering over action pills.",
                    zIndexValue: 10
                ) {
                    Toggle("", isOn: $settings.quickActionsConfig.playHapticsOnHover)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                // MARK: - Action Shelf Order & Visibility List
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built-in Actions")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                    
                    let activeOrder = settings.quickActionsConfig.actionOrder.filter { metadataMap[$0] != nil }
                    let rowHeight: CGFloat = 38
                    
                    VStack(spacing: 0) {
                        ForEach(Array(activeOrder.enumerated()), id: \.element) { index, actionId in
                            if let metadata = metadataMap[actionId] {
                                let isEnabled = !settings.quickActionsConfig.disabledActionIds.contains(actionId)
                                let isExpanded = expandedActionId == actionId
                                let isLast = index == activeOrder.count - 1
                                let isDragging = draggingActionId == actionId
                                let rowOffset = calculateDragOffset(
                                    index: index,
                                    isDragging: isDragging,
                                    dragStart: dragStartIndex,
                                    dragTarget: dragTargetIndex,
                                    translation: dragTranslation,
                                    rowHeight: rowHeight
                                )
                                
                                ActionRowView(
                                    metadata: metadata,
                                    isEnabled: isEnabled,
                                    isExpanded: isExpanded,
                                    isDragging: isDragging,
                                    onToggle: { toggleAction(id: actionId) },
                                    onExpand: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedActionId = isExpanded ? nil : actionId
                                        }
                                    },
                                    onDragChanged: { translation in
                                        handleMainDragChanged(actionId: actionId, translation: translation, activeOrder: activeOrder)
                                    },
                                    onDragEnded: {
                                        handleMainDragEnded(activeOrder: activeOrder)
                                    }
                                )
                                .offset(y: rowOffset)
                                .animation(isDragging ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: rowOffset)
                                .scaleEffect(isDragging ? 1.015 : 1.0)
                                .shadow(color: isDragging ? Color.black.opacity(0.18) : .clear, radius: 8, x: 0, y: 3)
                                .zIndex(isDragging ? 100 : 2)
                                
                                // Narrower Inset Configuration Drawer: Left edge at Action Icon (36), Right edge at Collapse Button (46)
                                if isExpanded && isEnabled && (metadata.hasParameters || metadata.hasSubActions) {
                                    VStack(spacing: 0) {
                                        HStack(spacing: 0) {
                                            Color.clear.frame(width: 36, height: 1)
                                            
                                            ActionDrawerDetailView(actionId: actionId)
                                                .padding(10)
                                                .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
                                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
                                                )
                                            
                                            Color.clear.frame(width: 46, height: 1)
                                        }
                                        .padding(.top, 6)
                                        .padding(.bottom, 8)
                                    }
                                    .clipped()
                                    .zIndex(1)
                                    .transition(.opacity)
                                }
                                
                                if !isLast {
                                    Divider()
                                        .opacity(0.35)
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                    )
                }
                
                // MARK: - Custom Actions Template Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Actions")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            // Alignment Spacer matching grip handle width (18pt)
                            Color.clear
                                .frame(width: 18, height: 26)
                            
                            // Action Icon Badge
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.purple.opacity(0.14))
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: "plus.circle.dashed")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.purple)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create Custom Action")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                
                                Text("Execute bespoke Shell commands or AppleScript on captured text.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Configure Button with continuous rounded rect matching ActionRowView
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingCustomActionTemplate.toggle()
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .rotationEffect(.degrees(showingCustomActionTemplate ? 180 : 0))
                                    .foregroundStyle(showingCustomActionTemplate ? .blue : .secondary)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(showingCustomActionTemplate ? Color.blue.opacity(0.15) : Color.primary.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(showingCustomActionTemplate ? Color.blue.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(showingCustomActionTemplate ? "Hide Template" : "Configure Custom Action")
                            
                            // Alignment Spacer matching mini toggle width (28pt)
                            Color.clear
                                .frame(width: 28, height: 22)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor))
                        .zIndex(2)
                        
                        // Narrower Inset Custom Action Drawer: Left edge at 36, Right edge at 46
                        if showingCustomActionTemplate {
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                Color.clear.frame(width: 36, height: 1)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Action Name")
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            TextField("Format JSON", text: $customActionName)
                                                .textFieldStyle(.roundedBorder)
                                                .controlSize(.small)
                                        }
                                        .frame(maxWidth: .infinity)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Engine")
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            Picker("", selection: $customActionType) {
                                                Text("Shell (zsh)").tag("Shell Script")
                                                Text("AppleScript").tag("AppleScript")
                                                Text("URL Scheme").tag("URL Scheme")
                                            }
                                            .labelsHidden()
                                            .controlSize(.small)
                                            .frame(width: 130)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Script Template (Passed as $1 / STDIN)")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        Text("echo \"$1\" | jq .")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                            .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    
                                    HStack {
                                        HStack(spacing: 5) {
                                            Image(systemName: "info.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.orange)
                                            Text("Custom Action Engine coming in v1.3 • Template Preview")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button("Save Action") {}
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            .disabled(true)
                                    }
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
                                )
                                
                                Color.clear.frame(width: 46, height: 1)
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 8)
                        }
                        .clipped()
                        .zIndex(1)
                        .transition(.opacity)
                    }
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                    )
                }
                
                // MARK: - Reset to Defaults
                HStack {
                    Spacer()
                    Button("Reset Quick Actions to Defaults") {
                        showingResetConfirmation = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
                    .alert("Reset Quick Actions to Defaults?", isPresented: $showingResetConfirmation) {
                        Button("Reset", role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                settings.resetQuickActionsToDefaults()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will restore default action ordering, enable all built-in actions, and revert search engine and language preferences.")
                    }
                }
            }
        }
    }
    
    // MARK: - Mutation & Drag Helpers
    
    private func toggleAction(id: String) {
        var disabled = Set(settings.quickActionsConfig.disabledActionIds)
        if disabled.contains(id) {
            disabled.remove(id)
        } else {
            disabled.insert(id)
            if expandedActionId == id {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25)) {
                    expandedActionId = nil
                }
            }
        }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25)) {
            settings.quickActionsConfig.disabledActionIds = Array(disabled)
        }
    }
    
    private func handleMainDragChanged(actionId: String, translation: CGFloat, activeOrder: [String]) {
        if draggingActionId == nil {
            draggingActionId = actionId
            dragStartIndex = activeOrder.firstIndex(of: actionId)
            dragTargetIndex = dragStartIndex
            if expandedActionId != nil {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2)) {
                    expandedActionId = nil
                }
            }
        }
        guard let startIdx = dragStartIndex else { return }
        let rowHeight: CGFloat = 38
        let slotDelta = Int(round(translation / rowHeight))
        let newTargetIndex = max(0, min(activeOrder.count - 1, startIdx + slotDelta))
        
        if newTargetIndex != dragTargetIndex {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            dragTargetIndex = newTargetIndex
        }
        dragTranslation = translation
    }
    
    private func handleMainDragEnded(activeOrder: [String]) {
        guard let startIdx = dragStartIndex, let targetIdx = dragTargetIndex, let actionId = draggingActionId else {
            draggingActionId = nil
            dragStartIndex = nil
            dragTargetIndex = nil
            dragTranslation = 0
            return
        }
        
        if startIdx != targetIdx {
            var order = settings.quickActionsConfig.actionOrder
            if let fromIdx = order.firstIndex(of: actionId),
               let toAction = activeOrder[targetIdx] as String?,
               let toIdx = order.firstIndex(of: toAction) {
                order.remove(at: fromIdx)
                order.insert(actionId, at: toIdx)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    settings.quickActionsConfig.actionOrder = order
                }
            }
        }
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            dragTranslation = 0
            dragStartIndex = nil
            dragTargetIndex = nil
            draggingActionId = nil
        }
    }
}

// MARK: - Action Row View

private struct ActionRowView: View {
    let metadata: ActionMetadata
    let isEnabled: Bool
    let isExpanded: Bool
    let isDragging: Bool
    let onToggle: () -> Void
    let onExpand: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Drag Grip Handle with global coordinate space to eliminate feedback loops
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isDragging ? Color.primary : Color.secondary.opacity(0.45))
                .frame(width: 18, height: 26)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            onDragChanged(value.translation.height)
                        }
                        .onEnded { _ in
                            onDragEnded()
                        }
                )
            
            // Action Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isEnabled ? 0.08 : 0.04))
                    .frame(width: 24, height: 24)
                
                ActionIconView(
                    icon: metadata.icon,
                    size: 14,
                    isHovered: isEnabled,
                    accentColor: .primary
                )
            }
            
            // Title Only (No explanation in non-extended form)
            Text(metadata.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isEnabled ? .primary : .secondary)
            
            Spacer()
            
            // Configure Icon Button (Dropdown chevron) with continuous rounded rect hit area
            if metadata.hasParameters || metadata.hasSubActions {
                Button(action: onExpand) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(isExpanded ? .blue : (isEnabled ? .secondary : .secondary.opacity(0.35)))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isExpanded ? Color.blue.opacity(0.15) : (isEnabled ? Color.primary.opacity(0.06) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(isExpanded ? Color.blue.opacity(0.3) : (isEnabled ? Color.secondary.opacity(0.2) : Color.clear), lineWidth: 0.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .help(isExpanded ? "Hide Settings" : "Configure Action")
            }
            
            // Enable Toggle Switch
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isDragging ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
    }
}

// MARK: - Action Drawer Detail View

private struct ActionDrawerDetailView: View {
    let actionId: String
    @EnvironmentObject var settings: SettingsManager
    
    // Direct manipulation drag states for sub-actions
    @State private var draggingSubActionId: String? = nil
    @State private var dragSubStartIndex: Int? = nil
    @State private var dragSubTargetIndex: Int? = nil
    @State private var dragSubTranslation: CGFloat = 0
    @State private var hoveredTrashSubId: String? = nil
    
    private var availableLanguagesToAdd: [TranslationTargetLanguage] {
        let defaultOrder = ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
        let currentOrder = settings.quickActionsConfig.subActionOrder["translate"] ?? defaultOrder
        let currentCodes = Set(currentOrder.map { $0.replacingOccurrences(of: "translate_to_", with: "") })
        let defaultCode = settings.quickActionsConfig.defaultTranslateLanguage
        return TranslationTargetLanguage.supportedLanguages.filter {
            !currentCodes.contains($0.code) && $0.code != defaultCode
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Action Specific Parameters
            if actionId == "search_web" {
                HStack(spacing: 8) {
                    Text("Search Engine:")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Picker("", selection: $settings.quickActionsConfig.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 130)
                }
            } else if actionId == "translate" {
                HStack(spacing: 8) {
                    Text("Default Language:")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Picker("", selection: $settings.quickActionsConfig.defaultTranslateLanguage) {
                        ForEach(TranslationTargetLanguage.supportedLanguages) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150)
                }
            }
            
            // Sub-actions Ordering List (Change Case transforms with Checkboxes)
            if actionId == "change_case" {
                let subActionList = ActionMetadata.caseSubActionsMetadata
                let subActionMap = Dictionary(uniqueKeysWithValues: subActionList.map { ($0.id, $0) })
                let currentOrder = (settings.quickActionsConfig.subActionOrder[actionId] ?? subActionList.map { $0.id })
                    .filter { subActionMap[$0] != nil }
                let disabledSubIds = Set(settings.quickActionsConfig.disabledSubActionIds[actionId] ?? [])
                let rowHeight: CGFloat = 28
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sub-Shelf Transforms")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    VStack(spacing: 0) {
                        ForEach(Array(currentOrder.enumerated()), id: \.element) { index, subId in
                            if let subMetadata = subActionMap[subId] {
                                let isEnabled = !disabledSubIds.contains(subId)
                                let isLast = index == currentOrder.count - 1
                                let isDragging = draggingSubActionId == subId
                                let subRowOffset = calculateDragOffset(
                                    index: index,
                                    isDragging: isDragging,
                                    dragStart: dragSubStartIndex,
                                    dragTarget: dragSubTargetIndex,
                                    translation: dragSubTranslation,
                                    rowHeight: rowHeight
                                )
                                
                                HStack(spacing: 8) {
                                    // Grip Handle with global coordinate space
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 9))
                                        .foregroundStyle(isDragging ? Color.primary : Color.secondary.opacity(0.4))
                                        .frame(width: 16, height: 22)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                                .onChanged { value in
                                                    handleSubDragChanged(subId: subId, translation: value.translation.height, currentOrder: currentOrder)
                                                }
                                                .onEnded { _ in
                                                    handleSubDragEnded(currentOrder: currentOrder)
                                                }
                                        )
                                    
                                    ActionIconView(
                                        icon: subMetadata.icon,
                                        size: 13,
                                        isHovered: isEnabled,
                                        accentColor: .primary
                                    )
                                    .frame(width: 16)
                                    
                                    Text(subMetadata.title)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(isEnabled ? .primary : .secondary)
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: Binding(
                                        get: { isEnabled },
                                        set: { _ in toggleSubAction(parentId: actionId, subId: subId) }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .controlSize(.mini)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isDragging ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                .offset(y: subRowOffset)
                                .animation(isDragging ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: subRowOffset)
                                .scaleEffect(isDragging ? 1.015 : 1.0)
                                .shadow(color: isDragging ? Color.black.opacity(0.18) : .clear, radius: 6, x: 0, y: 2)
                                .zIndex(isDragging ? 100 : 1)
                                .contentShape(Rectangle())
                                
                                if !isLast {
                                    Divider()
                                        .opacity(0.2)
                                        .padding(.leading, 28)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            } else if actionId == "translate" {
                // Flyout Languages List with Add/Delete pattern
                let defaultTranslateOrder = ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
                let currentOrder = (settings.quickActionsConfig.subActionOrder["translate"] ?? defaultTranslateOrder)
                    .filter { $0 != "translate_to_\(settings.quickActionsConfig.defaultTranslateLanguage)" }
                let subActionMap = Dictionary(uniqueKeysWithValues: ActionMetadata.translateSubActionsMetadata.map { ($0.id, $0) })
                let rowHeight: CGFloat = 28
                
                VStack(alignment: .leading, spacing: 6) {
                    Divider().opacity(0.3)
                    
                    Text("Flyout Languages")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if currentOrder.isEmpty {
                        Text("No flyout languages. Click + Add Language below to add destinations to the sub-shelf.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(currentOrder.enumerated()), id: \.element) { index, subId in
                                let subMetadata = subActionMap[subId]
                                let isLast = index == currentOrder.count - 1
                                let isDragging = draggingSubActionId == subId
                                let subRowOffset = calculateDragOffset(
                                    index: index,
                                    isDragging: isDragging,
                                    dragStart: dragSubStartIndex,
                                    dragTarget: dragSubTargetIndex,
                                    translation: dragSubTranslation,
                                    rowHeight: rowHeight
                                )
                                
                                HStack(spacing: 8) {
                                    // Grip Handle with global coordinate space
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 9))
                                        .foregroundStyle(isDragging ? Color.primary : Color.secondary.opacity(0.4))
                                        .frame(width: 16, height: 22)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                                .onChanged { value in
                                                    handleSubDragChanged(subId: subId, translation: value.translation.height, currentOrder: currentOrder)
                                                }
                                                .onEnded { _ in
                                                    handleSubDragEnded(currentOrder: currentOrder)
                                                }
                                        )
                                    
                                    ActionIconView(
                                        icon: subMetadata?.icon ?? .system("globe"),
                                        size: 13,
                                        isHovered: true,
                                        accentColor: .primary
                                    )
                                    .frame(width: 16)
                                    
                                    Text(subMetadata?.title ?? subId)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    // Delete Button (Trash with red hover)
                                    Button {
                                        deleteFlyoutLanguage(subId: subId)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(hoveredTrashSubId == subId ? Color.red : Color.secondary.opacity(0.55))
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { isHovering in
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if isHovering {
                                                hoveredTrashSubId = subId
                                            } else if hoveredTrashSubId == subId {
                                                hoveredTrashSubId = nil
                                            }
                                        }
                                    }
                                    .help("Remove from Flyout Shelf")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isDragging ? Color(NSColor.controlBackgroundColor) : Color.clear)
                                .offset(y: subRowOffset)
                                .animation(isDragging ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: subRowOffset)
                                .scaleEffect(isDragging ? 1.015 : 1.0)
                                .shadow(color: isDragging ? Color.black.opacity(0.18) : .clear, radius: 6, x: 0, y: 2)
                                .zIndex(isDragging ? 100 : 1)
                                .contentShape(Rectangle())
                                
                                if !isLast {
                                    Divider()
                                        .opacity(0.2)
                                        .padding(.leading, 28)
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    
                    // + Add Language Menu (Centered cleanly below the languages list, without bottom-facing dropdown chevron)
                    HStack {
                        Spacer()
                        
                        Menu {
                            ForEach(availableLanguagesToAdd) { lang in
                                Button(lang.name) {
                                    addFlyoutLanguage(code: lang.code)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Add Language")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.blue.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.blue.opacity(0.25), lineWidth: 0.5)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .disabled(availableLanguagesToAdd.isEmpty)
                        
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
    
    private func addFlyoutLanguage(code: String) {
        let subId = "translate_to_\(code)"
        let defaultOrder = ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
        var order = settings.quickActionsConfig.subActionOrder["translate"] ?? defaultOrder
        if !order.contains(subId) {
            order.append(subId)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                settings.quickActionsConfig.subActionOrder["translate"] = order
            }
        }
    }
    
    private func deleteFlyoutLanguage(subId: String) {
        let defaultOrder = ["translate_to_es", "translate_to_de", "translate_to_fr", "translate_to_ja", "translate_to_zh"]
        var order = settings.quickActionsConfig.subActionOrder["translate"] ?? defaultOrder
        order.removeAll { $0 == subId }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            settings.quickActionsConfig.subActionOrder["translate"] = order
        }
    }
    
    private func toggleSubAction(parentId: String, subId: String) {
        var disabledMap = settings.quickActionsConfig.disabledSubActionIds
        var disabled = Set(disabledMap[parentId] ?? [])
        if disabled.contains(subId) {
            disabled.remove(subId)
        } else {
            disabled.insert(subId)
        }
        disabledMap[parentId] = Array(disabled)
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25)) {
            settings.quickActionsConfig.disabledSubActionIds = disabledMap
        }
    }
    
    private func handleSubDragChanged(subId: String, translation: CGFloat, currentOrder: [String]) {
        if draggingSubActionId == nil {
            draggingSubActionId = subId
            dragSubStartIndex = currentOrder.firstIndex(of: subId)
            dragSubTargetIndex = dragSubStartIndex
        }
        guard let startIdx = dragSubStartIndex else { return }
        let rowHeight: CGFloat = 28
        let slotDelta = Int(round(translation / rowHeight))
        let newTargetIndex = max(0, min(currentOrder.count - 1, startIdx + slotDelta))
        
        if newTargetIndex != dragSubTargetIndex {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            dragSubTargetIndex = newTargetIndex
        }
        dragSubTranslation = translation
    }
    
    private func handleSubDragEnded(currentOrder: [String]) {
        guard let startIdx = dragSubStartIndex, let targetIdx = dragSubTargetIndex, let subId = draggingSubActionId else {
            draggingSubActionId = nil
            dragSubStartIndex = nil
            dragSubTargetIndex = nil
            dragSubTranslation = 0
            return
        }
        
        if startIdx != targetIdx {
            var subOrder = settings.quickActionsConfig.subActionOrder[actionId] ?? currentOrder
            if let fromIdx = subOrder.firstIndex(of: subId),
               let toAction = currentOrder[targetIdx] as String?,
               let toIdx = subOrder.firstIndex(of: toAction) {
                subOrder.remove(at: fromIdx)
                subOrder.insert(subId, at: toIdx)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    settings.quickActionsConfig.subActionOrder[actionId] = subOrder
                }
            }
        }
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            dragSubTranslation = 0
            dragSubStartIndex = nil
            dragSubTargetIndex = nil
            draggingSubActionId = nil
        }
    }
}
