# Spiral Quest board

The canonical board is `assets/boards/spiral_board_map.json`: 120 ordered tiles, START at 0 and FINISH at 119. Coordinates use a centered 1000-unit square, a 62-unit grid, 50-unit tiles and 12-unit gaps along the route. Parallel rings are 124 units apart. Tile indices determine movement order; layout changes do not change the route.

The game renders vector shapes directly. The SVG and PNG preview are development exports and are not bundled in the app. Regenerate them with `flutter test tools/export_vector_board.dart`. `docs/board_tiles.csv` records coordinates and rule data.

## Tile rules

| Tile | Effect |
| --- | --- |
| Sea | A boat carries you to the first tile beyond the sea and is retained. Without a boat, you drown and restart at START. |
| Boat / antidote / raw meat | Add the indicated quantity to inventory. |
| Snake | An antidote protects you; tiles may consume it. Without one, return to the linked antidote tile and collect an antidote. |
| Lion | Consume one raw meat to stay safe. Otherwise, automatically use one carried health pack to recover and stay on the lion tile; without a pack, become injured and go to hospital. |
| Hospital | Healthy players shop for supplies without a treatment fee. Injured players pay 10 coins, use one carried health pack, or restart at START for free. Treatment heals the injury and opens the hospital shop. Without 10 coins or a health pack, an injured player automatically restarts without debt. |
| Trap door | Miss one future turn. Automatically use one carried health pack to recover and stay on the trap door; without a pack, become injured and go to hospital. |
| Fire | Automatically use one carried health pack to recover and stay on the fire tile; without a pack, become injured and go to hospital. |
| Mine | Red kills and returns you to START even with a health pack. Green automatically uses one health pack to recover here; without one, go to hospital. Broken blue has a 50% chance of death and a 50% chance of the same treatable injury as green. |
| Cash | Add the tile amount to cash. |
| Star | Collect stars and a 25-coin bonus. Carrying stars within three spaces of police causes a jail sentence. |
| Police | Stay at the encounter and choose whether to pay a bribe. Paying avoids jail and adds no missed turn; refusing sends you to the nearest jail and costs one turn. Weapons are confiscated. Carried stars instead impose the mandatory star sentence. |
| Jail | Miss the indicated number of turns. |
| Portal | Choose a mystery card to travel to the closest portal behind or ahead. |
| Confusion | Your next dice move goes backwards. |
| Set back / move forward | Move by the indicated number of spaces. |
| Shop | Optionally buy weapons. See [weapon rules](WEAPONS.md). |
| Event | Reveal and resolve one event card. |
| Finish | An exact roll wins; an overshoot leaves you in place. |

The hospital sells health packs for 10 coins and antidotes for 5 coins. Purchases are optional and use available cash. A carried health pack is automatically consumed after a green mine, a blue mine injury, a lion attack, fire or trap door: it heals the injury immediately and prevents transport to hospital. The trap door still costs one future turn. A pack can also treat an existing injury at hospital. It does not replace an antidote for a snake bite. A carried antidote protects against a snake; without one, the player still returns to the linked antidote tile. Injury status, medical supplies, and pending treatment or shopping choices are saved with the match.

Current portals are 25, 55, 108 and 117. Tile 87 is a snake linked to antidote tile 10; tile 89 grants one star and the standard 25-coin bonus. Confusion tiles are 33, 102 and 118. The final snake is at 99; the following tile 100 is a normal space. Lions occupy 103–106; the former last lion at 107 is now a normal space. Mines occupy 85 (green), 98 (blue) and 109 (red). Tile 78 grants three portions of raw meat. Tiles 110, 111 and 115 are also normal spaces. The source board records its online revision in `onlineBoardId`; rooms on older board revisions require a new match with matching builds.

The app no longer includes a board editor or file import/export. Previously saved custom boards retain their identifiers, supported artwork and rules. One-time migrations apply updated tiles and grid positions while preserving backups. Legacy death and loan tile types remain readable as sea and mine tiles.

Use the standalone [Board Workshop](../tools/board_editor/README.md) to edit the source board locally. Saving creates a backup and a content-based online board ID; it does not build APKs.
