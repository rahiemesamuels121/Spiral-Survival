import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../game/domain/board_definition.dart';
import 'tile_guide.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({this.board, super.key});
  final BoardDefinition? board;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _query = '';

  Widget _card(String title, String body, {String? spaces}) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: AppTheme.panel,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppTheme.gold,
            ),
          ),
          const SizedBox(height: 8),
          Text(body),
          if (spaces != null) ...[
            const SizedBox(height: 10),
            Text(
              spaces,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final types = TileType.values.where((type) {
      final entry = tileGuide(type);
      return '${entry.title} ${entry.description}'.toLowerCase().contains(
        _query.trim().toLowerCase(),
      );
    }).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HOW TO PLAY'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'PLAY GUIDE'),
              Tab(text: 'TILE GUIDE'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              key: const PageStorageKey('how-to-play'),
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  '1. Choose a mode',
                  'Choose PASS & PLAY, VS COMPUTER or ONLINE on the main menu. Local modes lead to a separate screen for player counts, names and avatars; Online opens room and character selection. Pass & Play: 2–5 people share one device and pass it when prompted. VS Computer: one human plays against 1–4 computer opponents offline. Computers roll and make their own choices. Online: create or join a private room for 2–5 players, each using their own device; the host must stay connected.',
                ),
                _card(
                  'Choose a character before starting',
                  'There are only three choices. CAT WHISPERER (paw): pass lions without raw meat, health kits or injury. SECRET AGENT (badge): add 3 spaces to weapon range (Stabber 8, Pew pew 13) access Secret Society from up to 3 route spaces away before rolling or after landing nearby, and save \$50 on every Secret Society purchase, including the hitman at \$150. SWIMMER (pool): survive water and surf without a boat. Local players choose their avatars on the separate player setup screen after selecting a mode; online players choose in the lobby before the host starts. Characters stay locked throughout the match. Older saves can retain cosmetic avatars without these new class abilities.',
                ),
                _card(
                  '2. Follow the spiral',
                  'Everyone starts at START with \$10. Roll the die, follow the numbered route and resolve the space where you land. The first player to reach FINISH wins. You need an exact roll: an overshoot leaves you in place.',
                ),
                _card(
                  '3. Resolve your turn',
                  'Normal spaces finish without a result popup. For special effects, read the result and tap CONTINUE. Some spaces ask you to buy supplies, choose treatment, pay a bribe or pick a portal card. Purchases are optional. Finish each choice to continue. Missed turns are skipped automatically. In VS Computer, opponents play and close their own result cards automatically.',
                ),
                _card(
                  '4. Manage your supplies',
                  'Boats protect against sea spaces; antidotes protect against snakes; raw meat feeds lions. Health kits automatically heal treatable injuries, but cannot stop drowning or a lethal mine. Open Players and inventory to inspect your own cash, debt and supplies. Fines can create debt; purchases and bribes require enough cash.',
                ),
                _card(
                  '5. Weapons and attacks',
                  'Secret Agents can access Secret Society from up to 3 route spaces away before rolling or after landing nearby; other characters must land on its tile. After landing in range, tap the labeled SECRET SOCIETY button to hire, or END TURN to skip. No normal-tile result popup is shown. Hire an anonymous hitman through the Secret Society button. Stabbers reach 5 route spaces and Pew pews reach 10; Secret Agents extend those ranges to 8 and 13. On a roll of 4, 5 or 6, you may attack someone on your own space instead of moving. On a 6, you may attack a target in weapon range from your current space instead of moving. Choose before movement: one roll can buy either an attack or a move, never both. Newly bought weapons cannot attack after that turn’s movement. A hitman kill also ends your turn without movement; a contract hired after landing can be used before rolling on a later turn. A weapon attack uses one weapon, sends the target to START and awards 3 stars with no cash. Police within 3 spaces confiscate weapons; carrying stars there causes a jail sentence.',
                ),
                _card(
                  '6. Explore and save',
                  'Drag to pan, pinch or use +/− to zoom, fit the board to the screen, and use Focus current player to find the active token. Long-press a tile for its label. Portrait and landscape are supported. Local games save automatically; CONTINUE SAVED GAME restores the match, including computer opponents and hospital refill times. Open Help from the menu or Players and inventory; local computer turns pause while Help is open.',
                ),
                _card(
                  'Every tile explained',
                  'Open TILE GUIDE to search all tile effects, including the three mine colors, hospital stock and Secret Society contracts. When available, each entry lists matching spaces on your current board. Space amounts, supply counts, prices and linked destinations follow the board and match you are playing.',
                ),
              ],
            ),
            CustomScrollView(
              key: const PageStorageKey('tile-guide'),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        labelText: 'Search tiles',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                ),
                if (types.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No matching tiles.')),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList.builder(
                      itemCount: types.length,
                      itemBuilder: (context, index) {
                        final type = types[index];
                        final entry = tileGuide(type);
                        final spaces = widget.board?.tiles
                            .where((tile) => tile.type == type)
                            .map((tile) => tile.index)
                            .toList();
                        return _card(
                          entry.title,
                          entry.description,
                          spaces: spaces == null || spaces.isEmpty
                              ? null
                              : 'Spaces: ${spaces.join(', ')}',
                        );
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
