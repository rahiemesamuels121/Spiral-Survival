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
The attack screen shows available weapons with owned counts, ranges, and target
buttons. On smaller screens, scroll to reach additional targets or the move/end
turn button.

Using a weapon consumes one copy of that weapon, moves the target's token back
to START, and shows an outcome summary. It does not clear the target's cash,
other inventory, debt, or existing missed-turn penalties. Self-targets and players
already at START are excluded. Only one attack can occur per turn.

Each successful attack awards the attacker three stars and no cash. This reward
is separate from landing on a STAR tile, which still grants its cash bonus.
The new stars are subject to the normal police rule.

An armed player within 3 route spaces of a POLICE tile, in either direction,
is caught. This is checked before dice movement, as dice movement enters the
zone, on new destinations, and immediately after purchasing a weapon. Police
confiscate all stabbers and pew pews and leave other inventory alone. A caught
player cannot attack on that turn.

For a direct POLICE landing or a weapon-only encounter, the player stays on the
police tile or at the point where police stopped them while choosing whether to
pay a bribe. The bribe uses the police tile's amount, or 20 coins when no amount
is set. Paying leaves the player there, avoids jail, and adds no missed turn.
Refusing moves the player to the nearest jail and adds one missed turn. A bribe
requires available cash and never creates debt.

Stars also trigger the three-space police rule. Players carrying stars go
directly to the nearest jail, miss one turn per carried star, and clear all
stars. This sentence has no bribe option. If the player also has weapons,
police confiscate them and apply the star sentence once rather than adding
another missed turn.

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
