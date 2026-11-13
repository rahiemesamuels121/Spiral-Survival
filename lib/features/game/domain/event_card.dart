/// Proposed (not official) event-card rules for the reference board.
/// Cards are data-only so the game controller can be tested without Flame.
enum EventEffect {
  receiveCash,
  payFine,
  forward,
  backward,
  skipTurn,
  repayDebt,
}

class EventCard {
  const EventCard({
    required this.id,
    required this.title,
    required this.description,
    required this.effect,
    required this.value,
  });

  final String id;
  final String title;
  final String description;
  final EventEffect effect;
  final int value;
}

abstract final class EventCards {
  static const List<EventCard> all = [
    EventCard(
      id: 'cash_30',
      title: 'LUCKY BREAK',
      description: 'A surprise prize! Collect \$30.',
      effect: EventEffect.receiveCash,
      value: 30,
    ),
    EventCard(
      id: 'cash_50',
      title: 'BIG WIN',
      description: 'You won the game-night jackpot! Collect \$50.',
      effect: EventEffect.receiveCash,
      value: 50,
    ),
    EventCard(
      id: 'fine_20',
      title: 'UNEXPECTED BILL',
      description: 'An unexpected bill arrives. Pay \$20.',
      effect: EventEffect.payFine,
      value: 20,
    ),
    EventCard(
      id: 'fine_10',
      title: 'PARKING TICKET',
      description: 'Pay a \$10 penalty.',
      effect: EventEffect.payFine,
      value: 10,
    ),
    EventCard(
      id: 'forward_3',
      title: 'FAST TRACK',
      description: 'Move forward 3 additional spaces.',
      effect: EventEffect.forward,
      value: 3,
    ),
    EventCard(
      id: 'backward_2',
      title: 'ROADBLOCK',
      description: 'Move back 2 spaces.',
      effect: EventEffect.backward,
      value: 2,
    ),
    EventCard(
      id: 'skip_1',
      title: 'TAKE A BREAK',
      description: 'Miss your next turn.',
      effect: EventEffect.skipTurn,
      value: 1,
    ),
    EventCard(
      id: 'debt_25',
      title: 'DEBT RELIEF',
      description: 'Reduce your outstanding debt by up to \$25.',
      effect: EventEffect.repayDebt,
      value: 25,
    ),
  ];

  static EventCard byId(String id) {
    for (final card in all) {
      if (card.id == id) return card;
    }
    throw FormatException('Unknown event card: $id');
  }
}
