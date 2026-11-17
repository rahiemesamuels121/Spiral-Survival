import '../game/domain/board_definition.dart';

/// Kept exhaustive so every supported board effect has an explanation.
({String title, String description}) tileGuide(TileType type) => switch (type) {
  TileType.start => (
    title: 'Start',
    description:
        'Everyone begins here. Drowning, lethal mines and successful attacks return a player here. Returning to START does not erase their entire inventory.',
  ),
  TileType.normal => (
    title: 'Normal space',
    description:
        'No special effect and no landing-result popup. Decorative labels and illustrations on normal spaces do not add extra rules.',
  ),
  TileType.surf => (
    title: 'Surf',
    description:
        'A water hazard. Swimmers cross safely without a boat. Other characters need a boat or drown and return to START. A boat or swimming carries you to the first space after the water.',
  ),
  TileType.sea => (
    title: 'Sea',
    description:
        'Unless you are a Swimmer, without a boat you drown, return to START and end your turn. With a boat, sail to the first space after the sea. You keep the boat.',
  ),
  TileType.boat => (
    title: 'Boat',
    description:
        'Collect the displayed number of boats. A boat protects you when landing in the sea and is reusable.',
  ),
  TileType.antidote => (
    title: 'Antidote',
    description:
        'Collect antidotes to protect against snakes. They remain in your inventory unless a snake space explicitly consumes one.',
  ),
  TileType.rawMeat => (
    title: 'Raw meat',
    description:
        'Collect the displayed number of portions. Feeding a lion uses one portion.',
  ),
  TileType.lion => (
    title: 'Lion',
    description:
        'Cat Whisperers pass safely without consuming anything. Other characters use one raw meat to stay safe. Without meat, you are injured: a carried health kit is used automatically to recover here. Without a kit, go to the linked hospital.',
  ),
  TileType.snake => (
    title: 'Snake',
    description:
        'An antidote protects you. Without one, return to the linked antidote space and collect its antidote. Some boards consume an antidote when it protects you.',
  ),
  TileType.cash => (
    title: 'Cash',
    description:
        'Add the amount shown on the space to your cash. Spend cash on treatment, supplies, weapons, bribes or a hitman contract.',
  ),
  TileType.police => (
    title: 'Police',
    description:
        'Landing here offers a bribe (normally \$20) to stay, or jail and one missed turn. Carrying weapons or stars within 3 route spaces also triggers police, even while passing. Weapons are confiscated. Stars send you to jail for one missed turn per star, then clear; that sentence cannot be bribed away.',
  ),
  TileType.fine => (
    title: 'Fine',
    description:
        'Pay the amount on the space (normally \$20). If cash is insufficient, unpaid fines become debt; cash never goes below zero.',
  ),
  TileType.jail => (
    title: 'Jail',
    description:
        'Miss the number of turns specified by the space, normally one. Arrests for carrying stars instead use one missed turn per star. The game automatically skips missed turns.',
  ),
  TileType.goToJail => (
    title: 'Go to jail',
    description: 'Move to the linked jail and receive its missed-turn penalty.',
  ),
  TileType.mine => (
    title: 'Mines: red, blue and green',
    description:
        'RED: a lethal explosion returns you to START and ends your turn; health kits cannot prevent death. BLUE: an equal chance of death or injury. GREEN: injury. For a treatable injury, a carried kit is used automatically so you stay here; without one, go to the linked hospital.',
  ),
  TileType.portal => (
    title: 'Mystery portal',
    description:
        'Pick one of two hidden cards. One sends you to the nearest portal behind you, the other to the nearest ahead. The cards are shuffled. If no portal exists in that direction, use the opposite direction; stay here only if there is no other portal. Portal travel does not trigger another portal choice.',
  ),
  TileType.setBack => (
    title: 'Go back',
    description:
        'Move backwards by the number shown (normally 3), stopping at START if necessary. Resolve effects at the destination; police can intercept you along the route.',
  ),
  TileType.moveForward => (
    title: 'Move forward',
    description:
        'Advance by the number shown (normally 2), then resolve the destination. You cannot move beyond FINISH; if the whole move would overshoot it, stay here.',
  ),
  TileType.shop => (
    title: 'Weapon shop',
    description:
        'Entry is free and purchases are optional. Buy a Stabber or Pew pew at the displayed price. Keep purchased weapons until used or confiscated. Nearby police can immediately arrest an armed player.',
  ),
  TileType.event => (
    title: 'Event card',
    description:
        'Draw and apply a card: gain cash, pay a fine, move, miss a turn or reduce debt. Read the result and continue. Used cards are reshuffled when the draw pile runs out.',
  ),
  TileType.confusion => (
    title: 'Confusion',
    description:
        'Your next dice move goes backwards instead of forwards. After that move, normal forward movement resumes.',
  ),
  TileType.star => (
    title: 'Star',
    description:
        'Collect the displayed stars and a \$25 bonus. Stars are risky: entering within 3 route spaces of police sends you to jail for one missed turn per star.',
  ),
  TileType.hospital => (
    title: 'Hospital',
    description:
        'Healthy visitors pay no entry fee. Injured visitors pay \$10, use a carried health kit, or recover at START for free. Health kits cost \$10 and antidotes \$5. Each hospital starts with 2 kits and generates 1 every 5 real minutes without a stock limit, including time away from a saved game. Players share that hospital’s stock. Sold-out kits cannot be bought; antidotes and paid treatment remain available.',
  ),
  TileType.secretSociety => (
    title: 'Secret Society',
    description:
        'Land on Secret Society to hire. Secret Agents can also access it from up to 3 route spaces away in either direction, before rolling or after landing nearby, using the labeled Secret Society button. After landing, choose to hire or tap END TURN without a normal-tile popup. Hire the single hitman for \$200 (\$150 for Secret Agents) and choose any numbered space for him. Only the hirer sees his marker and contract. Before rolling on your turn, choose an opponent within 20 route spaces of the hitman in either direction. A kill ends the hirer’s turn without movement, returns the target to START, awards no cash or stars, and releases the hitman for a new hire. If you already moved to Secret Society this turn, keep the contract and choose a target before rolling on a later turn. His placement stays fixed until the kill. Online hosts hold the authoritative game state and can inspect contracts.',
  ),
  TileType.fire => (
    title: 'Fire',
    description:
        'You are injured. A carried health kit is used automatically so you recover here. Without a kit, go to the linked hospital for treatment.',
  ),
  TileType.trapDoor => (
    title: 'Trap door',
    description:
        'Miss one turn and become injured. A carried health kit lets you recover here, but you still miss the turn. Without a kit, go to the linked hospital.',
  ),
  TileType.finish => (
    title: 'Finish',
    description:
        'The first player to reach FINISH wins. You need an exact roll: if your dice would carry you beyond it, stay on your current space and try again on your next turn.',
  ),
};
