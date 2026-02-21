import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:health_wallet/core/theme/app_insets.dart';
import 'package:health_wallet/core/theme/app_text_style.dart';
import 'package:health_wallet/core/utils/build_context_extension.dart';
import 'package:health_wallet/core/widgets/custom_app_bar.dart';
import 'package:health_wallet/features/auth/presentation/care_x_session_provider.dart';
import 'package:health_wallet/core/services/blockchain/care_x_api_service.dart';

/// Tab 3 — File Access & Sharing (replaces old Import page)
@RoutePage()
class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FileAccessView();
  }
}

class _FileAccessView extends StatefulWidget {
  const _FileAccessView();

  @override
  State<_FileAccessView> createState() => _FileAccessViewState();
}

class _FileAccessViewState extends State<_FileAccessView> {
  final _recipientCtrl = TextEditingController();
  String? _shareError;
  bool _isSharing = false;

  @override
  void dispose() {
    _recipientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'File Access & Sharing',
        automaticallyImplyLeading: false,
        actions: [
          BlocBuilder<CareXSessionCubit, CareXSessionState>(
            builder: (ctx, state) => IconButton(
              icon: Icon(Icons.refresh_outlined,
                  color: context.colorScheme.onSurface),
              onPressed: () => ctx.read<CareXSessionCubit>().loadSession(),
            ),
          ),
        ],
      ),
      body: BlocBuilder<CareXSessionCubit, CareXSessionState>(
        builder: (context, state) {
          if (state.isLoading) {
            return Center(
                child: CircularProgressIndicator(
                    color: context.colorScheme.primary));
          }
          if (state.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Insets.large),
                child: Text(
                  'Error: ${state.error}',
                  style: AppTextStyle.bodyMedium
                      .copyWith(color: context.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = state.documents;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Insets.normal, Insets.medium, Insets.normal, 80),
            children: [
              // ── Share access panel ────────────────────────────────────
              _buildSharePanel(context, state, docs),
              const SizedBox(height: Insets.medium),

              // ── Document list ─────────────────────────────────────────
              _buildDocList(context, docs),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSharePanel(
    BuildContext context,
    CareXSessionState state,
    List<CareXDocument> docs,
  ) {
    return Container(
      padding: const EdgeInsets.all(Insets.medium),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Share Document Access',
                style: AppTextStyle.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color:
                          context.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${docs.length} files',
                  style: AppTextStyle.labelSmall.copyWith(
                    color: context.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.medium),
          TextField(
            controller: _recipientCtrl,
            style: AppTextStyle.bodySmall.copyWith(
              color: context.colorScheme.onSurface,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              labelText: 'Recipient Wallet Address',
              hintText: '0x...',
              prefixIcon: Icon(Icons.person_outline,
                  color: context.colorScheme.onSurface.withValues(alpha: 0.4)),
              labelStyle: AppTextStyle.bodySmall.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.5)),
              hintStyle: AppTextStyle.bodySmall.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.25)),
              filled: true,
              fillColor: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: context.isDarkMode
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.colorScheme.primary),
              ),
            ),
          ),
          if (_shareError != null)
            Padding(
              padding: const EdgeInsets.only(top: Insets.small),
              child: Text(_shareError!,
                  style: AppTextStyle.bodySmall
                      .copyWith(color: context.colorScheme.error)),
            ),
          const SizedBox(height: Insets.smallNormal),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colorScheme.primary,
                    foregroundColor: context.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                        vertical: Insets.smallNormal),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isSharing
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colorScheme.onPrimary),
                        )
                      : const Icon(Icons.share_outlined, size: 18),
                  label: Text(_isSharing ? 'Sharing…' : 'Share All Docs'),
                  onPressed:
                      _isSharing ? null : () => _handleShare(context, docs),
                ),
              ),
              const SizedBox(width: Insets.small),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.block_outlined,
                    color: Colors.redAccent, size: 20),
                onPressed: () => _handleRevoke(context),
                tooltip: 'Revoke access for this wallet',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocList(BuildContext context, List<CareXDocument> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              Icon(Icons.folder_off_outlined,
                  size: 48,
                  color: context.colorScheme.onSurface.withValues(alpha: 0.2)),
              const SizedBox(height: Insets.small),
              Text(
                'No documents on file',
                style: AppTextStyle.bodySmall.copyWith(
                    color:
                        context.colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(Insets.medium),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Documents',
            style: AppTextStyle.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colorScheme.onSurface,
            ),
          ),
          Divider(
              color: context.colorScheme.onSurface.withValues(alpha: 0.06),
              height: 24),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(
              color: context.colorScheme.onSurface.withValues(alpha: 0.05),
            ),
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            context.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.description_outlined,
                          size: 18, color: context.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.title ?? doc.documentType,
                            style: AppTextStyle.bodySmall.copyWith(
                              fontWeight: FontWeight.w500,
                              color: context.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (doc.ipfsHash == null)
                                _SecureBadge(
                                    secure: doc.documentType != 'revoked'),
                              const SizedBox(width: 6),
                              Text(
                                doc.timestamp ?? '',
                                style: AppTextStyle.bodySmall.copyWith(
                                  color: context.colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: Colors.green,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleShare(
      BuildContext context, List<CareXDocument> docs) async {
    final wallet = _recipientCtrl.text.trim();
    if (wallet.isEmpty) {
      setState(() => _shareError = 'Enter a recipient wallet address.');
      return;
    }
    setState(() {
      _isSharing = true;
      _shareError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final docIds = docs.map((d) => d.id).toList();
      await context.read<CareXSessionCubit>().shareDocuments(docIds, wallet);
      if (mounted) {
        setState(() => _isSharing = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Access granted to ${_truncate(wallet)}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSharing = false;
          _shareError = e.toString();
        });
      }
    }
  }

  Future<void> _handleRevoke(BuildContext context) async {
    final wallet = _recipientCtrl.text.trim();
    if (wallet.isEmpty) {
      setState(() => _shareError = 'Enter the wallet to revoke.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareXSessionCubit>().revokeAccess(wallet);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Access revoked for ${_truncate(wallet)}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _shareError = e.toString());
      }
    }
  }

  String _truncate(String s) =>
      s.length > 14 ? '${s.substring(0, 6)}…${s.substring(s.length - 4)}' : s;

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      );
}

class _SecureBadge extends StatelessWidget {
  final bool secure;
  const _SecureBadge({required this.secure});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: (secure ? Colors.green : Colors.orange).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        secure ? 'Secure' : 'Public',
        style: AppTextStyle.labelSmall.copyWith(
          color: secure ? Colors.green : Colors.orange,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
