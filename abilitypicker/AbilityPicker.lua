--[[
    AbilityPicker provides a UI for selecting abilities, such as for configuring
    what abilities to use in some automation script.

    Usage:
    -- Somewhere in main script execution:
    local AbilityPicker = require('AbilityPicker')
    local picker = AbilityPicker.new() -- optionally takes a table of ability types to display
    -- local picker = AbilityPicker.new({'Item','Spell','AA','CombatAbility','Skill'})
    picker:InitializeAbilities()

    -- Somewhere during ImGui callback execution:
    if ImGui.Button('Open Ability Picker') then picker:SetOpen() end
    picker:DrawAbilityPicker()

    -- Somewhere in main script execution:
    if picker.Selected then
        -- Process the item which was selected by the picker
        printf('Selected %s: %s', picker.Selected.Type, picker.Selected.Name)
        picker:ClearSelection()
    end

    -- In main loop, reload abilities if selected by user
    while true do
        picker.Reload()
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
    - Type = 'Skill'
        - ID, Name
]]

---@type Mq
local mq = require('mq')
---@type ImGui
require('ImGui')

local allTypes = {Spell=true,AA=true,CombatAbility=true,Item=true,Skill=true}
local animSpellIcons = mq.FindTextureAnimation('A_SpellIcons')
local animItems = mq.FindTextureAnimation('A_DragItem')
local aaTypes = {'General','Archtype','Class','Special'}

local AbilityPicker = {}
AbilityPicker.__index = AbilityPicker

function AbilityPicker.new(types)
    local newPicker = {
        Open = false,
        Draw = false,
        Spells = {Categories={}},
        AltAbilities = {Types={}},
        CombatAbilities = {Categories={}},
        Abilities = {},
        Items = {},
        Selected = nil,
        Filter = '',
        FilteredResults = {},
        Types = {},
    }
    if types then
        for _,abilityType in ipairs(types) do newPicker.Types[abilityType] = true end
    else
        newPicker.Types = allTypes
    end
    return setmetatable(newPicker, AbilityPicker)
end

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

local function AddSpellToMap(picker, spell)
    local category = spell.Category()
    local subCategory = spell.Subcategory()
    if not picker.Spells[category] then
        picker.Spells[category] = {SubCategories={}}
        table.insert(picker.Spells.Categories, category)
    end
    if not picker.Spells[category][subCategory] then
        picker.Spells[category][subCategory] = {}
        table.insert(picker.Spells[category].SubCategories, subCategory)
    end
    local name = spell.Name():gsub(' Rk%..*', '')
    table.insert(picker.Spells[category][subCategory], {ID=spell.ID(), Level=spell.Level(), Name=name, RankName=spell.Name(), TargetType=spell.TargetType(), Icon=spell.SpellIcon()})
end

local function InitSpellTree(picker)
    -- Build spell tree for picking spells
    for spellIter=1,1120 do
        local spell = mq.TLO.Me.Book(spellIter)
        if spell() then
            AddSpellToMap(picker, spell)
        end
    end
    SortMap(picker.Spells)
end

local function AddAAToMap(picker, aa)
    local type = aaTypes[aa.Type()]
    if not picker.AltAbilities[type] then
        picker.AltAbilities[type] = {}
        table.insert(picker.AltAbilities.Types, type)
    end
    table.insert(picker.AltAbilities[type], {ID=aa.ID(), Name=aa.Name(), TargetType=aa.Spell.TargetType(), Icon=aa.Spell.SpellIcon()})
end

local function InitAATree(picker)
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
            if aa() and aa.Spell() then AddAAToMap(picker, aa) end
        end
    end

    for _, type in ipairs(aaTypes) do
        if picker.AltAbilities[type] then
            table.sort(picker.AltAbilities[type], function(a, b) return a.Name < b.Name end)
        end
    end
end

local function AddDiscToMap(picker, disc)
    local category = disc.Category()
    local subCategory = disc.Subcategory()
    if not picker.CombatAbilities[category] then
        picker.CombatAbilities[category] = {SubCategories={}}
        table.insert(picker.CombatAbilities.Categories, category)
    end
    if not picker.CombatAbilities[category][subCategory] then
        picker.CombatAbilities[category][subCategory] = {}
        table.insert(picker.CombatAbilities[category].SubCategories, subCategory)
    end
    local name = disc.Name():gsub(' Rk%..*', '')
    table.insert(picker.CombatAbilities[category][subCategory], {ID=disc.ID(), Level=disc.Level(), Name=name, RankName=disc.Name(), TargetType=disc.TargetType(), Icon=disc.SpellIcon()})
end

local function InitDiscTree(picker)
    local discIter = 1
    repeat
        local disc = mq.TLO.Me.CombatAbility(discIter)
        if disc() then
            AddDiscToMap(picker, disc)
        end
        discIter = discIter + 1
    until mq.TLO.Me.CombatAbility(discIter)() == nil
    SortMap(picker.CombatAbilities)
end

local function InitSkillTree(picker)
    for i=0,100 do
        local ability = mq.TLO.Me.Ability(i)
        if ability() then
            table.insert(picker.Abilities, {ID=i, Name=ability()})
        end
    end
    table.sort(picker.Abilities, function(a, b) return a.Name < b.Name end)
end

local function InitItems(picker)
    for i=0,32 do
        local item = mq.TLO.Me.Inventory(i)
        if item() then
            if item.Container() > 0 then
                for j=1,item.Container() do
                    local bagItem = item.Item(j)
                    if bagItem() and bagItem.Spell() then
                        table.insert(picker.Items, {ID=bagItem.ID(), Name=bagItem.Name(), SpellName=bagItem.Clicky(), TargetType=bagItem.Clicky.Spell.TargetType(), Icon=bagItem.Icon()})
                    end
                end
            elseif item.Clicky() then
                table.insert(picker.Items, {ID=item.ID(), Name=item.Name(), SpellName=item.Clicky(), TargetType=item.Clicky.Spell.TargetType(), Icon=item.Icon()})
            end
        end
    end
    table.sort(picker.Items, function(a, b) return a.Name < b.Name end)
end

function AbilityPicker:InitializeAbilities()
    if self.Types.Spell then InitSpellTree(self) end
    if self.Types.AA then InitAATree(self) end
    if self.Types.CombatAbility then InitDiscTree(self) end
    if self.Types.Skill then InitSkillTree(self) end
    if self.Types.Item then InitItems(self) end
end

function AbilityPicker:Reload()
    if self.ReloadAll then
        self.Spells = {Categories={}}
        self.AltAbilities = {Types={}}
        self.CombatAbilities = {Categories={}}
        self.Abilities = {}
        self.Items = {}
        self:InitializeAbilities()
        self.ReloadAll = false
    elseif self.ReloadSpells then
        self.Spells = {Categories={}}
        InitSpellTree(self)
        self.ReloadSpells = false
    elseif self.ReloadDiscs then
        self.CombatAbilities = {Categories={}}
        InitDiscTree(self)
        self.ReloadDiscs = false
    elseif self.ReloadAAs then
        self.AltAbilities = {Types={}}
        InitAATree(self)
        self.ReloadAAs = false
    elseif self.ReloadItems then
        self.Items = {}
        InitItems(self)
        self.ReloadItems = false
    elseif self.ReloadAbilities then
        self.Abilities = {}
        InitSkillTree(self)
        self.ReloadAbilities = false
    end
end

local function ResetFilter(picker)
    picker.FilteredResults = {}
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

local function FilterSpells(picker, filter)
    local filteredSpells = FilterCatSubCatTree(picker.Spells, filter)
    picker.FilteredResults.Spells = filteredSpells
end

local function FilterDiscs(picker, filter)
    local filteredDiscs = FilterCatSubCatTree(picker.CombatAbilities, filter)
    picker.FilteredResults.CombatAbilities = filteredDiscs
end

local function FilterAAs(picker, filter)
    local filteredAAs = {Types={}}
    for _,type in ipairs(picker.AltAbilities.Types) do
        for _,altAbility in ipairs(picker.AltAbilities[type]) do
            if altAbility.Name:lower():find(filter) then
                if not filteredAAs[type] then table.insert(filteredAAs.Types, type) end
                filteredAAs[type] = filteredAAs[type] or {}
                table.insert(filteredAAs[type], altAbility)
            end
        end
    end
    picker.FilteredResults.AltAbilities = filteredAAs
end

local function FilterSkills(picker, filter)
    local filteredAbilities = {}
    for _,ability in ipairs(picker.Abilities) do
        if ability.Name:lower():find(filter) then
            table.insert(filteredAbilities, ability)
        end
    end
    picker.FilteredResults.Abilities = filteredAbilities
end

local function FilterItems(picker, filter)
    local filteredItems = {}
    for _,item in ipairs(picker.Items) do
        if item.Name:lower():find(filter) then
            table.insert(filteredItems, item)
        end
    end
    picker.FilteredResults.Items = filteredItems
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

local function SelectAbility(picker, type, id, name, rankName, level, spellName)
    picker.Selected = {ID=id, Type=type, Name=name, RankName=rankName, Level=level, SpellName=spellName}
    picker.Open = false
    picker.Draw = false
    picker.Filter = ''
    picker.FilteredResults = {}
end

local function DrawCatSubCatTree(picker, tbl, type)
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
                            SelectAbility(picker, type, ability.ID, ability.Name, ability.RankName, ability.Level)
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

local function DrawSpellTree(picker, spells)
    if ImGui.TreeNode('Spells') then
        DrawCatSubCatTree(picker, spells, 'Spell')
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Spells') then
                picker.ReloadSpells = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawAATree(picker, altAbilities)
    if ImGui.TreeNode('Alternate Abilities') then
        for _,type in ipairs(altAbilities.Types) do
            if ImGui.TreeNode(type) then
                for _,altAbility in ipairs(altAbilities[type]) do
                    animSpellIcons:SetTextureCell(altAbility.Icon)
                    ImGui.DrawTextureAnimation(animSpellIcons, 20, 20)
                    ImGui.SameLine()
                    if altAbility.TargetType then SetTextColor(altAbility) end
                    if ImGui.Selectable(altAbility.Name, false) then
                        SelectAbility(picker, 'AA', altAbility.ID, altAbility.Name)
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
                picker.ReloadAAs = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawDiscTree(picker, discs)
    if ImGui.TreeNode('Combat Abilities') then
        DrawCatSubCatTree(picker, discs, 'Disc')
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Combat Abilities') then
                picker.ReloadDiscs = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawItemTree(picker, items)
    if ImGui.TreeNode('Items') then
        for _,item in ipairs(items) do
            animItems:SetTextureCell(item.Icon-500)
            ImGui.DrawTextureAnimation(animItems, 20, 20)
            ImGui.SameLine()
            if item.TargetType then SetTextColor(item) end
            if ImGui.Selectable(string.format('%s - %s', item.Name, item.SpellName), false) then
                SelectAbility(picker, 'Item', item.ID, item.Name, nil, nil, item.SpellName)
            end
            if item.TargetType then ImGui.PopStyleColor() end
        end
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Items') then
                picker.ReloadItems = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawSkillTree(picker, abilities)
    if ImGui.TreeNode('Abilities') then
        for _,ability in ipairs(abilities) do
            if ability.TargetType then SetTextColor(ability) end
            if ImGui.Selectable(ability.Name, false) then
                SelectAbility(picker, 'Ability', ability.ID, ability.Name)
            end
            if ability.TargetType then ImGui.PopStyleColor() end
        end
        ImGui.TreePop()
    else
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload Abilities') then
                picker.ReloadAbilities = true
            end
            ImGui.EndPopup()
        end
    end
end

local function DrawSearchFilter(picker)
    local filter = ImGui.InputTextWithHint('##Filter', 'Search Abilities...', picker.Filter)
    if filter:len() >= 3 and picker.Filter ~= filter then
        picker.Filter = filter
        ResetFilter(picker)
        filter = filter:lower()
        if picker.Types.Spell then FilterSpells(picker, filter) end
        if picker.Types.CombatAbility then FilterDiscs(picker, filter) end
        if picker.Types.AA then FilterAAs(picker, filter) end
        if picker.Types.Item then FilterItems(picker, filter) end
        if picker.Types.Skill then FilterSkills(picker, filter) end
    else
        if filter:len() < 3 and picker.Filter ~= filter then ResetFilter(picker) end
        picker.Filter = filter
    end
end

function AbilityPicker:DrawAbilityPicker()
    if not self.Open then return end
    self.Open, self.Draw = ImGui.Begin('Ability Picker', self.Open, ImGuiWindowFlags.AlwaysAutoResize)
    if self.Draw then
        if ImGui.BeginPopupContextItem() then
            if ImGui.MenuItem('Reload All') then
                self.ReloadAll = true
            end
            ImGui.EndPopup()
        end
        DrawSearchFilter(self)
        if self.Types.Spell then
            DrawSpellTree(self, self.FilteredResults.Spells or self.Spells)
            ImGui.Separator()
        end
        if self.Types.AA then
            DrawAATree(self, self.FilteredResults.AltAbilities or self.AltAbilities)
            ImGui.Separator()
        end
        if self.Types.CombatAbility then
            DrawDiscTree(self, self.FilteredResults.CombatAbilities or self.CombatAbilities)
            ImGui.Separator()
        end
        if self.Types.Item then
            DrawItemTree(self, self.FilteredResults.Items or self.Items)
            ImGui.Separator()
        end
        if self.Types.Skill then
            DrawSkillTree(self, self.FilteredResults.Abilities or self.Abilities)
        end
    end
    ImGui.End()
end

function AbilityPicker:SetOpen()
    self.Open, self.Draw = true, true
end

function AbilityPicker:ClearSelection()
    self.Selected = nil
end

return AbilityPicker