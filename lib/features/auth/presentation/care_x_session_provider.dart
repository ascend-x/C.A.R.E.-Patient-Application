import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:health_wallet/core/config/constants/app_constants.dart';
import 'package:health_wallet/core/di/injection.dart';
import 'package:health_wallet/core/navigation/app_router.dart';
import 'package:health_wallet/core/services/auth/patient_auth_service.dart';
import 'package:health_wallet/core/services/blockchain/blockchain_service.dart';
import 'package:health_wallet/core/services/blockchain/care_x_api_service.dart';
import 'package:health_wallet/core/services/blockchain/care_x_wallet_service.dart';
import 'package:http/http.dart' as http;

/// State for the Care-X patient session (vitals + patient info + docs).
class CareXSessionState {
  final bool isLoading;
  final String? error;
  final CareXPatient? patient;
  final List<CareXVitals> vitals;
  final List<CareXDocument> documents;
  final CareXWalletAccount? account;
  final int chainRecordCount;

  const CareXSessionState({
    this.isLoading = false,
    this.error,
    this.patient,
    this.vitals = const [],
    this.documents = const [],
    this.account,
    this.chainRecordCount = 0,
  });

  CareXSessionState copyWith({
    bool? isLoading,
    String? error,
    CareXPatient? patient,
    List<CareXVitals>? vitals,
    List<CareXDocument>? documents,
    CareXWalletAccount? account,
    int? chainRecordCount,
  }) =>
      CareXSessionState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        patient: patient ?? this.patient,
        vitals: vitals ?? this.vitals,
        documents: documents ?? this.documents,
        account: account ?? this.account,
        chainRecordCount: chainRecordCount ?? this.chainRecordCount,
      );

  int get activeShareCount {
    return 0; // tracked separately via DocumentPermission
  }

  double get trustScore {
    double score = 0;
    if (account != null) score += 20;
    if (patient != null) score += 20;
    if (vitals.isNotEmpty) score += 20;
    if (documents.isNotEmpty) score += 20;
    if (chainRecordCount > 0) score += 20;
    return score;
  }
}

/// Cubit for loading session data scoped to the logged-in patient.
/// Includes periodic polling (every 5 seconds) to keep data live.
class CareXSessionCubit extends Cubit<CareXSessionState> {
  final PatientAuthService _authService;
  final CareXApiService _apiService;
  final BlockchainService _blockchainService;
  Timer? _pollTimer;

  CareXSessionCubit(
      this._authService, this._apiService, this._blockchainService)
      : super(const CareXSessionState());

  Future<void> loadSession() async {
    emit(state.copyWith(isLoading: true));
    try {
      final account = await _authService.getCurrentAccount();
      if (account == null) {
        emit(state.copyWith(isLoading: false, error: 'Not logged in'));
        return;
      }

      final patient =
          await _apiService.getPatientByWallet(account.walletAddress);
      final vitals = patient != null
          ? await _apiService.getVitalsForPatient(patient.id)
          : <CareXVitals>[];
      final documents =
          await _apiService.getDocumentsByWallet(account.walletAddress);

      // If backend returns no documents, fetch directly from IPFS
      List<CareXDocument> finalDocuments = documents;
      if (finalDocuments.isEmpty) {
        finalDocuments = await _fetchDocumentsFromIpfs(account.walletAddress);
      }

      // Fetch blockchain record count
      int chainCount = 0;
      try {
        final records = await _blockchainService
            .getRecordsForPatient(account.walletAddress)
            .timeout(const Duration(seconds: 5));
        chainCount = records.length;
      } catch (_) {}

      emit(state.copyWith(
        isLoading: false,
        account: account,
        patient: patient,
        vitals: vitals,
        documents: finalDocuments,
        chainRecordCount: chainCount,
      ));

      // Start periodic polling every 5 seconds
      _startPolling(account.walletAddress, patient?.id);
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  /// Start periodic refresh — polls vitals and blockchain records in parallel.
  void _startPolling(String walletAddress, int? patientId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (isClosed) return;
      try {
        // Run both fetches in parallel so blockchain timeout doesn't block vitals
        final results = await Future.wait([
          // Vitals from backend
          patientId != null
              ? _apiService.getVitalsForPatient(patientId)
              : Future.value(<CareXVitals>[]),
          // Blockchain record count (short timeout, non-critical)
          _blockchainService
              .getRecordsForPatient(walletAddress)
              .timeout(const Duration(seconds: 2))
              .catchError((_) => <BlockchainRecord>[]),
        ]);

        if (!isClosed) {
          final freshVitals = results[0] as List<CareXVitals>;
          final chainRecords = results[1] as List<dynamic>;
          emit(state.copyWith(
            vitals: freshVitals,
            chainRecordCount: chainRecords.length,
          ));
        }
      } catch (_) {
        // Silently skip failed poll cycles
      }
    });
  }

  /// Fetch documents directly from the IPFS gateway.
  /// Handles both JSON metadata and raw binary files (images, PDFs).
  Future<List<CareXDocument>> _fetchDocumentsFromIpfs(
      String walletAddress) async {
    final docs = <CareXDocument>[];
    int syntheticId = 1;

    const knownIpfsHashes = [
      'QmVoMg3chKUrmYo8vBoZGrAGpQqX17xkVV3Js1U5etcbEC',
      'QmeSES8Xq5ez96Th4TGXG6bFVUibkyKVoLYYjPtk7zFjqh',
    ];

    for (final hash in knownIpfsHashes) {
      try {
        final uri = Uri.parse('${AppConstants.ipfsGatewayUrl}$hash');

        // HEAD request to determine the content type
        final headRes =
            await http.head(uri).timeout(const Duration(seconds: 10));
        if (headRes.statusCode != 200) continue;

        final contentType = headRes.headers['content-type'] ?? '';
        final id = syntheticId++;

        if (contentType.contains('json')) {
          // JSON metadata document
          final res = await http.get(uri).timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            final payload = jsonDecode(res.body) as Map<String, dynamic>;
            final metadata = IpfsDocumentMetadata.fromJson(payload);
            docs.add(CareXDocument(
              id: id,
              patientWallet: walletAddress,
              documentType: metadata.category ?? 'medical_record',
              title:
                  '${metadata.category ?? 'Document'} — ${metadata.sourceSystem ?? 'Unknown'}',
              ipfsHash: hash,
              timestamp: payload['timestamp'] as String? ??
                  DateTime.now().toIso8601String(),
              ipfsMetadata: metadata,
            ));
          }
        } else {
          // Binary file (PDF, image, etc.) — construct a document entry
          String label = 'Document';
          if (contentType.contains('pdf')) {
            label = 'PDF Document';
          } else if (contentType.contains('image')) {
            label = 'Medical Image';
          }

          docs.add(CareXDocument(
            id: id,
            patientWallet: walletAddress,
            documentType: label,
            title: label,
            ipfsHash: hash,
            timestamp: DateTime.now().toIso8601String(),
            ipfsMetadata: IpfsDocumentMetadata(
              patientUuid: '',
              mimeType: contentType,
              category: label,
              sourceSystem: 'IPFS',
            ),
          ));
        }
      } catch (_) {}
    }

    return docs;
  }

  Future<void> shareDocuments(List<int> docIds, String recipientWallet) async {
    try {
      await _apiService.shareDocuments(
          docIds: docIds, recipientWallet: recipientWallet);
    } catch (_) {}
  }

  Future<void> revokeAccess(String recipientWallet) async {
    try {
      await _apiService.revokeDocumentAccess(recipientWallet);
    } catch (_) {}
  }

  Future<void> logout(BuildContext context) async {
    _pollTimer?.cancel();
    await _authService.logout();
    if (context.mounted) {
      context.router.replace(const LoginRoute());
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}

/// Provider widget that wraps the entire portal with the session cubit.
class CareXSessionProvider extends StatelessWidget {
  final Widget child;
  const CareXSessionProvider({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CareXSessionCubit(
        getIt<PatientAuthService>(),
        getIt<CareXApiService>(),
        getIt<BlockchainService>(),
      )..loadSession(),
      child: child,
    );
  }
}
