--!strict
-- Small widget helpers shared by every candidate menu style. No game rules here.
local Kit = {}

local FONTS: { [string]: Enum.Font } = {
    gotham = Enum.Font.Gotham,
    gothamMedium = Enum.Font.GothamMedium,
    gothamBold = Enum.Font.GothamBold,
    condensedBold = Enum.Font.Oswald,
    hand = Enum.Font.PatrickHand,
    marker = Enum.Font.PermanentMarker,
    mono = Enum.Font.RobotoMono,
}

function Kit.color(rgb: { number }): Color3
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function Kit.font(key: string?): Enum.Font
    return FONTS[key or "gotham"] or Enum.Font.Gotham
end

function Kit.tone(style: any, name: string?): Color3
    return Kit.color(style.colors[name or "ink"] or style.colors.ink)
end

function Kit.make(className: string, props: { [string]: any }, parent: Instance?): any
    local item = Instance.new(className)
    for key, value in props do
        (item :: any)[key] = value
    end
    item.Parent = parent
    return item
end

function Kit.corner(target: Instance, radius: number)
    Kit.make("UICorner", { CornerRadius = UDim.new(0, radius) }, target)
end

function Kit.pad(target: Instance, top: number, right: number, bottom: number, left: number)
    Kit.make("UIPadding", {
        PaddingTop = UDim.new(0, top),
        PaddingRight = UDim.new(0, right),
        PaddingBottom = UDim.new(0, bottom),
        PaddingLeft = UDim.new(0, left),
    }, target)
end

function Kit.stroke(target: Instance, color: Color3, thickness: number, transparency: number?)
    Kit.make("UIStroke", {
        Color = color,
        Thickness = thickness,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, target)
end

function Kit.column(target: Instance, gap: number, align: Enum.HorizontalAlignment?)
    return Kit.make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap),
        HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
    }, target)
end

function Kit.row(target: Instance, gap: number, align: Enum.VerticalAlignment?)
    return Kit.make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap),
        VerticalAlignment = align or Enum.VerticalAlignment.Center,
    }, target)
end

-- A panel in the current style: rounded, optionally outlined, optionally tilted.
function Kit.card(parent: Instance, style: any, props: { [string]: any }): Frame
    local tilt = props.Rotation
    props.Rotation = nil
    local fill = props.BackgroundColor3 or Kit.tone(style, "card")
    props.BackgroundColor3 = fill
    props.BorderSizePixel = 0
    props.BackgroundTransparency = props.BackgroundTransparency or style.cardTransparency
    local card = Kit.make("Frame", props, parent) :: Frame
    Kit.corner(card, style.corner)
    if style.stroke > 0 then
        Kit.stroke(card, Kit.tone(style, "line"), style.stroke)
    end
    if style.tilt and tilt then
        card.Rotation = tilt
    end
    return card
end

function Kit.text(parent: Instance, style: any, props: { [string]: any }): TextLabel
    local fontKey = props.FontKey
    props.FontKey = nil
    local toneName = props.Tone
    props.Tone = nil
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.Font = Kit.font(style.fonts[fontKey or "body"] or fontKey)
    props.TextColor3 = props.TextColor3 or Kit.tone(style, toneName)
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Top
    props.RichText = false
    return Kit.make("TextLabel", props, parent)
end

function Kit.button(parent: Instance, style: any, props: { [string]: any }): TextButton
    local toneName = props.Tone or "accent"
    props.Tone = nil
    local fontKey = props.FontKey
    props.FontKey = nil
    local solid = props.Solid ~= false
    props.Solid = nil
    local fill = Kit.tone(style, toneName)
    props.BackgroundColor3 = if solid then fill else Kit.tone(style, "chipOff")
    props.BackgroundTransparency = 0
    props.BorderSizePixel = 0
    props.AutoButtonColor = true
    props.Font = Kit.font(style.fonts[fontKey or "heading"] or fontKey)
    props.TextColor3 = if solid
        then Kit.color(if style.layout == "board" then { 24, 27, 31 } else { 255, 252, 246 })
        else Kit.tone(style, "ink")
    if not solid and toneName ~= "muted" then
        props.TextColor3 = fill
    end
    local item = Kit.make("TextButton", props, parent) :: TextButton
    Kit.corner(item, math.min(style.corner, 14))
    if not solid then
        Kit.stroke(item, fill, 1, 0.3)
    end
    return item
end

function Kit.dot(parent: Instance, color: Color3, size: number, order: number): Frame
    local dot = Kit.make("Frame", {
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, parent) :: Frame
    Kit.corner(dot, size)
    return dot
end

-- Horizontal meter bar used by the board and phone layouts.
function Kit.bar(
    parent: Instance,
    style: any,
    fraction: number,
    color: Color3,
    props: { [string]: any }
)
    props.BackgroundColor3 = Kit.tone(style, "chipOff")
    props.BorderSizePixel = 0
    local track = Kit.make("Frame", props, parent) :: Frame
    Kit.corner(track, 4)
    local fill = Kit.make("Frame", {
        Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, track) :: Frame
    Kit.corner(fill, 4)
    return track
end

function Kit.scroller(parent: Instance, props: { [string]: any }): ScrollingFrame
    props.BackgroundTransparency = 1
    props.BorderSizePixel = 0
    props.ScrollBarThickness = 3
    props.ScrollingDirection = Enum.ScrollingDirection.Y
    props.AutomaticCanvasSize = Enum.AutomaticSize.Y
    props.CanvasSize = UDim2.new()
    return Kit.make("ScrollingFrame", props, parent)
end

return Kit
