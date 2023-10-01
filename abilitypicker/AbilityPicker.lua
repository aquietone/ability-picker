--[[
    AbilityPicker provides a UI for selecting abilities, such as for configuring
    what abilities to use in some automation script.

    Usage:
    -- Somewhere in main script execution:
    local AbilityPicker = require('AbilityPicker')
    AbilityPicker.InitializeAbilities()

    -- Somewhere during ImGui callback execution:
    AbilityPicker.DrawAbilityPicker()

    -- Somewhere in main script execution:
    if AbilityPicker.Selected then
        -- Process the item which was selected by the picker
        printf('Selected %s: %s', Selected.Type, Selected.Name)
        AbilityPicker.ClearSelection()
    end

    When an ability is selected, AbilityPicker.Selected will contain the following values:
    - Type = 'Spell'
        - Name, RankName, Level
    - Type = 'Disc'
        - Name, RankName, Level
    - Type = 'AA'
        - Name
    - Type = 'Item'
        - Name, SpellName
    - Type = 'Ability'
        - Name
]]

---@type Mq
local mq = require('mq')
---@type ImGui
require('ImGui')

local AbilityPicker = {
    Open = false,
    Draw = false,
    Spells = {Categories={}},
    AltAbilities = {Types={}},
    CombatAbilities = {Categories={}},
    Abilities = {},
    Items = {},
    Selected = nil,
}

local aaTypes = {'General','Archtype','Class','Special'}

local function SortMap(map)
    -- sort categories and subcategories alphabetically, abilities by level
    table.sort(map.Categories)
    for category,subCategories in pairs(map) do
        if category ~= 'Categories' then
            table.sort(map[category].SubCategories)
            for subCategory,subCategorySpells in pairs(subCategories) do
                if subCategory ~= 'SubCategories' then
                    table.sort(subCategorySpells, function(a, b) return a.Level > b.Level end)
                end
            end
        end
    end
end

local function AddSpellToMap(spell)
    local category = spell.Category()
    local subCategory = spell.Subcategory()
    if not AbilityPicker.Spells[category] then
        AbilityPicker.Spells[category] = {SubCategories={}}
        table.insert(AbilityPicker.Spells.Categories, category)
    end
    if not AbilityPicker.Spells[category][subCategory] then
        AbilityPicker.Spells[category][subCategory] = {}
        table.insert(AbilityPicker.Spells[category].SubCategories, subCategory)
    end
    local name = spell.Name():gsub(' Rk%..*', '')
    table.insert(AbilityPicker.Spells[category][subCategory], {Level=spell.Level(), Name=name, RankName=spell.Name()})
end

local function InitSpellTree()
    -- Build spell tree for picking spells
    for spellIter=1,1120 do
        local spell = mq.TLO.Me.Book(spellIter)
        if spell() then
            AddSpellToMap(spell)
        end
    end
    SortMap(AbilityPicker.Spells)
end

local function AddAAToMap(aa)
    local type = aaTypes[aa.Type()]
    if not AbilityPicker.AltAbilities[type] then
        AbilityPicker.AltAbilities[type] = {}
        table.insert(AbilityPicker.AltAbilities.Types, type)
    end
    table.insert(AbilityPicker.AltAbilities[type], {Name=aa.Name()})
end

local function InitAATree()
    if not mq.TLO.Window("AAWindow")() then return 0 end

    local sections = {
        {Page = "AAW_GeneralPage", List = "AAW_GeneralList"},
        {Page = "AAW_ArchetypePage", List = "AAW_ArchList"},
        {Page = "AAW_ClassPage", List = "AAW_ClassList"},
        {Page = "AAW_SpecialPage", List = "AAW_SpecialList"},
    }

    for _, section in pairs(sections) do
        local control = mq.TLO.Window("AAWindow").Child("AAW_Subwindows").Child(section.Page).Child(section.List)
        local rows = control.Items()
        for i = 0, rows do
            local aaName = control.List(i)
            local aa = mq.TLO.Me.AltAbility(aaName)
            if aa() and aa.Spell() then AddAAToMap(aa) end
        end
    end

    for _, type in ipairs(aaTypes) do
        if AbilityPicker.AltAbilities[type] then
            table.sort(AbilityPicker.AltAbilities[type], function(a, b) return a.Name < b.Name end)
        end
    end
end

local function AddDiscToMap(disc)
    local category = disc.Category()
    local subCategory = disc.Subcategory()
    if not AbilityPicker.CombatAbilities[category] then
        AbilityPicker.CombatAbilities[category] = {SubCategories={}}
        table.insert(AbilityPicker.CombatAbilities.Categories, category)
    end
    if not AbilityPicker.CombatAbilities[category][subCategory] then
        AbilityPicker.CombatAbilities[category][subCategory] = {}
        table.insert(AbilityPicker.CombatAbilities[category].SubCategories, subCategory)
    end
    local name = disc.Name():gsub(' Rk%..*', '')
    table.insert(AbilityPicker.CombatAbilities[category][subCategory], {Level=disc.Level(), Name=name, RankName=disc.Name()})
end

local function InitDiscTree()
    local discIter = 1
    repeat
        local disc = mq.TLO.Me.CombatAbility(discIter)
        if disc() then
            AddDiscToMap(disc)
        end
        discIter = discIter + 1
    until mq.TLO.Me.CombatAbility(discIter)() == nil
    SortMap(AbilityPicker.CombatAbilities)
end

local function InitAbilityTree()
    for i=0,100 do
        local ability = mq.TLO.Me.Ability(i)
        if ability() then
            table.insert(AbilityPicker.Abilities, ability())
        end
    end
    table.sort(AbilityPicker.Abilities)
end

local function InitItems()
    for i=0,32 do
        local item = mq.TLO.Me.Inventory(i)
        if item.Container() > 0 then
            for j=1,item.Container() do
                local bagItem = item.Item(j)
                if bagItem() and bagItem.Spell() then
                    table.insert(AbilityPicker.Items, {Name=bagItem.Name(), SpellName=bagItem.Clicky()})
                end
            end
        else
            if item() and item.Clicky() then
                table.insert(AbilityPicker.Items, {Name=item.Name(), SpellName=item.Clicky()})
            end
        end
    end
    table.sort(AbilityPicker.Items, function(a, b) return a.Name < b.Name end)
end

function AbilityPicker.InitializeAbilities()
    InitSpellTree()
    InitAATree()
    InitDiscTree()
    InitAbilityTree()
    InitItems()
end

local function SelectAbility(type, name, rankName, level)
    AbilityPicker.Selected = {Type=type, Name=name, RankName=rankName, Level=level}
    AbilityPicker.Open = false
    AbilityPicker.Draw = false
end

local function DrawCatSubCatTree(table, type)
    for _,category in ipairs(table.Categories) do
        if ImGui.TreeNode(category) then
            local abilityCategory = table[category]
            for _,subCategory in ipairs(abilityCategory.SubCategories) do
                if ImGui.TreeNode(subCategory) then
                    local abilitySubCategory = abilityCategory[subCategory]
                    for _,ability in ipairs(abilitySubCategory) do
                        if ImGui.Selectable(string.format('%s - %s', ability.Level, ability.Name), false) then
                            SelectAbility(type, ability.Name, ability.RankName, ability.Level)
                        end
                    end
                    ImGui.TreePop()
                end
            end
            ImGui.TreePop()
        end
    end
end

local function DrawSpellTree()
    if ImGui.TreeNode('Spells') then
        DrawCatSubCatTree(AbilityPicker.Spells, 'Spell')
        ImGui.TreePop()
    end
end

local function DrawAATree()
    if ImGui.TreeNode('Alternate Abilities') then
        for _,type in ipairs(AbilityPicker.AltAbilities.Types) do
            if ImGui.TreeNode(type) then
                for _,altAbility in ipairs(AbilityPicker.AltAbilities[type]) do
                    if ImGui.Selectable(altAbility.Name, false) then
                        SelectAbility('AA', altAbility.Name)
                    end
                end
                ImGui.TreePop()
            end
        end
        ImGui.TreePop()
    end
end

local function DrawDiscTree()
    if ImGui.TreeNode('Combat Disciplines') then
        DrawCatSubCatTree(AbilityPicker.CombatAbilities, 'Disc')
        ImGui.TreePop()
    end
end

local function DrawItemTree()
    if ImGui.TreeNode('Items') then
        for _,item in ipairs(AbilityPicker.Items) do
            if ImGui.Selectable(string.format('%s - %s', item.Name, item.SpellName), false) then
                SelectAbility('Item', item.Name)
            end
        end
        ImGui.TreePop()
    end
end

local function DrawAbilityTree()
    if ImGui.TreeNode('Abilities') then
        for _,ability in ipairs(AbilityPicker.Abilities) do
            if ImGui.Selectable(ability, false) then
                SelectAbility('Ability', ability)
            end
        end
        ImGui.TreePop()
    end
end

function AbilityPicker.DrawAbilityPicker()
    if not AbilityPicker.Open then return end
    AbilityPicker.Open, AbilityPicker.Draw = ImGui.Begin('Ability Picker', AbilityPicker.Open)
    if AbilityPicker.Draw then
        DrawSpellTree()
        ImGui.Separator()
        DrawAATree()
        ImGui.Separator()
        DrawDiscTree()
        ImGui.Separator()
        DrawItemTree()
        ImGui.Separator()
        DrawAbilityTree()
    end
    ImGui.End()
end

function AbilityPicker.ClearSelection()
    AbilityPicker.Selected = nil
end

return AbilityPicker