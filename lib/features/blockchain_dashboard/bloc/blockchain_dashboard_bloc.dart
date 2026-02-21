import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:health_wallet/core/services/blockchain/blockchain_service.dart';
import 'package:health_wallet/core/services/blockchain/care_x_api_service.dart';
import 'package:health_wallet/core/services/blockchain/care_x_wallet_service.dart';
import 'package:injectable/injectable.dart';

part 'blockchain_dashboard_state.dart';
part 'blockchain_dashboard_event.dart';

@injectable
class BlockchainDashboardBloc
    extends Bloc<BlockchainDashboardEvent, BlockchainDashboardState> {
  final BlockchainService _blockchainService;
  final CareXApiService _apiService;
  final CareXWalletService _walletService;

  BlockchainDashboardBloc(
    this._blockchainService,
    this._apiService,
    this._walletService,
  ) : super(const BlockchainDashboardState()) {
    on<BlockchainDashboardStarted>(_onStarted);
    on<BlockchainWalletSelected>(_onWalletSelected);
    on<BlockchainDashboardRefreshed>(_onRefreshed);
    on<BlockchainDocumentShareRequested>(_onShareRequested);
    on<BlockchainDocumentRevokeRequested>(_onRevokeRequested);
  }

  Future<void> _onStarted(
    BlockchainDashboardStarted event,
    Emitter<BlockchainDashboardState> emit,
  ) async {
    emit(state.copyWith(status: BlockchainDashboardStatus.loading));
    try {
      final wallet = await _walletService.getCurrentWallet();
      final connected = await _blockchainService.isConnected();

      if (wallet == null) {
        emit(state.copyWith(
          status: BlockchainDashboardStatus.noWallet,
          isChainConnected: connected,
        ));
        return;
      }

      emit(state.copyWith(
        currentWallet: wallet,
        isChainConnected: connected,
      ));

      await _loadDashboardData(wallet.walletAddress, emit);
    } catch (e) {
      emit(state.copyWith(
        status: BlockchainDashboardStatus.failure,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onWalletSelected(
    BlockchainWalletSelected event,
    Emitter<BlockchainDashboardState> emit,
  ) async {
    emit(state.copyWith(status: BlockchainDashboardStatus.loading));
    await _walletService.saveWallet(event.account);
    emit(state.copyWith(currentWallet: event.account));
    await _loadDashboardData(event.account.walletAddress, emit);
  }

  Future<void> _onRefreshed(
    BlockchainDashboardRefreshed event,
    Emitter<BlockchainDashboardState> emit,
  ) async {
    if (state.currentWallet == null) return;
    emit(state.copyWith(status: BlockchainDashboardStatus.loading));
    await _loadDashboardData(state.currentWallet!.walletAddress, emit);
  }

  Future<void> _onShareRequested(
    BlockchainDocumentShareRequested event,
    Emitter<BlockchainDashboardState> emit,
  ) async {
    try {
      emit(state.copyWith(isSharingInProgress: true));
      await _apiService.shareDocuments(
        docIds: event.docIds,
        recipientWallet: event.recipientWallet,
      );
      emit(state.copyWith(
        isSharingInProgress: false,
        lastShareMessage: 'Access granted to ${event.recipientWallet}',
      ));
    } catch (e) {
      emit(state.copyWith(
        isSharingInProgress: false,
        error: 'Failed to share: $e',
      ));
    }
  }

  Future<void> _onRevokeRequested(
    BlockchainDocumentRevokeRequested event,
    Emitter<BlockchainDashboardState> emit,
  ) async {
    try {
      emit(state.copyWith(isSharingInProgress: true));
      await _apiService.revokeDocumentAccess(event.recipientWallet);
      emit(state.copyWith(
        isSharingInProgress: false,
        lastShareMessage: 'Access revoked for ${event.recipientWallet}',
      ));
      // Refresh documents list after revoke
      if (state.currentWallet != null) {
        await _loadDashboardData(state.currentWallet!.walletAddress, emit);
      }
    } catch (e) {
      emit(state.copyWith(
        isSharingInProgress: false,
        error: 'Failed to revoke: $e',
      ));
    }
  }

  Future<void> _loadDashboardData(
    String walletAddress,
    Emitter<BlockchainDashboardState> emit,
  ) async {
    try {
      final results = await Future.wait([
        _apiService.getPatientByWallet(walletAddress),
        _blockchainService.getRecordsForPatient(walletAddress),
        _apiService.getDocumentsByWallet(walletAddress),
      ]);

      final patient = results[0] as CareXPatient?;
      final chainRecords = results[1] as List<BlockchainRecord>;
      final documents = results[2] as List<CareXDocument>;

      List<CareXVitals> vitals = [];
      if (patient != null) {
        vitals = await _apiService.getVitalsForPatient(patient.id);
      }

      emit(state.copyWith(
        status: BlockchainDashboardStatus.success,
        patient: patient,
        vitals: vitals,
        chainRecords: chainRecords,
        documents: documents,
        error: null,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: BlockchainDashboardStatus.failure,
        error: e.toString(),
      ));
    }
  }
}
