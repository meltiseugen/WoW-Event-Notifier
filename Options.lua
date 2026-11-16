local _, addon = ...
local window

local function Label(parent, text, x, y, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    label:SetJustifyH("LEFT")
    return label
end

local function Checkbox(parent, text, x, y)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetHitRectInsets(0, -320, 0, 0)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.label:SetPoint("LEFT", button, "RIGHT", 0, 0)
    button.label:SetText(text)
    return button
end

local function EarlyControls(parent, event, y)
    local early = Checkbox(parent, "Enable early reminder", 28, y - 44)
    early:SetSize(24, 24)
    early:SetHitRectInsets(0, -158, 0, 0)
    early.label:SetFontObject(GameFontHighlightSmall)
    early:SetScript("OnClick", function(button)
        addon.db.earlyReminders[event.key].enabled = button:GetChecked() and true or false
        addon:UpdateOptions()
        addon:QueueRefresh()
    end)
    local minutes = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    minutes:SetSize(40, 22)
    minutes:SetPoint("TOPLEFT", 282, y - 45)
    minutes:SetAutoFocus(false)
    minutes:SetNumeric(true)
    minutes:SetMaxLetters(2)
    local function SaveMinutes(input)
        local value = addon:NormalizeEarlyMinutes(input:GetText())
        addon.db.earlyReminders[event.key].minutes = value
        input:SetText(tostring(value))
        addon:QueueRefresh()
    end
    minutes:SetScript("OnEditFocusLost", SaveMinutes)
    minutes:SetScript("OnEnterPressed", function(input)
        SaveMinutes(input)
        input:ClearFocus()
    end)
    minutes:SetScript("OnEscapePressed", function(input)
        input:SetText(tostring(addon.db.earlyReminders[event.key].minutes))
        input:ClearFocus()
    end)
    Label(parent, "min before (1-10)", 332, y - 51)
    return early, minutes
end

function addon:UpdateOptions()
    if not window or not window:IsShown() then return end
    window.enabled:SetChecked(self.db.enabled)
    for _, row in ipairs(window.rows) do
        row.check:SetChecked(self.db.selected[row.event.key])
        if row.early then
            local early = self.db.earlyReminders[row.event.key]
            row.early:SetChecked(early.enabled)
            row.early:SetEnabled(self.db.enabled and self.db.selected[row.event.key])
            row.minutes:SetEnabled(self.db.enabled and self.db.selected[row.event.key] and early.enabled)
            if not row.minutes:HasFocus() then row.minutes:SetText(tostring(early.minutes)) end
        end
        local available = false
        for _, entry in pairs(self.active or {}) do
            if entry.event.key == row.event.key then
                available = true
                break
            end
        end
        row.status:SetText(available and "|cff66dd88Available|r" or "")
    end
end

function addon:ToggleOptions()
    if window then
        window:SetShown(not window:IsShown())
        if window:IsShown() then
            self:QueueRefresh(true)
            self:UpdateOptions()
        end
        return
    end

    window = CreateFrame("Frame", "EventNotifierOptions", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(480, 550)
    window:SetPoint("CENTER")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetFrameStrata("DIALOG")
    window.TitleText:SetText("Event Notifier")
    table.insert(UISpecialFrames, "EventNotifierOptions")

    window.enabled = Checkbox(window, "Enable text alerts", 14, -34)
    window.enabled:SetScript("OnClick", function(button)
        self.db.enabled = button:GetChecked() and true or false
        self:UpdateOptions()
        self:QueueRefresh()
    end)

    window.panels, window.tabs, window.rows = {}, {}, {}
    local categories = {
        { key = "expansions", name = "Expansions" },
        { key = "holidays", name = "Holidays" },
        { key = "general", name = "General" },
    }
    local function SelectTab(key)
        for _, row in ipairs(window.rows) do
            if row.minutes and row.minutes:HasFocus() then row.minutes:ClearFocus() end
        end
        window.selectedTab = key
        for category, panel in pairs(window.panels) do
            panel:SetShown(category == key)
            window.tabs[category]:SetEnabled(category ~= key)
        end
        self:UpdateOptions()
    end
    for index, category in ipairs(categories) do
        local panel = CreateFrame("Frame", nil, window)
        panel:SetPoint("TOPLEFT", 16, -112)
        panel:SetSize(448, 350)
        window.panels[category.key] = panel
        local tab = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        tab:SetSize(140, 26)
        tab:SetPoint("TOPLEFT", 20 + (index - 1) * 146, -78)
        tab:SetText(category.name)
        tab:SetScript("OnClick", function() SelectTab(category.key) end)
        window.tabs[category.key] = tab
    end

    local midnightTab = CreateFrame("Button", nil, window.panels.expansions, "UIPanelButtonTemplate")
    midnightTab:SetSize(110, 24)
    midnightTab:SetPoint("TOPLEFT", 4, -4)
    midnightTab:SetText("Midnight")
    midnightTab:SetEnabled(false)
    local midnight = CreateFrame("Frame", nil, window.panels.expansions)
    midnight:SetPoint("TOPLEFT", 0, -40)
    midnight:SetSize(448, 310)

    local positions = { midnight = 0, general = -12 }
    for _, event in ipairs(self.events) do
        local category = event.category or "midnight"
        local parent = category == "general" and window.panels.general or midnight
        local y = positions[category]
        local check = Checkbox(parent, event.name, 0, y)
        check:SetScript("OnClick", function(button)
            self.db.selected[event.key] = button:GetChecked() and true or false
            self:UpdateOptions()
            self:QueueRefresh()
        end)
        check:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(event.name)
            GameTooltip:AddLine(event.description, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local status = Label(parent, "", 352, y - 10)
        local note = Label(parent, event.timing, 34, y - 30)
        note:SetWidth(404)
        note:SetTextColor(0.65, 0.65, 0.65)
        local row = { event = event, check = check, status = status }
        if event.earlyReminder then
            row.early, row.minutes = EarlyControls(parent, event, y)
        end
        window.rows[#window.rows + 1] = row
        positions[category] = y - (event.earlyReminder and 80 or 44)
    end

    Label(window.panels.general, "Notification position", 4, -92, "GameFontNormal")
    local move = CreateFrame("Button", nil, window.panels.general, "UIPanelButtonTemplate")
    move:SetSize(160, 26)
    move:SetPoint("TOPLEFT", 4, -116)
    move:SetText("Move Notifications")
    move:SetScript("OnClick", function() self:ToggleNotificationMove() end)
    local resetPosition = CreateFrame("Button", nil, window.panels.general, "UIPanelButtonTemplate")
    resetPosition:SetSize(130, 26)
    resetPosition:SetPoint("LEFT", move, "RIGHT", 10, 0)
    resetPosition:SetText("Reset Position")
    resetPosition:SetScript("OnClick", function() self:ResetNotificationPosition() end)
    local positionHint = Label(window.panels.general, "Drag the preview window, then click Done. Your position is saved.", 4, -154)
    positionHint:SetWidth(420)

    local test = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    test:SetSize(120, 26)
    test:SetPoint("BOTTOMLEFT", 20, 20)
    test:SetText("Test Alert")
    test:SetScript("OnClick", function() self:TestAlert() end)
    local refresh = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    refresh:SetSize(100, 26)
    refresh:SetPoint("LEFT", test, "RIGHT", 10, 0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function() self:QueueRefresh(true) end)
    Label(window, "Selections save automatically. Press Enter to save minutes.", 20, -478)
    SelectTab("expansions")
    self:QueueRefresh(true)
end

function addon:ShowOptions()
    if not window or not window:IsShown() then self:ToggleOptions() end
end
