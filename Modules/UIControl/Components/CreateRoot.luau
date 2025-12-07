local ReplicatedStorage = game:GetService("ReplicatedStorage")
local fusion = require(ReplicatedStorage.Packages.fusion)

export type EnumGui = {
	SafeAreaCompatibility: fusion.UsedAs<Enum.SafeAreaCompatibility>?,
	ScreenInsets: fusion.UsedAs<Enum.ScreenInsets>?,
	ZIndexBehavior: fusion.UsedAs<Enum.ZIndexBehavior>?,
}

export type Props = EnumGui & {
	Name: fusion.UsedAs<string>,
	Parent: fusion.UsedAs<string>,
	DisplayOrder: fusion.UsedAs<number>?,
	IgnoreGuiInset: fusion.UsedAs<boolean>?,
	ResetOnSpawn: fusion.UsedAs<boolean>?,
}

local defaultProps = {
	DisplayOrder = 0,
	IgnoreGuiInset = false,
	ResetOnSpawn = true,
	SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}

local function combine(props: Props)
	local result = table.clone(defaultProps)

	for key, value in pairs(props) do
		if value ~= nil then
			result[key] = value
		end
	end

	return result
end

return function(_scope: fusion.Scope<any>, props: Props): ScreenGui
	local scope = fusion.innerScope(_scope, fusion)
	return scope:New("ScreenGui")({ combine(props) })
end
