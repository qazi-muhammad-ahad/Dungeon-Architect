import 'package:flutter/material.dart';

/// Original hand-authored pixel sprites. These affect presentation only.
class DungeonPixels {
  static const voidColor = Color(0xff171921);
  static const floor = Color(0xff535d60);
  static const floorLight = Color(0xff78817c);
  static const wall = Color(0xff303943);
  static const wallLight = Color(0xff77818c);
  static const door = Color(0xffb3814d);
  static const entrance = Color(0xff80dcb3);
  static const exit = Color(0xffc4a5f1);
  static const encounter = Color(0xffffce79);

  static const _colors = {
    '#': Color(0xff161922),
    'm': Color(0xff8a9cab),
    'h': Color(0xffdce7d9),
    'd': Color(0xff445362),
    's': Color(0xffd8a776),
    'l': Color(0xff79503b),
    'g': Color(0xff446b4c),
    'G': Color(0xff9fbe69),
    'b': Color(0xff477b9b),
    'r': Color(0xffa44c49),
    'o': Color(0xffe7773e),
    'y': Color(0xffffce79),
    'p': Color(0xff9874c5),
    'w': Color(0xffd8ccad),
  };
  static const _sprites = {
    'player': [
      '.....#####......',
      '....#bbbbb#.....',
      '...#bhbbbbh#....',
      '...#bbbssbb#....',
      '....#s#ss#s#....',
      '.....#ssss#..h..',
      '...###bbbb###h..',
      '..#bl#bbbb#lhh#.',
      '..#sl#bbbb#l#h..',
      '...##llllll##m..',
      '....#blhhlb#.m..',
      '....#bbbbbb#....',
      '....#ll##ll#....',
      '....#ll##ll#....',
      '...#lll##lll#...',
      '...#####.####...',
    ],
    'archer': [
      '.....#####......',
      '....#ggggg#.....',
      '...#gGggGgg#....',
      '...#ggsssgg#....',
      '....#s#s#s#..l..',
      '.....#sss#..l.l.',
      '...###ggg###l..l',
      '..#gl#ggg#sl...l',
      '..#sl#ggg#s#lhhl',
      '...##lllll##l..l',
      '....#ggggg#..l.l',
      '....#glglg#...l.',
      '....#ll#ll#.....',
      '....#ll#ll#.....',
      '...#lll#lll#....',
      '...####.####....',
    ],
    'guard': [
      '.....#####......',
      '....#mmhmm#.....',
      '...#mmmhmmm#....',
      '...#d######d#...',
      '....#sysys#.....',
      '.....#sss#..h...',
      '...###mdm###h...',
      '..#rr#mmmh#mhh#.',
      '.#rrrr#mmm#d#h..',
      '.#ryrr#lll##dm..',
      '.#rryr#mmh#..m..',
      '..#rr#mmmmm#....',
      '...###dd#dd#....',
      '....#dd##dd#....',
      '...#mmm##mmm#...',
      '...#####.####...',
    ],
    'ogre': [
      '..h..######..h..',
      '..#h#GGGGGG#h#..',
      '...#GggGGggG#...',
      '..#GG#yGGy#GG#..',
      '..#GGggGGggGG#..',
      '...#Ghh##hhG#...',
      '..###GllllG###..',
      '.#GGG#llll#GGG#.',
      '#GGGG#lrrl#GGGG#',
      '#GGG##llll##GGG#',
      '.###.#llll#.###.',
      '....#GllllG#....',
      '...#GGG##GGG#...',
      '...#GGG##GGG#...',
      '..#llll##llll#..',
      '..#####..#####..',
    ],
    'lava': [
      '........y.......',
      '.......#y#......',
      '....o..#yo#.....',
      '....#o#yyo#.....',
      '...#oyyyoy#.....',
      '..#oyyyhyyoo#...',
      '..#oyyhhhyyo#...',
      '.#oyyhhhhhyy#...',
      '.#oyy#hhy#yy#...',
      '.#oyyyhhyyyoo#..',
      '..#oyyhhyyyo#...',
      '..#ooyyyyoo#....',
      '...#oooooo#.....',
      '....#opp#o#.....',
      '.....#ppp#......',
      '......###.......',
    ],
    'encounter': [
      '.....#####......',
      '....#wwwww#.....',
      '...#wwhwhww#....',
      '...#w##w##w#....',
      '...#www#www#....',
      '....#w#w#w#.....',
      '.....#www#......',
      '..####w#w####...',
      '.#w#.#www#.#w#..',
      '.#w#.#w#w#.#w#..',
      '..##.#www#.##...',
      '.....#lll#......',
      '....#ww#ww#.....',
      '....#ww#ww#.....',
      '...#www#www#....',
      '...####.####....',
    ],
    'door': [
      '....########....',
      '...#mmhhhhmm#...',
      '..#mh######hm#..',
      '.#mh#llllll#hm#.',
      '.#m#llhllhll#m#.',
      '.#m#llhllhll#m#.',
      '.#m#dddddddd#m#.',
      '.#m#llhllhll#m#.',
      '.#m#llhllhyl#m#.',
      '.#m#llhllhll#m#.',
      '.#m#dddddddd#m#.',
      '.#m#llhllhll#m#.',
      '.#m#llhllhll#m#.',
      '.#m#llllllll#m#.',
      '.#mm########mm#.',
      '..############..',
    ],
    'entrance': [
      '....########....',
      '...#mmmmmmmm#...',
      '..#mm######mm#..',
      '..#m#gggggg#m#..',
      '..#m#ggGGgg#m#..',
      '..#m#gGhhGg#m#..',
      '..#m#ggGGgg#m#..',
      '..#m#gggggg#m#..',
      '..#m#gggggg#m#..',
      '..#m#gggggg#m#..',
      '..#m#gggggg#m#..',
      '..#m#gggggg#m#..',
      '..#m#gggggg#m#..',
      '..#m########m#..',
      '..#mmmmmmmmmm#..',
      '...##########...',
    ],
    'exit': [
      '................',
      '......######....',
      '.....#pppppp#...',
      '....#pphhhhpp#..',
      '....#ph####hp#..',
      '....#p#....#p#..',
      '....#p#....#p#..',
      '....#p#....#p#..',
      '...##p######p##.',
      '..#mmmmmmmmmmmm#',
      '..##############',
      '.#mmmmmmmmmmmmm#',
      '.###############',
      '#mmmmmmmmmmmmmm#',
      '################',
      '................',
    ],
  };

  static String encounterKind(Map actor, Map? source) {
    final custom = source?['packs'] as List? ?? const [];
    final packs = custom.isEmpty
        ? source?['template_catalogue']?['packs'] as List? ?? const []
        : custom;
    final pack = packs.where((p) => p['id'] == actor['pack_id']).firstOrNull;
    final name = (pack?['name'] ?? '').toString().toLowerCase();
    if (name.contains('ogre') || name.contains('boss')) return 'ogre';
    if (name.contains('archer')) return 'archer';
    if (name.contains('guard')) return 'guard';
    if (name.contains('lava') || name.contains('spirit')) return 'lava';
    return 'encounter';
  }

  static Rect snap(Rect r, double dpr) => Rect.fromLTRB(
    (r.left * dpr).round() / dpr,
    (r.top * dpr).round() / dpr,
    (r.right * dpr).round() / dpr,
    (r.bottom * dpr).round() / dpr,
  );

  static void motif(
    Canvas canvas,
    Rect r,
    String kind,
    double dpr, {
    int variant = 0,
  }) {
    final paint = Paint()..isAntiAlias = false;
    void block(double x, double y, double w, double h, Color color) {
      paint.color = color;
      canvas.drawRect(
        snap(
          Rect.fromLTWH(
            r.left + x * r.width / 16,
            r.top + y * r.height / 16,
            w * r.width / 16,
            h * r.height / 16,
          ),
          dpr,
        ),
        paint,
      );
    }

    if (kind == 'floor') {
      if (r.width < 8) return;
      block(0, 0, 16, 1, voidColor.withValues(alpha: .32));
      block(0, 8, 16, 1, voidColor.withValues(alpha: .32));
      block(variant.isEven ? 4 : 11, 0, 1, 8, voidColor.withValues(alpha: .32));
      block(variant.isEven ? 12 : 3, 8, 1, 8, voidColor.withValues(alpha: .32));
      block(1, 1, 13, 1, floorLight.withValues(alpha: .55));
      block(2, 10, 10, 1, floorLight.withValues(alpha: .4));
      if (variant % 7 == 0) block(7, 4, 2, 1, const Color(0xff889a77));
      return;
    }
    if (kind == 'wall') {
      if (r.width < 8) return;
      block(0, 0, 16, 3, wallLight);
      block(0, 3, 16, 1, voidColor);
      block(0, 9, 16, 1, voidColor);
      block(7, 4, 1, 5, voidColor);
      block(3, 10, 1, 6, voidColor);
      block(13, 10, 1, 6, voidColor);
      block(1, 5, 5, 1, wallLight.withValues(alpha: .45));
      if (variant % 17 == 0) {
        block(5, 4, 5, 8, voidColor);
        block(7, 8, 2, 6, door);
        block(6, 5, 4, 4, const Color(0xffe7773e));
        block(7, 4, 2, 4, encounter);
      }
      return;
    }
    final rows = _sprites[kind] ?? _sprites['encounter']!;
    final minimum = kind == 'door' || kind == 'entrance' || kind == 'exit'
        ? 5.0
        : 9.0;
    final size = r.shortestSide.clamp(minimum, 40.0).toDouble();
    r = Rect.fromCenter(center: r.center, width: size, height: size);
    if (kind != 'door' && kind != 'entrance' && kind != 'exit') {
      block(3, 14, 10, 2, voidColor.withValues(alpha: .65));
    }
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      for (var x = 0; x < row.length; x++) {
        final key = row[x];
        if (key == '.') continue;
        final start = x;
        while (x + 1 < row.length && row[x + 1] == key) {
          x++;
        }
        block(
          start.toDouble(),
          y.toDouble(),
          (x - start + 1).toDouble(),
          1,
          _colors[key]!,
        );
      }
    }
  }
}
