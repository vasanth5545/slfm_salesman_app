import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';
import '../../services/activity_logger.dart';
import '../../widgets/custom_app_bar.dart';

/// Password-protected admin audit trail viewer.
/// Only accessible with the correct admin password.
/// User CANNOT delete or modify any log entries.
class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen>
    with SingleTickerProviderStateMixin {
  List<ActivityLog> _logs = [];
  List<ActivityLog> _filteredLogs = [];
  bool _isLoading = true;
  LogCategory? _selectedFilter;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _loadLogs();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await ActivityLogger.instance.getLogs(days: 3);
    if (mounted) {
      setState(() {
        _logs = logs;
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (_selectedFilter == null) {
      _filteredLogs = List.from(_logs);
    } else {
      _filteredLogs =
          _logs.where((l) => l.category == _selectedFilter).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'Activity Logs 🔐',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: Column(
        children: [
          // ─── Header Info Bar ───
          _buildInfoBar(theme),

          // ─── Filter Chips ───
          _buildFilterChips(theme),

          // ─── Log List ───
          Expanded(
            child: _isLoading ? _buildShimmer(theme) : _buildLogList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBar(ThemeData theme) {
    return Container(
      margin: EdgeInsets.fromLTRB(4.w, 1.5.h, 4.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A237E).withValues(alpha: 0.9),
            const Color(0xFF0D47A1).withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_outlined,
                color: Colors.white, size: 22),
          ),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Admin Audit Trail',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '3 நாள் Records • ${_logs.length} entries',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Refresh button
          IconButton(
            onPressed: _loadLogs,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Logs',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    final categories = [
      null, // All
      LogCategory.attendance,
      LogCategory.login,
      LogCategory.leave,
      LogCategory.lunch,
      LogCategory.network,
      LogCategory.sync,
      LogCategory.error,
      LogCategory.system,
    ];

    return Container(
      height: 50,
      margin: EdgeInsets.only(top: 1.h),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 3.w),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedFilter == cat;
          final label = cat == null ? 'All' : _getCategoryLabel(cat);
          final color =
              cat == null ? theme.colorScheme.primary : _getCategoryColor(cat);

          return Padding(
            padding: EdgeInsets.only(right: 2.w),
            child: FilterChip(
              label: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              selectedColor: color,
              backgroundColor: color.withValues(alpha: 0.1),
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: isSelected ? color : color.withValues(alpha: 0.3),
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedFilter = selected ? cat : null;
                  _applyFilter();
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogList(ThemeData theme) {
    if (_filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilter != null
                  ? 'No ${_getCategoryLabel(_selectedFilter!)} logs found'
                  : 'No activity logs yet',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    // Group logs by date
    final grouped = <String, List<ActivityLog>>{};
    for (var log in _filteredLogs) {
      final dateKey = DateFormat('yyyy-MM-dd').format(log.timestamp);
      grouped.putIfAbsent(dateKey, () => []).add(log);
    }

    final dateKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(4.w, 1.h, 4.w, 2.h),
        itemCount: dateKeys.length,
        itemBuilder: (context, index) {
          final dateStr = dateKeys[index];
          final dayLogs = grouped[dateStr]!;
          final date = DateTime.parse(dateStr);
          final isToday =
              DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateStr;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Header
              Container(
                margin: EdgeInsets.only(top: index == 0 ? 0 : 2.h, bottom: 1.h),
                padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.8.h),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today,
                        size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      isToday
                          ? 'Today — ${DateFormat('dd MMM yyyy').format(date)}'
                          : DateFormat('EEEE — dd MMM yyyy').format(date),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${dayLogs.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Log Entries
              ...dayLogs.map((log) => _buildLogEntry(theme, log)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogEntry(ThemeData theme, ActivityLog log) {
    final color = _getCategoryColor(log.category);
    final icon = _getCategoryIcon(log.category);
    final timeStr = DateFormat('hh:mm:ss a').format(log.timestamp);

    // Determine status color based on details text
    Color statusColor = color;
    String statusBadge = _getCategoryLabel(log.category);
    if (log.details.toLowerCase().contains('success') ||
        log.action.toLowerCase() == 'success') {
      statusColor = Colors.green;
      statusBadge = 'SUCCESS';
    } else if (log.details.toLowerCase().contains('fail') ||
        log.details.toLowerCase().contains('error') ||
        log.action.toLowerCase() == 'failed') {
      statusColor = Colors.red;
      statusBadge = 'FAILED / ERROR';
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 1.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showLogDetailsDialog(context, log, theme),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(color: statusColor, width: 4),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(3.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: statusColor),
                  ),
                  SizedBox(width: 3.w),

                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Action + Category Badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                log.action.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusBadge,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Details text
                        Text(
                          log.details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Time + Network row
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 12,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4)),
                            const SizedBox(width: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (log.networkType != null &&
                                log.networkType!.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              _buildNetworkBadge(log.networkType!),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogDetailsDialog(
      BuildContext context, ActivityLog log, ThemeData theme) {
    final timeStr = DateFormat('dd MMM yyyy, hh:mm:ss a').format(log.timestamp);
    final color = _getCategoryColor(log.category);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(_getCategoryIcon(log.category), color: color),
              const SizedBox(width: 8),
              const Text(
                'Log Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Action', log.action.toUpperCase(), theme),
                _detailRow('Category', _getCategoryLabel(log.category), theme),
                _detailRow('Time', timeStr, theme),
                _detailRow('Network', log.networkType ?? 'N/A', theme),
                if (log.salesmanId != null)
                  _detailRow('User ID', log.salesmanId!, theme),
                const SizedBox(height: 12),
                const Text('Details:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    log.details,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
                if (log.extra != null && log.extra!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('System Log/Extra:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: SelectableText(
                      log.extra!,
                      style: const TextStyle(
                          fontSize: 12, height: 1.5, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkBadge(String netType) {
    final isOnline = netType != 'offline' && netType != 'unknown';
    IconData icon;
    if (netType == 'wifi') {
      icon = Icons.wifi;
    } else if (netType == 'mobile') {
      icon = Icons.signal_cellular_alt;
    } else if (netType == 'offline') {
      icon = Icons.wifi_off;
    } else {
      icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isOnline
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: isOnline ? Colors.green : Colors.red),
          const SizedBox(width: 3),
          Text(
            netType.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isOnline ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(ThemeData theme) {
    final baseColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return ListView.builder(
      padding: EdgeInsets.all(4.w),
      itemCount: 8,
      itemBuilder: (_, __) => FadeTransition(
        opacity:
            Tween<double>(begin: 0.3, end: 0.8).animate(_shimmerController),
        child: Container(
          margin: EdgeInsets.only(bottom: 1.h),
          height: 80,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────

  String _getCategoryLabel(LogCategory cat) {
    switch (cat) {
      case LogCategory.attendance:
        return 'Attendance';
      case LogCategory.login:
        return 'Login';
      case LogCategory.leave:
        return 'Leave';
      case LogCategory.lunch:
        return 'Lunch';
      case LogCategory.network:
        return 'Network';
      case LogCategory.error:
        return 'Error';
      case LogCategory.sync:
        return 'Sync';
      case LogCategory.navigation:
        return 'Navigation';
      case LogCategory.system:
        return 'System';
    }
  }

  Color _getCategoryColor(LogCategory cat) {
    switch (cat) {
      case LogCategory.attendance:
        return const Color(0xFF2E7D32); // Green
      case LogCategory.login:
        return const Color(0xFF6A1B9A); // Purple
      case LogCategory.leave:
        return const Color(0xFF1565C0); // Blue
      case LogCategory.lunch:
        return const Color(0xFFE65100); // Orange
      case LogCategory.network:
        return const Color(0xFFF9A825); // Yellow/Amber
      case LogCategory.error:
        return const Color(0xFFC62828); // Red
      case LogCategory.sync:
        return const Color(0xFF00838F); // Teal
      case LogCategory.navigation:
        return const Color(0xFF546E7A); // Blue Grey
      case LogCategory.system:
        return const Color(0xFF757575); // Grey
    }
  }

  IconData _getCategoryIcon(LogCategory cat) {
    switch (cat) {
      case LogCategory.attendance:
        return Icons.fingerprint;
      case LogCategory.login:
        return Icons.login;
      case LogCategory.leave:
        return Icons.calendar_month;
      case LogCategory.lunch:
        return Icons.restaurant;
      case LogCategory.network:
        return Icons.wifi;
      case LogCategory.error:
        return Icons.error_outline;
      case LogCategory.sync:
        return Icons.sync;
      case LogCategory.navigation:
        return Icons.navigation;
      case LogCategory.system:
        return Icons.settings;
    }
  }
}

/// Static helper to show the password gate before opening logs screen
class ActivityLogsGate {
  static const String _adminPassword = String.fromEnvironment('ADMIN_PASSWORD', defaultValue: 'dummy_password_123');

  static void showPasswordDialog(BuildContext context) {
    final controller = TextEditingController();
    bool obscure = true;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock_outline,
                        color: Color(0xFF1A237E), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Access',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Enter password to view logs',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      errorText: errorText,
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(
                            obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () {
                          setDialogState(() => obscure = !obscure);
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                    onSubmitted: (_) =>
                        _tryOpen(context, dialogContext, controller, (e) {
                      setDialogState(() => errorText = e);
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      _tryOpen(context, dialogContext, controller, (e) {
                    setDialogState(() => errorText = e);
                  }),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Unlock'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void _tryOpen(
    BuildContext pageContext,
    BuildContext dialogContext,
    TextEditingController controller,
    void Function(String?) setError,
  ) {
    if (controller.text.trim() == _adminPassword) {
      Navigator.pop(dialogContext);
      Navigator.push(
        pageContext,
        MaterialPageRoute(
          builder: (context) => const ActivityLogsScreen(),
        ),
      );
    } else {
      setError('Incorrect password');
      controller.clear();
    }
  }
}
