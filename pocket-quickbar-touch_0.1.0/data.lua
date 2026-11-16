-- Settings glyph and Pocket Foundry long-touch page reset.
data:extend({
  {type="sprite",name="pqt-ghost",filename="__pocket-quickbar-touch__/graphics/ghost.png",width=16,height=16},
  {type="custom-input",name="pqt-reset-page-on-hold",key_sequence="",
    controller_key_sequence="controller-x",consuming="none"}
})

-- Matching sprites keep the settings glyph centered as the button scales.
data:extend{{type="sprite",name="pqt-settings-26",filename="__pocket-quickbar-touch__/graphics/settings-26.png",width=26,height=26}}
for px=28,68 do
  data:extend{{type="sprite",name="pqt-settings-"..px,
    filename="__pocket-quickbar-touch__/graphics/settings-"..px..".png",width=px,height=px}}
end
