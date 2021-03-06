--lets not wallop player things

local road_network = require("script/road_network")

local real_name = "transport-drone-road"

local road_tiles =
{
  ["transport-drone-road"] = true
}

local tile_proxies =
{
  ["transport-drone-proxy-tile"] = "transport-drone-road"
}

local is_road_tile = function(name)
  return road_tiles[name]
end

local raw_road_tile_built = function(event)

  for k, tile in pairs (event.tiles) do
    local position = tile.position
    road_network.add_node(event.surface_index, position.x, position.y)
  end

end

local can_place_road_tile = function(surface, position)
  return surface.can_place_entity
  {
    name = "road-tile-collision-proxy",
    position = {position.x + 0.5, position.y + 0.5},
    build_check_type = defines.build_check_type.manual
  }
end

local product_amount = util.product_amount
local road_tile_built = function(event, proxy)

  local tiles = event.tiles
  local surface = game.get_surface(event.surface_index)
  local refund_count = 0
  local new_tiles = {}
  local refund_product = {}

  for k, tile in pairs (tiles) do
    local position = tile.position
    if can_place_road_tile(surface, position) then
      new_tiles[k] = {name = proxy, position = position}
      road_network.add_node(event.surface_index, position.x, position.y)
    else
      new_tiles[k] = {name = tile.old_tile.name, position = position}
      refund_count = refund_count + 1
      if tile.old_tile.mineable_properties.minable then
        refund_product[tile.old_tile.name] = (refund_product[tile.old_tile.name] or 0) + 1
      end
    end
  end

  surface.set_tiles(new_tiles, true, false)

  if next(refund_product) then
    -- Remove first, so we make space in the inventory
    local remove_function = (event.player_index and game.get_player(event.player_index).remove_item) or (event.robot and event.robot.get_inventory(defines.inventory.robot_cargo).remove)
    if remove_function then
      local tile_prototypes = game.tile_prototypes
      for tile_name, count in pairs(refund_product) do
        local tile = tile_prototypes[tile_name]
        for k, product in pairs (tile.mineable_properties.products) do
          local count = product_amount(product) * count
          if count > 0 then
            remove_function({name = product.name, count = count})
          end
        end
      end
    end
  end

  if event.item and refund_count > 0 then
    local insert_function = (event.player_index and game.get_player(event.player_index).insert) or (event.robot and event.robot.get_inventory(defines.inventory.robot_cargo).insert)
    if insert_function then
      local inserted = insert_function({name = event.item.name, count = refund_count})
    end
  end

end

local non_road_tile_built = function(event)

  local tiles = event.tiles
  local new_tiles = {}
  local refund_count = 0
  for k, tile in pairs (tiles) do
    if road_network.remove_node(event.surface_index, tile.position.x, tile.position.y) then
      new_tiles[k] = {name = tile.old_tile.name, position = tile.position}
      refund_count = refund_count + 1
    end
  end

  local surface = game.get_surface(event.surface_index)
  surface.set_tiles(new_tiles)


  if event.item then

    if refund_count > 0 then
      if event.player_index then
        local player = game.get_player(event.player_index)
        if player then
          player.insert({name = event.item.name, count = refund_count})
          player.remove_item({name = "road", count = refund_count})
        end
      end
      local robot = event.robot
      if robot then
        robot.get_inventory(defines.inventory.robot_cargo).insert({name = event.item.name, count = refund_count})
        robot.get_inventory(defines.inventory.robot_cargo).remove({name = "road", count = refund_count})
      end
    end

  end

end


local no_tile_text = "You're playing with a naughty mod that isn't raising events properly. Tile is missing from the built tile event."
local broken_now = "The road network will probably be broken now if you were doing anything with road tiles."
local shown = false
local on_built_tile = function(event)

  if not event.tile then
    if game.is_multiplayer() then
      game.print(no_tile_text)
      game.print(broken_now)
    else
      if not shown then
        game.show_message_dialog{text = no_tile_text}
        game.show_message_dialog{text = broken_now}
        shown = true
      end
    end
    return
  end

  if is_road_tile(event.tile.name) then
    raw_road_tile_built(event)
    return
  end

  local proxy = tile_proxies[event.tile.name]

  if proxy then
    road_tile_built(event, proxy)
    return
  end

  non_road_tile_built(event)

end

local text = "You're playing with a naughty mod that isn't raising events properly. Surface index is missing from the tile mined event."
local on_mined_tile = function(event)
  if not event.surface_index then
    if game.is_multiplayer() then
      game.print(text)
      game.print(broken_now)
    else
      if not shown then
        game.show_message_dialog{text = text}
        game.show_message_dialog{text = broken_now}
        shown = true
      end
    end
    return
  end
  local tiles = event.tiles
  local new_tiles = {}
  local refund_count = 0
  for k, tile in pairs (tiles) do
    if is_road_tile(tile.old_tile.name) then
      if road_network.remove_node(event.surface_index, tile.position.x, tile.position.y) then
        --can't remove this tile, supply or requester is there.
        new_tiles[k] = {name = tile.old_tile.name, position = tile.position}
        refund_count = refund_count + 1
      end
    end
  end
  local surface = game.get_surface(event.surface_index)
  surface.set_tiles(new_tiles)

  if refund_count > 0 then
    if event.player_index then
      local player = game.get_player(event.player_index)
      if player then
        player.remove_item({name = "road", count = refund_count})
      end
    end
    local robot = event.robot
    if robot then
      robot.get_inventory(defines.inventory.robot_cargo).remove({name = "road", count = refund_count})
    end
  end

end

local script_raised_set_tiles = function(event)
  local surface = game.get_surface(event.surface_index)
  if not event.tiles then return end
  local new_tiles = {}
  for k, tile in pairs (event.tiles) do
    if is_road_tile(tile.name) then
      road_network.add_node(event.surface_index, tile.position.x, tile.position.y)
    else
      local proxy = tile_proxies[tile.name]
      if proxy then
        if can_place_road_tile(surface, tile.position) then
          new_tiles[k] = {name = proxy, position = tile.position}
          road_network.add_node(event.surface_index, tile.position.x, tile.position.y)
        else
          new_tiles[k] = {name = surface.get_hidden_tile(tile.position) or "grass-1", position = tile.position}
        end
      else
        if road_network.remove_node(event.surface_index, tile.position.x, tile.position.y) then
          --can't remove this tile, depot is here.
          new_tiles[k] = {name = "transport-drone-road", position = tile.position}
        end
      end
    end
  end
  surface.set_tiles(new_tiles)
end

local lib = {}

lib.events =
{
  [defines.events.on_player_built_tile] = on_built_tile,
  [defines.events.on_robot_built_tile] = on_built_tile,

  [defines.events.on_player_mined_tile] = on_mined_tile,
  [defines.events.on_robot_mined_tile] = on_mined_tile,

  [defines.events.script_raised_set_tiles] = script_raised_set_tiles

}

return lib