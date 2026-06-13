import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../../services/announcement_service.dart';
import '../../services/secure_storage_service.dart';
import 'package:intl/intl.dart';

class AnnouncementHistoryScreen extends StatefulWidget {
  const AnnouncementHistoryScreen({super.key});

  @override
  State<AnnouncementHistoryScreen> createState() =>
      _AnnouncementHistoryScreenState();
}

class _AnnouncementHistoryScreenState extends State<AnnouncementHistoryScreen>
    with TickerProviderStateMixin {
  late AnimationController _skeletonController;
  final AnnouncementService _service = AnnouncementService();
  String _showroomName = "";
  String _salesmanId = "";

  @override
  void initState() {
    super.initState();
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _loadData();
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final showroom = await SecureStorageService.getShowroomName() ?? '';
    final salesmanId = await SecureStorageService.getSalesmanId() ?? '';
    if (mounted) {
      setState(() {
        _showroomName = showroom;
        _salesmanId = salesmanId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Announcement>>(
        stream: _service.getAllAnnouncements(_showroomName, _salesmanId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildSkeletonList(theme);
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final announcements = snapshot.data ?? [];

          if (announcements.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 64, color: theme.colorScheme.outline),
                  SizedBox(height: 2.h),
                  Text("No notifications yet",
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(4.w),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final announcement = announcements[index];
              final isRead = announcement.readBy.containsKey(_salesmanId);
              final date =
                  DateTime.fromMillisecondsSinceEpoch(announcement.timestamp);
              final formattedDate =
                  DateFormat('dd MMM yyyy, hh:mm a').format(date);

              return Card(
                margin: EdgeInsets.only(bottom: 2.h),
                elevation: isRead ? 0 : 2,
                color: isRead
                    ? theme.colorScheme.surfaceContainerLow
                    : theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isRead
                      ? BorderSide.none
                      : BorderSide(
                          color: theme.colorScheme.primary, width: 0.5),
                ),
                child: InkWell(
                  onTap: () => _showAnnouncementDetails(announcement),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.all(4.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? theme.colorScheme.outline
                                        .withValues(alpha: 0.1)
                                    : theme.colorScheme.primary
                                        .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                announcement.target == 'global'
                                    ? Icons.public_rounded
                                    : (announcement.target == _salesmanId
                                        ? Icons.person_rounded
                                        : Icons.storefront_rounded),
                                size: 18,
                                color: isRead
                                    ? theme.colorScheme.outline
                                    : theme.colorScheme.primary,
                              ),
                            ),
                            SizedBox(width: 3.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    announcement.target == 'global'
                                        ? "All Showrooms"
                                        : (announcement.target == _salesmanId
                                            ? "Direct Message"
                                            : announcement.target),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: isRead
                                          ? theme.colorScheme.onSurfaceVariant
                                          : theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    formattedDate,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                      fontSize: 10,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 1.5.h),
                        Text(
                          announcement.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight:
                                isRead ? FontWeight.normal : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAnnouncementDetails(Announcement announcement) async {
    // 🛡️ SYNC: Use RTDB check instead of local list
    if (!announcement.readBy.containsKey(_salesmanId)) {
      await _service.acknowledgeAnnouncement(announcement.id, _salesmanId);
      _loadData();
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 1.5.h),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(6.w, 3.h, 6.w, 4.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.campaign_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 24),
                        ),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Announcement",
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                              ),
                              Text(
                                DateFormat('dd MMM yyyy, hh:mm a').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                        announcement.timestamp)),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(height: 1, thickness: 0.5),
                    ),
                    // 📝 SELECTABLE TEXT: Better for long messages (2000+ chars)
                    SelectableText(
                      announcement.message,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.6,
                            fontSize: 16,
                            letterSpacing: 0.2,
                          ),
                    ),
                    SizedBox(height: 4.h),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "Got it",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonList(ThemeData theme) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      itemCount: 6,
      itemBuilder: (context, index) => _buildSkeletonCard(theme),
    );
  }

  Widget _buildSkeletonCard(ThemeData theme) {
    final baseColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.8).animate(_skeletonController),
      child: Container(
        margin: EdgeInsets.only(bottom: 2.h),
        padding: EdgeInsets.all(4.w),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 100,
                  height: 14,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            SizedBox(height: 1.5.h),
            Container(
              width: double.infinity,
              height: 18,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 1.h),
            Container(
              width: 200,
              height: 18,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 2.h),
            Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
