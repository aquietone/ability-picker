--[[
    AbilityPicker provides a UI for selecting abilities, such as for configuring
    what abilities to use in some automation script.

    Usage:
    -- Somewhere in main script execution:
    local AbilityPicker = require('AbilityPicker')
    AbilityPicker.InitializeAbilities()

    -- Somewhere during ImGui callback execution:
    if ImGui.Button('Open Ability Picker') then AbilityPicker.SetOpen() end
    AbilityPicker.DrawAbilityPicker()

    -- Somewhere in main script execution:
    if AbilityPicker.Selected then
        -- Process the item which was selected by the picker
        printf('Selected %s: %s', Selected.Type, Selected.Name)
        AbilityPicker.ClearSelection()
    end

    -- In main loop, reload abilities if selected by user
    while true do
        AbilityPicker.Reload()
    end

    When an ability is selected, AbilityPicker.Selected will contain the following values:
    - Type = 'Spell'
        - ID, Name, RankName, Level
    - Type = 'Disc'
        - ID, Name, RankName, Level
    - Type = 'AA'
        - ID, Name
    - Type = 'Item'
        - ID, Name, SpellName
    - Type = 'Ability'
        - ID, Name
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
    Filter = '',
    FilteredResults = {}
}

local animSpellIcons = mq.FindTextureAnimation('A_SpellIcons')
local animItems = mq.FindTextureAnimation('A_DragItem')

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
    table.insert(AbilityPicker.Spells[category][subCategory], {ID=spell.ID(), Level=spell.Level(), Name=name, RankName=spell.Name(), TargetType=spell.TargetType(), Icon=spell.SpellIcon()})
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
    table.insert(AbilityPicker.AltAbilities[type], {ID=aa.ID(), Name=aa.Name(), TargetType=aa.Spell.TargetType(), Icon=aa.Spell.SpellIcon()})
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
    table.insert(AbilityPicker.CombatAbilities[category][subCategory], {ID=disc.ID(), Level=disc.Level(), Name=name, RankName=disc.Name(), TargetType=disc.TargetType(), Icon=disc.SpellIcon()})
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
            table.insert(AbilityPicker.Abilities, {ID=i, Name=ability()})
        end
    end
    table.sort(AbilityPicker.Abilities, function(a, b) return a.Name < b.Name end)
end

local function InitItems()
    for i=0,32 do
        local item = mq.TLO.Me.Inventory(i)
        if item.Container() > 0 then
            for j=1,item.Container() do
                local bagItem = item.Item(j)
                if bagItem() and bagItem.Spell() then
                    table.insert(AbilityPicker.Items, {ID=bagItem.ID(), Name=bagItem.Name(), SpellName=bagItem.Clicky(), TargetType=bagItem.Clicky.Spell.TargetType(), Icon=bagItem.Icon()})
                end
            end
        else
            if item() and item.Clicky() then
                table.insert(AbilityPicker.Items, {ID=item.ID(), Name=item.Name(), SpellName=item.Clicky(), TargetType=item.Clicky.Spell.TargetType(), Icon=item.Icon()})
            end
        end
    end
    table.sort(AbilityPicker.Items, function(a, b) return a.Name < b.Name end)
end

--mq.event('NewSpellMemmed', '#*#You have finished scribing #1#.', NewSpellMemmed)
function AbilityPicker.InitializeAbilities()
    InitSpellTree()
    InitAATree()
    InitDiscTree()
    InitAbilityTree()
    InitItems()
end

function AbilityPicker.Reload()
    if AbilityPicker.ReloadAll then
        AbilityPicker.Spells = {Categories={}}
        AbilityPicker.AltAbilities = {Types={}}
        AbilityPicker.CombatAbilities = {Categories={}}
        AbilityPicker.Abilities = {}
        AbilityPicker.Items = {}
        AbilityPicker.InitializeAbilities()
        AbilityPicker.ReloadAll = false
    elseif AbilityPicker.ReloadSpells then
        AbilityPicker.Spells = {Categories={}}
        InitSpellTree()
        AbilityPicker.ReloadSpells = false
    elseif AbilityPicker.ReloadDiscs then
        AbilityPicker.CombatAbilities = {Categories={}}
        InitDiscTree()
        AbilityPicker.ReloadDiscs = false
    elseif AbilityPicker.ReloadAAs then
        AbilityPicker.AltAbilities = {Types={}}
        InitAATree()
        AbilityPicker.ReloadAAs = false
    elseif AbilityPicker.ReloadItems then
        AbilityPicker.Items = {}
        InitItems()
        AbilityPicker.ReloadItems = false
    elseif AbilityPicker.ReloadAbilities then
        AbilityPicker.Abilities = {}
        InitAbilityTree()
        AbilityPicker.ReloadAbilities = false
    end
end

local function ResetFilter()
    AbilityPicker.FilteredResults = {}
end

local function FilterCatSubCatTree(tbl, filter)
    local filteredAbilities = {Categories={}}
    for _,category in ipairs(tbl.Categories) do
        local abilityCategory = tbl[category]
        for _,subCategory in ipairs(abilityCategory.SubCategories) do
            local abilitySubCategory = abilityCategory[subCategory]
            for _,ability in ipairs(abilitySubCategory) do
                if ability.Name:lower():find(filter) then
                    if not filteredAbilities[category] then table.insert(filteredAbilities.Categories, category) end
                    filteredAbilities[category] = filteredAbilities[category] or {SubCategories={}}
                    if not filteredAbilities[category][subCategory] then table.insert(filteredAbilities[category].SubCategories, subCategory) end
                    filteredAbilities[category][subCategory] = filteredAbilities[category][subCategory] or {}
                    table.insert(filteredAbilities[category][subCategory], ability)
                end
            end
        end
    end
    return filteredAbilities
end

local function FilterSpells(filter)
    local filteredSpells = FilterCatSubCatTree(AbilityPicker.Spells, filter)
    AbilityPicker.FilteredResults.Spells = filteredSpells
end

local function FilterDiscs(filter)
    local filteredDiscs = FilterCatSubCatTree(AbilityPicker.CombatAbilities, filter)
    AbilityPicker.FilteredResults.CombatAbilities = filteredDiscs
end

local function FilterAAs(filter)
    local filteredAAs = {Types={}}
    for _,type in ipairs(AbilityPicker.AltAbilities.Types) do
        for _,altAbility in ipairs(AbilityPicker.AltAbilities[type]) do
            if altAbility.Name:lower():find(filter) then
                if not filteredAAs[type] then table.insert(filteredAAs.Types, type) end
                filteredAAs[type] = filteredAAs[type] or {}
                table.insert(filteredAAs[type], altAbility)
            end
        end
    end
    AbilityPicker.FilteredResults.AltAbilities = filteredAAs
end

local function FilterAbilities(filter)
    local filteredAbilities = {}
    for _,ability in ipairs(AbilityPicker.Abilities) do
        if ability.Name:lower():find(filter) then
            table.insert(filteredAbilities, ability)
        end
    end
    AbilityPicker.FilteredResults.Abilities = filteredAbilities
end

local function FilterItems(filter)
    local filteredItems = {}
    for _,item in ipairs(AbilityPicker.Items) do
        if item.Name:lower():find(filter) then
            table.insert(filteredItems, item)
        end
    end
    AbilityPicker.FilteredResults.Items = filteredItems
end

-- Color spell names in spell picker similar to the spell bar context menus
local function SetTextColor(ability)
    local targetType = ability.TargetType
    if targetType == 'Single' or targetType == 'Line of Sight' or targetType == 'Undead' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif targetType == 'Self' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
    elseif targetType == 'Group v2' or targetType == 'Group v1' or targetType == 'AE PC v2' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 1, 1)
    elseif targetType == 'Beam' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 1, 1)
    elseif targetType == 'Targeted AE' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.5, 0, 1)
    elseif targetType == 'PB AE' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 0.5, 1, 1)
    elseif targetType == 'Pet' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif targetType == 'Pet2' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
    elseif targetType == 'Free Target' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)
    end
end

local function SelectAbility(type, id, name, rankName, level, spellName)
    AbilityPicker.Selected = {ID=id, Type=type, Name=name, RankName=rankName, Level=level, SpellName=spellName}
    AbilityPicker.Open = false
    AbilityPicker.Draw = false
    AbilityPicker.Filter = ''
    AbilityPicker.FilteredResults = {}
end

local function DrawCatSubCatTree(tbl, type)
    for _,category in ipairs(tbl.Categories) do
        if ImGui.TreeNode(category) then
            local abilityCategory = tbl[category]
            for _,subCategory in ipairs(abilityCategory.SubCategories) do
                if ImGui.TreeNode(subCategory) then
                    local abilitySubCategory = abilityCategory[subCategory]
                    for _,ability in ipairs(abilitySubCategory) do
                        animSpellIcons:SetTextureCell(ability.Icon)
                        ImGui.DrawTextureAnimation(animSpellIcons, 20, 20)
                        ImGui.SameLine()
                        if ability.TargetType then SetTextColor(ability) end
                        if ImGui.Selectable(string.format('%s - %s', ability.Level, ability.Name), false) then
                            SelectAbility(type, ability.ID, ability.Name, ability.RankName, ability.Level)
                        end
                        if ability.TargetType then ImGui.PopStyleColor() end
                    end
                    ImGui.TreePop()
                end
            end
            ImGui.TreePop()
        end
    end
end

local function DrawSpellTree(spells)
    if ImGui.TreeNode('Spells') then
        DrawCatSubCatTree(spells, 'Spell')
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Spells') then
                AbilityPicker.ReloadSpells = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawAATree(altAbilities)
    if ImGui.TreeNode('Alternate Abilities') then
        for _,type in ipairs(altAbilities.Types) do
            if ImGui.TreeNode(type) then
                for _,altAbility in ipairs(altAbilities[type]) do
                    animSpellIcons:SetTextureCell(altAbility.Icon)
                    ImGui.DrawTextureAnimation(animSpellIcons, 20, 20)
                    ImGui.SameLine()
                    if altAbility.TargetType then SetTextColor(altAbility) end
                    if ImGui.Selectable(altAbility.Name, false) then
                        SelectAbility('AA', altAbility.ID, altAbility.Name)
                    end
                    if altAbility.TargetType then ImGui.PopStyleColor() end
                end
                ImGui.TreePop()
            end
        end
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Alternate Abilities') then
                AbilityPicker.ReloadAAs = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawDiscTree(discs)
    if ImGui.TreeNode('Combat Abilities') then
        DrawCatSubCatTree(discs, 'Disc')
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Combat Abilities') then
                AbilityPicker.ReloadDiscs = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawItemTree(items)
    if ImGui.TreeNode('Items') then
        for _,item in ipairs(items) do
            animItems:SetTextureCell(item.Icon-500)
            ImGui.DrawTextureAnimation(animItems, 20, 20)
            ImGui.SameLine()
            if item.TargetType then SetTextColor(item) end
            if ImGui.Selectable(string.format('%s - %s', item.Name, item.SpellName), false) then
                SelectAbility('Item', item.ID, item.Name, nil, nil, item.SpellName)
            end
            if item.TargetType then ImGui.PopStyleColor() end
        end
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Items') then
                AbilityPicker.ReloadItems = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawAbilityTree(abilities)
    if ImGui.TreeNode('Abilities') then
        for _,ability in ipairs(abilities) do
            if ability.TargetType then SetTextColor(ability) end
            if ImGui.Selectable(ability.Name, false) then
                SelectAbility('Ability', ability.ID, ability.Name)
            end
            if ability.TargetType then ImGui.PopStyleColor() end
        end
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Abilities') then
                AbilityPicker.ReloadAbilities = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawSearchFilter()
    local filter = ImGui.InputTextWithHint('##Filter', 'Search Abilities...', AbilityPicker.Filter)
    if filter:len() >= 3 and AbilityPicker.Filter ~= filter then
        AbilityPicker.Filter = filter
        ResetFilter()
        filter = filter:lower()
        FilterSpells(filter)
        FilterDiscs(filter)
        FilterAAs(filter)
        FilterItems(filter)
        FilterAbilities(filter)
    else
        if filter:len() < 3 and AbilityPicker.Filter ~= filter then ResetFilter() end
        AbilityPicker.Filter = filter
    end
end

function AbilityPicker.DrawAbilityPicker()
    if not AbilityPicker.Open then return end
    AbilityPicker.Open, AbilityPicker.Draw = ImGui.Begin('Ability Picker', AbilityPicker.Open, ImGuiWindowFlags.AlwaysAutoResize)
    if AbilityPicker.Draw then
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload All') then
                AbilityPicker.ReloadAll = true
            end
            ImGui.EndPopup()
        end
        DrawSearchFilter()
        DrawSpellTree(AbilityPicker.FilteredResults.Spells or AbilityPicker.Spells)
        ImGui.Separator()
        DrawAATree(AbilityPicker.FilteredResults.AltAbilities or AbilityPicker.AltAbilities)
        ImGui.Separator()
        DrawDiscTree(AbilityPicker.FilteredResults.CombatAbilities or AbilityPicker.CombatAbilities)
        ImGui.Separator()
        DrawItemTree(AbilityPicker.FilteredResults.Items or AbilityPicker.Items)
        ImGui.Separator()
        DrawAbilityTree(AbilityPicker.FilteredResults.Abilities or AbilityPicker.Abilities)
    end
    ImGui.End()
end

function AbilityPicker.SetOpen()
    AbilityPicker.Open, AbilityPicker.Draw = true, true
end

function AbilityPicker.ClearSelection()
    AbilityPicker.Selected = nil
end

return AbilityPicker