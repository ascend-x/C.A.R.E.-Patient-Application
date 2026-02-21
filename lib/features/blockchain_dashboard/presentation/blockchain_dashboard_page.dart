import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:health_wallet/core/di/injection.dart';
import 'package:health_wallet/core/services/blockchain/care_x_api_service.dart';
import 'package:health_wallet/core/services/blockchain/care_x_wallet_service.dart';
import 'package:health_wallet/core/services/blockchain/blockchain_service.dart';
import 'package:health_wallet/features/blockchain_dashboard/bloc/blockchain_dashboard_bloc.dart';
import 'package:intl/intl.dart';

@RoutePage()
class BlockchainDashboardPage extends StatelessWidget {
  const BlockchainDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BlockchainDashboardBloc(
        getIt<BlockchainService>(),
        getIt<CareXApiService>(),
        getIt<CareXWalletService>(),
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
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1224),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFF00FF87),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Care-X Live Dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
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
                        : Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
                backgroundColor: const Color(0xFF0D1224),
                side: BorderSide(
                  color: state.isChainConnected
                      ? const Color(0xFF00FF87)
                      : Colors.red,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
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
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF87)),
            );
          }

          if (state.status == BlockchainDashboardStatus.noWallet) {
            return _WalletPickerInitial();
          }

          if (state.status == BlockchainDashboardStatus.failure) {
            return _ErrorView(error: state.error ?? 'Unknown error');
          }

          return RefreshIndicator(
            color: const Color(0xFF00FF87),
            backgroundColor: const Color(0xFF0D1224),
            onRefresh: () async {
              ctx
                  .read<BlockchainDashboardBloc>()
                  .add(const BlockchainDashboardRefreshed());
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WalletSwitcher(currentWallet: state.currentWallet),
                const SizedBox(height: 16),
                if (state.patient != null)
                  _PatientCard(patient: state.patient!),
                const SizedBox(height: 16),
                _VitalsSection(vitals: state.vitals),
                const SizedBox(height: 16),
                _BlockchainRecordsSection(records: state.chainRecords),
                const SizedBox(height: 16),
                _DocumentsSection(
                  documents: state.documents,
                  currentWallet: state.currentWallet,
                ),
                const SizedBox(height: 16),
                _AccessControlSection(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Wallet picker (initial state when no wallet saved) ───────────────────────

class _WalletPickerInitial extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 64, color: Color(0xFF00FF87)),
            const SizedBox(height: 16),
            const Text(
              'Select a patient wallet to continue',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ...CareXAccounts.all.map((acct) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D1224),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF00FF87)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => context
                        .read<BlockchainDashboardBloc>()
                        .add(BlockchainWalletSelected(acct)),
                    child: Text(acct.name),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Wallet switcher chip ─────────────────────────────────────────────────────

class _WalletSwitcher extends StatelessWidget {
  final CareXWalletAccount? currentWallet;
  const _WalletSwitcher({required this.currentWallet});

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      title: '👤 Active Patient Wallet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentWallet?.name ?? '—',
            style: const TextStyle(
              color: Color(0xFF00FF87),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currentWallet?.walletAddress ?? '',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: CareXAccounts.all.map((acct) {
              final isActive =
                  acct.walletAddress == currentWallet?.walletAddress;
              return ChoiceChip(
                label: Text(acct.name.split(' ').first),
                selected: isActive,
                selectedColor: const Color(0xFF00FF87),
                backgroundColor: const Color(0xFF1A2035),
                labelStyle: TextStyle(
                  color: isActive ? Colors.black : Colors.white60,
                  fontSize: 12,
                ),
                onSelected: (_) => context
                    .read<BlockchainDashboardBloc>()
                    .add(BlockchainWalletSelected(acct)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Patient info card ────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final CareXPatient patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      title: '🧑‍⚕️ Patient Info (EMR)',
      child: Row(
        children: [
          Expanded(
            child: _InfoChip(label: 'Name', value: patient.name),
          ),
          Expanded(child: _InfoChip(label: 'Age', value: '${patient.age}y')),
          Expanded(
            child: _InfoChip(
              label: 'ID',
              value: '#${patient.id}',
            ),
          ),
        ],
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
      title: '💓 Latest Vitals (EMR → Blockchain)',
      child: vitals.isEmpty
          ? const Text('No vitals recorded yet.',
              style: TextStyle(color: Colors.white38))
          : Column(
              children:
                  vitals.take(3).map((v) => _VitalRow(vitals: v)).toList(),
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
        color: const Color(0xFF0D1224),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              (vitals.isCritical ?? false) ? Colors.redAccent : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          if (vitals.isCritical ?? false)
            const Icon(Icons.warning_amber, color: Colors.redAccent, size: 16),
          if (vitals.isCritical ?? false) const SizedBox(width: 6),
          Expanded(
            child: Text(
              'BPM: ${vitals.bpm?.toStringAsFixed(0) ?? '—'}  '
              'SpO₂: ${vitals.spo2?.toStringAsFixed(1) ?? '—'}%  '
              'Temp: ${vitals.temperature?.toStringAsFixed(1) ?? '—'}°C',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            vitals.timestamp?.substring(0, 10) ?? '',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── On-chain records section ─────────────────────────────────────────────────

class _BlockchainRecordsSection extends StatelessWidget {
  final List<BlockchainRecord> records;
  const _BlockchainRecordsSection({required this.records});

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      title: '⛓️ On-Chain Records (Ganache)',
      child: records.isEmpty
          ? const Text('No records anchored to chain yet.',
              style: TextStyle(color: Colors.white38))
          : Column(
              children: records
                  .take(5)
                  .map((r) => _ChainRecordRow(record: r))
                  .toList(),
            ),
    );
  }
}

class _ChainRecordRow extends StatelessWidget {
  final BlockchainRecord record;
  const _ChainRecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1224),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFF00FF87), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.ipfsHash.length > 20
                      ? '${record.ipfsHash.substring(0, 20)}…'
                      : record.ipfsHash,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd MMM yyyy, HH:mm').format(record.timestamp),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (record.isCritical)
            const Icon(Icons.warning_amber, color: Colors.redAccent, size: 14),
        ],
      ),
    );
  }
}

// ─── Documents section ────────────────────────────────────────────────────────

class _DocumentsSection extends StatelessWidget {
  final List<CareXDocument> documents;
  final CareXWalletAccount? currentWallet;

  const _DocumentsSection(
      {required this.documents, required this.currentWallet});

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      title: '📄 Medical Documents',
      child: documents.isEmpty
          ? const Text('No documents on file.',
              style: TextStyle(color: Colors.white38))
          : Column(
              children: documents
                  .map((d) => _DocRow(doc: d, currentWallet: currentWallet))
                  .toList(),
            ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final CareXDocument doc;
  final CareXWalletAccount? currentWallet;

  const _DocRow({required this.doc, required this.currentWallet});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1224),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined,
              color: Colors.white54, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title ?? doc.documentType,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  'ID #${doc.id}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Color(0xFF00FF87), size: 18),
            tooltip: 'Share this document',
            onPressed: () => _showShareDialog(context, doc),
          ),
        ],
      ),
    );
  }

  void _showShareDialog(BuildContext context, CareXDocument doc) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1224),
        title:
            const Text('Share Document', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Doctor wallet address (0x...)',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF00FF87))),
          ),
        ),
        actions: [
          TextButton(
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF87),
              foregroundColor: Colors.black,
            ),
            child: const Text('Grant Access'),
            onPressed: () {
              final wallet = controller.text.trim();
              if (wallet.isNotEmpty) {
                context.read<BlockchainDashboardBloc>().add(
                      BlockchainDocumentShareRequested(
                        docIds: [doc.id],
                        recipientWallet: wallet,
                      ),
                    );
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─── Access control section ───────────────────────────────────────────────────

class _AccessControlSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(
      text:
          '0x3E96F97A042F3005E51DeE6775B84f1599C1b850', // Default: Doctor wallet
    );

    return _DashCard(
      title: '🔑 Live Key Sharing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Grant or revoke a doctor\'s access to ALL your medical documents on the Care-X blockchain.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Recipient (Doctor) Wallet Address',
              labelStyle: TextStyle(color: Colors.white38),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00FF87))),
              prefixIcon: Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white38),
            ),
          ),
          const SizedBox(height: 12),
          BlocBuilder<BlockchainDashboardBloc, BlockchainDashboardState>(
            buildWhen: (p, c) => p.documents != c.documents,
            builder: (ctx, state) => Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF87),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('Share All'),
                    onPressed: () {
                      final wallet = controller.text.trim();
                      if (wallet.isNotEmpty && state.documents.isNotEmpty) {
                        ctx.read<BlockchainDashboardBloc>().add(
                              BlockchainDocumentShareRequested(
                                docIds:
                                    state.documents.map((d) => d.id).toList(),
                                recipientWallet: wallet,
                              ),
                            );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.block),
                    label: const Text('Revoke All'),
                    onPressed: () {
                      final wallet = controller.text.trim();
                      if (wallet.isNotEmpty) {
                        ctx.read<BlockchainDashboardBloc>().add(
                              BlockchainDocumentRevokeRequested(wallet),
                            );
                      }
                    },
                  ),
                ),
              ],
            ),
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
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Divider(color: Colors.white12, height: 20),
          child,
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
      ],
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
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Could not load data\n\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF87),
                  foregroundColor: Colors.black),
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
