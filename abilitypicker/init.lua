-- Sample script using AbilityPicker.lua
--- @type Mq
local mq = require('mq')
--- @type ImGui
require('ImGui')
local AbilityPicker = require('AbilityPicker')

local terminate = false
local isOpen, shouldDraw = true, true

local function updateImGui()
    if not isOpen then return end

    isOpen, shouldDraw = ImGui.Begin('AbilityPickerSample', isOpen)
    if shouldDraw then
        if ImGui.Button('Open AbilityPicker') then
            AbilityPicker.Open, AbilityPicker.Draw = true, true
        end
        if AbilityPicker.Selected then
            local selected = AbilityPicker.Selected or {}
            if selected.Type == 'Spell' or selected.Type == 'Disc' then
                ImGui.Text('Selected %s:\nID=%s\nName=%s\nRankName=%s\nLevel=%s', selected.Type, selected.ID, selected.Name, selected.RankName, selected.Level)
            elseif selected.Type == 'Item' then
                ImGui.Text('Selected %s:\nID=%s\nName=%s\nSpellName=%s', selected.Type, selected.ID, selected.Name, selected.SpellName)
            elseif selected.Type == 'AA' or selected.Type == 'Ability' then
                ImGui.Text('Selected %s:\nID=%s\n%s', selected.Type, selected.ID, selected.Name)
            end
        end
        if AbilityPicker.Selected and ImGui.Button('Clear Selection') then
            AbilityPicker.ClearSelection()
        end
    end
    ImGui.End()
    AbilityPicker.DrawAbilityPicker()
end

AbilityPicker.InitializeAbilities()

mq.imgui.init('AbilityPickerSample', updateImGui)

while not terminate do
    mq.delay(1000)
end