-- Sample script using AbilityPicker.lua
--- @type Mq
local mq = require('mq')
--- @type ImGui
require('ImGui')
local AbilityPicker = require('AbilityPicker')

local terminate = false
local isOpen, shouldDraw = true, true

local picker = AbilityPicker.new({'Item'})

local function updateImGui()
    if not isOpen then return end

    isOpen, shouldDraw = ImGui.Begin('AbilityPickerSample', isOpen)
    if shouldDraw then
        if ImGui.Button('Open AbilityPicker') then
            picker:SetOpen()
        end
        if picker.Selected then
            local selected = picker.Selected or {}
            if selected.Type == 'Spell' or selected.Type == 'Disc' then
                ImGui.Text('Selected %s:\nID=%s\nName=%s\nRankName=%s\nLevel=%s', selected.Type, selected.ID, selected.Name, selected.RankName, selected.Level)
            elseif selected.Type == 'Item' then
                ImGui.Text('Selected %s:\nID=%s\nName=%s\nSpellName=%s', selected.Type, selected.ID, selected.Name, selected.SpellName)
            elseif selected.Type == 'AA' or selected.Type == 'Ability' then
                ImGui.Text('Selected %s:\nID=%s\n%s', selected.Type, selected.ID, selected.Name)
            end
        end
        if picker.Selected and ImGui.Button('Clear Selection') then
            picker:ClearSelection()
        end
    end
    ImGui.End()
    picker:DrawAbilityPicker()
end

picker:InitializeAbilities()

mq.imgui.init('AbilityPickerSample', updateImGui)

while not terminate do
    mq.delay(1000)
    picker:Reload()
end