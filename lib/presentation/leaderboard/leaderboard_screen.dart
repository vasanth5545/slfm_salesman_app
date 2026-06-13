import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../../widgets/custom_bottom_bar.dart';
import '../../core/constants/api_urls.dart';
import '../../services/secure_storage_service.dart';
import '../../core/database/local_db_helper.dart';
import '../../core/constants/animal_data.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/profile_avatar_widget.dart';
import '../../services/feature_control_service.dart';

import '../../core/theme/app_colors.dart';

// --- SHARED MODELS & DATA ---
class AvatarConfig {
  String emoji;
  String? animal;
  String? photoUrl;
  AvatarConfig({required this.emoji, this.animal, this.photoUrl});
}

class UserModel {
  final int id;
  final String empId;
  final String name;
  final int score;
  final bool isLocal;
  final bool isCurrentUser;
  AvatarConfig avatarConfig;
  int currentRank;

  final int pendingCount;
  final String showroomName;
  final DateTime? lastBilledAt;
  final String role;

  UserModel({
    required this.id,
    required this.empId,
    required this.name,
    required this.score,
    required this.isLocal,
    required this.isCurrentUser,
    required this.avatarConfig,
    this.currentRank = 0,
    this.pendingCount = 0,
    this.showroomName = '',
    this.lastBilledAt,
    this.role = '',
  });
}

// --- MAIN LEADERBOARD SCREEN ---
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List<UserModel> users = [];
  bool isLoading = true;
  String activeFilter = 'All Showrooms';
  int pendingTotal = 0;
  bool _isLeaderboardVisible = true; // 🔥 Global Toggle

  String currentUserShowroom = '';
  String errorMsg = '';
  bool _isSpectator =
      false; // true for non-sales roles (office staff, admin, etc.)
  int _scarfaceLimit = 1000; // 🔥 Dynamic from DB config record

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Temporarily create with 3 tabs; will be replaced after role check
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _loadCachedStates();
    _initRoleAndFetch();
    _setupFeatureControl(); // 🔥 START LISTENER
  }

  void _setupFeatureControl() {
    final service = FeatureControlService();
    service.leaderboardVisible.addListener(_updateLeaderboardVisibility);
    _updateLeaderboardVisibility();
  }

  void _updateLeaderboardVisibility() {
    if (mounted) {
      setState(() {
        _isLeaderboardVisible =
            FeatureControlService().leaderboardVisible.value;
      });
    }
  }

  Future<void> _loadCachedStates() async {
    // Leaderboard visibility is now managed by FeatureControlService instantly
    final partCached =
        await SecureStorageService.readString('cached_leaderboard_participant');

    if (mounted) {
      setState(() {
        if (partCached != null) {
          bool isPart = partCached == 'true';
          if (!isPart) {
            _isSpectator = true;
            final oldController = _tabController;
            _tabController =
                TabController(length: 2, vsync: this, initialIndex: 1);
            oldController.dispose();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();

    FeatureControlService()
        .leaderboardVisible
        .removeListener(_updateLeaderboardVisibility);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initRoleAndFetch() async {
    final role = await SecureStorageService.getUserRole();
    final showroom =
        await SecureStorageService.readString('showroom_name') ?? '';
    final r = role.toLowerCase().trim();

    bool isParticipant = (r == 'salesman' || r == 'promoter');

    // 🔥 DYNAMIC CONFIG: Fetch participation status from PHP (now with role)
    try {
      final url =
          "${ApiUrl.getFeatureStatus}?showroom=${Uri.encodeComponent(showroom)}&role=${Uri.encodeComponent(role)}";
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final bool isFeatureEnabled =
              data['data']['is_leaderboard_participant'] ?? true;
          await SecureStorageService.writeString(
              'cached_leaderboard_participant', isFeatureEnabled.toString());
          if (!isFeatureEnabled) {
            isParticipant = false;
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Participation Check Failed: $e");
    }

    if (!isParticipant && mounted) {
      // Switch to 2-tab view for spectators
      final oldController = _tabController;
      _tabController = TabController(
          length: 2, vsync: this, initialIndex: 1); // Default to Podium
      oldController.dispose();
      setState(() => _isSpectator = true);
    }
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    final showroom =
        await SecureStorageService.readString('showroom_name') ?? 'Main Branch';
    final currentEmpId = await SecureStorageService.getSalesmanId() ?? '';
    final currentName = await SecureStorageService.getSalesmanName() ?? 'You';

    // 🔥 STEP 1: INSTANTLY load from local SQLite (offline-first)
    try {
      final localStats =
          await LocalDbHelper.instance.getWalkingStats(currentEmpId);
      final int localBilled = localStats['billed'] ?? 0;
      final int localPending = localStats['pending'] ?? 0;

      debugPrint(
          '🏆 Local SQLite Stats: Billed=$localBilled, Pending=$localPending');

      if (mounted && (localBilled > 0 || localPending > 0)) {
        setState(() {
          users = [
            UserModel(
              id: 0,
              empId: currentEmpId,
              name: currentName,
              score: localBilled,
              isLocal: true,
              isCurrentUser: true,
              avatarConfig: AvatarConfig(emoji: 'monkey'),
              pendingCount: localPending,
              showroomName: showroom,
            ),
          ];
          if (activeFilter == 'All Showrooms' && showroom.isNotEmpty) {
            activeFilter = showroom;
          }
          currentUserShowroom = showroom;
          pendingTotal = localPending;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Local SQLite read error: $e');
    }

    // 🔥 STEP 2: Try API in background
    try {
      final apiUrl = '${ApiUrl.baseUrl}/get_leaderboard.php';
      debugPrint('🏆 Leaderboard API Call: $apiUrl');

      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 20));

      debugPrint('🏆 Leaderboard Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          // Extract Reward Limit from DB
          if (data['rewards_config'] != null) {
            _scarfaceLimit = data['rewards_config']['scarface_limit'] ?? 1000;
          }

          List<dynamic> apiUsers = data['data'];
          List<UserModel> fetchedUsers = [];
          int totalPending = 0;

          for (var u in apiUsers) {
            String uShowroom = u['showroom_name']?.toString() ?? 'Main Branch';
            int uPending = int.tryParse(u['pendingCount'].toString()) ?? 0;

            // Parse last_billed_at for tie-breaking
            DateTime? lastBilled;
            if (u['last_billed_at'] != null &&
                u['last_billed_at'].toString().isNotEmpty) {
              lastBilled = DateTime.tryParse(u['last_billed_at'].toString());
            }

            fetchedUsers.add(UserModel(
              id: 0,
              empId: u['empId']?.toString() ?? '',
              name: u['name']?.toString() ?? 'Unknown',
              score: int.tryParse(u['score'].toString()) ?? 0,
              isLocal: (uShowroom == showroom),
              isCurrentUser: (u['empId']?.toString() == currentEmpId),
              role: u['role']?.toString() ?? '',
              avatarConfig: AvatarConfig(
                emoji: u['emoji'] ?? 'monkey',
                animal: u['avatar_animal'],
                photoUrl: u['profile_photo'],
              ),
              pendingCount: uPending,
              showroomName: uShowroom,
              lastBilledAt: lastBilled,
            ));
            totalPending += uPending;
          }

          if (mounted) {
            setState(() {
              users =
                  fetchedUsers; // Always update, even if list is now empty (e.g. after role change)
              pendingTotal = totalPending;
              errorMsg = '';

              if (fetchedUsers.isNotEmpty) {
                // 🔥 SMART FILTER: Show their showroom only if it has participants.
                final currentShowroomUsers = fetchedUsers
                    .where((u) => u.showroomName == showroom)
                    .toList();

                if (currentShowroomUsers.isEmpty) {
                  activeFilter = 'All Showrooms';
                } else {
                  if (activeFilter == 'All Showrooms') {
                    activeFilter = showroom;
                  }
                }
              }
              currentUserShowroom = showroom;
              isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() => isLoading = false);
          }
        }
      } else {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('❌ Leaderboard API error: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          if (users.isEmpty) {
            errorMsg = 'No internet & no local data available';
          }
        });
      }
    }
  }

  List<UserModel> get _rankedUsers {
    List<UserModel> filtered = List.from(users);

    // 🔥 TASK 1 FIX: Smart Filter
    // If the activeFilter doesn't match anyone in the users list, strictly use 'All Showrooms'
    bool filterExists = false;
    if (activeFilter != 'All Showrooms') {
      filterExists = users.any((u) => u.showroomName == activeFilter);
    }
    String effectiveFilter = filterExists ? activeFilter : 'All Showrooms';

    if (effectiveFilter != 'All Showrooms') {
      filtered =
          filtered.where((u) => u.showroomName == effectiveFilter).toList();
    }

    // 🔥 SORT: Primary = score DESC, Tie-breaker = lastBilledAt ASC
    // When same billed count, whoever achieved it EARLIER (smaller date) ranks higher
    filtered.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;

      // Tie-breaker: earlier lastBilledAt = higher rank
      if (a.lastBilledAt != null && b.lastBilledAt != null) {
        return a.lastBilledAt!.compareTo(b.lastBilledAt!);
      }
      // If one has no date, the one WITH a date ranks higher
      if (a.lastBilledAt != null) return -1;
      if (b.lastBilledAt != null) return 1;
      return 0;
    });

    // 🔥 Assign rank + auto-assign unique animals
    Set<String> usedAnimals = {};
    int currentNumericalRank = 1;
    for (int i = 0; i < filtered.length; i++) {
      if (filtered[i].score > 0) {
        filtered[i].currentRank = currentNumericalRank;

        // 🔥 FORCE: Top 3 ALWAYS get locked animals, NO MATTER WHAT!
        final top3Animal = AnimalData.getTop3Animal(currentNumericalRank);
        if (top3Animal != null) {
          filtered[i].avatarConfig.animal = top3Animal;
          usedAnimals.add(top3Animal);
        } else {
          // Rank 4+: Keep their chosen animal if it exists
        }
        currentNumericalRank++;
      } else {
        // Users with 0 score are "Ranked" but not numbered 1, 2, 3
        filtered[i].currentRank = 0;
        // Keep their chosen animal if it exists!
      }
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLeaderboardVisible) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_outlined,
                  color: Colors.amber, size: 80),
              const SizedBox(height: 20),
              Text(
                "FEATURE DISABLED",
                style: GoogleFonts.orbitron(
                  color: Colors.amber,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "This feature is temporarily unavailable\nin your showroom.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("BACK"),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors(isDark);
    final rankedUsers = _rankedUsers;
    final currentUserRanked = rankedUsers.isNotEmpty
        ? rankedUsers.firstWhere((u) => u.isCurrentUser,
            orElse: () => rankedUsers.first)
        : UserModel(
            id: 0,
            empId: '',
            name: 'Not Ranked', // Changed from misleading 'Loading'
            score: 0,
            isLocal: true,
            isCurrentUser: true,
            avatarConfig: AvatarConfig(emoji: 'lion'));

    // 🔥 Build tab children based on spectator mode
    final List<Widget> tabChildren = _isSpectator
        ? [
            // Spectator: Only PODIUM + RANKINGS (no MY STATUS)
            PodiumView(
              users: rankedUsers,
              targetScore: _scarfaceLimit,
            ),
            ListViewScreen(
              allUsers: users,
              rankedUsers: rankedUsers,
              activeFilter: activeFilter,
              onFilterChanged: (val) => setState(() => activeFilter = val),
              targetScore: _scarfaceLimit,
            ),
          ]
        : [
            // Participant: MY STATUS + PODIUM + RANKINGS
            WinnerView(
              user: currentUserRanked,
              targetScore: _scarfaceLimit,
            ),
            PodiumView(
              users: rankedUsers,
              targetScore: _scarfaceLimit,
            ),
            ListViewScreen(
              allUsers: users,
              rankedUsers: rankedUsers,
              activeFilter: activeFilter,
              onFilterChanged: (val) => setState(() => activeFilter = val),
              targetScore: _scarfaceLimit,
            ),
          ];

    return Scaffold(
      backgroundColor: colors.bg,
      bottomNavigationBar: CustomBottomBar(currentRoute: '/leaderboard'),
      body: SafeArea(
        child: Column(
          children: [
            _buildNeonHeader(context),
            Expanded(
              child: isLoading
                  ? const LeaderboardSkeleton()
                  : errorMsg.isNotEmpty && users.isEmpty
                      ? _buildErrorView()
                      : TabBarView(
                          controller: _tabController,
                          children: tabChildren,
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeonHeader(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.surface.withValues(alpha: 0.8),
            colors.bg.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacementNamed(context, '/dashboard');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: colors.textPrimary.withValues(alpha: 0.1)),
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      color: colors.textPrimary, size: 18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF8A2BE2), Color(0xFF00B4FF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(bounds),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "LEADERBOARD",
                        style: GoogleFonts.orbitron(
                          textStyle: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                      if (pendingTotal > 0 || users.isNotEmpty)
                        Row(
                          children: [
                            if (users.isNotEmpty)
                              Text(
                                "${users.fold<int>(0, (sum, u) => sum + u.score)} BILLED",
                                style: GoogleFonts.orbitron(
                                  textStyle: TextStyle(
                                    color: colors.gold.withValues(alpha: 0.8),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            if (users.isNotEmpty && pendingTotal > 0)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text("•",
                                    style: TextStyle(
                                        color: colors.textPrimary
                                            .withValues(alpha: 0.3))),
                              ),
                            if (pendingTotal > 0)
                              Text(
                                "$pendingTotal PENDING",
                                style: GoogleFonts.orbitron(
                                  textStyle: TextStyle(
                                    color: Colors.orangeAccent
                                        .withValues(alpha: 0.8),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    colors.gold.withValues(alpha: 0.2),
                    colors.gold.withValues(alpha: 0.05),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: colors.gold, width: 2.5),
                ),
              ),
              dividerColor: Colors.transparent,
              labelColor: colors.gold,
              unselectedLabelColor: colors.textSecondary,
              labelStyle: GoogleFonts.orbitron(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
              unselectedLabelStyle: GoogleFonts.orbitron(
                fontSize: 10,
                fontWeight: FontWeight
                    .w400, // 🔥 Changed from w500 to w400 (Regular) as Medium asset is missing
                letterSpacing: 0.5,
              ),
              tabs: _isSpectator
                  ? const [
                      Tab(text: 'PODIUM'),
                      Tab(text: 'RANKINGS'),
                    ]
                  : const [
                      Tab(text: 'MY STATUS'),
                      Tab(text: 'PODIUM'),
                      Tab(text: 'RANKINGS'),
                    ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.textPrimary.withValues(alpha: 0.03),
                border: Border.all(color: colors.divider),
              ),
              child: Icon(Icons.cloud_off_rounded,
                  color: colors.textSecondary, size: 48),
            ),
            const SizedBox(height: 20),
            Text(errorMsg,
                style: GoogleFonts.orbitron(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                setState(() {
                  isLoading = true;
                  errorMsg = '';
                });
                _fetchLeaderboard();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colors.gold.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded,
                        color: Colors.black, size: 18),
                    const SizedBox(width: 8),
                    Text("RETRY",
                        style: GoogleFonts.orbitron(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MY STATUS VIEW (Tab 1)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class WinnerView extends StatefulWidget {
  final UserModel user;
  final int targetScore;
  const WinnerView({super.key, required this.user, required this.targetScore});

  @override
  State<WinnerView> createState() => _WinnerViewState();
}

class _WinnerViewState extends State<WinnerView> with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _lottieController = AnimationController(vsync: this);
  }

  void _playLottieSequence(LottieComposition composition) async {
    _lottieController.duration = composition.duration;
    double frame80Fraction = 80 / 150.0;
    _lottieController.value = 0.0;
    try {
      await _lottieController.animateTo(frame80Fraction);
      if (mounted) {
        _lottieController.repeat(min: frame80Fraction, max: 1.0);
      }
    } catch (e) {
      debugPrint('❌ Lottie sequence error: $e');
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _lottieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _spinController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _spinController.value * 2 * math.pi,
                child: Transform.scale(
                  scale: 2.5,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: List.generate(32, (index) {
                          return index % 2 == 0
                              ? colors.gold.withValues(alpha: 0.08)
                              : Colors.transparent;
                        }),
                        stops: List.generate(32, (index) => index / 32),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ).createShader(bounds),
                    child: Text(
                        widget.user.currentRank == 1
                            ? 'CONGRATULATIONS!'
                            : 'YOUR STATUS',
                        style: GoogleFonts.orbitron(
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                          ),
                        )),
                  ),
                  const SizedBox(height: 140),
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(140, 140),
                        painter: _HexBorderPainter(
                            color: colors.gold, strokeWidth: 4),
                      ),
                      ClipPath(
                        clipper: _HexClipper(),
                        child: Container(
                          width: 140,
                          height: 140,
                          color: colors.textPrimary.withValues(alpha: 0.05),
                        ),
                      ),
                      ProfileAvatarWidget(
                          photoUrl: widget.user.avatarConfig.photoUrl,
                          animalName: widget.user.avatarConfig.animal,
                          name: widget.user.name,
                          rank: widget.user.currentRank,
                          radius: 56,
                          badgeRadius: 20,
                          isHexagon: true),
                      Positioned(
                        top: -140,
                        child: Lottie.asset(
                          'assets/leaderboard/Crown.json',
                          width: 160,
                          height: 160,
                          controller: _lottieController,
                          onLoaded: (composition) =>
                              _playLottieSequence(composition),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        colors.gold.withValues(alpha: 0.3),
                        colors.gold.withValues(alpha: 0.05),
                      ]),
                      border: Border.all(color: colors.gold, width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: colors.gold.withValues(alpha: 0.3),
                            blurRadius: 15)
                      ],
                    ),
                    child: Text(
                        widget.user.score > 0
                            ? '#${widget.user.currentRank}'
                            : 'BILL\nPODANUM!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                            fontSize: widget.user.score > 0 ? 20 : 10,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                            color: colors.gold)),
                  ),
                  const SizedBox(height: 16),
                  Text(widget.user.empId,
                      style: GoogleFonts.orbitron(
                          color: colors.textSecondary,
                          fontSize: 12,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(widget.user.name,
                      style: GoogleFonts.orbitron(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatChip(context, Icons.star_rounded, 'Billed',
                          '${widget.user.score}', colors.gold),
                      const SizedBox(width: 16),
                      _buildStatChip(
                          context,
                          Icons.hourglass_bottom_rounded,
                          'Pending',
                          '${widget.user.pendingCount}',
                          Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildLargeProgressBar(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLargeProgressBar(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    double percentage =
        (widget.user.score / widget.targetScore).clamp(0.0, 1.0);

    return Column(
      children: [
        Text(
          'REWARD PROGRESS',
          style: GoogleFonts.orbitron(
            color: colors.textPrimary.withValues(alpha: 0.24),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: percentage),
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            int displayPercent = (value * 100).toInt();
            return Container(
              width: 320,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.textPrimary.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: colors.textPrimary.withValues(alpha: 0.05)),
                boxShadow: [
                  BoxShadow(
                    color: (displayPercent >= 100
                            ? colors.success
                            : colors.neonBlue)
                        .withValues(alpha: 0.1),
                    blurRadius: 30,
                  )
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$displayPercent%',
                        style: GoogleFonts.orbitron(
                          color: colors.gold,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    children: [
                      // Background track
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors.textPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      // Animated Fill
                      FractionallySizedBox(
                        widthFactor: value,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: displayPercent >= 100
                                  ? [Colors.green, Colors.greenAccent]
                                  : [Colors.blue.shade700, Colors.blueAccent],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: (displayPercent >= 100
                                        ? colors.success
                                        : colors.neonBlue)
                                    .withValues(alpha: 0.5),
                                blurRadius: 10,
                              )
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayPercent >= 100
                        ? 'SCARFACE MASCOT UNLOCKED!'
                        : 'NEXT RANK: SCARFACE LION',
                    style: GoogleFonts.orbitron(
                      color: colors.textPrimary.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    displayPercent >= 100
                        ? 'GOTO PROFILE TO EQUIP'
                        : '${widget.targetScore - widget.user.score} BILLS REMAINING',
                    style: TextStyle(
                      color: colors.textPrimary.withValues(alpha: 0.38),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String label,
      String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 10)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text('$label: $value',
              style: GoogleFonts.orbitron(
                  color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// PODIUM VIEW (Tab 2)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class PodiumView extends StatelessWidget {
  final List<UserModel> users;
  final int targetScore;
  const PodiumView({super.key, required this.users, required this.targetScore});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    if (users.length < 3) {
      return const LeaderboardSkeleton();
    }
    return Column(
      children: [
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildPodiumItem(context, users[1], 2, 85),
            _buildPodiumItem(context, users[0], 1, 115),
            _buildPodiumItem(context, users[2], 3, 75),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.surface, colors.bg],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                  top:
                      BorderSide(color: colors.divider.withValues(alpha: 0.5))),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: math.max(0, users.length - 3),
              itemBuilder: (context, index) {
                if (index + 3 >= users.length) {
                  return const SizedBox.shrink();
                }
                return _NeonLeaderboardCard(
                  user: users[index + 3],
                  targetScore: targetScore,
                );
              },
            ),
          ),
        )
      ],
    );
  }

  // 🔥 Rank color: 1st=Gold, 2nd=Silver, 3rd=Copper
  static Color getRankColor(BuildContext context, int rank) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    if (rank == 1) {
      return colors.gold;
    }
    if (rank == 2) {
      return colors.silver;
    }
    if (rank == 3) {
      return colors.bronze;
    }
    return colors.textSecondary;
  }

  Widget _buildPodiumItem(
      BuildContext context, UserModel user, int rank, double height) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    final Color themeColor = getRankColor(context, rank);
    final double avatarSize = rank == 1 ? 44 : 34;
    final bool isRealRank = user.score > 0;

    return Container(
      width: rank == 1 ? 120 : 105,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (rank == 1 && isRealRank)
            const Text('👑', style: TextStyle(fontSize: 28)),
          Text(
            rank == 1
                ? '1st'
                : rank == 2
                    ? '2nd'
                    : '3rd',
            style: GoogleFonts.orbitron(
              color: isRealRank
                  ? themeColor
                  : colors.textPrimary.withValues(alpha: 0.2),
              fontWeight: FontWeight.bold,
              fontSize: rank == 1 ? 14 : 12,
              letterSpacing: 1,
              shadows: (rank == 1 && isRealRank)
                  ? [
                      Shadow(
                          color: themeColor.withValues(alpha: 0.8),
                          blurRadius: 10)
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          // Avatar with hex frame
          Stack(
            alignment: Alignment.center,
            children: [
              if (isRealRank)
                ClipPath(
                  clipper: _HexClipper(),
                  child: Container(
                    width: avatarSize * 2 + 16,
                    height: avatarSize * 2 + 16,
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.3),
                      boxShadow: [
                        BoxShadow(
                            color: themeColor.withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 3)
                      ],
                    ),
                  ),
                ),
              CustomPaint(
                size: Size(avatarSize * 2 + 8, avatarSize * 2 + 8),
                painter: _HexBorderPainter(
                    color: isRealRank
                        ? themeColor
                        : colors.textPrimary.withValues(alpha: 0.1),
                    strokeWidth: rank == 1 ? 3.5 : 2.5),
              ),
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: isRealRank
                    ? ProfileAvatarWidget(
                        photoUrl: user.avatarConfig.photoUrl,
                        animalName: user.avatarConfig.animal,
                        name: user.name,
                        rank: rank,
                        radius: avatarSize,
                        badgeRadius: 9,
                        badgeBottom: -18,
                        badgeRight: -4,
                        isHexagon: true,
                      )
                    : ClipPath(
                        clipper: _HexClipper(),
                        child: Container(
                          width: avatarSize * 2,
                          height: avatarSize * 2,
                          color: colors.textPrimary.withValues(alpha: 0.05),
                          alignment: Alignment.center,
                          child: Text(
                            isRealRank ? user.name : 'RANKED',
                            style: GoogleFonts.orbitron(
                              color: colors.textPrimary.withValues(alpha: 0.6),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: isRealRank
                            ? [themeColor, themeColor.withValues(alpha: 0.7)]
                            : [
                                colors.textPrimary.withValues(alpha: 0.1),
                                colors.textPrimary.withValues(alpha: 0.05)
                              ]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isRealRank
                        ? [
                            BoxShadow(
                                color: themeColor.withValues(alpha: 0.5),
                                blurRadius: 8)
                          ]
                        : null,
                  ),
                  child: Text(isRealRank ? '$rank' : 'RANKED',
                      style: GoogleFonts.orbitron(
                          color: isRealRank
                              ? Colors.black
                              : colors.textPrimary.withValues(alpha: 0.3),
                          fontSize: isRealRank ? 12 : 8,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(isRealRank ? user.name : 'RANKED',
              style: GoogleFonts.orbitron(
                  color: isRealRank
                      ? colors.textPrimary
                      : colors.textPrimary.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          if (isRealRank) ...[
            Text('Billed: ${user.score}',
                style: GoogleFonts.orbitron(
                    color: themeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10)),
            Text('Pending: ${user.pendingCount}',
                style: GoogleFonts.orbitron(
                    color: colors.textPrimary.withValues(alpha: 0.5),
                    fontWeight: FontWeight.bold,
                    fontSize: 9)),
          ] else
            Text('RANKED',
                style: GoogleFonts.orbitron(
                    color: colors.textPrimary.withValues(alpha: 0.24),
                    fontWeight: FontWeight.bold,
                    fontSize: 8)),
          SizedBox(height: math.max(0, height - 100)),
          // Glowing base ring
          Container(
            width: rank == 1 ? 100 : 80,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(colors: [
                Colors.transparent,
                (isRealRank
                        ? themeColor
                        : colors.textPrimary.withValues(alpha: 0.1))
                    .withValues(alpha: 0.8),
                Colors.transparent
              ]),
              boxShadow: isRealRank
                  ? [
                      BoxShadow(
                          color: themeColor.withValues(alpha: 0.6),
                          blurRadius: 12,
                          spreadRadius: 2)
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// NEON LEADERBOARD CARD (Rankings + Podium list)
// Uses ranking PNG badges for top 3
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _NeonLeaderboardCard extends StatelessWidget {
  final UserModel user;
  final int targetScore;
  const _NeonLeaderboardCard({required this.user, required this.targetScore});

  // 🔥 1st=Gold, 2nd=Silver, 3rd=Copper
  Color _getRankColor(BuildContext context, int rank) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    if (rank == 1) {
      return colors.gold;
    }
    if (rank == 2) {
      return colors.silver;
    }
    if (rank == 3) {
      return colors.bronze;
    }
    if (rank <= 5) {
      return const Color(0xFF607D8B);
    }
    return colors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    final rankColor = _getRankColor(context, user.currentRank);
    final bool isTop3 = user.currentRank >= 1 && user.currentRank <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            isTop3 ? rankColor.withValues(alpha: 0.08) : colors.cardBg,
            colors.surface.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rankColor.withValues(alpha: isTop3 ? 0.4 : 0.12),
          width: isTop3 ? 1.5 : 1,
        ),
        boxShadow: [
          if (isTop3)
            BoxShadow(color: rankColor.withValues(alpha: 0.15), blurRadius: 12),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Rank circle (left)
              Container(
                width: user.score > 0 ? 40 : 65,
                height: 36,
                decoration: BoxDecoration(
                  shape: user.score > 0 ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius:
                      user.score > 0 ? null : BorderRadius.circular(18),
                  gradient: isTop3
                      ? LinearGradient(colors: [
                          rankColor.withValues(alpha: 0.3),
                          rankColor.withValues(alpha: 0.08)
                        ])
                      : null,
                  color: !isTop3
                      ? colors.textPrimary.withValues(alpha: 0.05)
                      : null,
                  border: Border.all(
                      color: rankColor.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                          user.score > 0 ? '#${user.currentRank}' : 'RANKED',
                          maxLines: 1,
                          style: GoogleFonts.orbitron(
                            color: rankColor,
                            fontSize: user.score > 0 ? 12 : 9,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Avatar
              // Avatar
              ProfileAvatarWidget(
                  photoUrl: user.avatarConfig.photoUrl,
                  animalName: user.avatarConfig.animal,
                  name: user.name,
                  rank: user.currentRank,
                  radius: 22,
                  badgeRadius: 9,
                  showRankBadge:
                      false), // False because rank is already on left

              const SizedBox(width: 12),

              // Name + ID + Stats
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (user.currentRank == 1)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.workspace_premium,
                                color: colors.gold, size: 16),
                          ),
                        Flexible(
                          child: Text(
                            (user.score > 0 ? user.name : "RANKED")
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .join('\n') +
                                (user.isCurrentUser ? " (YOU)" : ""),
                            style: GoogleFonts.orbitron(
                              color: colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              height: 1.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${user.empId} • ${user.showroomName}',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _miniStat('Billed', '${user.score}', colors.gold),
                        _miniStat(
                            'Pending', '${user.pendingCount}', colors.primary),
                      ],
                    ),
                  ],
                ),
              ),

              // 🔥 RIGHT: Ranking PNG badge for top 3 ONLY
              if (isTop3)
                Image.asset(
                  user.currentRank == 1
                      ? 'assets/leaderboard/ranking/top_1.png'
                      : user.currentRank == 2
                          ? 'assets/leaderboard/ranking/top_2.png'
                          : 'assets/leaderboard/ranking/top_3.png',
                  width: 70,
                  height: 70,
                  fit: BoxFit.contain,
                ),
            ],
          ),
          // 🔥 PROGRESS BAR - ONLY FOR THE CURRENT USER (THEM)
          if (user.isCurrentUser) _buildProgressLine(context),
        ],
      ),
    );
  }

  // 🔥 Futuristic Progress Bar Widget
  Widget _buildProgressLine(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    double percentage = (user.score / targetScore).clamp(0.0, 1.0);
    int displayPercent = (percentage * 100).toInt();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$displayPercent%',
                style: GoogleFonts.orbitron(
                  color: colors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                displayPercent >= 100 ? 'TARGET REACHED!' : 'TOWARDS SCARFACE',
                style: GoogleFonts.orbitron(
                  color: displayPercent >= 100
                      ? colors.success
                      : colors.textPrimary.withValues(alpha: 0.24),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percentage,
              backgroundColor: colors.textPrimary.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(colors.gold),
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            label == 'Billed'
                ? Icons.stars_rounded
                : Icons.hourglass_top_rounded,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: GoogleFonts.orbitron(
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.bold,
              fontSize: 9,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.orbitron(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class ListViewScreen extends StatelessWidget {
  final List<UserModel> allUsers;
  final List<UserModel> rankedUsers;
  final String activeFilter;
  final Function(String) onFilterChanged;
  final int targetScore;
  const ListViewScreen(
      {super.key,
      required this.allUsers,
      required this.rankedUsers,
      required this.activeFilter,
      required this.onFilterChanged,
      required this.targetScore});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    final showrooms = {
      'All Showrooms',
      ...allUsers.map((u) => u.showroomName).where((s) => s.isNotEmpty)
    }.toList();

    return Column(
      children: [
        // Dropdown filter with neon gradient border
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [colors.cardBg, const Color(0xFF141738)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.neonPurple.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                    color: colors.neonPurple.withValues(alpha: 0.08),
                    blurRadius: 12),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: showrooms.contains(activeFilter)
                    ? activeFilter
                    : 'All Showrooms',
                isExpanded: true,
                dropdownColor: colors.surface,
                icon:
                    Icon(Icons.keyboard_arrow_down_rounded, color: colors.gold),
                style: GoogleFonts.orbitron(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11),
                onChanged: (v) {
                  if (v != null) {
                    onFilterChanged(v);
                  }
                },
                items: showrooms.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value,
                        style: GoogleFonts.orbitron(
                            fontSize: 11, color: colors.textPrimary)),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        // Rankings List
        Expanded(
          child: rankedUsers.isEmpty
              ? _buildNoResultsView(context)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rankedUsers.length,
                  itemBuilder: (context, index) {
                    return _NeonLeaderboardCard(
                      user: rankedUsers[index],
                      targetScore: targetScore,
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildNoResultsView(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_rounded,
              color: colors.textPrimary.withValues(alpha: 0.2), size: 60),
          const SizedBox(height: 16),
          Text(
            "No participants found in this filter",
            style: GoogleFonts.orbitron(
              color: colors.textPrimary.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => onFilterChanged('All Showrooms'),
            child: Text(
              "VIEW ALL SHOWROOMS",
              style: GoogleFonts.orbitron(
                color: colors.gold,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HEX CLIPPER & PAINTER
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width, h = size.height;
    path.moveTo(w * 0.5, 0);
    path.lineTo(w, h * 0.25);
    path.lineTo(w, h * 0.75);
    path.lineTo(w * 0.5, h);
    path.lineTo(0, h * 0.75);
    path.lineTo(0, h * 0.25);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _HexBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  _HexBorderPainter({required this.color, this.strokeWidth = 2.5});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path();
    final w = size.width, h = size.height;
    path.moveTo(w * 0.5, 0);
    path.lineTo(w, h * 0.25);
    path.lineTo(w, h * 0.75);
    path.lineTo(w * 0.5, h);
    path.lineTo(0, h * 0.75);
    path.lineTo(0, h * 0.25);
    path.close();

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SKELETON LOADER
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
class LeaderboardSkeleton extends StatefulWidget {
  const LeaderboardSkeleton({super.key});

  @override
  State<LeaderboardSkeleton> createState() => _LeaderboardSkeletonState();
}

class _LeaderboardSkeletonState extends State<LeaderboardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double slide = _controller.value;
        return Column(
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildPodiumSkeleton(85, slide),
                _buildPodiumSkeleton(115, slide),
                _buildPodiumSkeleton(75, slide),
              ],
            ),
            const SizedBox(height: 30),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: ListView.builder(
                  itemCount: 5,
                  itemBuilder: (context, index) => _buildCardSkeleton(slide),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPodiumSkeleton(double height, double slide) {
    return Container(
      width: 100,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _shimmerBox(60, 60, slide, isCircle: true),
          const SizedBox(height: 12),
          _shimmerBox(80, height, slide),
        ],
      ),
    );
  }

  Widget _buildCardSkeleton(double slide) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _shimmerBox(45, 45, slide, isCircle: true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBox(100, 12, slide),
                const SizedBox(height: 8),
                _shimmerBox(60, 8, slide),
              ],
            ),
          ),
          _shimmerBox(40, 24, slide),
        ],
      ),
    );
  }

  Widget _shimmerBox(double width, double height, double slide,
      {bool isCircle = false}) {
    final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(4),
        gradient: LinearGradient(
          colors: [
            colors.textPrimary.withValues(alpha: 0.03),
            colors.textPrimary.withValues(alpha: 0.1),
            colors.textPrimary.withValues(alpha: 0.03)
          ],
          stops: [math.max(0, slide - 0.3), slide, math.min(1, slide + 0.3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
