import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:health_wallet/core/di/injection.dart';
import 'package:health_wallet/core/navigation/app_router.dart';
import 'package:health_wallet/core/services/auth/patient_auth_service.dart';
import 'package:health_wallet/core/services/blockchain/care_x_api_service.dart';
import 'package:health_wallet/core/services/blockchain/care_x_wallet_service.dart';

/// State for the Care-X patient session (vitals + patient info + docs).
class CareXSessionState {
  final bool isLoading;
  final String? error;
  final CareXPatient? patient;
  final List<CareXVitals> vitals;
  final List<CareXDocument> documents;
  final CareXWalletAccount? account;

  const CareXSessionState({
    this.isLoading = false,
    this.error,
    this.patient,
    this.vitals = const [],
    this.documents = const [],
    this.account,
  });

  CareXSessionState copyWith({
    bool? isLoading,
    String? error,
    CareXPatient? patient,
    List<CareXVitals>? vitals,
    List<CareXDocument>? documents,
    CareXWalletAccount? account,
  }) =>
      CareXSessionState(
        isLoading: isLoading ?? this.isLoading,
        error: error,
        patient: patient ?? this.patient,
        vitals: vitals ?? this.vitals,
        documents: documents ?? this.documents,
        account: account ?? this.account,
      );

  int get activeShareCount {
    return 0; // tracked separately via DocumentPermission
  }

  double get trustScore {
    double score = 0;
    if (account != null) score += 25;
    if (vitals.isNotEmpty) score += 25;
    if (documents.isNotEmpty) score += 25;
    if (patient != null) score += 25;
    return score;
  }
}

/// Cubit for loading session data scoped to the logged-in patient.
class CareXSessionCubit extends Cubit<CareXSessionState> {
  final PatientAuthService _authService;
  final CareXApiService _apiService;

  CareXSessionCubit(this._authService, this._apiService)
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

      emit(state.copyWith(
        isLoading: false,
        account: account,
        patient: patient,
        vitals: vitals,
        documents: documents,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
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
    await _authService.logout();
    if (context.mounted) {
      context.router.replace(const LoginRoute());
    }
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
      )..loadSession(),
      child: child,
    );
  }
}
