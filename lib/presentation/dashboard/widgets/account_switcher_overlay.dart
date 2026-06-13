import 'package:flutter/material.dart';
import 'package:slfm_salesman_app/main.dart'; // 🔥 Resolves globalSecurityGuardState
import 'package:sizer/sizer.dart';
import '../../../services/secure_storage_service.dart';
import '../../../widgets/profile_image_widget.dart';
import '../../../routes/app_routes.dart';
import 'package:slfm_salesman_app/core/theme/app_colors.dart';

class AccountSwitcherOverlay extends StatefulWidget {
  const AccountSwitcherOverlay({super.key});

  @override
  State<AccountSwitcherOverlay> createState() => _AccountSwitcherOverlayState();
}

class _AccountSwitcherOverlayState extends State<AccountSwitcherOverlay> {
  List<Map<String, dynamic>> _accounts = [];
  String? _currentSalesmanId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    // 🔥 Ensure the current active session is synced to the switcher registry before loading
    await SecureStorageService.syncCurrentSessionToSwitcher();

    final accounts = await SecureStorageService.getSavedAccounts();
    final currentId = await SecureStorageService.getSalesmanId();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _currentSalesmanId = currentId;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: EdgeInsets.only(
        top: 2.h,
        left: 4.w,
        right: 4.w,
        bottom: 2.h + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: 2.h),
            decoration: BoxDecoration(
              color: colors.textSecondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Text(
            "Account Switcher",
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),

          SizedBox(height: 3.h),

          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: CircularProgressIndicator(color: colors.textPrimary),
            )
          else if (_accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text("No saved accounts found",
                  style: TextStyle(color: colors.textSecondary)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _accounts.length,
                separatorBuilder: (ctx, i) => Divider(
                    color: colors.divider.withValues(alpha: 0.1), height: 1),
                itemBuilder: (context, index) {
                  final account = _accounts[index];
                  final isCurrent =
                      account['salesman_id'].toString() == _currentSalesmanId;

                  if (isCurrent) {
                    return _buildAccountTile(account, isCurrent);
                  }

                  return Dismissible(
                    key: Key(account['salesman_id'].toString()),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) =>
                        _showDeleteConfirmation(account),
                    onDismissed: (direction) => _onRemoveAccount(account),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text("Remove",
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          Icon(Icons.delete_sweep_outlined,
                              color: Colors.redAccent),
                        ],
                      ),
                    ),
                    child: _buildAccountTile(account, isCurrent),
                  );
                },
              ),
            ),

          SizedBox(height: 2.h),

          // Add Account Button
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.login);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 1.5.h, horizontal: 4.w),
              decoration: BoxDecoration(
                border:
                    Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline,
                      color: Colors.blueAccent, size: 20),
                  SizedBox(width: 2.w),
                  Text(
                    "Add New Member Account",
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 3.h),
        ],
      ),
    );
  }

  Widget _buildAccountTile(Map<String, dynamic> account, bool isCurrent) {
    final colors = AppColors.of(context);
    return ListTile(
      onTap: isCurrent ? null : () => _onSwitchAccount(account),
      contentPadding: EdgeInsets.symmetric(vertical: 0.5.h, horizontal: 2.w),
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border:
              isCurrent ? Border.all(color: Colors.blueAccent, width: 2) : null,
        ),
        child: ProfileImageWidget(
          name: account['salesman_name'] ?? 'S',
          profilePhoto: account['profile_photo'] ?? '',
          avatarAnimal: account['avatar_animal'] ?? '',
          size: 44,
        ),
      ),
      title: Text(
        (account['salesman_name'] ?? 'Unknown').toString(),
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
          fontSize: 12.sp,
        ),
      ),
      subtitle: Text(
        account['showroom_name'] ?? 'Showroom',
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 9.sp,
        ),
      ),
      trailing: isCurrent
          ? Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.blueAccent, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 12),
            )
          : Icon(Icons.arrow_forward_ios,
              color: colors.textSecondary.withValues(alpha: 0.3), size: 14),
    );
  }

  Future<void> _onSwitchAccount(Map<String, dynamic> account) async {
    // 🔥 TASK 2 FIX: Don't pop() the sheet first — it causes a visible collapse animation.
    // Instead, switch account and navigate directly. pushNamedAndRemoveUntil
    // will remove ALL routes (including this bottom sheet modal) atomically,
    // so the user sees a clean transition to splash screen.
    final navigator = Navigator.of(context);

    // Switch active session
    await SecureStorageService.switchActiveAccount(account);

    // 🔥 REFRESH SECURITY LISTENERS FOR NEW ACCOUNT
    globalSecurityGuardState?.setupGlobalSuspensionAndPresence();

    // 🔥 FIX: Navigate to splash — this removes ALL routes including the modal sheet
    navigator.pushNamedAndRemoveUntil(AppRoutes.splashScreen, (route) => false);
  }

  Future<bool?> _showDeleteConfirmation(Map<String, dynamic> account) async {
    final colors = AppColors.of(context);
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text("Remove Account?",
            style: TextStyle(
                color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          "Do you want to remove ${account['salesman_name']}'s account from this device?",
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text("Cancel", style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove",
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _onRemoveAccount(Map<String, dynamic> account) async {
    final id = account['salesman_id'].toString();
    await SecureStorageService.removeAccountFromSwitcher(id);
    _loadAccounts(); // Refresh list

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Removed ${account['salesman_name']}"),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
