# Shops, weapons, and police

Shop entry is free. A player landing on any SHOP-type tile can buy weapons or
leave without a purchase. Purchases use available cash and never create debt.

| Weapon | Price | Range | Requirement |
| --- | --- | --- | --- |
| Stabber | $40 | Within 5 spaces, forward or backward | Roll a 6 for range; 4–6 on the same tile |
| Pew pew | $95 | Within 10 spaces, forward or backward | Roll a 6 for range; 4–6 on the same tile |

Before moving, a roll of 4, 5 or 6 offers a choice when carrying a weapon and
sharing a tile: move using the roll, or attack one player on that tile instead.
Attacking consumes the move and one weapon. The attacker stays in place.
After movement and landing decisions, a 6 still allows the existing ranged attack. Distance is measured
between current route indices after movement. The player can select one weapon
and one target or end the turn. Both range limits include their boundary.

Using a weapon consumes one copy of that weapon, moves the target's token back
to START, and shows an outcome summary. It does not clear the target's cash,
other inventory, debt, or existing missed-turn penalties. Self-targets and players
already at START are excluded. Only one attack can occur per turn.

An armed player within 3 route spaces of a POLICE tile, in either direction,
is caught. This is checked before dice movement, as dice movement enters the
zone, on new destinations, and immediately after purchasing a weapon. Police
confiscate all stabbers and pew pews, leave other inventory alone, and send the
player to the nearest jail. The existing choice to pay the police fine or miss
one turn then applies. A caught player cannot attack on that turn.

Stars also trigger the three-space police rule. Star arrests impose one missed
turn per carried star and clear all stars. There is no fine alternative for
this sentence. If the player also has weapons, police confiscate them and apply
the star sentence once rather than adding another missed turn.

If a weapon is bought at a shop inside the police zone, the purchase still
costs money and the new weapon is immediately confiscated. This rule is shown
on the shop screen before buying.

Inventory, prices, pending shop visits, pending attacks, arrest decisions, and
acknowledged outcomes are saved with the match. Old saves start with no weapons.
Unfinished animations follow the existing policy: restore the last stable state.
The prices default to $40 and $95 in `domain/weapon.dart` and are retained in
the saved session's `weaponRules` so resumed purchases stay consistent.

Portal glow and rotation freeze while waiting for input and during result screens.
They animate during dice rolls and movement; camera focus and movement still finish normally.
