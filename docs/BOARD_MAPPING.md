# Spiral Quest board

The canonical board is `assets/boards/spiral_board_map.json`: 120 ordered tiles, START at 0 and FINISH at 119. Coordinates use a centered 1000-unit square, a 62-unit grid, 50-unit tiles and 12-unit gaps along the route. Parallel rings are 124 units apart. Tile indices determine movement order; layout changes do not change the route.

The game renders vector shapes directly. The SVG and PNG preview are development exports and are not bundled in the app. Regenerate them with `flutter test tools/export_vector_board.dart`. `docs/board_tiles.csv` records coordinates and rule data.

## Tile rules

| Tile | Effect |
| --- | --- |
| Sea | A boat carries you to the first tile beyond the sea and is retained. Without a boat, you drown and restart at START. |
| Boat / antidote / raw meat | Add the indicated quantity to inventory. |
| Snake | An antidote protects you; tiles may consume it. Without one, return to the linked antidote tile and collect an antidote. |
| Lion | Consume one raw meat to stay safe; otherwise go to hospital. |
| Hospital | Pay 10 coins to stay, or restart at START for free. Fewer than 10 coins causes an automatic restart without debt. |
| Trap door | Miss one future turn and go to hospital. |
| Fire | Go to hospital. |
| Mine | You die and restart at START. |
| Cash | Add the tile amount to cash. |
| Star | Collect stars and a 25-coin bonus. Carrying stars within three spaces of police causes a jail sentence. |
| Police | Go to the nearest jail. Choose a fine or a missed turn, subject to contraband rules. |
| Jail | Miss the indicated number of turns. |
| Portal | Choose a mystery card to travel to the closest portal behind or ahead. |
| Confusion | Your next dice move goes backwards. |
| Set back / move forward | Move by the indicated number of spaces. |
| Shop | Optionally buy weapons. See [weapon rules](WEAPONS.md). |
| Event | Reveal and resolve one event card. |
| Finish | An exact roll wins; an overshoot leaves you in place. |

Current portals are 25, 55, 87, 108 and 117. Confusion tiles are 33, 102 and 118. Mines occupy 98–101, 109 and 110. Tiles 111 and 115 are normal spaces.

The app no longer includes a board editor or file import/export. Previously saved custom boards retain their identifiers, supported artwork and rules. One-time migrations apply updated tiles and grid positions while preserving backups. Legacy death and loan tile types remain readable as sea and mine tiles.
