import 'package:fluentui_emoji_icon/fluentui_emoji_icon.dart';

class AnimalData {
  // 🔥 TOP 3 LOCKED: 1st=Lion, 2nd=Tiger, 3rd=Elephant (NEVER change)
  /*
   🔥 ICON ADJUSTMENT GUIDE:
   - 'adjScale': Big/Small (e.g., 1.5 is bigger, 0.8 is smaller)
   - 'adjX': Left/Right (e.g., 5.0 moves Right, -5.0 moves Left)
   - 'adjY': Top/Bottom (e.g., 5.0 moves Bottom, -5.0 moves Top)
  */
  static final List<Map<String, dynamic>> animals = [
    // ── TOP 3 RESERVED (rank-locked) ──
    {
      'name': 'Lion',
      'icon': Fluents.flLion,
      'isTop3': true,
      'rank': 1,
      'assetPath': 'assets/leaderboard/top_3_podium/lion.png',
      'adjScale': 1.8,
      'adjX': 2.5,
      'adjY': 0.0
    },
    {
      'name': 'Tiger',
      'icon': Fluents.flTiger,
      'isTop3': true,
      'rank': 2,
      'assetPath': 'assets/leaderboard/top_3_podium/tiger.png',
      'adjScale': 2.3, // Perusu (Big)
      'adjX': 1.5, // Right side
      'adjY': 0.0 // Mela (Top)
    },
    {
      'name': 'Elephant',
      'icon': Fluents.flElephant,
      'isTop3': true,
      'rank': 3,
      'assetPath': 'assets/leaderboard/top_3_podium/elephant.png',
      'adjScale': 2.3, // Perusu (Big)
      'adjX': 1.2, // Right side
      'adjY': 1.0 // Keela (Bottom)
    },
    {
      'name': 'Scarface Lion',
      'icon': Fluents.flLion,
      'isScarface': true,
      'assetPath': 'assets/leaderboard/SCARFACE_LION.png',
      'adjScale': 1.0,
      'adjX': 0.0,
      'adjY': 0.0
    },

    // ── AUTO-ASSIGN POOL (uses only verified FluentUI emoji icons) ──
    {'name': 'Leopard', 'icon': Fluents.flLeopard},
    {'name': 'Bear', 'icon': Fluents.flBear},
    {'name': 'Monkey', 'icon': Fluents.flMonkey},
    {'name': 'Giraffe', 'icon': Fluents.flGiraffe},
    {'name': 'Fox', 'icon': Fluents.flFox},
    {'name': 'Panda', 'icon': Fluents.flPanda},
    {'name': 'Zebra', 'icon': Fluents.flZebra},
    {'name': 'Cheetah', 'icon': Fluents.flLeopard},
    {'name': 'Rhino', 'icon': Fluents.flRhinoceros},
    {'name': 'Gorilla', 'icon': Fluents.flGorilla},
    {'name': 'Wolf', 'icon': Fluents.flWolf},
    {'name': 'Deer', 'icon': Fluents.flDeer},
    {'name': 'Cat', 'icon': Fluents.flCat},
    {'name': 'Mouse', 'icon': Fluents.flMouse},
    {'name': 'Dog', 'icon': Fluents.flDog},
    {'name': 'Rabbit', 'icon': Fluents.flRabbit},
    {'name': 'Hamster', 'icon': Fluents.flHamster},
    {'name': 'Chipmunk', 'icon': Fluents.flChipmunk},
    {'name': 'Hedgehog', 'icon': Fluents.flHedgehog},
    {'name': 'Bat', 'icon': Fluents.flBat},
    {'name': 'Koala', 'icon': Fluents.flKoala},
    {'name': 'Beaver', 'icon': Fluents.flBeaver},
    {'name': 'Bison', 'icon': Fluents.flBison},
    {'name': 'Camel', 'icon': Fluents.flCamel},
    {'name': 'Llama', 'icon': Fluents.flLlama},
    {'name': 'Horse', 'icon': Fluents.flHorse},
    {'name': 'Unicorn', 'icon': Fluents.flUnicorn},
    // {'name': 'Donkey', 'icon': Fluents.flDonkey}, // REMOVED DUE TO ERROR
    {'name': 'Ox', 'icon': Fluents.flOx},
    {'name': 'Ram', 'icon': Fluents.flRam},
    {'name': 'Goat', 'icon': Fluents.flGoat},
    {'name': 'Ewe', 'icon': Fluents.flEwe},
    {'name': 'Pig', 'icon': Fluents.flPig},
    {'name': 'Boar', 'icon': Fluents.flBoar},
    {'name': 'Hippopotamus', 'icon': Fluents.flHippopotamus},
    {'name': 'Mammoth', 'icon': Fluents.flMammoth},
    {'name': 'Badger', 'icon': Fluents.flBadger},
    {'name': 'Skunk', 'icon': Fluents.flSkunk},
    {'name': 'Kangaroo', 'icon': Fluents.flKangaroo},
    {'name': 'Otter', 'icon': Fluents.flOtter},
    {'name': 'Sloth', 'icon': Fluents.flSloth},
    {'name': 'Raccoon', 'icon': Fluents.flRaccoon},
    // {'name': 'Moose', 'icon': Fluents.flMoose}, // REMOVED DUE TO ERROR
    {'name': 'Eagle', 'icon': Fluents.flEagle},
    {'name': 'Owl', 'icon': Fluents.flOwl},
    {'name': 'Flamingo', 'icon': Fluents.flFlamingo},
    {'name': 'Peacock', 'icon': Fluents.flPeacock},
    {'name': 'Parrot', 'icon': Fluents.flParrot},
    {'name': 'Swan', 'icon': Fluents.flSwan},
    {'name': 'Dove', 'icon': Fluents.flDove},
    {'name': 'Duck', 'icon': Fluents.flDuck},
    {'name': 'Penguin', 'icon': Fluents.flPenguin},
    {'name': 'Rooster', 'icon': Fluents.flRooster},
    {'name': 'Turkey', 'icon': Fluents.flTurkey},
    {'name': 'Dodo', 'icon': Fluents.flDodo},
    {'name': 'Crocodile', 'icon': Fluents.flCrocodile},
    {'name': 'Turtle', 'icon': Fluents.flTurtle},
    {'name': 'Lizard', 'icon': Fluents.flLizard},
    {'name': 'Snake', 'icon': Fluents.flSnake},
    {'name': 'Dragon', 'icon': Fluents.flDragon},
    {'name': 'Whale', 'icon': Fluents.flWhale},
    {'name': 'Dolphin', 'icon': Fluents.flDolphin},
    {'name': 'Shark', 'icon': Fluents.flShark},
    {'name': 'Blowfish', 'icon': Fluents.flBlowfish},
    {'name': 'Octopus', 'icon': Fluents.flOctopus},
    {'name': 'Butterfly', 'icon': Fluents.flButterfly},
    {'name': 'Bug', 'icon': Fluents.flBug},
    {'name': 'Honeybee', 'icon': Fluents.flHoneybee},
    {'name': 'Ant', 'icon': Fluents.flAnt},
    {'name': 'Cricket', 'icon': Fluents.flCricket},
    {'name': 'Cockroach', 'icon': Fluents.flCockroach},
    {'name': 'Spider', 'icon': Fluents.flSpider},
    {'name': 'Scorpion', 'icon': Fluents.flScorpion},
    {'name': 'Crab', 'icon': Fluents.flCrab},
    {'name': 'Lobster', 'icon': Fluents.flLobster},
    {'name': 'Shrimp', 'icon': Fluents.flShrimp},
    {'name': 'Snail', 'icon': Fluents.flSnail},
    {'name': 'Frog', 'icon': Fluents.flFrog},
    {'name': 'Worm', 'icon': Fluents.flWorm},
  ];

  static List<String> get allNames =>
      animals.map((a) => a['name'].toString()).toList();

  /// Animals available for auto-assign (excludes top3 locked + scarface)
  static List<String> get autoAssignPool => animals
      .where((a) => a['isTop3'] != true && a['isScarface'] != true)
      .map((a) => a['name'].toString())
      .toList();

  /// Get the locked animal for top 3 ranks
  static String? getTop3Animal(int rank) {
    if (rank == 1) return 'Lion';
    if (rank == 2) return 'Tiger';
    if (rank == 3) return 'Elephant';
    return null;
  }

  /// Auto-assign a UNIQUE animal to a user based on their empId
  /// Uses a deterministic hash so the same user always gets the same animal
  /// [usedAnimals] = set of already-assigned animal names to avoid duplicates
  static String assignUniqueAnimal(String empId, Set<String> usedAnimals) {
    final pool = autoAssignPool;
    // Deterministic hash from empId
    int hash = 0;
    for (int i = 0; i < empId.length; i++) {
      hash = (hash * 31 + empId.codeUnitAt(i)) & 0x7FFFFFFF;
    }

    // Try to find an unused animal starting from hash position
    for (int attempt = 0; attempt < pool.length; attempt++) {
      final index = (hash + attempt) % pool.length;
      final animal = pool[index];
      if (!usedAnimals.contains(animal)) {
        return animal;
      }
    }
    // Fallback: all pool exhausted, use hash-based pick (allow repeats)
    return pool[hash % pool.length];
  }

  static Map<String, double> getAdjustments(String? animalName) {
    if (animalName == null) return {'scale': 1.0, 'x': 0.0, 'y': 0.0};
    try {
      final animal = animals.firstWhere(
        (a) => a['name'].toString().toLowerCase() == animalName.toLowerCase(),
      );
      return {
        'scale': (animal['adjScale'] ?? 1.0) as double,
        'x': (animal['adjX'] ?? 0.0) as double,
        'y': (animal['adjY'] ?? 0.0) as double,
      };
    } catch (_) {
      return {'scale': 1.0, 'x': 0.0, 'y': 0.0};
    }
  }

  static String? getAssetPath(String? animalName) {
    if (animalName == null) return null;
    try {
      final animal = animals.firstWhere(
        (a) => a['name'].toString().toLowerCase() == animalName.toLowerCase(),
      );
      return animal['assetPath'] as String?;
    } catch (_) {
      return null;
    }
  }

  static FluentData? getIcon(String? animalName) {
    if (animalName == null) return null;
    try {
      final animal = animals.firstWhere(
        (a) => a['name'].toString().toLowerCase() == animalName.toLowerCase(),
      );
      return animal['icon'] as FluentData;
    } catch (_) {
      return null;
    }
  }
}
