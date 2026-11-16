-- Pocket Quickbar Touch 0.1.0 by Hinnli. Factorio 2.1.x / Pocket Foundry.
-- The bar mirrors vanilla quickbar slots and does not create another inventory.
local MAIN, PREFS = "pqt_main", "pqt_settings"
local MAX_PAGES, VANILLA_SLOTS = 10, 10
local GAP = 2
local HEADER_HEIGHT, HEADER_BUTTON_SIZE = 32, 26
local SETTINGS_WIDTH = 540
local LABEL_WIDTH, CONTROL_WIDTH, RESET_WIDTH, COLUMN_GAP = 290, 194, 28, 6
local OPTIONS_WIDTH = LABEL_WIDTH + CONTROL_WIDTH + RESET_WIDTH + COLUMN_GAP * 2
local DEFAULTS = {
  size=34, rows=2, cols=10, bottom=12,
  show_count=true, show_title=true, inventory_only=false, vertical=false,
  only_controller=true
}
local SLIDERS = {size={28,68}, rows={1,4}, cols={3,10}, bottom={0,160}}
local TOGGLES = {show_count=true,show_title=true,inventory_only=true,only_controller=true}

local function clamp(x, a, b)
  return math.max(a, math.min(b, x))
end
local function copy_state(p)
  local t={}
  for k,v in pairs(DEFAULTS) do
    if p[k]==nil then t[k]=v else t[k]=p[k] end
  end
  t.position=p.position and {x=p.position.x,y=p.position.y} or nil
  return t
end
local function saved(player)
  storage.pqt_players=storage.pqt_players or {}
  local p=storage.pqt_players[player.index]
  if not p then p={pages={}};storage.pqt_players[player.index]=p end
  p.pages=p.pages or {}
  for k,v in pairs(DEFAULTS) do
    if p[k]==nil then
      if k=="size" and player.mod_settings["pqt-size"] then
        p[k]=player.mod_settings["pqt-size"].value
      elseif k=="rows" and player.mod_settings["pqt-rows"] then
        p[k]=player.mod_settings["pqt-rows"].value
      elseif k=="only_controller" and player.mod_settings["pqt-only-controller"] then
        p[k]=player.mod_settings["pqt-only-controller"].value
      else p[k]=v end
    end
  end
  if p.vertical then p.show_title=false end -- Existing vertical configurations from 0.1.7
  return p
end
local function state(player)
  local p=saved(player)
  return p.draft or p
end
local function editing(player) return saved(player).draft ~= nil end
local function destroy(player,name)
  local elem=player.gui.screen[name]
  if elem and elem.valid then elem.destroy() end
end
local function enabled(player)
  if not player.valid or not player.connected then return false end
  local p=state(player)
  return not p.only_controller or player.input_method==defines.input_method.game_controller
end
local function quality_name(q)
  if type(q)=="string" then return q end
  if q and q.name then return q.name end
  return "normal"
end
local function slot_item(slot)
  if not slot then return nil end
  if (slot.type=="filter" or slot.type=="remote") and slot.filter then
    local f=slot.filter
    if type(f)=="string" then return f,"normal" end
    if f.name then return type(f.name)=="string" and f.name or f.name.name,quality_name(f.quality) end
  elseif slot.type=="item" and slot.item and slot.item.name then
    return slot.item.name,quality_name(slot.item.quality)
  end
  return nil
end
local function page_for(player,row)
  local p=saved(player)
  if not p.pages[row] then
    local current=player.get_active_quick_bar_page(row) or row
    p.pages[row]=(current>=1 and current<=MAX_PAGES) and current or row
  end
  return p.pages[row]
end
local function screen_geom(player)
  local r=player.display_resolution
  return r.width,r.height,math.max(0.1,player.display_scale or 1)
end
-- Geometry of the *slots* is independent from the optional title and the
-- small settings button.  The outer invisible frame deliberately avoids
-- painting a large rectangular background where there is no control.
-- Reserve a transparent header row in BOTH modes.  Its height never
-- changes when EDIT opens, so the slots keep precisely the same location.
local function metrics(player)
  local p=state(player)
  local size=clamp(p.size,SLIDERS.size[1],SLIDERS.size[2])
  local rows=clamp(p.rows,1,4)
  local cols=clamp(p.cols,3,math.min(10,player.quick_bar_width or VANILLA_SLOTS))
  local body_width,body_height
  if p.vertical then
    body_width=rows*size+(rows-1)*GAP+4
    body_height=(cols+1)*size+cols*GAP+4
  else
    body_width=(cols+1)*size+cols*GAP+4
    body_height=rows*size+(rows-1)*GAP+4
  end
  local has_title=p.show_title and not p.vertical
  local side_width=(not p.vertical and not has_title) and (size+4+GAP) or 0
  local footer_height=p.vertical and (size+4) or 0
  -- The title is a native Factorio frame header; small bars need enough
  -- room for its text and the SMALL frame-action button.
  local title_width=has_title and 250 or 0
  local width=math.max(body_width+side_width,title_width)
  local height=HEADER_HEIGHT+body_height+footer_height
  return width,height,size,rows,cols,HEADER_HEIGHT,body_height,body_width
end

-- Scaling around a stable anchor, including bars which were already dragged.
-- The returned location is used for this redraw only. An automatic (not
-- dragged) bar keeps position=nil, so merely changing cell size won't
-- accidentally mark the position as custom.
local function resized_location(player, old_width, old_height)
  local p=state(player)
  local root=player.gui.screen[MAIN]
  local old=root and root.valid and root.location or p.position
  if not old then return nil end
  local new_width,new_height=metrics(player)
  local _,_,scale=screen_geom(player)
  local location
  if p.vertical then
    -- The left edge and vertical midpoint remain fixed.
    location={x=old.x,
      y=math.floor(old.y+(old_height-new_height)*scale/2+0.5)}
  else
    -- The horizontal midpoint and bottom edge remain fixed.
    location={
      x=math.floor(old.x+(old_width-new_width)*scale/2+0.5),
      y=math.floor(old.y+(old_height-new_height)*scale+0.5)
    }
  end
  if p.position then p.position=location end
  return location
end

local function body_of(root)
  -- Both title modes expose the same slot container, even when the hidden
  -- title's drag handle is integrated inside the painted slot frame.
  local layout=root and (root.pqt_unified or root)
  local line=layout and layout.pqt_body_line
  local body=line and line.pqt_body
  return body and (body.pqt_inner or body)
end

local function edit_button(parent,size)
  local b=parent.add{type="sprite-button",name="pqt_edit",style="frame_action_button",
    sprite="pqt-settings-"..size,tooltip={"pqt.edit-tip"},tags={pqt_action="edit"}}
  b.style.size={size,size}
  b.style.padding=0
  return b
end
-- Native Factorio titlebar geometry (24 px grip, 4 px trailing margin).
-- The FLOW is the drag target carrier; the grip itself is non-interactive,
-- matching the standard Factorio header construction.
local function add_grip(parent,root)
  parent.drag_target=root
  local grip=parent.add{type="empty-widget",name="pqt_grip",style="draggable_space_header",
    ignored_by_interaction=true}
  grip.style.horizontally_stretchable=true
  grip.style.height=24
  grip.style.right_margin=4
  return grip
end
local function add_ghost_badge(button,px)
  local badge=button.add{type="sprite",name="pqt_ghost_badge",sprite="pqt-ghost",
    resize_to_sprite=false,ignored_by_interaction=true}
  badge.style.size={px,px}
  badge.visible=false
  button.style.horizontal_align="right"
  button.style.vertical_align="bottom"
end
local function render_item(button,player,name,quality,count,show_count)
  button.sprite="item/"..name
  button.quality=(quality~="normal") and quality or nil
  button.elem_tooltip={type="item-with-quality",name=name,quality=quality or "normal"}
  button.tooltip=nil
  local badge=button.pqt_ghost_badge
  if show_count then
    button.number=count>0 and count or nil
    if badge and badge.valid then badge.visible=count==0 end
  else
    button.number=nil
    if badge and badge.valid then badge.visible=false end
  end
end

-- Vanilla's choose-elem-button opens exactly Factorio's own "Set filter"
-- window.  The name filter is applied only when inventory-only is enabled;
-- it does not change the native selector's categories or window geometry.
local function inventory_elem_filters(player)
  if not state(player).inventory_only then return nil end
  local names,seen={},{}
  local inv=player.get_main_inventory()
  if inv then
    for _,stack in pairs(inv.get_contents()) do
      if stack.name and (stack.count or 0)>0 and not seen[stack.name] then
        seen[stack.name]=true;names[#names+1]=stack.name
      end
    end
  end
  if #names==0 then names={"__pqt-no-owned-item__"} end
  return {{filter="name",name=names}}
end

-- Native empty slots use Factorio's own filter editor; filled slots use
-- sprite-buttons so that the game renders their item count inside the cell.
local function draw(player,force_default,preferred_location)
  local old=player.gui.screen[MAIN]
  local preserve=nil
  if not force_default and old and old.valid and old.location then
    preserve={x=old.location.x,y=old.location.y}
  end
  destroy(player,MAIN)
  if not enabled(player) then return end
  local p=state(player)
  local width,height,size,rows,cols,headheight,bodyheight,bodywidth=metrics(player)
  local has_title=p.show_title and not p.vertical
  local editing_now=editing(player)

  -- With a visible title, root is the single painted window.
  -- With a hidden title, pqt_body is the single painted window for both
  -- normal and editing views; the outer root stays transparent.
  local root_spec={type="frame",name=MAIN,direction="vertical"}
  if not has_title then root_spec.style="invisible_frame" end
  local root=player.gui.screen.add(root_spec)
  root.auto_center=false
  root.style.padding=has_title and 2 or 0
  if has_title then root.style.minimal_width=width end
  -- A zero-spacing inner vertical flow prevents the base-game frame
  -- style from adding a gap between its header and its slots.
  local layout=root
  if has_title then
    layout=root.add{type="flow",name="pqt_unified",direction="vertical"}
    layout.style.vertical_spacing=0
    layout.style.padding=0
  end

  -- Keep the slot origin constant at HEADER_HEIGHT, regardless of EDIT.
  -- Title on: one painted outer frame, with its usual header and slot flow.
  -- Title off + EDIT closed: an invisible 32px reservation above the
  -- compact framed slot body. Nothing is painted in the reservation.
  -- Title off + EDIT open: put the grip INSIDE the SAME slot frame,
  -- replacing the reservation. No second framed header window appears.
  if has_title or not editing_now then
    local headrow=layout.add{type="flow",name="pqt_header_row",direction="horizontal"}
    headrow.style.height=HEADER_HEIGHT
    headrow.style.width=width-(has_title and 4 or 0)
    if has_title then headrow.style.horizontally_stretchable=true end
    if has_title then
      -- One native horizontal title flow: no nested flow that could shift the
      -- text baseline or leave a taller-than-vanilla drag handle.
      headrow.style.vertical_align="center"
      local title_label=headrow.add{type="label",caption={"pqt.bar-title"},
        style="frame_title",ignored_by_interaction=not editing_now}
      -- Factorio's frame_title text sits a little low inside our fixed 32px
      -- header. Lift its baseline by two GUI pixels without changing the
      -- header height or the slot coordinates.
      title_label.style.vertical_align="center"
      title_label.style.top_margin=-2
      if editing_now then
        -- The label is a drag target too, not just the grippy empty space.
        -- drag_target accepts labels in Factorio 2.1.
        title_label.drag_target=root
        add_grip(headrow,root)
      else
        local spacer=headrow.add{type="empty-widget"}
        spacer.style.horizontally_stretchable=true
        spacer.style.height=24
      end
      edit_button(headrow,HEADER_BUTTON_SIZE)
    else
      local spacer=headrow.add{type="empty-widget"}
      spacer.style.size={width,HEADER_HEIGHT}
    end
  end

  local body_line=layout.add{type="flow",name="pqt_body_line",direction="horizontal"}
  body_line.style.horizontal_spacing=0 -- adjoining framed blocks must have no gutter
  local body=body_line.add{type=has_title and "flow" or "frame",
    name="pqt_body",direction=(not has_title and editing_now) and "vertical" or "horizontal"}
  body.style.padding=has_title and 0 or 2

  -- The integrated grip must be within the SAME painted pqt_body frame.
  -- A zero-spacing vertical flow avoids an extra default frame gap.
  local content=body
  if not has_title and editing_now then
    content=body.add{type="flow",name="pqt_inner",direction="vertical"}
    content.style.vertical_spacing=0
    content.style.padding=0
    local head=content.add{type="flow",name="pqt_drag_row",direction="horizontal"}
    head.style.height=HEADER_HEIGHT
    head.style.horizontally_stretchable=true
    head.style.vertical_align="center"
    add_grip(head,root)
  end
  local lines=content.add{type="flow",name="pqt_lines",
    direction=p.vertical and "horizontal" or "vertical"}
  if p.vertical then lines.style.horizontal_spacing=GAP
  else lines.style.vertical_spacing=GAP end

  local native_filters=inventory_elem_filters(player)
  local active=saved(player).active_picker
  for row=1,rows do
    local line=lines.add{type="flow",name="pqt_row_"..row,
      direction=p.vertical and "vertical" or "horizontal"}
    if p.vertical then line.style.vertical_spacing=GAP
    else line.style.horizontal_spacing=GAP end
    local page=line.add{type="button",name="pqt_page_"..row,
      style="quick_bar_page_button",caption=tostring(page_for(player,row)),
      tooltip={"pqt.page"},tags={pqt_action="page",row=row},raise_hover_events=true}
    page.style.size={size,size}
    page.style.padding=0
    page.style.horizontal_align="center"
    page.style.vertical_align="center"
    for col=1,cols do
      local slot=player.get_quick_bar_slot(page_for(player,row),col)
      local name,quality=slot_item(slot)
      -- Never swap *all* populated slots to choose-elem-buttons in edit
      -- mode. That element cannot display the native item quantity; the
      -- old overlay text both moved and covered item sprites. Only an
      -- empty slot or an explicitly activated editor becomes a picker.
      local chooser=(slot==nil) or
        (editing_now and active and active.row==row and active.col==col
         and active.page==page_for(player,row))
      local b
      if chooser then
        b=line.add{type="choose-elem-button",name="pqt_slot_"..row.."_"..col,
          elem_type="item-with-quality",tags={pqt_action="native-slot",row=row,col=col}}
        if native_filters then b.elem_filters=native_filters end
        if name and prototypes.item[name] then
          b.elem_value={name=name,quality=quality or "normal"}
        end
      else
        b=line.add{type="sprite-button",name="pqt_slot_"..row.."_"..col,
          style="slot_button",tags={pqt_action="slot",row=row,col=col}}
        add_ghost_badge(b,math.max(10,math.floor(size*0.3)))
        if editing_now then b.tooltip={"pqt.edit-existing-tip"} end
      end
      b.style.size={size,size}
    end
  end

  if not has_title and not p.vertical then
    -- Exactly to the right of the LOWEST row; not below the entire bar.
    local tools_column=body_line.add{type="flow",name="pqt_tools_column",direction="vertical"}
    tools_column.style.vertical_spacing=0
    local spacer=tools_column.add{type="empty-widget"}
    spacer.style.height=math.max(0,bodyheight-(size+4)
      + ((not has_title and editing_now) and HEADER_HEIGHT or 0))
    local tools=tools_column.add{type="frame",name="pqt_tools",direction="horizontal"}
    tools.style.padding=2
    edit_button(tools,size)
  elseif p.vertical then
    -- Directly below the leftmost column, aligned with the bottom-left corner.
    local tools_row=root.add{type="flow",name="pqt_tools_row",direction="horizontal"}
    local tools=tools_row.add{type="frame",name="pqt_tools",direction="horizontal"}
    tools.style.padding=2
    edit_button(tools,size)
  end

  local w,h,scale=screen_geom(player)
  local physw,physh=math.ceil(width*scale),math.ceil(height*scale)
  local x,y
  if force_default then
    if p.vertical then
      x=math.floor((p.bottom or 0)*scale)
      y=math.floor((h-physh)/2)
    else
      x=math.floor((w-physw)/2)
      y=math.floor(h-physh-(p.bottom or 0)*scale)
    end
  elseif preferred_location then
    x,y=preferred_location.x,preferred_location.y
  elseif p.position then
    x,y=p.position.x,p.position.y
  elseif preserve then
    x,y=preserve.x,preserve.y
  elseif p.vertical then
    x=math.floor((p.bottom or 0)*scale)
    y=math.floor((h-physh)/2)
  else
    x=math.floor((w-physw)/2)
    y=math.floor(h-physh-(p.bottom or 0)*scale)
  end
  x=math.floor(clamp(x,0,math.max(0,w-physw)))
  y=math.floor(clamp(y,0,math.max(0,h-physh)))
  saved(player).programmatic={x=x,y=y}
  root.location={x=x,y=y}
end
local function needs_rebuild(player)
  local root=player.gui.screen[MAIN]
  if not root or not root.valid then return true end
  local body=body_of(root)
  local lines=body and body.pqt_lines
  if not lines then return true end
  local _,_,_,rows,cols=metrics(player)
  for row=1,rows do
    local line=lines["pqt_row_"..row]
    if not line or not line.valid then return true end
    for col=1,cols do
      local b=line["pqt_slot_"..row.."_"..col]
      local slot=player.get_quick_bar_slot(page_for(player,row),col)
      if not b or not b.valid then return true end
      local active=saved(player).active_picker
      local expected=(slot==nil) or not not (editing(player) and active
        and active.row==row and active.col==col
        and active.page==page_for(player,row))
      if (b.type=="choose-elem-button")~=expected then return true end
    end
  end
  return false
end
local function refresh(player)
  local root=player.gui.screen[MAIN]
  if not root or not root.valid then return end
  local p=state(player)
  local inv=player.get_main_inventory()
  local cursor=player.cursor_stack
  local ghost=player.cursor_ghost
  local _,_,_,rows,cols=metrics(player)
  local lines=body_of(root).pqt_lines
  for row=1,rows do
    local line=lines["pqt_row_"..row]
    local page=page_for(player,row)
    line["pqt_page_"..row].caption=tostring(page)
    for col=1,cols do
      local slot=player.get_quick_bar_slot(page,col)
      local name,quality=slot_item(slot)
      local b=line["pqt_slot_"..row.."_"..col]
      local known=name and prototypes.item[name]
      local count=known and inv and inv.get_item_count({name=name,quality=quality or "normal"}) or 0
      if b.type=="choose-elem-button" then
        local value=b.elem_value
        local current=value and value.name
        local current_quality=value and quality_name(value.quality)
        if current~=(known and name or nil) or
            (known and current_quality~=(quality or "normal")) then
          b.elem_value=known and {name=name,quality=quality or "normal"} or nil
        end
      elseif known then
        render_item(b,player,name,quality,count,p.show_count)
        local matching_cursor=cursor and cursor.valid_for_read and cursor.name==name
          and quality_name(cursor.quality)==(quality or "normal")
        local matching_ghost=ghost and ghost.name==name
          and quality_name(ghost.quality)==(quality or "normal")
        b.toggled=not not (matching_cursor or matching_ghost)
      else
        b.sprite=(slot and slot.type=="record") and "item/blueprint" or "utility/empty_module_slot"
        b.quality=nil;b.number=nil;b.elem_tooltip=nil;b.toggled=false
        if b.pqt_ghost_badge then b.pqt_ghost_badge.visible=false end
        b.tooltip=slot and {"pqt.special"} or {"pqt.empty"}
      end
    end
  end
end
local function build(player,force_default,preferred_location)
  draw(player,force_default,preferred_location)
  refresh(player)
end

local function add_reset(parent,key)
  local b=parent.add{type="sprite-button",name="pqt_reset_"..key,
    style="tool_button_red",sprite="utility/reset",
    tooltip={"pqt.reset-one"},tags={pqt_action="reset-one",key=key}}
  b.style.size={RESET_WIDTH,RESET_WIDTH}
  b.style.padding=1
  return b
end
-- Native Factorio mod-settings rows are engine-owned; our panel uses the
-- same three columns for every setting and supports enabled/disabled resets.
local function update_reset_buttons(player)
  local dlg=player.gui.screen[PREFS]
  local window=dlg and dlg.valid and dlg.pqt_window
  local content=window and window.pqt_content
  local opts=content and content.pqt_options
  if not opts then return end
  local draft=state(player)
  local any_changed=(draft.position~=nil)
  for key,default in pairs(DEFAULTS) do
    local changed=(draft[key]~=default)
    if changed then any_changed=true end
    -- Vertical mode enforces no title. Resetting title individually cannot
    -- override the selected orientation, so avoid a misleading active reset.
    local reset=opts["pqt_reset_"..key]
    if reset and reset.valid then
      reset.enabled=(changed and (key~="show_title" or not draft.vertical))
    end
  end
  local pos_reset=opts.pqt_reset_position
  if pos_reset and pos_reset.valid then pos_reset.enabled=(draft.position~=nil) end
  local all=content.pqt_actions and content.pqt_actions.pqt_reset_all
  if all and all.valid then all.enabled=any_changed end
end
local function add_option_label(table_gui,key)
  local title=table_gui.add{type="label",name="pqt_label_"..key,caption={"pqt."..key}}
  title.style.minimal_width=LABEL_WIDTH
  title.style.maximal_width=LABEL_WIDTH
  title.style.single_line=true
  return title
end
local function option_container(table_gui,key)
  local flow=table_gui.add{type="flow",name="pqt_control_"..key,direction="horizontal"}
  flow.style.width=CONTROL_WIDTH
  flow.style.horizontal_spacing=6
  flow.style.vertical_align="center"
  return flow
end
local function add_slider(table_gui,key,value)
  add_option_label(table_gui,key)
  local flow=option_container(table_gui,key)
  local rng=SLIDERS[key]
  local s=flow.add{type="slider",name="pqt_slide_"..key,
    minimum_value=rng[1],maximum_value=rng[2],value=value,
    value_step=1,discrete_values=true,tags={pqt_action="adjust",key=key}}
  s.style.width=156
  local value_label=flow.add{type="label",name="pqt_value_"..key,caption=tostring(value)}
  value_label.style.width=32
  value_label.style.horizontal_align="center"
  add_reset(table_gui,key)
end
local function add_checkbox(table_gui,key,value)
  add_option_label(table_gui,key)
  local flow=option_container(table_gui,key)
  flow.add{type="checkbox",name="pqt_checkbox_"..key,state=value,caption="",
    tags={pqt_action="toggle",key=key}}
  add_reset(table_gui,key)
end
local function add_orientation(table_gui,vertical)
  add_option_label(table_gui,"vertical")
  local picker=table_gui.add{type="drop-down",name="pqt_orientation",
    items={{"pqt.orientation-horizontal"},{"pqt.orientation-vertical"}},
    selected_index=vertical and 2 or 1,tags={pqt_action="orientation"}}
  picker.style.width=CONTROL_WIDTH
  add_reset(table_gui,"vertical")
end
local function update_axis_labels(player)
  local dlg=player.gui.screen[PREFS]
  local opts=dlg and dlg.valid and dlg.pqt_window.pqt_content and dlg.pqt_window.pqt_content.pqt_options
  if not opts then return end
  local vertical=state(player).vertical
  opts.pqt_label_rows.caption=vertical and {"pqt.rows-vertical"} or {"pqt.rows"}
  opts.pqt_label_cols.caption=vertical and {"pqt.cols-vertical"} or {"pqt.cols"}
end
local function update_title_checkbox(player)
  local dlg=player.gui.screen[PREFS]
  local opts=dlg and dlg.valid and dlg.pqt_window.pqt_content and dlg.pqt_window.pqt_content.pqt_options
  if not opts then return end
  local box=opts.pqt_control_show_title.pqt_checkbox_show_title
  box.enabled=not state(player).vertical
  box.state=state(player).show_title and not state(player).vertical
end
local function update_position_caption(player)
  local dlg=player.gui.screen[PREFS]
  if not dlg or not dlg.valid then return end
  local content=dlg.pqt_window.pqt_content
  local label=content and content.pqt_options and content.pqt_options.pqt_pos_state
  if label and label.valid then
    local p=state(player)
    label.caption=p.position and {"pqt.position-custom"} or
      (p.vertical and {"pqt.position-vertical"} or {"pqt.position-default"})
  end
end
local function show_settings(player)
  destroy(player,PREFS)
  local p=state(player)
  -- Center the whole invisible wrapper, including a transparent footer. The
  -- actual painted dialog therefore starts ABOVE the screen center on the
  -- FIRST frame. Never reposition it a tick later (that produced a jump).
  local dlg=player.gui.screen.add{type="frame",name=PREFS,direction="vertical",
    style="invisible_frame"}
  dlg.auto_center=true
  dlg.style.padding=0
  local window=dlg.add{type="frame",name="pqt_window",direction="vertical"}
  window.style.padding=8
  window.style.minimal_width=SETTINGS_WIDTH
  local title=window.add{type="flow",name="pqt_title",direction="horizontal"}
  title.style.horizontally_stretchable=true
  title.style.vertical_align="center"
  title.add{type="label",caption={"pqt.settings-title"},style="frame_title",ignored_by_interaction=true}
  add_grip(title,dlg)
  local content=window.add{type="flow",name="pqt_content",direction="vertical"}
  content.style.horizontally_stretchable=true
  content.style.vertical_spacing=6
  local intro=content.add{type="label",caption={"pqt.settings-hint"}}
  intro.style.single_line=false
  intro.style.maximal_width=OPTIONS_WIDTH
  local opts=content.add{type="table",name="pqt_options",column_count=3}
  opts.style.width=OPTIONS_WIDTH
  opts.style.horizontal_spacing=COLUMN_GAP
  opts.style.vertical_spacing=4
  add_slider(opts,"size",p.size)
  add_slider(opts,"rows",p.rows)
  add_slider(opts,"cols",p.cols)
  add_slider(opts,"bottom",p.bottom)
  add_orientation(opts,p.vertical)
  add_checkbox(opts,"show_count",p.show_count)
  add_checkbox(opts,"show_title",p.show_title and not p.vertical)
  add_checkbox(opts,"inventory_only",p.inventory_only)
  -- Mirrors the only-controller per-user mod setting, while retaining the
  -- Factorio-native settings entry for compatibility with existing profiles.
  add_checkbox(opts,"only_controller",p.only_controller)
  add_option_label(opts,"position")
  local pos=opts.add{type="label",name="pqt_pos_state",caption=""}
  pos.style.width=CONTROL_WIDTH
  add_reset(opts,"position")
  update_position_caption(player)
  update_axis_labels(player)
  update_title_checkbox(player)
  local actions=content.add{type="flow",name="pqt_actions",direction="horizontal"}
  actions.style.top_margin=10
  actions.style.horizontal_spacing=6
  actions.style.width=OPTIONS_WIDTH
  local all=actions.add{type="button",name="pqt_reset_all",
    caption={"pqt.reset-all"},tags={pqt_action="reset-all"}}
  local save=actions.add{type="button",caption={"pqt.save"},tags={pqt_action="save"}}
  local cancel=actions.add{type="button",caption={"pqt.cancel"},tags={pqt_action="cancel-edit"}}
  -- Exact table width including two inter-column gaps. No overhang.
  all.style.width=170;save.style.width=172;cancel.style.width=170
  local offset=dlg.add{type="empty-widget",name="pqt_center_offset"}
  offset.style.height=44
  offset.style.width=1
  update_reset_buttons(player)
end
local function sync_option(player,key)
  -- Repaint only the modified setting; never recreate/move the settings window.
  local dlg=player.gui.screen[PREFS]
  if not dlg or not dlg.valid then return end
  local opts=dlg.pqt_window.pqt_content.pqt_options
  local d=state(player)
  if SLIDERS[key] then
    local flow=opts["pqt_control_"..key]
    flow["pqt_slide_"..key].slider_value=d[key]
    flow["pqt_value_"..key].caption=tostring(d[key])
  elseif key=="vertical" then
    opts.pqt_orientation.selected_index=d.vertical and 2 or 1
    update_axis_labels(player)
    update_title_checkbox(player)
  elseif TOGGLES[key] then
    local check=opts["pqt_control_"..key]["pqt_checkbox_"..key]
    check.state=d[key]
  end
  if key=="vertical" or key=="show_title" then update_title_checkbox(player) end
  update_position_caption(player)
  update_reset_buttons(player)
end
local function start_edit(player)
  local p=saved(player)
  p.draft=copy_state(p)
  p.active_picker=nil
  build(player)
  show_settings(player)
end
local function finish_edit(player,commit)
  local p=saved(player)
  if p.draft and commit then
    for k in pairs(DEFAULTS) do p[k]=p.draft[k] end
    p.position=p.draft.position
  end
  p.draft=nil
  p.active_picker=nil
  destroy(player,PREFS)
  if commit then
    -- Keep the engine's three per-player settings synchronized with the
    -- in-game editor. Factorio itself still controls their native UI.
    for setting,key in pairs({["pqt-size"]="size",["pqt-rows"]="rows",
        ["pqt-only-controller"]="only_controller"}) do
      local previous=player.mod_settings[setting]
      if previous and previous.value~=p[key] then
        player.mod_settings[setting]={value=p[key]}
      end
    end
  end
  -- Native item picker is part of Factorio and needs no separate GUI.
  build(player)
  if commit then player.print({"pqt.saved"}) end
end

local function set_slot(player,row,col,slot)
  local ok,err=pcall(function() player.set_quick_bar_slot(page_for(player,row),col,slot) end)
  if not ok then log("[PQT] failed to set quickbar slot: "..tostring(err));player.print({"pqt.slot-error"}) end
  return ok
end
local function select_item(player,name,quality)
  local prototype=prototypes.item[name]
  if not prototype then return false end
  local cur=player.cursor_stack
  local ghost=player.cursor_ghost
  if (cur and cur.valid_for_read and cur.name==name and quality_name(cur.quality)==quality) or
    (ghost and ghost.name==name and quality_name(ghost.quality)==quality) then
    player.clear_cursor()
    return true
  end
  player.clear_cursor()
  local ok,selected=pcall(function() return player.pipette(prototype,quality,true) end)
  if not ok then log("[PQT] pipette: "..tostring(selected)) end
  if not ok or not selected then player.print({"pqt.pick-failed"});return false end
  return true
end
local function reset_one(player,key)
  local draft=saved(player).draft
  if not draft then return end
  local old_width,old_height=metrics(player)
  if key=="position" then draft.position=nil
  elseif DEFAULTS[key]~=nil then draft[key]=DEFAULTS[key] end
  if key=="bottom" or key=="vertical" then draft.position=nil end
  if draft.vertical then draft.show_title=false end
  local location
  if key=="size" or key=="rows" or key=="cols" then
    location=resized_location(player,old_width,old_height)
  end
  build(player,key=="position" or key=="bottom" or key=="vertical",location)
  sync_option(player,key)
  if key=="vertical" then sync_option(player,"show_title") end
  -- Deliberately DO NOT recreate PREFS here: it is a separate draggable window.
end

local function reset_page(player,row)
  if not row or row<1 or row>4 then return end
  local p=saved(player)
  p.pages[row]=row
  player.set_active_quick_bar_page(row,row)
  build(player)
end

script.on_event(defines.events.on_gui_click,function(event)
  local el=event.element
  if not el or not el.valid then return end
  local t=el.tags
  if not t or not t.pqt_action then return end
  local player=game.get_player(event.player_index)
  if not player then return end
  local action=t.pqt_action
  if action=="edit" then
    if editing(player) then finish_edit(player,true) else start_edit(player) end
  elseif action=="save" then finish_edit(player,true)
  elseif action=="cancel-edit" then finish_edit(player,false)
  elseif action=="reset-all" then
    local d=saved(player).draft
    if d then for k,v in pairs(DEFAULTS) do d[k]=v end;d.position=nil;build(player,true);show_settings(player) end
  elseif action=="reset-one" then reset_one(player,t.key)
  elseif action=="page" then
    -- One or several short taps always switch pages. A held X maps to a
    -- right-click in Factorio's controller GUI and is handled separately.
    if event.button==defines.mouse_button_type.right then
      reset_page(player,t.row)
    else
      local p=saved(player)
      p.active_picker=nil
      p.pages[t.row]=page_for(player,t.row)%MAX_PAGES+1
      player.set_active_quick_bar_page(t.row,p.pages[t.row])
      build(player)
    end
  elseif action=="slot" then
    if editing(player) and event.button~=defines.mouse_button_type.right then
      -- One tap arms the native editor for this populated slot.  The next
      -- tap opens Factorio's original "Set filter" dialog; we don't draw
      -- any extra quantity labels or change the other cells.
      saved(player).active_picker={row=t.row,col=t.col,page=page_for(player,t.row)}
      build(player)
      return
    end
    if event.button==defines.mouse_button_type.right then
      if set_slot(player,t.row,t.col,nil) then build(player) end
    else
      local slot=player.get_quick_bar_slot(page_for(player,t.row),t.col)
      local name,quality=slot_item(slot)
      if name and prototypes.item[name] then
        select_item(player,name,quality or "normal");refresh(player)
      else player.print({"pqt.special"}) end
    end
  end
end)
-- A native choose-elem-button opens the built-in Factorio filter picker on
-- the FIRST tap. Its category tabs and the Other category are not recreated.
script.on_event(defines.events.on_gui_elem_changed,function(event)
  local el=event.element
  if not el or not el.valid or el.type~="choose-elem-button" then return end
  local t=el.tags
  if not t or t.pqt_action~="native-slot" then return end
  local player=game.get_player(event.player_index)
  if not player then return end
  local value=el.elem_value
  saved(player).active_picker=nil
  if not value or not value.name then
    if set_slot(player,t.row,t.col,nil) then build(player) end
    return
  end
  local name,quality=value.name,quality_name(value.quality)
  local inv=player.get_main_inventory()
  if state(player).inventory_only and
      (not inv or inv.get_item_count({name=name,quality=quality})<1) then
    player.print({"pqt.inventory-only-warning"})
    local old=player.get_quick_bar_slot(page_for(player,t.row),t.col)
    local old_name,old_quality=slot_item(old)
    el.elem_value=old_name and {name=old_name,quality=old_quality or "normal"} or nil
    return
  end
  if set_slot(player,t.row,t.col,{type="filter",filter={name=name,quality=quality}}) then
    build(player)
  end
end)
-- Pocket Foundry sends controller-X for a long touch in gamepad mode.
-- The hovered page can be reset without treating rapid taps as a hold.
script.on_event(defines.events.on_gui_hover,function(e)
  local el=e.element
  if not el or not el.valid then return end
  local tags=el.tags
  if not tags or tags.pqt_action~="page" then return end
  local p=game.get_player(e.player_index)
  if p then saved(p).hovered_page=tags.row end
end)
script.on_event(defines.events.on_gui_leave,function(e)
  local el=e.element
  if not el or not el.valid then return end
  local tags=el.tags
  if not tags or tags.pqt_action~="page" then return end
  local p=game.get_player(e.player_index)
  if p and saved(p).hovered_page==tags.row then saved(p).hovered_page=nil end
end)
script.on_event("pqt-reset-page-on-hold",function(e)
  local p=game.get_player(e.player_index)
  if not p or not enabled(p) then return end
  local row=saved(p).hovered_page
  if row and p.gui.screen[MAIN] and p.gui.screen[MAIN].valid then
    reset_page(p,row)
  end
end)
script.on_event(defines.events.on_gui_value_changed,function(event)
  local el=event.element
  if not el or not el.valid then return end
  local t=el.tags
  if not t or t.pqt_action~="adjust" or not SLIDERS[t.key] then return end
  local player=game.get_player(event.player_index)
  if not player or not editing(player) then return end
  local d=saved(player).draft
  local old_width,old_height=metrics(player)
  local rng=SLIDERS[t.key]
  local v=clamp(math.floor(el.slider_value+0.5),rng[1],rng[2])
  if d[t.key]==v then return end
  d[t.key]=v
  if t.key=="bottom" then d.position=nil end
  local location
  if t.key=="size" or t.key=="rows" or t.key=="cols" then
    location=resized_location(player,old_width,old_height)
  end
  local dlg=player.gui.screen[PREFS]
  if dlg and dlg.valid then
    local opt=dlg.pqt_window.pqt_content and dlg.pqt_window.pqt_content.pqt_options
    local control=opt and opt["pqt_control_"..t.key]
    local value_label=control and control["pqt_value_"..t.key]
    if value_label and value_label.valid then value_label.caption=tostring(v) end
  end
  build(player,t.key=="bottom",location)
  if t.key=="bottom" then update_position_caption(player) end
  update_reset_buttons(player)
end)
script.on_event(defines.events.on_gui_checked_state_changed,function(event)
  local el=event.element
  if not el or not el.valid then return end
  local t=el.tags
  if not t or t.pqt_action~="toggle" or not TOGGLES[t.key] then return end
  local player=game.get_player(event.player_index)
  if not player or not editing(player) then return end
  local draft=saved(player).draft
  draft[t.key]=el.state
  if t.key=="show_title" or t.key=="inventory_only" or t.key=="only_controller" then build(player)
  else refresh(player) end
  update_reset_buttons(player)
end)
script.on_event(defines.events.on_gui_selection_state_changed,function(event)
  local el=event.element
  if not el or not el.valid then return end
  local player=game.get_player(event.player_index)
  if not player then return end
  if el.name~="pqt_orientation" or not editing(player) then return end
  local d=saved(player).draft
  d.vertical=(el.selected_index==2)
  if d.vertical then d.show_title=false end
  d.position=nil
  build(player,true)
  sync_option(player,"show_title")
  update_title_checkbox(player)
  update_axis_labels(player)
  update_position_caption(player)
  update_reset_buttons(player)
end)
script.on_event(defines.events.on_gui_location_changed,function(event)
  local el=event.element
  if not el or not el.valid or el.name~=MAIN then return end
  local player=game.get_player(event.player_index)
  if not player or not editing(player) then return end
  local p=saved(player)
  local pos=el.location
  if not pos then return end
  if p.programmatic and pos.x==p.programmatic.x and pos.y==p.programmatic.y then
    p.programmatic=nil;return
  end
  p.programmatic=nil
  p.draft.position={x=math.floor(pos.x),y=math.floor(pos.y)}
  update_position_caption(player)
  update_reset_buttons(player)
end)
script.on_event(defines.events.on_gui_closed,function(event)
  local el=event.element
  if not el or not el.valid then return end
  local player=game.get_player(event.player_index)
  if not player then return end
  if el.name==PREFS and editing(player) then finish_edit(player,false) end
end)
script.on_event(defines.events.on_player_set_quick_bar_slot,function(e)
  local p=game.get_player(e.player_index);if p then build(p) end
end)
script.on_event(defines.events.on_player_cursor_stack_changed,function(e)
  local p=game.get_player(e.player_index);if p then refresh(p) end
end)
script.on_event(defines.events.on_player_input_method_changed,function(e)
  local p=game.get_player(e.player_index);if p then build(p) end
end)
script.on_event(defines.events.on_runtime_mod_setting_changed,function(e)
  local p=game.get_player(e.player_index)
  if not p then return end
  local s=saved(p)
  if editing(p) then return end
  local old_width,old_height=metrics(p)
  if e.setting=="pqt-size" then s.size=p.mod_settings["pqt-size"].value
  elseif e.setting=="pqt-rows" then s.rows=p.mod_settings["pqt-rows"].value
  elseif e.setting=="pqt-only-controller" then
    s.only_controller=p.mod_settings["pqt-only-controller"].value
  else return end
  local location
  if e.setting~="pqt-only-controller" then
    location=resized_location(p,old_width,old_height)
  end
  build(p,false,location)
end)
script.on_event({defines.events.on_player_display_resolution_changed,defines.events.on_player_display_scale_changed},function(e)
  local p=game.get_player(e.player_index);if p then build(p) end
end)
script.on_event(defines.events.on_player_created,function(e)
  local p=game.get_player(e.player_index);if p then build(p) end
end)
script.on_event(defines.events.on_player_joined_game,function(e)
  local p=game.get_player(e.player_index);if p then build(p) end
end)
script.on_init(function()
  storage.pqt_players={}
  for _,p in pairs(game.players) do build(p) end
end)
script.on_configuration_changed(function()
  storage.pqt_players=storage.pqt_players or {}
  for _,p in pairs(game.players) do
    local s=saved(p)
    s.draft=nil
    destroy(p,PREFS)
    -- Remove the custom chooser from 0.1.10 when updating an open save.
    destroy(p,"pqt_filter")
    s.picker=nil
    s.active_picker=nil
    -- v0.1.11 had zero header height with the title hidden; the new
    -- transparent reserved row adds 32 GUI px.  Carry older custom
    -- positions upwards once so the physical slots stay where they were.
    if s.position and not s.layout_v12 then
      local old_header=(s.show_title and not s.vertical) and (s.size+4) or 0
      local scale=p.display_scale or 1
      s.position.y=math.max(0,math.floor(s.position.y+(old_header-HEADER_HEIGHT)*scale))
    end
    s.layout_v12=true
    build(p)
  end
end)
script.on_nth_tick(6,function()
  for _,p in pairs(game.connected_players) do
    local ps=saved(p)
    if enabled(p) then
      if needs_rebuild(p) then build(p) else refresh(p) end
    else destroy(p,MAIN) end
  end
end)
