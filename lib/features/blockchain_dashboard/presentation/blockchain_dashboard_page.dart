import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:health_wallet/core/di/injection.dart';
import 'package:health_wallet/core/services/blockchain/care_x_api_service.dart';
import 'package:health_wallet/core/services/auth/patient_auth_service.dart';
import 'package:health_wallet/core/services/blockchain/blockchain_service.dart';
import 'package:health_wallet/features/blockchain_dashboard/bloc/blockchain_dashboard_bloc.dart';

@RoutePage()
class BlockchainDashboardPage extends StatelessWidget {
  const BlockchainDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BlockchainDashboardBloc(
        getIt<BlockchainService>(),
        getIt<CareXApiService>(),
        getIt<PatientAuthService>(),
      )..add(const BlockchainDashboardStarted()),
      child: const _BlockchainDashboardView(),
    );
  }
}

class _BlockchainDashboardView extends StatelessWidget {
  const _BlockchainDashboardView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Care-X Live Dashboard',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          BlocBuilder<BlockchainDashboardBloc, BlockchainDashboardState>(
            buildWhen: (p, c) => p.isChainConnected != c.isChainConnected,
            builder: (ctx, state) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: Icon(
                  Icons.circle,
                  size: 10,
                  color: state.isChainConnected
                      ? const Color(0xFF00FF87)
                      : Colors.red,
                ),
                label: Text(
                  state.isChainConnected ? 'Ganache ✓' : 'Offline',
                  style: TextStyle(
                    color: state.isChainConnected
                        ? const Color(0xFF00FF87)
                        : Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
                backgroundColor: Theme.of(context).colorScheme.surface,
                side: BorderSide(
                  color: state.isChainConnected
                      ? const Color(0xFF00FF87)
                      : Colors.red,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh,
                color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => context
                .read<BlockchainDashboardBloc>()
                .add(const BlockchainDashboardRefreshed()),
          ),
        ],
      ),
      body: BlocConsumer<BlockchainDashboardBloc, BlockchainDashboardState>(
        listenWhen: (p, c) =>
            c.lastShareMessage != null &&
            p.lastShareMessage != c.lastShareMessage,
        listener: (ctx, state) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(state.lastShareMessage ?? ''),
              backgroundColor: const Color(0xFF00FF87),
            ),
          );
        },
        builder: (ctx, state) {
          if (state.status == BlockchainDashboardStatus.loading ||
              state.status == BlockchainDashboardStatus.initial) {
            return Center(
              child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary),
            );
          }

          if (state.status == BlockchainDashboardStatus.failure) {
            return _ErrorView(error: state.error ?? 'Unknown error');
          }

          return RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surface,
            onRefresh: () async {
              ctx
                  .read<BlockchainDashboardBloc>()
                  .add(const BlockchainDashboardRefreshed());
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _VitalsSection(vitals: state.vitals),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Vitals section ───────────────────────────────────────────────────────────

class _VitalsSection extends StatelessWidget {
  final List<CareXVitals> vitals;
  const _VitalsSection({required this.vitals});

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      title: '💓 All Vitals (EMR → Blockchain)',
      child: vitals.isEmpty
          ? Text('No vitals recorded yet.',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)))
          : Column(
              children: vitals.map((v) => _VitalRow(vitals: v)).toList(),
            ),
    );
  }
}

class _VitalRow extends StatelessWidget {
  final CareXVitals vitals;
  const _VitalRow({required this.vitals});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (vitals.isCritical ?? false)
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        children: [
          if (vitals.isCritical ?? false)
            Icon(Icons.warning_amber,
                color: Theme.of(context).colorScheme.error, size: 16),
          if (vitals.isCritical ?? false) const SizedBox(width: 6),
          Expanded(
            child: Text(
              'BPM: ${vitals.bpm?.toStringAsFixed(0) ?? '—'}  '
              'SpO₂: ${vitals.spo2?.toStringAsFixed(1) ?? '—'}%  '
              'Temp: ${vitals.temperature?.toStringAsFixed(1) ?? '—'}°C',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            vitals.timestamp?.substring(0, 10) ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

// ─── Shared widget helpers ─────────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DashCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          Divider(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              height: 20),
          child,
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text(
              'Could not load data\n\n$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary),
              onPressed: () => context
                  .read<BlockchainDashboardBloc>()
                  .add(const BlockchainDashboardRefreshed()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
